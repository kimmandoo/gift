use std::{path::Path, path::PathBuf, sync::Arc};

use crate::{
    api::settings_api::get_git_installation, domain::repository::RepositoryOpened, error::GitError,
    service::repository_service::RepositoryService, state::AppState,
};

fn global_state() -> &'static Arc<AppState> {
    static STATE: std::sync::OnceLock<Arc<AppState>> = std::sync::OnceLock::new();
    STATE.get_or_init(|| Arc::new(AppState::new()))
}

pub async fn open_repository(path: String) -> Result<RepositoryOpened, GitError> {
    let installation = get_git_installation().await?;
    let service = RepositoryService::new(
        PathBuf::from(installation.executable_path),
        Arc::clone(global_state()),
    );
    service.open_repository(Path::new(&path)).await
}
