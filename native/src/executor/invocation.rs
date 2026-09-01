use std::{ffi::OsString, path::PathBuf};

use crate::domain::operation::GitOperationKind;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OutputPolicy {
    Capture { max_bytes: usize },
    Stream { max_chunk_bytes: usize },
}

impl OutputPolicy {
    pub const DEFAULT_CAPTURE_BYTES: usize = 16 * 1024 * 1024;

    pub const fn capture_default() -> Self {
        Self::Capture {
            max_bytes: Self::DEFAULT_CAPTURE_BYTES,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitInvocation {
    pub program: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: PathBuf,
    pub stdin: Option<Vec<u8>>,
    pub kind: GitOperationKind,
    pub output_policy: OutputPolicy,
}

impl GitInvocation {
    pub fn new(
        program: PathBuf,
        args: Vec<OsString>,
        cwd: PathBuf,
        stdin: Option<Vec<u8>>,
        kind: GitOperationKind,
        output_policy: OutputPolicy,
    ) -> Self {
        Self {
            program,
            args,
            cwd,
            stdin,
            kind,
            output_policy,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessOutput {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub exit_code: Option<i32>,
}
