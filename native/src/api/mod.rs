pub mod settings_api;

pub use settings_api::{configure_git_path, get_git_installation};

pub struct Health {
    pub product: String,
    pub core_version: String,
}

pub fn health() -> Health {
    Health {
        product: "Branchline".to_owned(),
        core_version: env!("CARGO_PKG_VERSION").to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::health;

    #[test]
    fn health_exposes_product_and_core_version() {
        let result = health();
        assert_eq!(result.product, "Branchline");
        assert_eq!(result.core_version, env!("CARGO_PKG_VERSION"));
    }
}
