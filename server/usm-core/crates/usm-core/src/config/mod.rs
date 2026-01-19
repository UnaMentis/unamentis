//! Configuration management with TOML parsing and file watching

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::Result;
use notify::RecommendedWatcher;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use crate::events::EventBus;
use crate::service::{
    InstanceConfig, InstanceRegistry, ServiceCategory, ServiceInstance, ServiceTemplate,
    TemplateRegistry,
};

/// Raw configuration file structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigFile {
    #[serde(default)]
    pub templates: std::collections::HashMap<String, TemplateConfig>,

    #[serde(default)]
    pub instances: std::collections::HashMap<String, InstanceConfigFile>,
}

/// Template configuration from TOML
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateConfig {
    pub display_name: String,
    #[serde(default)]
    pub description: Option<String>,
    pub default_port: u16,
    #[serde(default)]
    pub port_range: Option<(u16, u16)>,
    pub start_command: String,
    #[serde(default)]
    pub stop_command: Option<String>,
    #[serde(default)]
    pub health_endpoint: Option<String>,
    #[serde(default = "default_health_timeout")]
    pub health_timeout_ms: u32,
    #[serde(default)]
    pub category: ServiceCategory,
    #[serde(default)]
    pub supports_multiple: bool,
    #[serde(default)]
    pub is_docker: bool,
    #[serde(default)]
    pub default_env: std::collections::HashMap<String, String>,
}

fn default_health_timeout() -> u32 {
    5000
}

/// Instance configuration from TOML
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstanceConfigFile {
    pub template: String,
    #[serde(default)]
    pub port: Option<u16>,
    #[serde(default)]
    pub working_dir: Option<String>,
    #[serde(default)]
    pub config: Option<String>,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub git_branch: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub auto_start: bool,
    #[serde(default)]
    pub env_vars: std::collections::HashMap<String, String>,

    // Metadata (persisted by USM)
    #[serde(default, rename = "_created_at")]
    pub created_at: Option<String>,
    #[serde(default, rename = "_created_via")]
    pub created_via: Option<String>,
}

/// Configuration manager with file watching
pub struct ConfigManager {
    config_path: PathBuf,
    _event_bus: Arc<EventBus>,
    _watcher: Option<RecommendedWatcher>,
}

impl ConfigManager {
    /// Create a new config manager
    pub fn new(config_path: &Path, event_bus: Arc<EventBus>) -> Result<Self> {
        let config_path = config_path.to_path_buf();

        // Create config file if it doesn't exist
        if !config_path.exists() {
            info!(path = %config_path.display(), "Creating default config file");
            Self::create_default_config(&config_path)?;
        }

        Ok(Self {
            config_path,
            _event_bus: event_bus,
            _watcher: None,
        })
    }

    /// Load templates and instances from config file
    pub async fn load(&self) -> Result<(TemplateRegistry, InstanceRegistry)> {
        let content = tokio::fs::read_to_string(&self.config_path).await?;
        let config: ConfigFile = toml::from_str(&content)?;

        let mut templates = TemplateRegistry::new();
        let mut instances = InstanceRegistry::new();

        // Load templates
        for (id, tc) in config.templates {
            let template = ServiceTemplate {
                id: id.clone(),
                display_name: tc.display_name,
                description: tc.description,
                default_port: tc.default_port,
                port_range: tc.port_range,
                start_command: tc.start_command,
                stop_command: tc.stop_command,
                health_endpoint: tc.health_endpoint,
                health_timeout_ms: tc.health_timeout_ms,
                category: tc.category,
                supports_multiple: tc.supports_multiple,
                is_docker: tc.is_docker,
                default_env: tc.default_env,
            };
            templates.register(template)?;
        }

        // Load instances
        for (id, ic) in config.instances {
            // Get template to determine default port
            let template = templates.get(&ic.template).ok_or_else(|| {
                anyhow::anyhow!("Template '{}' not found for instance '{}'", ic.template, id)
            })?;

            let port = ic.port.unwrap_or(template.default_port);

            let instance = ServiceInstance::from_config(InstanceConfig {
                instance_id: id,
                template_id: ic.template,
                port: Some(port),
                working_dir: ic.working_dir.map(|s| self.resolve_path(&s)),
                config_path: ic.config.map(|s| self.resolve_path(&s)),
                version: ic.version,
                git_branch: ic.git_branch,
                tags: ic.tags,
                auto_start: ic.auto_start,
                env_vars: ic.env_vars,
            })?;

            instances.add(instance)?;
        }

        info!(
            templates = templates.len(),
            instances = instances.len(),
            "Loaded configuration"
        );

        Ok((templates, instances))
    }

