mod support;

use std::fs;

use support::TestRepo;

#[test]
fn status_01_committed_repository_has_clean_porcelain_status() {
    let repo = TestRepo::new();
    repo.write("hello.txt", "hello\n")
        .expect("wrote hello file");
    repo.commit_all("Add hello");

    let status = repo.git(["status", "--porcelain"]);

    assert!(
        status.stdout.is_empty(),
        "expected a clean repository\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&status.stdout),
        String::from_utf8_lossy(&status.stderr),
    );
}

#[test]
fn commit_all_ignores_global_gpg_signing_configuration() {
    let global_config =
        tempfile::NamedTempFile::new().expect("created temporary global Git config");
    fs::write(
        global_config.path(),
        "[commit]\n\tgpgSign = true\n[user]\n\tsigningKey = branchline-test-missing-key\n",
    )
    .expect("configured required commit signing without a key");
    let repo = TestRepo::with_global_config(global_config.path());

    repo.write("hello.txt", "hello\n")
        .expect("wrote hello file");
    repo.commit_all("Add hello without signing");

    assert!(repo.git(["status", "--porcelain"]).stdout.is_empty());
}

#[test]
fn write_rejects_parent_directory_components() {
    let repo = TestRepo::new();

    let error = repo
        .write("../outside.txt", "outside\n")
        .expect_err("parent-directory path must be rejected");

    assert!(error.contains("relative path"), "unexpected error: {error}");
}

#[test]
fn write_rejects_absolute_paths() {
    let repo = TestRepo::new();
    let outside_path = repo
        .path()
        .parent()
        .expect("test repository has a parent directory")
        .join("outside.txt");

    let error = repo
        .write(&outside_path, "outside\n")
        .expect_err("absolute path must be rejected");

    assert!(error.contains("relative path"), "unexpected error: {error}");
}

#[test]
fn bare_remote_creates_valid_bare_git_repository() {
    let remote = TestRepo::bare_remote();
    let repo = TestRepo::new();
    repo.write("remote_test.txt", "remote test\n")
        .expect("wrote remote test file");
    repo.commit_all("Add remote test file");
    repo.git([
        "remote",
        "add",
        "origin",
        remote.path().to_str().expect("valid path"),
    ]);
    let push_output = repo.git(["push", "origin", "HEAD"]);
    assert!(push_output.status.success());
}
