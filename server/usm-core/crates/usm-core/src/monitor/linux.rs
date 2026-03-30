//! Linux process monitor using procfs
//!
//! This module is only compiled on Linux targets.

use std::path::Path;
use std::process::Command;

use anyhow::Result;
use sysinfo::{Pid, System};
use tracing::{debug, trace, warn};

use super::backend::{ProcessInfo, ProcessMonitor};
use crate::metrics::{InstanceMetrics, SystemMetrics};

/// Linux-specific process monitor using procfs and sysinfo
pub struct LinuxMonitor {
    system: std::sync::Mutex<System>,
}

impl LinuxMonitor {
    /// Create a new Linux process monitor
    pub fn new() -> Self {
        Self {
            system: std::sync::Mutex::new(System::new_all()),
        }
    }

    /// Refresh system information
    fn refresh(&self) {
        if let Ok(mut system) = self.system.lock() {
            system.refresh_all();
        }
    }

    /// Find PID listening on a port using /proc/net/tcp
    /// Falls back to ss command if procfs parsing fails
    fn find_pid_by_port(&self, port: u16) -> Option<u32> {
        // Try using ss command (more reliable on Linux)
        let output = Command::new("ss")
            .args(["-tlnp", &format!("sport = :{}", port)])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        // Parse ss output to extract PID
        for line in stdout.lines().skip(1) {
            if let Some(pid_info) = line.split("pid=").nth(1) {
                if let Some(pid_str) = pid_info.split(',').next() {
                    if let Ok(pid) = pid_str.trim().parse() {
                        return Some(pid);
                    }
                }
            }
        }
        None
    }
}

impl Default for LinuxMonitor {
    fn default() -> Self {
        Self::new()
    }
}

impl ProcessMonitor for LinuxMonitor {
    fn find_by_port(&self, port: u16) -> Option<ProcessInfo> {
        let pid = self.find_pid_by_port(port)?;
        self.refresh();

        let system = self.system.lock().ok()?;
        let process = system.process(Pid::from_u32(pid))?;

        Some(ProcessInfo {
            pid,
            name: process.name().to_string_lossy().to_string(),
            cpu_percent: process.cpu_usage() as f64,
            memory_bytes: process.memory(),
            threads: 0, // sysinfo doesn't expose thread count directly
        })
    }

    fn find_by_name(&self, pattern: &str) -> Vec<ProcessInfo> {
        self.refresh();

        let system = self.system.lock().unwrap();

        system
            .processes()
            .iter()
            .filter(|(_, process)| {
                process
                    .name()
                    .to_string_lossy()
                    .to_lowercase()
                    .contains(&pattern.to_lowercase())
            })
            .map(|(pid, process)| ProcessInfo {
                pid: pid.as_u32(),
                name: process.name().to_string_lossy().to_string(),
                cpu_percent: process.cpu_usage() as f64,
                memory_bytes: process.memory(),
                threads: 0,
            })
            .collect()
    }

    fn get_process_metrics(&self, pid: u32) -> Option<InstanceMetrics> {
        self.refresh();

        let system = self.system.lock().ok()?;
        let process = system.process(Pid::from_u32(pid))?;

        Some(InstanceMetrics {
            cpu_percent: process.cpu_usage() as f64,
            memory_bytes: process.memory(),
            memory_percent: (process.memory() as f64 / system.total_memory() as f64) * 100.0,
            threads: 0,
            open_files: 0,
            uptime_seconds: process.run_time(),
        })
    }

    fn get_system_metrics(&self) -> SystemMetrics {
        self.refresh();

        let system = self.system.lock().unwrap();

        SystemMetrics {
            cpu_percent: system.global_cpu_usage() as f64,
            memory_total_bytes: system.total_memory(),
            memory_used_bytes: system.used_memory(),
            memory_percent: (system.used_memory() as f64 / system.total_memory() as f64) * 100.0,
            load_average: System::load_average(),
        }
    }

    fn start_process(&self, command: &str, working_dir: Option<&Path>) -> Result<u32> {
        debug!(command = %command, working_dir = ?working_dir, "Starting process");

        let mut cmd = Command::new("/bin/bash");
        cmd.args(["-c", &format!("{} &", command)]);

        if let Some(dir) = working_dir {
            cmd.current_dir(dir);
        }

        // Detach from our process group
        cmd.stdout(std::process::Stdio::null());
        cmd.stderr(std::process::Stdio::null());

        let child = cmd.spawn()?;
        let pid = child.id();

        trace!(pid = pid, "Process started");
        Ok(pid)
    }

    fn kill_process(&self, pid: u32) -> Result<()> {
        debug!(pid = pid, "Killing process");

        // First try SIGTERM
        let status = Command::new("/bin/kill")
            .args(["-TERM", &pid.to_string()])
            .status()?;

        if !status.success() {
            warn!(pid = pid, "SIGTERM failed, trying SIGKILL");
            Command::new("/bin/kill")
                .args(["-KILL", &pid.to_string()])
                .status()?;
        }

        Ok(())
    }

    fn execute_command(&self, command: &str) -> Result<()> {
        debug!(command = %command, "Executing command");

        let status = Command::new("/bin/bash").args(["-c", command]).status()?;

        if !status.success() {
            anyhow::bail!("Command failed with status: {:?}", status.code());
        }

        Ok(())
    }

    fn is_running(&self, pid: u32) -> bool {
        self.refresh();

        if let Ok(system) = self.system.lock() {
            system.process(Pid::from_u32(pid)).is_some()
        } else {
            // Fallback: check if /proc/{pid} exists
            std::path::Path::new(&format!("/proc/{}", pid)).exists()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linux_monitor_creation() {
        let _monitor = LinuxMonitor::new();
    }

    #[test]
    fn test_system_metrics() {
        let monitor = LinuxMonitor::new();
        let metrics = monitor.get_system_metrics();

        // Basic sanity checks
        assert!(metrics.memory_total_bytes > 0);
        assert!(metrics.memory_percent >= 0.0 && metrics.memory_percent <= 100.0);
    }
}
