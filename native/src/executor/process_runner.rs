use std::{io, process::Stdio};

use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWriteExt},
    process::{ChildStdin, Command},
};

use crate::{
    error::{GitError, GitErrorCategory},
    executor::invocation::{GitInvocation, OutputPolicy, ProcessOutput},
};

pub struct ProcessGitRunner;

struct ReadResult {
    bytes: Vec<u8>,
    exceeded: bool,
}

impl ProcessGitRunner {
    pub const fn new() -> Self {
        Self
    }

    pub async fn run(&self, invocation: GitInvocation) -> Result<ProcessOutput, GitError> {
        let mut command = Command::new(&invocation.program);
        command
            .args(&invocation.args)
            .current_dir(&invocation.cwd)
            .stdin(if invocation.stdin.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        let mut child = command
            .spawn()
            .map_err(|error| GitError::process_spawn(&invocation.program, &error))?;
        let stdout = child.stdout.take().ok_or_else(|| {
            GitError::new(
                GitErrorCategory::Internal,
                "Git did not provide a standard output pipe.",
                "stdout pipe was unavailable",
                false,
                None,
            )
        })?;
        let stderr = child.stderr.take().ok_or_else(|| {
            GitError::new(
                GitErrorCategory::Internal,
                "Git did not provide a standard error pipe.",
                "stderr pipe was unavailable",
                false,
                None,
            )
        })?;
        let stdin = child.stdin.take();
        let input = invocation.stdin;
        let policy = invocation.output_policy.clone();

        let (stdout_result, stderr_result, stdin_result) = tokio::join!(
            read_pipe(stdout, &policy),
            read_pipe(stderr, &policy),
            write_stdin(stdin, input),
        );
        let status = child.wait().await.map_err(|error| {
            GitError::new(
                GitErrorCategory::ProcessFailed,
                "Git did not finish cleanly.",
                error.to_string(),
                true,
                None,
            )
        })?;

        if let Err(error) = stdin_result
            && error.kind() != io::ErrorKind::BrokenPipe
        {
            return Err(GitError::new(
                GitErrorCategory::ProcessFailed,
                "Git could not receive its input.",
                error.to_string(),
                true,
                status.code(),
            ));
        }

        let stdout = stdout_result.map_err(|error| io_error("stdout", error))?;
        let stderr = stderr_result.map_err(|error| io_error("stderr", error))?;
        if stdout.exceeded || stderr.exceeded {
            return Err(GitError::new(
                GitErrorCategory::OutputOverflow,
                "Git returned more output than the configured limit.",
                format!(
                    "captured output exceeded {:?} policy",
                    invocation.output_policy
                ),
                false,
                status.code(),
            ));
        }
        if !status.success() {
            return Err(GitError::from_stderr(
                GitErrorCategory::ProcessFailed,
                "Git reported an error.",
                &stderr.bytes,
                false,
                status.code(),
            ));
        }

        Ok(ProcessOutput {
            stdout: stdout.bytes,
            stderr: stderr.bytes,
            exit_code: status.code(),
        })
    }
}

impl Default for ProcessGitRunner {
    fn default() -> Self {
        Self::new()
    }
}

async fn read_pipe<R>(mut pipe: R, policy: &OutputPolicy) -> io::Result<ReadResult>
where
    R: AsyncRead + Unpin,
{
    let limit = match policy {
        OutputPolicy::Capture { max_bytes } => *max_bytes,
        OutputPolicy::Stream { max_chunk_bytes } => *max_chunk_bytes,
    };
    let mut bytes = Vec::with_capacity(limit.min(8192));
    let mut buffer = [0_u8; 8192];
    let mut exceeded = false;

    loop {
        let read = pipe.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        let remaining = limit.saturating_sub(bytes.len());
        let retained = remaining.min(read);
        bytes.extend_from_slice(&buffer[..retained]);
        exceeded |= retained < read;
    }

    Ok(ReadResult { bytes, exceeded })
}

async fn write_stdin(mut stdin: Option<ChildStdin>, input: Option<Vec<u8>>) -> io::Result<()> {
    if let (Some(stdin), Some(input)) = (stdin.as_mut(), input) {
        stdin.write_all(&input).await?;
    }
    drop(stdin);
    Ok(())
}

fn io_error(stream: &str, error: io::Error) -> GitError {
    GitError::new(
        GitErrorCategory::ProcessFailed,
        "Git output could not be read.",
        format!("{stream}: {error}"),
        true,
        None,
    )
}
