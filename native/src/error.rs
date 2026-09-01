use std::{fmt, io, path::Path};

use crate::executor::redaction::redact_bytes;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitErrorCategory {
    GitNotFound,
    UnsupportedGitVersion,
    NotRepository,
    RepositoryMoved,
    InvalidRevision,
    DetachedHead,
    UnbornBranch,
    DirtyWorktree,
    MergeConflict,
    NonFastForward,
    AuthenticationRequired,
    PermissionDenied,
    NetworkUnavailable,
    HookRejected,
    Cancelled,
    Timeout,
    StaleConfirmation,
    InvalidOpaqueId,
    StaleOpaqueId,
    ParseFailure,
    UnsupportedRepositoryState,
    Internal,
    InvalidGitPath,
    ProcessSpawnFailed,
    ProcessFailed,
    OutputOverflow,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitError {
    pub category: GitErrorCategory,
    pub user_message: String,
    pub diagnostic: String,
    pub retryable: bool,
    pub exit_code: Option<i32>,
}

impl GitError {
    pub fn new(
        category: GitErrorCategory,
        user_message: impl Into<String>,
        diagnostic: impl Into<String>,
        retryable: bool,
        exit_code: Option<i32>,
    ) -> Self {
        Self {
            category,
            user_message: user_message.into(),
            diagnostic: diagnostic.into(),
            retryable,
            exit_code,
        }
    }

    pub fn from_stderr(
        category: GitErrorCategory,
        user_message: impl Into<String>,
        stderr: &[u8],
        retryable: bool,
        exit_code: Option<i32>,
    ) -> Self {
        Self::new(
            category,
            user_message,
            redact_bytes(stderr),
            retryable,
            exit_code,
        )
    }

    pub fn invalid_git_path(path: &Path, error: &io::Error) -> Self {
        Self::new(
            GitErrorCategory::InvalidGitPath,
            "The selected Git executable could not be used.",
            format!("{}: {error}", path.display()),
            true,
            None,
        )
    }

    pub fn process_spawn(program: &Path, error: &io::Error) -> Self {
        let category = if error.kind() == io::ErrorKind::NotFound {
            GitErrorCategory::GitNotFound
        } else {
            GitErrorCategory::ProcessSpawnFailed
        };
        let message = if category == GitErrorCategory::GitNotFound {
            "Git could not be found."
        } else {
            "Git could not be started."
        };
        Self::new(
            category,
            message,
            format!("{}: {error}", program.display()),
            true,
            None,
        )
    }
}

impl fmt::Display for GitError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.category, self.user_message)
    }
}

impl std::error::Error for GitError {}

impl fmt::Display for GitErrorCategory {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}
