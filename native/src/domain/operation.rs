#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitOperationKind {
    Read,
    Mutation,
    Remote,
}
