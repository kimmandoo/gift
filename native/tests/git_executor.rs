use std::{
    ffi::OsString,
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use native::{
    domain::operation::GitOperationKind,
    error::GitErrorCategory,
    executor::redaction::redact_remote,
    executor::{GitInvocation, OutputPolicy, ProcessGitRunner},
    service::git_installation::{GitInstallationService, GitVersion, parse_git_version},
};
use tempfile::tempdir;

#[test]
fn parses_vendor_suffixed_git_version() {
    let version = parse_git_version(b"git version 2.51.0.windows.1\n").expect("valid Git version");

    assert_eq!(version, GitVersion::new(2, 51, 0, "windows.1"));
}

#[test]
fn rejects_git_versions_below_the_minimum() {
    let error = GitVersion::new(2, 34, 9, "")
        .ensure_supported()
        .unwrap_err();

    assert_eq!(error.category, GitErrorCategory::UnsupportedGitVersion);
}

#[test]
fn redacts_credentials_from_remote_urls() {
    assert_eq!(
        redact_remote("https://alice:secret@example.com/org/repo.git"),
        "https://***@example.com/org/repo.git"
    );
}

#[tokio::test]
async fn executes_git_with_an_exact_path_containing_spaces_and_ampersand() {
    let fixture = tempdir().expect("created fixture directory");
    let repository = fixture.path().join("repo with spaces & ampersand");
    fs::create_dir(&repository).expect("created repository directory");
    init_repository(&repository);

    let invocation = GitInvocation::new(
        git_executable(),
        args(["rev-parse", "--show-toplevel"]),
        repository.clone(),
        None,
        GitOperationKind::Read,
        OutputPolicy::capture_default(),
    );
    let output = ProcessGitRunner::new()
        .run(invocation)
        .await
        .expect("executed Git without a shell");

    let reported_root = PathBuf::from(String::from_utf8_lossy(&output.stdout).trim());
    assert_eq!(
        reported_root
            .canonicalize()
            .expect("reported canonical root"),
        repository.canonicalize().expect("canonical root")
    );
}

#[tokio::test]
async fn reports_capture_overflow_without_retaining_unbounded_output() {
    let fixture = tempdir().expect("created fixture directory");
    init_repository(fixture.path());
    let blob = write_blob(fixture.path());
    let batch_input = format!("{blob}\n").repeat(256).into_bytes();
    let invocation = GitInvocation::new(
        git_executable(),
        args(["cat-file", "--batch"]),
        fixture.path().to_path_buf(),
        Some(batch_input),
        GitOperationKind::Read,
        OutputPolicy::Capture { max_bytes: 64 },
    );

    let error = ProcessGitRunner::new()
        .run(invocation)
        .await
        .expect_err("large capture must be rejected");

    assert_eq!(error.category, GitErrorCategory::OutputOverflow);
}

#[tokio::test]
async fn discovers_git_from_path_and_preserves_previous_installation_on_failure() {
    let git_path = git_executable();
    let mut service = GitInstallationService::new(None);
    let discovered = service
        .get_or_discover()
        .await
        .expect("discovered Git from PATH");
    assert_eq!(discovered.executable_path, git_path.to_string_lossy());

    let previous = service.current().expect("cached installation");
    let missing_path = tempdir()
        .expect("created invalid configuration directory")
        .path()
        .join("missing-git");
    let error = service
        .configure_git_path(missing_path)
        .await
        .expect_err("missing Git path must be rejected");

    assert_eq!(error.category, GitErrorCategory::InvalidGitPath);
    assert_eq!(service.current(), Some(previous));
}

#[tokio::test]
async fn validates_an_explicit_git_path_before_path_fallback() {
    let git_path = git_executable();
    let mut service = GitInstallationService::new(Some(git_path.clone()));

    let installation = service
        .get_or_discover()
        .await
        .expect("validated explicit Git path");

    assert_eq!(installation.executable_path, git_path.to_string_lossy());
}

fn args<const N: usize>(values: [&str; N]) -> Vec<OsString> {
    values.into_iter().map(OsString::from).collect()
}

fn init_repository(path: &Path) {
    let output = Command::new("git")
        .args(["init", "--quiet"])
        .current_dir(path)
        .output()
        .expect("started Git");
    assert!(
        output.status.success(),
        "git init failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn write_blob(path: &Path) -> String {
    let mut child = Command::new("git")
        .args(["hash-object", "-w", "--stdin"])
        .current_dir(path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("started Git hash-object");
    use std::io::Write;
    child
        .stdin
        .take()
        .expect("Git stdin")
        .write_all(b"payload\n")
        .expect("wrote blob");
    let output = child.wait_with_output().expect("completed hash-object");
    assert!(output.status.success());
    String::from_utf8(output.stdout)
        .expect("ASCII blob hash")
        .trim()
        .to_owned()
}

fn git_executable() -> PathBuf {
    std::env::split_paths(&std::env::var_os("PATH").expect("PATH is configured"))
        .flat_map(|directory| [directory.join("git"), directory.join("git.exe")])
        .find(|candidate| candidate.is_file())
        .expect("Git executable is available on PATH")
}
