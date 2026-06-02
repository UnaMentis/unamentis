"""Tests for IP coarsening on telemetry/log intake (audit finding B10)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ip_privacy import coarsen_ip


class TestCoarsenIp:
    def test_ipv4_masked_to_24(self):
        assert coarsen_ip("203.0.113.42") == "203.0.113.0/24"

    def test_ipv4_strips_port(self):
        assert coarsen_ip("203.0.113.42:51234") == "203.0.113.0/24"

    def test_ipv6_masked_to_48(self):
        assert coarsen_ip("2001:db8:1234:5678::1") == "2001:db8:1234::/48"

    def test_ipv6_strips_zone_id(self):
        assert coarsen_ip("fe80::1%en0") == "fe80::/48"

    def test_empty_returns_unknown(self):
        assert coarsen_ip("") == "unknown"

    def test_none_returns_unknown(self):
        assert coarsen_ip(None) == "unknown"

    def test_unparseable_returns_unknown(self):
        assert coarsen_ip("not-an-ip") == "unknown"

    def test_unknown_passthrough(self):
        assert coarsen_ip("unknown") == "unknown"

    def test_result_is_never_the_raw_host(self):
        # The coarsened value must not equal the original host address.
        assert coarsen_ip("198.51.100.77") != "198.51.100.77"
