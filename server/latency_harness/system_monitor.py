"""
UnaMentis - System Resource Monitor
===================================

Monitors local system resources during mass test runs:
- CPU usage (overall and per-core)
- Memory usage (total, used, available, GPU/wired)
- Thermal state (temperature, throttling)
- Process-specific metrics

Designed for Apple Silicon Macs with unified memory architecture.

USAGE
-----
```python
from latency_harness.system_monitor import SystemMonitor

monitor = SystemMonitor(sample_interval_ms=500)
await monitor.start()

# During test run...
snapshot = await monitor.get_current()
print(f"CPU: {snapshot.cpu_percent}%, Temp: {snapshot.thermal_state}")

# After test
summary = await monitor.stop()
print(f"Peak CPU: {summary.peak_cpu_percent}%")
print(f"Peak Memory: {summary.peak_memory_mb}MB")
```

METRICS COLLECTED
-----------------
- cpu_percent: Overall CPU utilization (0-100)
- cpu_per_core: List of per-core utilization
- memory_used_mb: Total memory in use
- memory_available_mb: Available memory
- memory_wired_mb: Wired/pinned memory (includes GPU allocations)
- memory_gpu_mb: Estimated GPU memory usage (Apple Silicon unified memory)
- thermal_pressure: none, nominal, moderate, heavy, critical
- cpu_temp_celsius: CPU die temperature (if available)
- fan_speed_rpm: Fan speed (if available)

SEE ALSO
--------
- test_orchestrator.py: Uses this monitor during mass tests
- MassTestPanel.tsx: Displays resource metrics in dashboard
"""

import asyncio
import logging
import platform
import subprocess
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Optional, Dict, Any
from enum import Enum

logger = logging.getLogger(__name__)


class ThermalPressure(str, Enum):
    """System thermal pressure levels."""
    NONE = "none"
    NOMINAL = "nominal"
    MODERATE = "moderate"
    HEAVY = "heavy"
    CRITICAL = "critical"


@dataclass
class ResourceSnapshot:
    """Point-in-time system resource snapshot."""
    timestamp: datetime

    # CPU
    cpu_percent: float  # Overall CPU usage 0-100
    cpu_per_core: List[float] = field(default_factory=list)  # Per-core usage
    cpu_frequency_mhz: Optional[float] = None

    # Memory
    memory_total_mb: float = 0
    memory_used_mb: float = 0
    memory_available_mb: float = 0
    memory_wired_mb: float = 0  # Includes GPU allocations on Apple Silicon
    memory_gpu_mb: float = 0  # Estimated GPU-specific memory
    memory_percent: float = 0

    # Thermal
    thermal_pressure: ThermalPressure = ThermalPressure.NOMINAL
    cpu_temp_celsius: Optional[float] = None
    gpu_temp_celsius: Optional[float] = None
    fan_speed_rpm: Optional[int] = None

    # Process info
    browser_memory_mb: float = 0  # Memory used by browser processes
    python_memory_mb: float = 0  # Memory used by this process

    def to_dict(self) -> Dict[str, Any]:
        return {
            "timestamp": self.timestamp.isoformat(),
            "cpu": {
                "percent": round(self.cpu_percent, 1),
                "perCore": [round(c, 1) for c in self.cpu_per_core],
                "frequencyMhz": self.cpu_frequency_mhz,
            },
            "memory": {
                "totalMb": round(self.memory_total_mb, 1),
                "usedMb": round(self.memory_used_mb, 1),
                "availableMb": round(self.memory_available_mb, 1),
                "wiredMb": round(self.memory_wired_mb, 1),
                "gpuMb": round(self.memory_gpu_mb, 1),
                "percent": round(self.memory_percent, 1),
            },
            "thermal": {
                "pressure": self.thermal_pressure.value,
                "cpuTempC": self.cpu_temp_celsius,
                "gpuTempC": self.gpu_temp_celsius,
                "fanRpm": self.fan_speed_rpm,
            },
            "processes": {
                "browserMemoryMb": round(self.browser_memory_mb, 1),
                "pythonMemoryMb": round(self.python_memory_mb, 1),
            },
        }


