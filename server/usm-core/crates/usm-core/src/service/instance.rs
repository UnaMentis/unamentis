//! Service instances - running services created from templates

use std::collections::HashMap;
use std::path::PathBuf;

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Status of a service instance
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ServiceStatus {
    #[default]
    Stopped,
    Running,
    Starting,
    Stopping,
    Error,
    Unknown,
}

impl std::fmt::Display for ServiceStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ServiceStatus::Stopped => write!(f, "stopped"),
            ServiceStatus::Running => write!(f, "running"),
            ServiceStatus::Starting => write!(f, "starting"),
            ServiceStatus::Stopping => write!(f, "stopping"),
            ServiceStatus::Error => write!(f, "error"),
            ServiceStatus::Unknown => write!(f, "unknown"),
        }
    }
}

/// Configuration for creating a new service instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstanceConfig {
    /// Unique identifier for this instance
    pub instance_id: String,

    /// Template to use for this instance
    pub template_id: String,

    /// Port override (uses template default if not specified)
    #[serde(default)]
    pub port: Option<u16>,

    /// Working directory for the service
    #[serde(default)]
    pub working_dir: Option<PathBuf>,

    /// Path to config file
    #[serde(default)]
    pub config_path: Option<PathBuf>,

    /// Version identifier (semantic version, git tag, etc.)
    #[serde(default)]
    pub version: Option<String>,

    /// Git branch (for development instances)
    #[serde(default)]
    pub git_branch: Option<String>,

    /// Tags for filtering and organization
    #[serde(default)]
    pub tags: Vec<String>,

    /// Whether to start automatically on USM startup
    #[serde(default)]
    pub auto_start: bool,

    /// Environment variable overrides
    #[serde(default)]
    pub env_vars: HashMap<String, String>,
}

/// A running service instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceInstance {
    /// Unique identifier
    pub id: String,

    /// Template this instance was created from
    pub template_id: String,

    /// Port this instance is listening on
    pub port: u16,

    /// Working directory
    #[serde(default)]
    pub working_dir: Option<PathBuf>,

    /// Config file path
    #[serde(default)]
    pub config_path: Option<PathBuf>,

    /// Version identifier
    #[serde(default)]
    pub version: Option<String>,

    /// Git branch
    #[serde(default)]
    pub git_branch: Option<String>,

    /// Tags for filtering
    #[serde(default)]
    pub tags: Vec<String>,

    /// Auto-start on USM startup
    #[serde(default)]
    pub auto_start: bool,

    /// Environment variables
    #[serde(default)]
    pub env_vars: HashMap<String, String>,

    // === Runtime state (not persisted) ===
    /// Current status
    #[serde(default, skip_serializing)]
    pub status: ServiceStatus,

    /// Process ID if running
    #[serde(default, skip_serializing)]
    pub pid: Option<u32>,

    /// When the service was started
    #[serde(default, skip_serializing)]
    pub started_at: Option<DateTime<Utc>>,

    // === Metadata (persisted) ===
    /// When this instance was created
    #[serde(default = "Utc::now", rename = "_created_at")]
    pub created_at: DateTime<Utc>,

    /// How this instance was created ("api" or "config")
    #[serde(default = "default_created_via", rename = "_created_via")]
    pub created_via: String,
}

fn default_created_via() -> String {
    "config".to_string()
}

impl ServiceInstance {
    /// Create a new instance from configuration
    pub fn from_config(config: InstanceConfig) -> Result<Self> {
        // Validate instance ID
        if config.instance_id.is_empty() {
            anyhow::bail!("Instance ID cannot be empty");
        }

        if config.template_id.is_empty() {
            anyhow::bail!("Template ID cannot be empty");
        }

        // Port will be assigned from template default if not specified
        let port = config.port.unwrap_or(0);

        Ok(Self {
            id: config.instance_id,
            template_id: config.template_id,
            port,
            working_dir: config.working_dir,
            config_path: config.config_path,
            version: config.version,
            git_branch: config.git_branch,
            tags: config.tags,
            auto_start: config.auto_start,
            env_vars: config.env_vars,
            status: ServiceStatus::Stopped,
            pid: None,
            started_at: None,
            created_at: Utc::now(),
            created_via: "api".to_string(),
        })
    }

    /// Check if this instance has a specific tag
    pub fn has_tag(&self, tag: &str) -> bool {
        self.tags.iter().any(|t| t == tag)
    }

    /// Check if this instance matches any of the given tags
    pub fn matches_tags(&self, tags: &[&str]) -> bool {
        tags.iter().any(|t| self.has_tag(t))
    }

    /// Get uptime duration if running
    pub fn uptime(&self) -> Option<chrono::Duration> {
        self.started_at.map(|started| Utc::now() - started)
    }

