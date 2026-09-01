use std::{fs, path::Path, path::PathBuf, sync::Arc};

use crate::{
    domain::{operation::GitOperationKind, repository::RepositoryOpened},
    error::{GitError, GitErrorCategory},
    executor::{GitInvocation, OutputPolicy, ProcessGitRunner},
    state::AppState,
};

pub struct RepositoryService {
    git_path: PathBuf,
    runner: ProcessGitRunner,
    state: Arc<AppState>,
}

impl RepositoryService {
    pub fn new(git_path: PathBuf, state: Arc<AppState>) -> Self {
        Self {
            git_path,
            runner: ProcessGitRunner::new(),
            state,
        }
    }

    pub async fn open_repository(&self, path: &Path) -> Result<RepositoryOpened, GitError> {
        let working_directory = fs::canonicalize(path).map_err(|error| {
            GitError::new(
                GitErrorCategory::NotRepository,
                "The selected folder is not a Git repository.",
                format!("could not resolve selected folder: {error}"),
                false,
                None,
            )
        })?;

        let bare_output = self
            .run_git(&working_directory, &["rev-parse", "--is-bare-repository"])
            .await
            .map_err(as_not_repository)?;
        let bare = String::from_utf8_lossy(&bare_output.stdout)
            .trim()
            .to_owned();
        match bare.as_str() {
            "true" => {
                return Err(GitError::new(
                    GitErrorCategory::UnsupportedRepositoryState,
                    "Bare repositories cannot be opened in the workspace.",
                    "git rev-parse --is-bare-repository returned true",
                    false,
                    None,
                ));
            }
            "false" => {}
            _ => {
                return Err(GitError::new(
                    GitErrorCategory::ParseFailure,
                    "Git returned an unrecognized repository state.",
                    format!("unexpected bare-repository result: {bare}"),
                    false,
                    None,
                ));
            }
        }

        let root_output = self
            .run_git(&working_directory, &["rev-parse", "--show-toplevel"])
            .await
            .map_err(as_not_repository)?;
        let reported_root = String::from_utf8_lossy(&root_output.stdout)
            .trim()
            .to_owned();
        if reported_root.is_empty() {
            return Err(GitError::new(
                GitErrorCategory::ParseFailure,
                "Git returned an empty repository root.",
                "rev-parse --show-toplevel returned no path",
                false,
                None,
            ));
        }
        let canonical_root = fs::canonicalize(PathBuf::from(reported_root)).map_err(|error| {
            GitError::new(
                GitErrorCategory::RepositoryMoved,
                "The repository folder is no longer available.",
                format!("could not resolve Git repository root: {error}"),
                true,
                None,
            )
        })?;

        Ok(self.state.register(canonical_root).await)
    }

    async fn run_git(
        &self,
        cwd: &Path,
        args: &[&str],
    ) -> Result<crate::executor::ProcessOutput, GitError> {
        let invocation = GitInvocation::new(
            self.git_path.clone(),
            args.iter().map(|arg| (*arg).into()).collect(),
            cwd.to_path_buf(),
            None,
            GitOperationKind::Read,
            OutputPolicy::capture_default(),
        );
        self.runner.run(invocation).await
    }
}

fn as_not_repository(error: GitError) -> GitError {
    if error.category == GitErrorCategory::ProcessFailed {
        GitError::new(
            GitErrorCategory::NotRepository,
            "The selected folder is not a Git repository.",
            error.diagnostic,
            false,
            error.exit_code,
        )
    } else {
        error
    }
}
