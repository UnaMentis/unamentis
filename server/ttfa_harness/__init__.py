"""
UnaMentis TTFA (Time To First Audio) Test Harness

Simulator-based performance test suite that measures the time from feature
activation to first audible audio output across all audio-producing features.

Target: < 1000ms for all features, no exceptions.

Architecture:
    In-app TTFAInstrumentation actor emits structured os_log events.
    This external harness drives the simulator, captures log events,
    and computes TTFA per feature with baseline regression detection.

Usage:
    python -m ttfa_harness.cli --suite quick
    python -m ttfa_harness.cli --suite full --create-baseline initial
    python -m ttfa_harness.cli --suite quick --baseline main --fail-on-regression
"""

__version__ = "1.0.0"