    /// Get uptime as human-readable string
    pub fn uptime_string(&self) -> Option<String> {
        self.uptime().map(|duration| {
            let secs = duration.num_seconds();
            if secs < 60 {
                format!("{}s", secs)
            } else if secs < 3600 {
                format!("{}m", secs / 60)
            } else if secs < 86400 {
                format!("{}h {}m", secs / 3600, (secs % 3600) / 60)
            } else {
                format!("{}d {}h", secs / 86400, (secs % 86400) / 3600)
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_instance_from_config() {
        let config = InstanceConfig {
            instance_id: "test-instance".to_string(),
            template_id: "test-template".to_string(),
            port: Some(8080),
            working_dir: Some(PathBuf::from("/opt/app")),
            config_path: None,
            version: Some("1.0.0".to_string()),
            git_branch: None,
            tags: vec!["production".to_string(), "stable".to_string()],
            auto_start: true,
            env_vars: Default::default(),
        };

        let instance = ServiceInstance::from_config(config).unwrap();

        assert_eq!(instance.id, "test-instance");
        assert_eq!(instance.template_id, "test-template");
        assert_eq!(instance.port, 8080);
        assert_eq!(instance.status, ServiceStatus::Stopped);
        assert!(instance.has_tag("production"));
        assert!(instance.has_tag("stable"));
        assert!(!instance.has_tag("development"));
    }

    #[test]
    fn test_instance_tags() {
        let config = InstanceConfig {
            instance_id: "test".to_string(),
            template_id: "test".to_string(),
            port: None,
            working_dir: None,
            config_path: None,
            version: None,
            git_branch: None,
            tags: vec!["production".to_string(), "api".to_string()],
            auto_start: false,
            env_vars: Default::default(),
        };

        let instance = ServiceInstance::from_config(config).unwrap();

        assert!(instance.matches_tags(&["production"]));
        assert!(instance.matches_tags(&["development", "production"]));
        assert!(!instance.matches_tags(&["development", "staging"]));
    }

    #[test]
    fn test_status_display() {
        assert_eq!(ServiceStatus::Running.to_string(), "running");
        assert_eq!(ServiceStatus::Stopped.to_string(), "stopped");
        assert_eq!(ServiceStatus::Error.to_string(), "error");
    }
}

/// Property-based tests for ServiceInstance
#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;

    // --- Strategies ---

    fn identifier_strategy() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9-]{1,20}".prop_map(|s| s.to_string())
    }

    fn tag_strategy() -> impl Strategy<Value = String> {
        "[a-z][a-z0-9-]{1,10}".prop_map(|s| s.to_string())
    }

    fn tags_strategy() -> impl Strategy<Value = Vec<String>> {
        prop::collection::vec(tag_strategy(), 0..5)
    }

    fn port_strategy() -> impl Strategy<Value = u16> {
        1024u16..=65535u16
    }

    // --- Property Tests: Tag Matching ---

    proptest! {
        /// has_tag is reflexive: if tag is in list, has_tag returns true
        #[test]
        fn has_tag_finds_existing_tags(
            instance_id in identifier_strategy(),
            template_id in identifier_strategy(),
            tags in tags_strategy(),
        ) {
            let config = InstanceConfig {
                instance_id,
                template_id,
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: tags.clone(),
                auto_start: false,
                env_vars: Default::default(),
            };

            let instance = ServiceInstance::from_config(config).unwrap();

            for tag in &tags {
                prop_assert!(instance.has_tag(tag),
                    "Instance should have tag '{}' but has_tag returned false", tag);
            }
        }

        /// has_tag returns false for non-existent tags
        #[test]
        fn has_tag_rejects_missing_tags(
            instance_id in identifier_strategy(),
            template_id in identifier_strategy(),
            tags in tags_strategy(),
            missing_tag in "missing-[a-z]{5}",
        ) {
            let config = InstanceConfig {
                instance_id,
                template_id,
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: tags.clone(),
                auto_start: false,
                env_vars: Default::default(),
            };

            let instance = ServiceInstance::from_config(config).unwrap();

            // If tags doesn't contain missing_tag
            if !tags.contains(&missing_tag) {
                prop_assert!(!instance.has_tag(&missing_tag),
                    "Instance should NOT have tag '{}' but has_tag returned true", missing_tag);
            }
        }

        /// matches_tags is consistent with has_tag
        #[test]
        fn matches_tags_consistent_with_has_tag(
            instance_id in identifier_strategy(),
            template_id in identifier_strategy(),
            tags in tags_strategy(),
        ) {
            let config = InstanceConfig {
                instance_id,
                template_id,
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: tags.clone(),
                auto_start: false,
                env_vars: Default::default(),
            };

            let instance = ServiceInstance::from_config(config).unwrap();

            // If any tag matches, matches_tags should return true
            for tag in &tags {
                let tag_refs: Vec<&str> = vec![tag.as_str()];
                prop_assert!(instance.matches_tags(&tag_refs),
                    "matches_tags(['{}']) should be true when has_tag('{}') is true", tag, tag);
            }

            // Empty tag list should not match
            prop_assert!(!instance.matches_tags(&[]),
                "Empty tag list should not match any instance");
        }
    }

    // --- Property Tests: Validation ---

    proptest! {
        /// Empty instance_id is rejected
        #[test]
        fn empty_instance_id_rejected(template_id in identifier_strategy()) {
            let config = InstanceConfig {
                instance_id: "".to_string(),
                template_id,
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: vec![],
                auto_start: false,
                env_vars: Default::default(),
            };

            prop_assert!(ServiceInstance::from_config(config).is_err());
        }

        /// Empty template_id is rejected
        #[test]
        fn empty_template_id_rejected(instance_id in identifier_strategy()) {
            let config = InstanceConfig {
                instance_id,
                template_id: "".to_string(),
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: vec![],
                auto_start: false,
                env_vars: Default::default(),
            };

            prop_assert!(ServiceInstance::from_config(config).is_err());
        }

        /// Valid config creates instance with correct fields
        #[test]
        fn valid_config_creates_instance(
            instance_id in identifier_strategy(),
            template_id in identifier_strategy(),
            port in port_strategy(),
        ) {
            let config = InstanceConfig {
                instance_id: instance_id.clone(),
                template_id: template_id.clone(),
                port: Some(port),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: vec![],
                auto_start: false,
                env_vars: Default::default(),
            };

            let instance = ServiceInstance::from_config(config).unwrap();

            prop_assert_eq!(instance.id, instance_id);
            prop_assert_eq!(instance.template_id, template_id);
            prop_assert_eq!(instance.port, port);
            prop_assert_eq!(instance.status, ServiceStatus::Stopped);
            prop_assert!(instance.pid.is_none());
            prop_assert!(instance.started_at.is_none());
        }
    }

    // --- Property Tests: Serialization ---

    proptest! {
        /// ServiceStatus JSON roundtrip
        #[test]
        fn status_json_roundtrip(idx in 0usize..6) {
            let statuses = [
                ServiceStatus::Stopped,
                ServiceStatus::Running,
                ServiceStatus::Starting,
                ServiceStatus::Stopping,
                ServiceStatus::Error,
                ServiceStatus::Unknown,
            ];
            let status = statuses[idx % statuses.len()];

            let json = serde_json::to_string(&status).expect("JSON serialize failed");
            let restored: ServiceStatus = serde_json::from_str(&json).expect("JSON deserialize failed");
            prop_assert_eq!(status, restored);
        }

        /// All status variants have unique display strings
        #[test]
        fn status_display_unique(_dummy in 0..1) {
            let statuses = [
                ServiceStatus::Stopped,
                ServiceStatus::Running,
                ServiceStatus::Starting,
                ServiceStatus::Stopping,
                ServiceStatus::Error,
                ServiceStatus::Unknown,
            ];

            let displays: Vec<String> = statuses.iter().map(|s| s.to_string()).collect();
            let unique_count = displays.iter().collect::<std::collections::HashSet<_>>().len();

            prop_assert_eq!(displays.len(), unique_count,
                "Not all status display strings are unique");
        }
    }

    // --- Property Tests: Uptime ---

    proptest! {
        /// Uptime is never negative
        #[test]
        fn uptime_never_negative(secs_ago in 0i64..1_000_000) {
            let started = Utc::now() - chrono::Duration::seconds(secs_ago);
            let mut instance = ServiceInstance::from_config(InstanceConfig {
                instance_id: "test".to_string(),
                template_id: "test".to_string(),
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: vec![],
                auto_start: false,
                env_vars: Default::default(),
            }).unwrap();

            instance.started_at = Some(started);

            if let Some(duration) = instance.uptime() {
                prop_assert!(duration.num_seconds() >= 0,
                    "Uptime should never be negative, got {} seconds", duration.num_seconds());
            }
        }
    }

    #[test]
    fn uptime_formatting_consistency() {
        // Test various durations to ensure formatting is consistent
        let test_cases = [
            (30i64, "s"),    // seconds format
            (90, "m"),       // minutes format
            (3700, "h"),     // hours format
            (90000, "d"),    // days format
        ];

        for (secs, expected_suffix) in test_cases {
            let started = Utc::now() - chrono::Duration::seconds(secs);
            let mut instance = ServiceInstance::from_config(InstanceConfig {
                instance_id: "test".to_string(),
                template_id: "test".to_string(),
                port: Some(8080),
                working_dir: None,
                config_path: None,
                version: None,
                git_branch: None,
                tags: vec![],
                auto_start: false,
                env_vars: Default::default(),
            }).unwrap();

            instance.started_at = Some(started);

            let uptime_str = instance.uptime_string();
            assert!(uptime_str.is_some(), "Uptime string should be Some when started_at is set");
            assert!(uptime_str.unwrap().contains(expected_suffix),
                "Uptime for {} secs should contain '{}'", secs, expected_suffix);
        }
    }
}