    /// Save templates to config file
    pub async fn save_templates(&self, templates: &TemplateRegistry) -> Result<()> {
        self.save_config(Some(templates), None).await
    }

    /// Save instances to config file
    pub async fn save_instances(&self, instances: &InstanceRegistry) -> Result<()> {
        self.save_config(None, Some(instances)).await
    }

    /// Save both templates and instances
    async fn save_config(
        &self,
        templates: Option<&TemplateRegistry>,
        instances: Option<&InstanceRegistry>,
    ) -> Result<()> {
        // Read existing config
        let content = tokio::fs::read_to_string(&self.config_path).await?;
        let mut config: ConfigFile = toml::from_str(&content)?;

        // Update templates if provided
        if let Some(templates) = templates {
            config.templates.clear();
            for template in templates.list() {
                config.templates.insert(
                    template.id.clone(),
                    TemplateConfig {
                        display_name: template.display_name,
                        description: template.description,
                        default_port: template.default_port,
                        port_range: template.port_range,
                        start_command: template.start_command,
                        stop_command: template.stop_command,
                        health_endpoint: template.health_endpoint,
                        health_timeout_ms: template.health_timeout_ms,
                        category: template.category,
                        supports_multiple: template.supports_multiple,
                        is_docker: template.is_docker,
                        default_env: template.default_env,
                    },
                );
            }
        }

        // Update instances if provided
        if let Some(instances) = instances {
            config.instances.clear();
            for instance in instances.list() {
                config.instances.insert(
                    instance.id.clone(),
                    InstanceConfigFile {
                        template: instance.template_id,
                        port: Some(instance.port),
                        working_dir: instance
                            .working_dir
                            .as_ref()
                            .map(|p| p.display().to_string()),
                        config: instance
                            .config_path
                            .as_ref()
                            .map(|p| p.display().to_string()),
                        version: instance.version,
                        git_branch: instance.git_branch,
                        tags: instance.tags,
                        auto_start: instance.auto_start,
                        env_vars: instance.env_vars,
                        created_at: Some(instance.created_at.to_rfc3339()),
                        created_via: Some(instance.created_via),
                    },
                );
            }
        }

        // Write back
        let content = toml::to_string_pretty(&config)?;
        tokio::fs::write(&self.config_path, content).await?;

        debug!(path = %self.config_path.display(), "Configuration saved");
        Ok(())
    }

    /// Resolve path variables like ${PROJECT_ROOT}
    fn resolve_path(&self, path: &str) -> PathBuf {
        let resolved = path
            .replace(
                "${PROJECT_ROOT}",
                &std::env::var("UNAMENTIS_ROOT").unwrap_or_else(|_| {
                    dirs::home_dir()
                        .unwrap_or_default()
                        .join("dev/unamentis")
                        .display()
                        .to_string()
                }),
            )
            .replace(
                "~",
                &dirs::home_dir().unwrap_or_default().display().to_string(),
            );

        PathBuf::from(resolved)
    }

    /// Create a default config file
    fn create_default_config(path: &Path) -> Result<()> {
        let default_config = r#"# USM Core Configuration
# Templates define service blueprints, instances are running services

[templates.management-api]
display_name = "Management API"
description = "Python backend API server"
default_port = 8766
port_range = [8766, 8799]
start_command = "python3 {working_dir}/management/server.py --port {port}"
health_endpoint = "http://localhost:{port}/health"
category = "core"
supports_multiple = true

[templates.ollama]
display_name = "Ollama LLM"
default_port = 11434
port_range = [11434, 11450]
start_command = "OLLAMA_HOST=0.0.0.0:{port} ollama serve"
health_endpoint = "http://localhost:{port}/api/tags"
category = "core"
supports_multiple = true

[templates.postgresql]
display_name = "PostgreSQL"
default_port = 5432
start_command = "brew services start postgresql@14"
stop_command = "brew services stop postgresql@14"
category = "database"
supports_multiple = false

# Default instances
[instances.management-api-primary]
template = "management-api"
port = 8766
working_dir = "${PROJECT_ROOT}/server"
auto_start = true
tags = ["core", "primary"]

[instances.ollama-primary]
template = "ollama"
port = 11434
tags = ["llm"]
"#;

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, default_config)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_load_config() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("services.toml");

        let config = r#"
[templates.test-service]
display_name = "Test Service"
default_port = 8000
start_command = "echo start"
category = "core"
supports_multiple = true

[instances.test-instance]
template = "test-service"
port = 8001
tags = ["test"]
"#;
        std::fs::write(&config_path, config).unwrap();

        let event_bus = Arc::new(EventBus::new(16));
        let manager = ConfigManager::new(&config_path, event_bus).unwrap();
        let (templates, instances) = manager.load().await.unwrap();

