pub mod operation;
pub mod repository;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitInstallation {
    pub executable_path: String,
    pub version: String,
}

pub use repository::{RepositoryId, RepositoryOpened};
