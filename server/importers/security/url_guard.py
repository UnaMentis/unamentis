"""
SSRF and archive-extraction guards for the importer pipeline.

The importers fetch and parse external curriculum (HTML, EPUB/ZIP, PDF, JSON
APIs, image URLs). Those URLs are attacker-influenceable (they come from scraped
pages and third-party API responses), so a server-side fetch is an SSRF
primitive: without validation it can be coerced into requesting cloud metadata
(169.254.169.254), loopback services, or other internal hosts, and archive
extraction without path checks is a zip-slip arbitrary-file-write primitive.

This module centralizes the defenses so every fetch and extraction site shares
one implementation:

- ``assert_url_allowed`` / ``safe_fetch``: scheme allow-list, resolution of the
  host to its IPs with rejection of loopback/private/link-local/reserved ranges,
  re-validation on every redirect hop, and a hard response-size cap.
- ``safe_extract_zip``: per-member path containment, symlink and absolute-path
  rejection, and per-file / total uncompressed-size caps (zip-bomb defense).

The validators are intentionally dependency-free (stdlib + aiohttp) and testable
without network access via the injectable ``resolver`` hook.
"""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import os
import socket
import zipfile
from collections.abc import Awaitable, Callable, Iterable
from urllib.parse import urljoin, urlparse

logger = logging.getLogger(__name__)

# Default limits. Callers may override per site.
DEFAULT_MAX_BYTES = 100 * 1024 * 1024  # 100 MB per response
DEFAULT_MAX_REDIRECTS = 5
DEFAULT_ALLOWED_SCHEMES = ("http", "https")

# Zip extraction defaults.
DEFAULT_MAX_ZIP_FILES = 10_000
DEFAULT_MAX_ZIP_TOTAL_BYTES = 500 * 1024 * 1024  # 500 MB uncompressed
DEFAULT_MAX_ZIP_FILE_BYTES = 100 * 1024 * 1024  # 100 MB per entry

# Hostnames that must never be fetched even before DNS resolution.
_BLOCKED_HOSTNAMES = frozenset(
    {
        "metadata.google.internal",
        "metadata",
        "instance-data",
        "instance-data.ec2.internal",
    }
)

# A resolver maps a hostname to a list of (family, ip_string) tuples.
Resolver = Callable[[str], Awaitable[Iterable[str]]]


class UnsafeURLError(ValueError):
    """Raised when a URL is not allowed to be fetched (SSRF protection)."""


def is_blocked_ip(ip_str: str) -> bool:
    """Return True if an IP address is in a range we must never fetch.

    Blocks loopback, private, link-local (includes the 169.254.169.254 cloud
    metadata address), reserved, multicast, and unspecified ranges, for both
    IPv4 and IPv6. IPv4-mapped IPv6 addresses are unwrapped and re-checked.
    """
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        # Not a parseable address: treat as unsafe rather than guessing.
        return True

    # Unwrap IPv4-mapped IPv6 (e.g. ::ffff:169.254.169.254) and re-check.
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        return is_blocked_ip(str(ip.ipv4_mapped))

    return (
        ip.is_loopback
        or ip.is_private
        or ip.is_link_local
        or ip.is_reserved
        or ip.is_multicast
        or ip.is_unspecified
    )


async def _default_resolver(host: str) -> list[str]:
    """Resolve a hostname to its IP addresses using the running event loop."""
    loop = asyncio.get_running_loop()
    infos = await loop.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
    # getaddrinfo returns (family, type, proto, canonname, sockaddr);
    # sockaddr[0] is the IP for both AF_INET and AF_INET6.
    return [info[4][0] for info in infos]


async def assert_url_allowed(
    url: str,
    *,
    allowed_schemes: Iterable[str] = DEFAULT_ALLOWED_SCHEMES,
    resolver: Resolver | None = None,
) -> None:
    """Validate that ``url`` is safe to fetch, or raise ``UnsafeURLError``.

    Checks the scheme against the allow-list, rejects known-internal hostnames,
    resolves the host to all of its IP addresses, and rejects the request if any
    resolved address falls in a blocked range. Resolving every address (and
    re-validating per redirect in ``safe_fetch``) is the standard mitigation
    against an attacker pointing a public name at an internal IP.
    """
    parsed = urlparse(url)
    scheme = (parsed.scheme or "").lower()
    if scheme not in {s.lower() for s in allowed_schemes}:
        raise UnsafeURLError(
            f"Scheme {scheme!r} is not allowed (allowed: {sorted(allowed_schemes)})"
        )

    host = parsed.hostname
    if not host:
        raise UnsafeURLError(f"URL has no host: {url!r}")

    if host.lower() in _BLOCKED_HOSTNAMES:
        raise UnsafeURLError(f"Hostname {host!r} is blocked")

    # If the host is already a literal IP, validate it directly.
    try:
        ipaddress.ip_address(host)
        literal_ip = True
    except ValueError:
        literal_ip = False

    resolve = resolver or _default_resolver
    if literal_ip:
        addresses: Iterable[str] = [host]
    else:
        try:
            addresses = list(await resolve(host))
        except (socket.gaierror, OSError) as exc:
            raise UnsafeURLError(f"Could not resolve host {host!r}: {exc}") from exc

    if not addresses:
        raise UnsafeURLError(f"Host {host!r} resolved to no addresses")

    for addr in addresses:
        if is_blocked_ip(addr):
            raise UnsafeURLError(f"Host {host!r} resolves to a blocked address ({addr})")


