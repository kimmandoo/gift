use std::{collections::HashMap, path::PathBuf, sync::Arc};

use tokio::sync::{Mutex, RwLock};

use crate::{
    domain::repository::{RepositoryId, RepositoryOpened},
    error::{GitError, GitErrorCategory},
};

pub struct AppState {
    repositories: RwLock<HashMap<RepositoryId, RepositoryRecord>>,
}

#[derive(Debug, Clone)]
pub struct RepositoryHandle {
    pub root: PathBuf,
    pub generation: u64,
    pub mutation_lock: Arc<Mutex<()>>,
}

#[derive(Clone)]
struct RepositoryRecord {
    root: PathBuf,
    generation: u64,
    mutation_lock: Arc<Mutex<()>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            repositories: RwLock::new(HashMap::new()),
        }
    }

    pub async fn register(&self, root: PathBuf) -> RepositoryOpened {
        let repository_id = RepositoryId::new();
        let record = RepositoryRecord {
            root: root.clone(),
            generation: 0,
            mutation_lock: Arc::new(Mutex::new(())),
        };
        self.repositories
            .write()
            .await
            .insert(repository_id.clone(), record);

        RepositoryOpened {
            repository_id,
            root: root.to_string_lossy().into_owned(),
        }
    }

    pub async fn lookup(&self, repository_id: &RepositoryId) -> Result<RepositoryHandle, GitError> {
        let record = self
            .repositories
            .read()
            .await
            .get(repository_id)
            .cloned()
            .ok_or_else(|| {
                GitError::new(
                    GitErrorCategory::InvalidOpaqueId,
                    "The repository handle is not valid for this session.",
                    "repository ID was not found in this registry",
                    false,
                    None,
                )
            })?;

        if !record.root.is_dir() {
            return Err(GitError::new(
                GitErrorCategory::RepositoryMoved,
                "The repository folder is no longer available.",
                "registered repository root does not exist",
                true,
                None,
            ));
        }

        Ok(RepositoryHandle {
            root: record.root,
            generation: record.generation,
            mutation_lock: record.mutation_lock,
        })
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}
