use std::{
    ffi::OsStr,
    fs,
    path::Path,
    process::{Command, Output},
};

use tempfile::{TempDir, tempdir};

pub struct TestRepo {
    directory: TempDir,
}

impl TestRepo {
    pub fn new() -> Self {
        let repo = Self {
            directory: tempdir().expect("created temporary Git repository directory"),
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

    pub fn write(&self, relative_path: impl AsRef<Path>, contents: impl AsRef<[u8]>) {
        let path = self.path().join(relative_path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .unwrap_or_else(|error| panic!("failed to create {}: {error}", parent.display()));
        }
        fs::write(&path, contents)
            .unwrap_or_else(|error| panic!("failed to write {}: {error}", path.display()));
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
        let output = Command::new("git")
            .args(&args)
            .current_dir(self.path())
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
        self.git(["commit", "--quiet", "-m", message]);
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
