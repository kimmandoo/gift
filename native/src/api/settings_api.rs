use std::{path::PathBuf, sync::OnceLock};

use tokio::sync::Mutex;

use crate::{
    domain::GitInstallation, error::GitError, service::git_installation::GitInstallationService,
};

fn global_service() -> &'static Mutex<GitInstallationService> {
    static SERVICE: OnceLock<Mutex<GitInstallationService>> = OnceLock::new();
    SERVICE.get_or_init(|| Mutex::new(GitInstallationService::new(None)))
}

pub async fn get_git_installation() -> Result<GitInstallation, GitError> {
    let mut service = global_service().lock().await;
    service.get_or_discover().await
}

pub async fn configure_git_path(path: String) -> Result<GitInstallation, GitError> {
    let mut service = global_service().lock().await;
    service.configure_git_path(PathBuf::from(path)).await
}
