use std::{
    ffi::OsStr,
    fs,
    path::{Component, Path, PathBuf},
    process::{Command, Output},
};

use tempfile::{TempDir, tempdir};

pub struct TestRepo {
    directory: TempDir,
    global_config: Option<PathBuf>,
}

impl TestRepo {
    pub fn new() -> Self {
        Self::new_with_global_config(None)
    }

    pub fn with_global_config(global_config: impl AsRef<Path>) -> Self {
        Self::new_with_global_config(Some(global_config.as_ref().to_path_buf()))
    }

    fn new_with_global_config(global_config: Option<PathBuf>) -> Self {
        let repo = Self {
            directory: tempdir().expect("created temporary Git repository directory"),
            global_config,
        };

        repo.git(["init", "--quiet"]);
        repo.git(["config", "--local", "user.name", "Branchline Test"]);
        repo.git([
            "config",
            "--local",
            "user.email",
            "branchline-test@example.invalid",
        ]);
        repo
    }

    pub fn path(&self) -> &Path {
        self.directory.path()
    }

    pub fn write(
        &self,
        relative_path: impl AsRef<Path>,
        contents: impl AsRef<[u8]>,
    ) -> Result<(), String> {
        let relative_path = relative_path.as_ref();
        validate_relative_path(relative_path)?;

        let path = self.path().join(relative_path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
        }
        fs::write(&path, contents)
            .map_err(|error| format!("failed to write {}: {error}", path.display()))
    }

    pub fn git<I, S>(&self, args: I) -> Output
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let args = args
            .into_iter()
            .map(|arg| arg.as_ref().to_owned())
            .collect::<Vec<_>>();
        let mut command = Command::new("git");
        command.args(&args).current_dir(self.path());
        if let Some(global_config) = &self.global_config {
            command.env("GIT_CONFIG_GLOBAL", global_config);
        }
        let output = command
            .output()
            .unwrap_or_else(|error| panic!("failed to execute git {args:?}: {error}"));

        assert!(
            output.status.success(),
            "git {args:?} failed with {}\nstdout:\n{}\nstderr:\n{}",
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        );
        output
    }

    pub fn commit_all(&self, message: &str) {
        self.git(["add", "--all"]);
        self.git(["commit", "--quiet", "--no-gpg-sign", "-m", message]);
    }

    #[allow(dead_code)]
    pub fn bare_remote() -> TempDir {
        let remote = tempdir().expect("created temporary bare Git remote directory");
        let output = Command::new("git")
            .args([
                OsStr::new("init"),
                OsStr::new("--bare"),
                remote.path().as_os_str(),
            ])
            .output()
            .unwrap_or_else(|error| panic!("failed to execute git init --bare: {error}"));

        assert!(
            output.status.success(),
            "git init --bare failed with {}\nstdout:\n{}\nstderr:\n{}",
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        );
        remote
    }
}

fn validate_relative_path(relative_path: &Path) -> Result<(), String> {
    if relative_path.is_absolute()
        || relative_path.components().any(|component| {
            matches!(
                component,
                Component::Prefix(_) | Component::RootDir | Component::ParentDir
            )
        })
    {
        return Err(format!(
            "test repository path must be a relative path without a prefix, root, or parent directory: {}",
            relative_path.display()
        ));
    }

    Ok(())
}