async def safe_fetch(
    session,
    url: str,
    *,
    method: str = "GET",
    max_bytes: int = DEFAULT_MAX_BYTES,
    max_redirects: int = DEFAULT_MAX_REDIRECTS,
    allowed_schemes: Iterable[str] = DEFAULT_ALLOWED_SCHEMES,
    resolver: Resolver | None = None,
    **kwargs,
) -> bytes:
    """Fetch ``url`` with SSRF protection, manual redirect validation, and a
    hard size cap.

    Redirects are followed manually (``allow_redirects=False``) so each hop is
    re-validated with ``assert_url_allowed`` before it is requested, closing the
    "validate the first URL then redirect to an internal host" bypass. The body
    is read incrementally and aborted if it exceeds ``max_bytes``.

    Returns the response body as bytes. Raises ``UnsafeURLError`` for a
    disallowed URL and ``ValueError`` if the body exceeds the cap.
    """
    current = url
    for _hop in range(max_redirects + 1):
        await assert_url_allowed(current, allowed_schemes=allowed_schemes, resolver=resolver)
        async with session.request(method, current, allow_redirects=False, **kwargs) as resp:
            if resp.status in (301, 302, 303, 307, 308):
                location = resp.headers.get("Location")
                if not location:
                    raise UnsafeURLError(f"Redirect from {current!r} without a Location header")
                current = urljoin(current, location)
                continue

            # Enforce the size cap up front when the server declares a length.
            declared = resp.headers.get("Content-Length")
            if declared is not None:
                try:
                    if int(declared) > max_bytes:
                        raise ValueError(
                            f"Response exceeds {max_bytes} byte cap (Content-Length={declared})"
                        )
                except ValueError as exc:
                    if "cap" in str(exc):
                        raise
                    # Non-integer Content-Length: ignore and rely on streaming.

            chunks = []
            total = 0
            async for chunk in resp.content.iter_chunked(64 * 1024):
                total += len(chunk)
                if total > max_bytes:
                    raise ValueError(f"Response exceeds {max_bytes} byte cap")
                chunks.append(chunk)
            return b"".join(chunks)

    raise UnsafeURLError(f"Too many redirects (>{max_redirects}) starting at {url!r}")


def safe_extract_zip(
    zip_file: zipfile.ZipFile,
    dest_dir: str,
    *,
    max_files: int = DEFAULT_MAX_ZIP_FILES,
    max_total_bytes: int = DEFAULT_MAX_ZIP_TOTAL_BYTES,
    max_file_bytes: int = DEFAULT_MAX_ZIP_FILE_BYTES,
) -> list[str]:
    """Safely extract a ZIP archive, defending against zip-slip and zip bombs.

    For each member: reject absolute paths and any path that escapes
    ``dest_dir`` after normalization (``..`` traversal), skip symlink entries,
    and enforce per-file and total uncompressed-size caps. Returns the list of
    written file paths. Raises ``ValueError`` on a malicious entry or a cap
    breach.

    Use this instead of ``ZipFile.extractall``, which performs none of these
    checks.
    """
    dest_root = os.path.realpath(dest_dir)
    os.makedirs(dest_root, exist_ok=True)

    infos = zip_file.infolist()
    if len(infos) > max_files:
        raise ValueError(f"Archive has too many entries ({len(infos)} > {max_files})")

    total = 0
    written: list[str] = []
    for info in infos:
        name = info.filename

        # Reject absolute paths outright.
        if name.startswith("/") or (len(name) > 1 and name[1] == ":"):
            raise ValueError(f"Refusing absolute path in archive: {name!r}")

        # Reject symlinks (top 4 bits of external_attr hold the unix file type;
        # 0xA000 == S_IFLNK).
        if (info.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError(f"Refusing symlink entry in archive: {name!r}")

        target = os.path.realpath(os.path.join(dest_root, name))
        if target != dest_root and not target.startswith(dest_root + os.sep):
            raise ValueError(f"Refusing path traversal in archive: {name!r}")

        if info.is_dir():
            os.makedirs(target, exist_ok=True)
            continue

        if info.file_size > max_file_bytes:
            raise ValueError(
                f"Archive entry {name!r} exceeds per-file cap ({info.file_size} > {max_file_bytes})"
            )
        total += info.file_size
        if total > max_total_bytes:
            raise ValueError(f"Archive uncompressed size exceeds total cap (> {max_total_bytes})")

        os.makedirs(os.path.dirname(target), exist_ok=True)
        with zip_file.open(info) as src, open(target, "wb") as dst:
            remaining = max_file_bytes
            while True:
                buf = src.read(64 * 1024)
                if not buf:
                    break
                remaining -= len(buf)
                if remaining < 0:
                    raise ValueError(f"Archive entry {name!r} larger than declared; aborting")
                dst.write(buf)
        written.append(target)

    return written