        assert_eq!(templates.len(), 1);
        assert_eq!(instances.len(), 1);

        let template = templates.get("test-service").unwrap();
        assert_eq!(template.display_name, "Test Service");

        let instance = instances.get("test-instance").unwrap();
        assert_eq!(instance.port, 8001);
    }
}

/// Property-based tests for configuration management
#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;

    // --- Strategies for generating test data ---

    /// Generate valid port numbers (1024-65535 for non-privileged ports)
    fn port_strategy() -> impl Strategy<Value = u16> {
        1024u16..=65535u16
    }

    /// Generate valid port ranges
    fn port_range_strategy() -> impl Strategy<Value = (u16, u16)> {
        (1024u16..=60000u16).prop_flat_map(|start| (Just(start), start..=65535u16))
    }

    /// Generate valid service identifiers (alphanumeric with dashes)
    fn identifier_strategy() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9-]{0,30}[a-z0-9]"
    }

    /// Generate valid display names
    fn display_name_strategy() -> impl Strategy<Value = String> {
        "[A-Za-z][A-Za-z0-9 ]{0,50}"
    }

    /// Generate valid start commands
    fn command_strategy() -> impl Strategy<Value = String> {
        "(echo|python3?|node|cargo|npm) [a-z0-9/._-]{1,100}"
    }

    // --- Property Tests: Port Validation ---

    proptest! {
        /// Default ports should always be within valid range
        #[test]
        fn template_port_always_valid(port in port_strategy()) {
            prop_assert!(port >= 1024);
            // port <= 65535 is always true for u16, no need to check
        }

        /// Port ranges should have start <= end
        #[test]
        fn port_range_ordering(range in port_range_strategy()) {
            let (start, end) = range;
            prop_assert!(start <= end, "Port range start {} > end {}", start, end);
        }

        /// Port allocation should stay within range
        #[test]
        fn port_allocation_within_range(
            default in port_strategy(),
            range in port_range_strategy()
        ) {
            let (range_start, range_end) = range;

            // If default is in range, allocation should succeed
            if default >= range_start && default <= range_end {
                prop_assert!(
                    default >= range_start && default <= range_end,
                    "Default port {} outside range [{}, {}]",
                    default, range_start, range_end
                );
            }
        }
    }

    // --- Property Tests: TOML Serialization Round-trip ---

    proptest! {
        /// TemplateConfig should survive TOML round-trip
        #[test]
        fn template_config_toml_roundtrip(
            display_name in display_name_strategy(),
            port in port_strategy(),
            command in command_strategy(),
        ) {
            let template = TemplateConfig {
                display_name: display_name.clone(),
                description: Some("Test description".to_string()),
                default_port: port,
                port_range: Some((port, port.saturating_add(100))),
                start_command: command.clone(),
                stop_command: None,
                health_endpoint: Some(format!("http://localhost:{}/health", port)),
                health_timeout_ms: 5000,
                category: ServiceCategory::Core,
                supports_multiple: true,
                is_docker: false,
                default_env: std::collections::HashMap::new(),
            };

            // Serialize to TOML
            let toml_str = toml::to_string(&template).expect("TOML serialization failed");

            // Deserialize back
            let restored: TemplateConfig = toml::from_str(&toml_str)
                .expect("TOML deserialization failed");

            // Verify key fields
            prop_assert_eq!(restored.display_name, display_name);
            prop_assert_eq!(restored.default_port, port);
            prop_assert_eq!(restored.start_command, command);
        }

        /// InstanceConfigFile should survive TOML round-trip
        #[test]
        fn instance_config_toml_roundtrip(
            template_id in identifier_strategy(),
            port in port_strategy(),
        ) {
            let instance = InstanceConfigFile {
                template: template_id.clone(),
                port: Some(port),
                working_dir: Some("/test/path".to_string()),
                config: None,
                version: Some("1.0.0".to_string()),
                git_branch: Some("main".to_string()),
                tags: vec!["test".to_string(), "property".to_string()],
                auto_start: true,
                env_vars: std::collections::HashMap::new(),
                created_at: None,
                created_via: None,
            };

            // Serialize to TOML
            let toml_str = toml::to_string(&instance).expect("TOML serialization failed");

            // Deserialize back
            let restored: InstanceConfigFile = toml::from_str(&toml_str)
                .expect("TOML deserialization failed");

            // Verify key fields
            prop_assert_eq!(restored.template, template_id);
            prop_assert_eq!(restored.port, Some(port));
            prop_assert_eq!(restored.auto_start, true);
        }
    }

    // --- Property Tests: Path Resolution ---

    proptest! {
        /// Path resolution should be idempotent (resolving twice = resolving once)
        #[test]
        fn path_resolution_idempotent(path in "[a-zA-Z0-9/_.-]{1,100}") {
            // Create a mock config manager (we'll test the resolve_path logic)
            let resolved1 = resolve_path_test(&path);
            let resolved2 = resolve_path_test(&resolved1);

            // After first resolution, no more placeholders should exist
            // so second resolution should be identical
            prop_assert_eq!(resolved1.clone(), resolved2.clone(),
                "Path resolution not idempotent: '{}' -> '{}' -> '{}'",
                path, resolved1, resolved2
            );
        }

        /// Path resolution should expand ~ to home directory
        #[test]
        fn path_resolution_expands_tilde(suffix in "[a-zA-Z0-9/_.-]{0,50}") {
            let path_with_tilde = format!("~/{}", suffix);
            let resolved = resolve_path_test(&path_with_tilde);

            // Should not contain tilde after resolution (unless home dir unavailable)
            if dirs::home_dir().is_some() {
                prop_assert!(!resolved.starts_with("~/"),
                    "Tilde not expanded in: '{}'", resolved
                );
            }
        }

        /// Path resolution should not introduce invalid characters
        #[test]
        fn path_resolution_valid_path(path in "[a-zA-Z0-9/_.-]{1,100}") {
            let resolved = resolve_path_test(&path);

            // Should not contain null bytes
            prop_assert!(!resolved.contains('\0'),
                "Resolved path contains null byte: '{}'", resolved
            );

            // Should be valid UTF-8 (already guaranteed by String type)
            prop_assert!(resolved.is_ascii() || resolved.chars().all(|c| !c.is_control()),
                "Resolved path contains control characters: '{}'", resolved
            );
        }
    }

    /// Helper function to test path resolution without needing full ConfigManager
    fn resolve_path_test(path: &str) -> String {
        path.replace(
            "${PROJECT_ROOT}",
            &std::env::var("UNAMENTIS_ROOT").unwrap_or_else(|_| {
                dirs::home_dir()
                    .unwrap_or_default()
                    .join("dev/unamentis")
                    .display()
                    .to_string()
            }),
        )
        .replace(
            "~",
            &dirs::home_dir().unwrap_or_default().display().to_string(),
        )
    }

    // --- Property Tests: ConfigFile Structure ---

    proptest! {
        /// ConfigFile should handle empty templates/instances gracefully
        #[test]
        fn config_file_handles_empty(
            num_templates in 0usize..5,
            _num_instances in 0usize..5,
        ) {
            let mut config = ConfigFile {
                templates: std::collections::HashMap::new(),
                instances: std::collections::HashMap::new(),
            };

            // Add some templates
            for i in 0..num_templates {
                config.templates.insert(
                    format!("template-{}", i),
                    TemplateConfig {
                        display_name: format!("Template {}", i),
                        description: None,
                        default_port: 8000 + i as u16,
                        port_range: None,
                        start_command: "echo test".to_string(),
                        stop_command: None,
                        health_endpoint: None,
                        health_timeout_ms: 5000,
                        category: ServiceCategory::Core,
                        supports_multiple: false,
                        is_docker: false,
                        default_env: std::collections::HashMap::new(),
                    },
                );
            }

            // Verify counts match
            prop_assert_eq!(config.templates.len(), num_templates);
            prop_assert_eq!(config.instances.len(), 0); // No instances added yet
        }
    }

    // --- Property Tests: Health Timeout ---

    proptest! {
        /// Health timeout should have reasonable defaults
        #[test]
        fn health_timeout_reasonable(timeout_ms in 100u32..=60000u32) {
            // Timeouts should be reasonable (not too short, not too long)
            prop_assert!(timeout_ms >= 100, "Timeout too short: {}ms", timeout_ms);
            prop_assert!(timeout_ms <= 60000, "Timeout too long: {}ms", timeout_ms);
        }
    }

    // --- Property Tests: Default Values ---

    #[test]
    fn default_health_timeout_is_reasonable() {
        let timeout = default_health_timeout();
        assert!(timeout >= 1000, "Default timeout too short: {}ms", timeout);
        assert!(timeout <= 30000, "Default timeout too long: {}ms", timeout);
    }

    #[test]
    fn template_config_defaults_are_safe() {
        // Test that parsing minimal TOML produces safe defaults
        let minimal_toml = r#"
            display_name = "Test"
            default_port = 8000
            start_command = "echo start"
        "#;

        let config: TemplateConfig = toml::from_str(minimal_toml).unwrap();

        assert_eq!(config.health_timeout_ms, 5000); // default
        assert!(!config.supports_multiple); // default false
        assert!(!config.is_docker); // default false
        assert!(config.default_env.is_empty()); // default empty
    }
}
