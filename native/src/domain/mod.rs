pub mod operation;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitInstallation {
    pub executable_path: String,
    pub version: String,
}
