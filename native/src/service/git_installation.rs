use std::{
    env, fmt, fs,
    path::{Path, PathBuf},
};

use crate::{
    domain::{GitInstallation, operation::GitOperationKind},
    error::{GitError, GitErrorCategory},
    executor::{GitInvocation, OutputPolicy, ProcessGitRunner},
};

const MINIMUM_GIT_VERSION: (u64, u64, u64) = (2, 35, 0);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitVersion {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
    pub suffix: String,
}

impl GitVersion {
    pub fn new(major: u64, minor: u64, patch: u64, suffix: &str) -> Self {
        Self {
            major,
            minor,
            patch,
            suffix: suffix.to_owned(),
        }
    }

    pub fn ensure_supported(&self) -> Result<(), GitError> {
        if (self.major, self.minor, self.patch) < MINIMUM_GIT_VERSION {
            return Err(GitError::new(
                GitErrorCategory::UnsupportedGitVersion,
                "Git 2.35 or newer is required.",
                format!("detected Git {self}"),
                false,
                None,
            ));
        }
        Ok(())
    }
}

impl fmt::Display for GitVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}.{}.{}", self.major, self.minor, self.patch)?;
        if !self.suffix.is_empty() {
            write!(formatter, ".{}", self.suffix)?;
        }
        Ok(())
    }
}

pub fn parse_git_version(output: &[u8]) -> Result<GitVersion, GitError> {
    let text = String::from_utf8_lossy(output);
    let version_text = text
        .lines()
        .find_map(|line| line.strip_prefix("git version "))
        .and_then(|line| line.split_whitespace().next())
        .ok_or_else(|| {
            GitError::new(
                GitErrorCategory::ParseFailure,
                "Git returned an unrecognized version.",
                "expected output beginning with git version",
                false,
                None,
            )
        })?;
    let mut components = version_text.split('.');
    let major = parse_version_component(components.next(), version_text)?;
    let minor = parse_version_component(components.next(), version_text)?;
    let patch = parse_version_component(components.next(), version_text)?;
    let suffix = components.collect::<Vec<_>>().join(".");
    Ok(GitVersion {
        major,
        minor,
        patch,
        suffix,
    })
}

pub struct GitInstallationService {
    runner: ProcessGitRunner,
    configured_path: Option<PathBuf>,
    installation: Option<InstalledGit>,
}

#[derive(Clone)]
struct InstalledGit {
    path: PathBuf,
    version: GitVersion,
}

impl GitInstallationService {
    pub fn new(configured_path: Option<PathBuf>) -> Self {
        Self {
            runner: ProcessGitRunner::new(),
            configured_path,
            installation: None,
        }
    }

    pub fn current(&self) -> Option<GitInstallation> {
        self.installation.as_ref().map(InstalledGit::to_public)
    }

    pub async fn get_or_discover(&mut self) -> Result<GitInstallation, GitError> {
        if let Some(installation) = self.current() {
            return Ok(installation);
        }
        let path = match self.configured_path.clone() {
            Some(path) => canonicalize_git_path(&path)?,
            None => find_git_on_path()?,
        };
        let installation = self.validate(path).await?;
        self.installation = Some(installation);
        Ok(self
            .current()
            .expect("validated Git installation is cached"))
    }

    pub async fn configure_git_path(&mut self, path: PathBuf) -> Result<GitInstallation, GitError> {
        let canonical_path = canonicalize_git_path(&path)?;
        let installation = self.validate(canonical_path).await?;
        self.configured_path = Some(installation.path.clone());
        self.installation = Some(installation);
        Ok(self
            .current()
            .expect("validated Git installation is cached"))
    }

    async fn validate(&self, path: PathBuf) -> Result<InstalledGit, GitError> {
        let cwd = env::current_dir().map_err(|error| {
            GitError::new(
                GitErrorCategory::Internal,
                "The current directory could not be determined.",
                error.to_string(),
                true,
                None,
            )
        })?;
        let invocation = GitInvocation::new(
            path.clone(),
            vec!["--version".into()],
            cwd,
            None,
            GitOperationKind::Read,
            OutputPolicy::capture_default(),
        );
        let output = self.runner.run(invocation).await?;
        let version = parse_git_version(&output.stdout)?;
        version.ensure_supported()?;
        Ok(InstalledGit { path, version })
    }
}

impl InstalledGit {
    fn to_public(&self) -> GitInstallation {
        GitInstallation {
            executable_path: display_path(&self.path),
            version: self.version.to_string(),
        }
    }
}

fn parse_version_component(component: Option<&str>, version: &str) -> Result<u64, GitError> {
    component
        .ok_or_else(|| invalid_version(version))?
        .parse()
        .map_err(|_| invalid_version(version))
}

fn invalid_version(version: &str) -> GitError {
    GitError::new(
        GitErrorCategory::ParseFailure,
        "Git returned an unrecognized version.",
        format!("invalid semantic version: {version}"),
        false,
        None,
    )
}

fn canonicalize_git_path(path: &Path) -> Result<PathBuf, GitError> {
    if !path.is_file() {
        return Err(GitError::invalid_git_path(
            path,
            &std::io::Error::new(std::io::ErrorKind::NotFound, "file does not exist"),
        ));
    }
    fs::canonicalize(path).map_err(|error| GitError::invalid_git_path(path, &error))
}

fn display_path(path: &Path) -> String {
    let display = path.to_string_lossy();
    #[cfg(windows)]
    if let Some(display) = display.strip_prefix(r"\\?\") {
        return display.to_owned();
    }
    display.into_owned()
}

fn find_git_on_path() -> Result<PathBuf, GitError> {
    let path = env::var_os("PATH").ok_or_else(|| {
        GitError::new(
            GitErrorCategory::GitNotFound,
            "Git could not be found on PATH.",
            "PATH is not configured",
            true,
            None,
        )
    })?;
    for directory in env::split_paths(&path) {
        for name in git_executable_names() {
            let candidate = directory.join(name);
            if candidate.is_file() {
                return fs::canonicalize(&candidate)
                    .map_err(|error| GitError::invalid_git_path(&candidate, &error));
            }
        }
    }
    Err(GitError::new(
        GitErrorCategory::GitNotFound,
        "Git could not be found on PATH.",
        "no Git executable was present in PATH entries",
        true,
        None,
    ))
}

#[cfg(windows)]
fn git_executable_names() -> [&'static str; 2] {
    ["git.exe", "git"]
}

#[cfg(not(windows))]
fn git_executable_names() -> [&'static str; 1] {
    ["git"]
}