@dataclass
class ResourceSummary:
    """Aggregated resource metrics over a test run."""
    run_id: str
    started_at: datetime
    ended_at: datetime
    sample_count: int

    # CPU aggregates
    avg_cpu_percent: float = 0
    peak_cpu_percent: float = 0
    min_cpu_percent: float = 100

    # Memory aggregates
    avg_memory_used_mb: float = 0
    peak_memory_used_mb: float = 0
    avg_memory_gpu_mb: float = 0
    peak_memory_gpu_mb: float = 0

    # Thermal aggregates
    peak_thermal_pressure: ThermalPressure = ThermalPressure.NONE
    thermal_throttle_seconds: float = 0  # Time spent in heavy/critical
    peak_cpu_temp_celsius: Optional[float] = None

    # Browser process memory
    avg_browser_memory_mb: float = 0
    peak_browser_memory_mb: float = 0

    # All snapshots (for detailed analysis)
    snapshots: List[ResourceSnapshot] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "runId": self.run_id,
            "startedAt": self.started_at.isoformat(),
            "endedAt": self.ended_at.isoformat(),
            "sampleCount": self.sample_count,
            "cpu": {
                "avgPercent": round(self.avg_cpu_percent, 1),
                "peakPercent": round(self.peak_cpu_percent, 1),
                "minPercent": round(self.min_cpu_percent, 1),
            },
            "memory": {
                "avgUsedMb": round(self.avg_memory_used_mb, 1),
                "peakUsedMb": round(self.peak_memory_used_mb, 1),
                "avgGpuMb": round(self.avg_memory_gpu_mb, 1),
                "peakGpuMb": round(self.peak_memory_gpu_mb, 1),
            },
            "thermal": {
                "peakPressure": self.peak_thermal_pressure.value,
                "throttleSeconds": round(self.thermal_throttle_seconds, 1),
                "peakCpuTempC": self.peak_cpu_temp_celsius,
            },
            "browser": {
                "avgMemoryMb": round(self.avg_browser_memory_mb, 1),
                "peakMemoryMb": round(self.peak_browser_memory_mb, 1),
            },
        }


