#[allow(dead_code)]
mod support;

use std::{fs, path::PathBuf, sync::Arc};

use native::{
    error::GitErrorCategory, service::repository_service::RepositoryService, state::AppState,
};
use support::TestRepo;
use tempfile::tempdir;

#[tokio::test]
async fn opens_nested_directory_with_canonical_root_and_opaque_id() {
    let repository = TestRepo::new();
    let nested = repository.path().join("src").join("nested");
    fs::create_dir_all(&nested).expect("created nested directory");
    let state = Arc::new(AppState::new());
    let service = RepositoryService::new(git_executable(), Arc::clone(&state));

    let opened = service
        .open_repository(&nested)
        .await
        .expect("opened nested repository");

    assert_eq!(
        PathBuf::from(&opened.root),
        repository.path().canonicalize().unwrap()
    );
    assert!(state.lookup(&opened.repository_id).await.is_ok());
    assert!(!opened.repository_id.value.is_empty());
}

#[tokio::test]
async fn rejects_a_directory_that_is_not_a_repository() {
    let directory = tempdir().expect("created non-repository directory");
    let state = Arc::new(AppState::new());
    let service = RepositoryService::new(git_executable(), state);

    let error = service
        .open_repository(directory.path())
        .await
        .expect_err("non-repository must be rejected");

    assert_eq!(error.category, GitErrorCategory::NotRepository);
}

#[tokio::test]
async fn rejects_bare_repositories_for_workspace_opening() {
    let repository = TestRepo::bare_remote();
    let state = Arc::new(AppState::new());
    let service = RepositoryService::new(git_executable(), state);

    let error = service
        .open_repository(repository.path())
        .await
        .expect_err("bare repositories must be rejected");

    assert_eq!(error.category, GitErrorCategory::UnsupportedRepositoryState);
}

#[tokio::test]
async fn reports_repository_moved_when_registered_root_disappears() {
    let repository = TestRepo::new();
    let state = Arc::new(AppState::new());
    let service = RepositoryService::new(git_executable(), Arc::clone(&state));
    let opened = service
        .open_repository(repository.path())
        .await
        .expect("opened repository");

    drop(repository);

    let error = state
        .lookup(&opened.repository_id)
        .await
        .expect_err("deleted repository must not resolve");
    assert_eq!(error.category, GitErrorCategory::RepositoryMoved);
}

#[tokio::test]
async fn does_not_resolve_an_id_in_a_different_registry() {
    let repository = TestRepo::new();
    let first_state = Arc::new(AppState::new());
    let service = RepositoryService::new(git_executable(), Arc::clone(&first_state));
    let opened = service
        .open_repository(repository.path())
        .await
        .expect("opened repository");
    let second_state = AppState::new();

    let error = second_state
        .lookup(&opened.repository_id)
        .await
        .expect_err("opaque IDs must be registry-local");
    assert_eq!(error.category, GitErrorCategory::InvalidOpaqueId);
}

fn git_executable() -> PathBuf {
    std::env::split_paths(&std::env::var_os("PATH").expect("PATH is configured"))
        .flat_map(|directory| [directory.join("git"), directory.join("git.exe")])
        .find(|candidate| candidate.is_file())
        .expect("Git executable is available on PATH")
}
