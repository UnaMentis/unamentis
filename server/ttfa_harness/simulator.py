"""
UnaMentis TTFA Harness - Simulator Control

Drives the iOS Simulator via xcrun simctl for TTFA test orchestration.
Inspired by demo/ios_demo_video_generator.py.
"""

import asyncio
import json
import logging
import time
from typing import Optional, AsyncIterator

logger = logging.getLogger("ttfa_harness.simulator")

BUNDLE_ID = "com.unamentis.app"


class SimulatorError(Exception):
    """Error from simulator operations."""

    pass


class Simulator:
    """Controls an iOS Simulator for TTFA testing."""

    def __init__(self, device_name: str = "iPhone 16 Pro"):
        self.device_name = device_name
        self.udid: Optional[str] = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def boot(self) -> str:
        """Boot the simulator, returning its UDID."""
        self.udid = await self._find_or_create_device()

        # Check if already booted
        state = await self._get_device_state(self.udid)
        if state != "Booted":
            logger.info("Booting simulator %s (%s)", self.device_name, self.udid)
            await self._run("xcrun", "simctl", "boot", self.udid)
            # Wait for boot
            for _ in range(30):
                await asyncio.sleep(1)
                if await self._get_device_state(self.udid) == "Booted":
                    break
            else:
                raise SimulatorError(f"Simulator {self.udid} did not boot within 30s")
        else:
            logger.info(
                "Simulator already booted: %s (%s)", self.device_name, self.udid
            )

        return self.udid

    async def install_app(self, app_path: str) -> None:
        """Install the app bundle on the simulator."""
        if not self.udid:
            raise SimulatorError("Simulator not booted")
        logger.info("Installing app from %s", app_path)
        await self._run("xcrun", "simctl", "install", self.udid, app_path)

    async def launch_app(self) -> None:
        """Launch the UnaMentis app."""
        if not self.udid:
            raise SimulatorError("Simulator not booted")
        logger.info("Launching %s", BUNDLE_ID)
        await self._run("xcrun", "simctl", "launch", self.udid, BUNDLE_ID)
        # Give app time to initialize
        await asyncio.sleep(2.0)

    async def terminate_app(self) -> None:
        """Terminate the UnaMentis app."""
        if not self.udid:
            return
        try:
            await self._run("xcrun", "simctl", "terminate", self.udid, BUNDLE_ID)
        except SimulatorError:
            pass  # App may not be running

    # ------------------------------------------------------------------
    # Interaction
    # ------------------------------------------------------------------

    async def open_url(self, url: str) -> None:
        """Open a URL (deep link) on the simulator."""
        if not self.udid:
            raise SimulatorError("Simulator not booted")
        logger.debug("Opening URL: %s", url)
        await self._run("xcrun", "simctl", "openurl", self.udid, url)

    async def tap(self, x: int, y: int) -> None:
        """Tap at a coordinate on the simulator."""
        if not self.udid:
            raise SimulatorError("Simulator not booted")
        logger.debug("Tapping at (%d, %d)", x, y)
        # simctl does not have a native tap command; use idb or the MCP tools.
        # For CI, we rely on deep links and accessibility-based taps via
        # the MCP ios-simulator tools when available.
        # Fallback: use AppleScript to interact with the Simulator app.
        script = f"""
        tell application "Simulator"
            activate
        end tell
        delay 0.3
        tell application "System Events"
            tell process "Simulator"
                click at {{{x}, {y}}}
            end tell
        end tell
        """
        proc = await asyncio.create_subprocess_exec(
            "osascript",
            "-e",
            script,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await proc.communicate()

    async def screenshot(self, output_path: str) -> None:
        """Take a screenshot for debugging."""
        if not self.udid:
            raise SimulatorError("Simulator not booted")
        await self._run("xcrun", "simctl", "io", self.udid, "screenshot", output_path)

    # ------------------------------------------------------------------
    # Log Streaming
    # ------------------------------------------------------------------

    async def start_log_stream(self) -> asyncio.subprocess.Process:
        """
        Start streaming os_log events filtered to the TTFA subsystem.

        Returns the subprocess so the caller can read stdout line by line.
        The output is in ndjson format for easy parsing.
        """
        if not self.udid:
            raise SimulatorError("Simulator not booted")

        predicate = 'subsystem == "com.unamentis.ttfa"'
        logger.info("Starting log stream with predicate: %s", predicate)

        proc = await asyncio.create_subprocess_exec(
            "xcrun",
            "simctl",
            "spawn",
            self.udid,
            "log",
            "stream",
            "--predicate",
            predicate,
            "--style",
            "ndjson",
            "--level",
            "info",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        return proc

    async def read_log_lines(
        self,
        proc: asyncio.subprocess.Process,
        timeout: float = 30.0,
    ) -> AsyncIterator[str]:
        """
        Yield log lines from the stream process until timeout.

        This is an async generator that yields each line as it arrives.
        """
        if proc.stdout is None:
            return

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                line_bytes = await asyncio.wait_for(
                    proc.stdout.readline(),
                    timeout=min(remaining, 1.0),
                )
                if not line_bytes:
                    break
                line = line_bytes.decode("utf-8", errors="replace").strip()
                if line:
                    yield line
            except asyncio.TimeoutError:
                continue

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    async def _find_or_create_device(self) -> str:
        """Find a simulator UDID by device name, or raise if not found."""
        result = await self._run("xcrun", "simctl", "list", "devices", "--json")
        data = json.loads(result)
        for runtime, devices in data.get("devices", {}).items():
            if "iOS" not in runtime:
                continue
            for device in devices:
                if device["name"] == self.device_name and device["isAvailable"]:
                    return device["udid"]
        raise SimulatorError(
            f"No available simulator found with name '{self.device_name}'. "
            "Check `xcrun simctl list devices`."
        )

    async def _get_device_state(self, udid: str) -> str:
        """Get the current state of a simulator device."""
        result = await self._run("xcrun", "simctl", "list", "devices", "--json")
        data = json.loads(result)
        for runtime, devices in data.get("devices", {}).items():
            for device in devices:
                if device["udid"] == udid:
                    return device["state"]
        return "Unknown"

    @staticmethod
    async def _run(*args: str) -> str:
        """Run a command and return stdout. Raises on non-zero exit."""
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        if proc.returncode != 0:
            raise SimulatorError(
                f"Command failed ({proc.returncode}): {' '.join(args)}\n"
                f"stderr: {stderr.decode('utf-8', errors='replace')}"
            )
        return stdout.decode("utf-8", errors="replace")
