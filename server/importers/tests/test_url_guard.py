"""Tests for the importer SSRF / zip-slip guards (security/url_guard.py)."""

import asyncio
import io
import zipfile

import pytest

from ..security.url_guard import (
    UnsafeURLError,
    assert_url_allowed,
    is_blocked_ip,
    safe_extract_zip,
    safe_fetch,
)


def _resolver(mapping):
    """Build an async resolver from a {host: [ips]} mapping for tests."""

    async def resolve(host):
        return mapping.get(host, [])

    return resolve


# ===== is_blocked_ip =====


@pytest.mark.parametrize(
    "ip",
    [
        "127.0.0.1",  # loopback
        "::1",  # loopback v6
        "10.0.0.5",  # private
        "192.168.1.10",  # private
        "172.16.0.1",  # private
        "169.254.169.254",  # link-local (cloud metadata)
        "fe80::1",  # link-local v6
        "fc00::1",  # unique-local v6 (private)
        "0.0.0.0",  # nosec B104 - test input asserting 0.0.0.0 is blocked, not a bind address
        "224.0.0.1",  # multicast
        "::ffff:169.254.169.254",  # IPv4-mapped metadata address
        "not-an-ip",  # unparseable -> unsafe
    ],
)
def test_is_blocked_ip_blocks_internal(ip):
    assert is_blocked_ip(ip) is True


@pytest.mark.parametrize("ip", ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:2800:220:1::1"])
def test_is_blocked_ip_allows_public(ip):
    assert is_blocked_ip(ip) is False


# ===== assert_url_allowed =====


def test_rejects_non_http_schemes():
    for url in ("file:///etc/passwd", "ftp://host/x", "gopher://h/", "data:text/plain,hi"):
        with pytest.raises(UnsafeURLError):
            asyncio.run(assert_url_allowed(url, resolver=_resolver({})))


def test_rejects_missing_host():
    with pytest.raises(UnsafeURLError):
        asyncio.run(assert_url_allowed("http:///nohost", resolver=_resolver({})))


def test_rejects_blocked_hostname():
    with pytest.raises(UnsafeURLError):
        asyncio.run(
            assert_url_allowed(
                "http://metadata.google.internal/computeMetadata/v1/",
                resolver=_resolver({}),
            )
        )


def test_rejects_literal_private_ip():
    for url in (
        "http://127.0.0.1/",
        "http://169.254.169.254/latest/meta-data/",
        "http://10.1.2.3/",
    ):
        with pytest.raises(UnsafeURLError):
            asyncio.run(assert_url_allowed(url, resolver=_resolver({})))


def test_rejects_host_resolving_to_private():
    resolver = _resolver({"evil.example.com": ["10.0.0.1"]})
    with pytest.raises(UnsafeURLError):
        asyncio.run(assert_url_allowed("https://evil.example.com/x", resolver=resolver))


def test_rejects_mixed_resolution_with_one_private():
    # A public + private mix must be rejected (rebinding / multi-A defense).
    resolver = _resolver({"mixed.example.com": ["93.184.216.34", "169.254.169.254"]})
    with pytest.raises(UnsafeURLError):
        asyncio.run(assert_url_allowed("https://mixed.example.com/x", resolver=resolver))


def test_allows_public_host():
    resolver = _resolver({"example.com": ["93.184.216.34"]})
    # Should not raise.
    asyncio.run(assert_url_allowed("https://example.com/page", resolver=resolver))


def test_rejects_unresolvable_host():
    with pytest.raises(UnsafeURLError):
        asyncio.run(assert_url_allowed("https://nope.example.com/x", resolver=_resolver({})))


# ===== safe_fetch (fake transport, no network) =====


class FakeContent:
    def __init__(self, body: bytes):
        self._body = body

    async def iter_chunked(self, n):
        for i in range(0, len(self._body), n):
            yield self._body[i : i + n]


class FakeResponse:
    def __init__(self, status=200, headers=None, body=b""):
        self.status = status
        self.headers = headers or {}
        self.content = FakeContent(body)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class FakeSession:
    """Minimal stand-in for aiohttp.ClientSession (not a Mock)."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.requested_urls = []

    def request(self, method, url, allow_redirects=False, **kwargs):
        self.requested_urls.append(url)
        return self._responses.pop(0)


def test_safe_fetch_returns_body():
    session = FakeSession([FakeResponse(200, {}, b"hello world")])
    resolver = _resolver({"example.com": ["93.184.216.34"]})
    body = asyncio.run(safe_fetch(session, "https://example.com/x", resolver=resolver))
    assert body == b"hello world"


def test_safe_fetch_follows_redirect_and_revalidates():
    # First hop redirects to an internal host -> must be rejected on the 2nd hop.
    session = FakeSession(
        [
            FakeResponse(302, {"Location": "http://169.254.169.254/latest/"}, b""),
            FakeResponse(200, {}, b"secrets"),
        ]
    )
    resolver = _resolver({"example.com": ["93.184.216.34"]})
    with pytest.raises(UnsafeURLError):
        asyncio.run(safe_fetch(session, "https://example.com/x", resolver=resolver))


def test_safe_fetch_enforces_content_length_cap():
    session = FakeSession([FakeResponse(200, {"Content-Length": "999999"}, b"x")])
    resolver = _resolver({"example.com": ["93.184.216.34"]})
    with pytest.raises(ValueError):
        asyncio.run(safe_fetch(session, "https://example.com/x", max_bytes=1000, resolver=resolver))


def test_safe_fetch_enforces_streaming_cap():
    big = b"a" * 5000
    session = FakeSession([FakeResponse(200, {}, big)])
    resolver = _resolver({"example.com": ["93.184.216.34"]})
    with pytest.raises(ValueError):
        asyncio.run(safe_fetch(session, "https://example.com/x", max_bytes=1000, resolver=resolver))


# ===== safe_extract_zip =====


def _make_zip(entries: dict) -> zipfile.ZipFile:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for name, data in entries.items():
            zf.writestr(name, data)
    buf.seek(0)
    return zipfile.ZipFile(buf, "r")


def test_safe_extract_zip_normal(tmp_path):
    zf = _make_zip({"a.txt": "hello", "sub/b.txt": "world"})
    written = safe_extract_zip(zf, str(tmp_path))
    assert len(written) == 2
    assert (tmp_path / "a.txt").read_text() == "hello"
    assert (tmp_path / "sub" / "b.txt").read_text() == "world"


def test_safe_extract_zip_blocks_traversal(tmp_path):
    zf = _make_zip({"../escape.txt": "pwned"})
    with pytest.raises(ValueError):
        safe_extract_zip(zf, str(tmp_path))
    assert not (tmp_path.parent / "escape.txt").exists()


def test_safe_extract_zip_blocks_absolute_path(tmp_path):
    # zipfile normalizes a leading slash, so craft the absolute path in the entry.
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        info = zipfile.ZipInfo("/etc/evil.txt")
        zf.writestr(info, "x")
    buf.seek(0)
    with pytest.raises(ValueError):
        safe_extract_zip(zipfile.ZipFile(buf, "r"), str(tmp_path))


def test_safe_extract_zip_enforces_total_cap(tmp_path):
    zf = _make_zip({"big.bin": "a" * 5000})
    with pytest.raises(ValueError):
        safe_extract_zip(zf, str(tmp_path), max_total_bytes=1000)


def test_safe_extract_zip_enforces_file_cap(tmp_path):
    zf = _make_zip({"big.bin": "a" * 5000})
    with pytest.raises(ValueError):
        safe_extract_zip(zf, str(tmp_path), max_file_bytes=1000)
