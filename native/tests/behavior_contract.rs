mod support;

use support::TestRepo;

#[test]
fn status_01_committed_repository_has_clean_porcelain_status() {
    let repo = TestRepo::new();
    repo.write("hello.txt", "hello\n");
    repo.commit_all("Add hello");

    let status = repo.git(["status", "--porcelain"]);

    assert!(
        status.stdout.is_empty(),
        "expected a clean repository\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&status.stdout),
        String::from_utf8_lossy(&status.stderr),
    );
}