class SystemMonitor:
    """
    Monitors system resources during test runs.

    Optimized for Apple Silicon Macs with unified memory.
    Falls back gracefully on other platforms.
    """

    def __init__(
        self,
        sample_interval_ms: int = 500,
        run_id: str = "",
    ):
        self.sample_interval_ms = sample_interval_ms
        self.run_id = run_id
        self._is_running = False
        self._task: Optional[asyncio.Task] = None
        self._snapshots: List[ResourceSnapshot] = []
        self._started_at: Optional[datetime] = None
        self._is_apple_silicon = self._detect_apple_silicon()
        self._psutil_available = self._check_psutil()

    def _detect_apple_silicon(self) -> bool:
        """Detect if running on Apple Silicon Mac."""
        if platform.system() != "Darwin":
            return False
        try:
            result = subprocess.run(
                ["sysctl", "-n", "machdep.cpu.brand_string"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            return "Apple" in result.stdout
        except Exception:
            return False

    def _check_psutil(self) -> bool:
        """Check if psutil is available."""
        try:
            import psutil
            return True
        except ImportError:
            logger.warning("psutil not installed. Install with: pip install psutil")
            return False

    async def start(self):
        """Start the monitoring loop."""
        if self._is_running:
            return

        self._is_running = True
        self._started_at = datetime.now()
        self._snapshots = []

        self._task = asyncio.create_task(self._monitor_loop())
        logger.info(f"System monitor started (interval: {self.sample_interval_ms}ms)")

    async def stop(self) -> ResourceSummary:
        """Stop monitoring and return summary."""
        self._is_running = False

        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

        summary = self._compute_summary()
        logger.info(
            f"System monitor stopped: {summary.sample_count} samples, "
            f"peak CPU {summary.peak_cpu_percent}%, "
            f"peak memory {summary.peak_memory_used_mb}MB"
        )
        return summary

    async def get_current(self) -> ResourceSnapshot:
        """Get current resource snapshot."""
        return await self._take_snapshot()

    async def _monitor_loop(self):
        """Background monitoring loop."""
        while self._is_running:
            try:
                snapshot = await self._take_snapshot()
                self._snapshots.append(snapshot)
            except Exception as e:
                logger.warning(f"Failed to take snapshot: {e}")

            await asyncio.sleep(self.sample_interval_ms / 1000)

    async def _take_snapshot(self) -> ResourceSnapshot:
        """Take a single resource snapshot."""
        snapshot = ResourceSnapshot(timestamp=datetime.now())

        # Get CPU and memory via psutil if available
        if self._psutil_available:
            await self._collect_psutil_metrics(snapshot)

        # Get thermal info (macOS specific)
        if platform.system() == "Darwin":
            await self._collect_thermal_metrics(snapshot)

            # Get GPU memory estimate for Apple Silicon
            if self._is_apple_silicon:
                await self._collect_gpu_memory(snapshot)

        # Get browser process memory
        await self._collect_browser_memory(snapshot)

        return snapshot

    async def _collect_psutil_metrics(self, snapshot: ResourceSnapshot):
        """Collect CPU and memory metrics via psutil."""
        try:
            import psutil

            # CPU
            snapshot.cpu_percent = psutil.cpu_percent(interval=None)
            snapshot.cpu_per_core = psutil.cpu_percent(interval=None, percpu=True)

            try:
                freq = psutil.cpu_freq()
                if freq:
                    snapshot.cpu_frequency_mhz = freq.current
            except Exception:
                pass

            # Memory
            mem = psutil.virtual_memory()
            snapshot.memory_total_mb = mem.total / (1024 * 1024)
            snapshot.memory_used_mb = mem.used / (1024 * 1024)
            snapshot.memory_available_mb = mem.available / (1024 * 1024)
            snapshot.memory_percent = mem.percent

            # Wired memory (important for GPU on Apple Silicon)
            if hasattr(mem, 'wired'):
                snapshot.memory_wired_mb = mem.wired / (1024 * 1024)

            # This process memory
            process = psutil.Process()
            snapshot.python_memory_mb = process.memory_info().rss / (1024 * 1024)

        except Exception as e:
            logger.debug(f"psutil metrics collection failed: {e}")

    async def _collect_thermal_metrics(self, snapshot: ResourceSnapshot):
        """Collect thermal metrics on macOS."""
        try:
            # Get thermal pressure via pmset
            result = await asyncio.to_thread(
                subprocess.run,
                ["pmset", "-g", "therm"],
                capture_output=True,
                text=True,
                timeout=5,
            )

            if result.returncode == 0:
                output = result.stdout.lower()
                if "cpu_speed_limit" in output:
                    # Parse speed limit percentage
                    for line in result.stdout.split("\n"):
                        if "cpu_speed_limit" in line.lower():
                            try:
                                # Format: CPU_Speed_Limit = 100
                                parts = line.split("=")
                                if len(parts) == 2:
                                    speed = int(parts[1].strip())
                                    if speed >= 100:
                                        snapshot.thermal_pressure = ThermalPressure.NONE
                                    elif speed >= 80:
                                        snapshot.thermal_pressure = ThermalPressure.NOMINAL
                                    elif speed >= 60:
                                        snapshot.thermal_pressure = ThermalPressure.MODERATE
                                    elif speed >= 40:
                                        snapshot.thermal_pressure = ThermalPressure.HEAVY
                                    else:
                                        snapshot.thermal_pressure = ThermalPressure.CRITICAL
                            except ValueError:
                                pass

            # Try to get CPU temperature via osx-cpu-temp or similar
            # This requires third-party tools, so we make it optional
            await self._try_get_temperature(snapshot)

        except Exception as e:
            logger.debug(f"Thermal metrics collection failed: {e}")

    async def _try_get_temperature(self, snapshot: ResourceSnapshot):
        """Try to get CPU temperature (requires osx-cpu-temp or similar)."""
        try:
            # Try osx-cpu-temp if installed
            result = await asyncio.to_thread(
                subprocess.run,
                ["osx-cpu-temp"],
                capture_output=True,
                text=True,
                timeout=2,
            )
            if result.returncode == 0:
                # Output format: "CPU: 45.0°C"
                temp_str = result.stdout.strip()
                if "°C" in temp_str:
                    temp = float(temp_str.split(":")[1].replace("°C", "").strip())
                    snapshot.cpu_temp_celsius = temp
        except FileNotFoundError:
            pass  # osx-cpu-temp not installed
        except Exception:
            pass

    async def _collect_gpu_memory(self, snapshot: ResourceSnapshot):
        """Estimate GPU memory usage on Apple Silicon."""
        try:
            # On Apple Silicon, GPU uses unified memory
            # We can estimate GPU usage from IOKit
            result = await asyncio.to_thread(
                subprocess.run,
                ["ioreg", "-r", "-c", "IOAccelerator", "-d", "1"],
                capture_output=True,
                text=True,
                timeout=5,
            )

            if result.returncode == 0:
                # Look for VRAM usage in output
                # This gives us allocated GPU memory
                for line in result.stdout.split("\n"):
                    if "VRAM" in line or "vram" in line:
                        # Try to parse memory value
                        try:
                            # Look for patterns like "VRAM,totalMB" = 8192
                            if "=" in line:
                                parts = line.split("=")
                                if len(parts) == 2:
                                    val = parts[1].strip().replace('"', '')
                                    if val.isdigit():
                                        # This is typically total, not used
                                        pass
                        except Exception:
                            pass

            # Alternative: Use vm_stat for memory pressure
            result = await asyncio.to_thread(
                subprocess.run,
                ["vm_stat"],
                capture_output=True,
                text=True,
                timeout=5,
            )

            if result.returncode == 0:
                # Parse vm_stat output for wired/purgeable memory
                # Wired memory on Apple Silicon includes GPU allocations
                page_size = 16384  # Apple Silicon uses 16K pages

                for line in result.stdout.split("\n"):
                    if "Pages wired down:" in line:
                        try:
                            pages = int(line.split(":")[1].strip().rstrip("."))
                            snapshot.memory_wired_mb = (pages * page_size) / (1024 * 1024)
                        except ValueError:
                            pass
                    elif "Pages occupied by compressor:" in line:
                        # Compressed memory (not GPU related but useful)
                        pass

            # Estimate GPU memory as portion of wired memory
            # This is a rough heuristic - GPU typically uses 20-40% of wired
            if snapshot.memory_wired_mb > 0:
                # Conservative estimate: assume 30% of wired is GPU
                snapshot.memory_gpu_mb = snapshot.memory_wired_mb * 0.3

        except Exception as e:
            logger.debug(f"GPU memory collection failed: {e}")

    async def _collect_browser_memory(self, snapshot: ResourceSnapshot):
        """Collect memory used by browser processes (Chromium/Chrome)."""
        if not self._psutil_available:
            return

        try:
            import psutil

            browser_memory = 0
            browser_names = ["chromium", "chrome", "google chrome", "playwright"]

            for proc in psutil.process_iter(['name', 'memory_info']):
                try:
                    name = proc.info['name'].lower()
                    if any(browser in name for browser in browser_names):
                        mem_info = proc.info['memory_info']
                        if mem_info:
                            browser_memory += mem_info.rss
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass

            snapshot.browser_memory_mb = browser_memory / (1024 * 1024)

        except Exception as e:
            logger.debug(f"Browser memory collection failed: {e}")

    def _compute_summary(self) -> ResourceSummary:
        """Compute summary statistics from collected snapshots."""
        if not self._snapshots:
            return ResourceSummary(
                run_id=self.run_id,
                started_at=self._started_at or datetime.now(),
                ended_at=datetime.now(),
                sample_count=0,
            )

        summary = ResourceSummary(
            run_id=self.run_id,
            started_at=self._started_at or self._snapshots[0].timestamp,
            ended_at=self._snapshots[-1].timestamp,
            sample_count=len(self._snapshots),
            snapshots=self._snapshots,
        )

        # Compute aggregates
        cpu_values = [s.cpu_percent for s in self._snapshots]
        memory_values = [s.memory_used_mb for s in self._snapshots]
        gpu_values = [s.memory_gpu_mb for s in self._snapshots]
        browser_values = [s.browser_memory_mb for s in self._snapshots]
        temps = [s.cpu_temp_celsius for s in self._snapshots if s.cpu_temp_celsius]

        # CPU
        summary.avg_cpu_percent = sum(cpu_values) / len(cpu_values)
        summary.peak_cpu_percent = max(cpu_values)
        summary.min_cpu_percent = min(cpu_values)

        # Memory
        summary.avg_memory_used_mb = sum(memory_values) / len(memory_values)
        summary.peak_memory_used_mb = max(memory_values)
        summary.avg_memory_gpu_mb = sum(gpu_values) / len(gpu_values) if gpu_values else 0
        summary.peak_memory_gpu_mb = max(gpu_values) if gpu_values else 0

        # Browser
        summary.avg_browser_memory_mb = sum(browser_values) / len(browser_values) if browser_values else 0
        summary.peak_browser_memory_mb = max(browser_values) if browser_values else 0

        # Thermal
        pressure_order = [
            ThermalPressure.NONE,
            ThermalPressure.NOMINAL,
            ThermalPressure.MODERATE,
            ThermalPressure.HEAVY,
            ThermalPressure.CRITICAL,
        ]
        pressures = [s.thermal_pressure for s in self._snapshots]
        summary.peak_thermal_pressure = max(pressures, key=lambda p: pressure_order.index(p))

        # Count time in thermal throttling (heavy or critical)
        throttle_samples = sum(
            1 for s in self._snapshots
            if s.thermal_pressure in [ThermalPressure.HEAVY, ThermalPressure.CRITICAL]
        )
        summary.thermal_throttle_seconds = throttle_samples * (self.sample_interval_ms / 1000)

        # Temperature
        if temps:
            summary.peak_cpu_temp_celsius = max(temps)

        return summary


# Singleton instance
_monitor_instance: Optional[SystemMonitor] = None


def get_system_monitor(
    sample_interval_ms: int = 500,
    run_id: str = "",
) -> SystemMonitor:
    """Get or create the system monitor instance."""
    global _monitor_instance
    if _monitor_instance is None or not _monitor_instance._is_running:
        _monitor_instance = SystemMonitor(sample_interval_ms, run_id)
    return _monitor_instance
