use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RepositoryId {
    pub value: String,
}

impl RepositoryId {
    pub fn new() -> Self {
        Self {
            value: Uuid::new_v4().to_string(),
        }
    }
}

impl Default for RepositoryId {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepositoryOpened {
    pub repository_id: RepositoryId,
    pub root: String,
}
