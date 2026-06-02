"""IP address privacy helpers.

Client IPs captured on telemetry/log intake are coarsened so the server does not
retain a precise, per-user network identifier. IPv4 is masked to its /24 network
and IPv6 to its /48, which preserves a coarse abuse/geo signal without
identifying an individual device. This is the privacy posture for the public
beta (see docs/PRIVACY_PRESERVING_USER_DATA.md).
"""

from __future__ import annotations

import ipaddress

UNKNOWN = "unknown"


def coarsen_ip(ip: str | None) -> str:
    """Return a privacy-coarsened form of a client IP address.

    IPv4 is reduced to its /24 network (host bits zeroed) and IPv6 to its /48.
    Empty or unparseable input returns ``"unknown"``. The return value is a
    network-prefix string (for example ``"203.0.113.0/24"``), never a raw host
    address.
    """
    if not ip:
        return UNKNOWN

    candidate = ip.strip()
    if candidate == UNKNOWN:
        return UNKNOWN

    # Drop an IPv6 zone id (fe80::1%en0) and an accidental IPv4 host:port suffix.
    candidate = candidate.split("%", 1)[0]
    if candidate.count(":") == 1 and "." in candidate:
        candidate = candidate.split(":", 1)[0]

    try:
        addr = ipaddress.ip_address(candidate)
    except ValueError:
        return UNKNOWN

    prefix = 24 if addr.version == 4 else 48
    network = ipaddress.ip_network(f"{addr}/{prefix}", strict=False)
    return str(network)
