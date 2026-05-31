"""
Image Acquisition Service for curriculum imports.

Handles:
1. Validating and downloading images from URLs
2. Finding alternative images when URLs fail (via Wikimedia Commons search)
3. Generating placeholder images as a final fallback

This ensures curricula always have displayable visual assets.
"""

from __future__ import annotations

import asyncio
import base64
import logging
import re
import tempfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

import aiohttp

from ..security.url_guard import UnsafeURLError, assert_url_allowed

logger = logging.getLogger(__name__)


class ImageSourceType(Enum):
    """Source of the acquired image."""

    ORIGINAL = "original"  # Downloaded from original URL
    WIKIMEDIA_SEARCH = "wikimedia"  # Found via Wikimedia Commons search
    GENERATED = "generated"  # Generated placeholder
    FAILED = "failed"  # All methods failed


@dataclass
class AcquiredImage:
    """Result of image acquisition."""

    success: bool
    source_type: ImageSourceType
    data: bytes | None = None
    mime_type: str | None = None
    new_url: str | None = None
    width: int = 0
    height: int = 0
    attribution: str | None = None
    error: str | None = None


@dataclass
class ImageAssetInfo:
    """Information about an image asset from UMCF."""

    id: str
    url: str | None
    local_path: str | None
    title: str | None
    alt: str | None
    caption: str | None
    audio_description: str | None
    asset_type: str  # image, diagram, chart, etc.
    width: int = 0
    height: int = 0


class ImageAcquisitionService:
    """
    Service for acquiring images during curriculum import.

    Attempts multiple strategies:
    1. Download from original URL
    2. Search Wikimedia Commons for alternative
    3. Generate placeholder based on description
    """

    WIKIMEDIA_API = "https://commons.wikimedia.org/w/api.php"

    # Common image-related keywords to help search
    SEARCH_ENHANCERS = {
        "diagram": ["diagram", "illustration", "chart"],
        "chart": ["chart", "graph", "data visualization"],
        "image": ["photo", "picture", "image"],
        "map": ["map", "geography", "cartography"],
    }

    def __init__(
        self,
        cache_dir: Path | None = None,
        max_retries: int = 3,
        timeout: int = 30,
    ):
        self.cache_dir = cache_dir or Path(tempfile.gettempdir()) / "unamentis_image_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.max_retries = max_retries
        self.timeout = timeout
        self._session: aiohttp.ClientSession | None = None

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create aiohttp session."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=self.timeout),
                headers={
                    "User-Agent": "UnaMentis/1.0 (Educational AI Tutor; https://github.com/unamentis)"
                },
            )
        return self._session

    async def close(self):
        """Close the session."""
        if self._session and not self._session.closed:
            await self._session.close()

    async def acquire_image(self, asset: ImageAssetInfo) -> AcquiredImage:
        """
        Acquire an image through multiple fallback strategies.

        Args:
            asset: Image asset information from UMCF

        Returns:
            AcquiredImage with the result
        """
        # Strategy 1: Try original URL
        if asset.url:
            result = await self._download_from_url(asset.url)
            if result.success:
                logger.info(f"Successfully downloaded image from original URL: {asset.id}")
                return result
            logger.warning(f"Original URL failed for {asset.id}: {result.error}")

        # Strategy 2: Search Wikimedia Commons
        search_query = self._build_search_query(asset)
        if search_query:
            result = await self._search_wikimedia(search_query, asset)
            if result.success:
                logger.info(f"Found alternative image on Wikimedia for {asset.id}")
                return result
            logger.warning(f"Wikimedia search failed for {asset.id}")

        # Strategy 3: Generate placeholder
        result = await self._generate_placeholder(asset)
        if result.success:
            logger.info(f"Generated placeholder image for {asset.id}")
            return result

        # All strategies failed
        return AcquiredImage(
            success=False,
            source_type=ImageSourceType.FAILED,
            error=f"All acquisition strategies failed for {asset.id}",
        )

    async def _download_from_url(self, url: str) -> AcquiredImage:
        """Download image from URL."""
        try:
            await assert_url_allowed(url)
        except UnsafeURLError as e:
            return AcquiredImage(
                success=False,
                source_type=ImageSourceType.ORIGINAL,
                error=f"Blocked unsafe image URL: {e}",
            )
        try:
            session = await self._get_session()

            for attempt in range(self.max_retries):
                try:
                    async with session.get(url) as response:
                        if response.status == 200:
                            data = await response.read()
                            content_type = response.headers.get("Content-Type", "image/jpeg")

                            # Verify it's actually image data
                            if not self._is_valid_image(data):
                                return AcquiredImage(
                                    success=False,
                                    source_type=ImageSourceType.ORIGINAL,
                                    error="Downloaded data is not a valid image",
                                )

                            # Get dimensions
                            width, height = self._get_image_dimensions(data)

                            return AcquiredImage(
                                success=True,
                                source_type=ImageSourceType.ORIGINAL,
                                data=data,
                                mime_type=content_type,
                                new_url=url,
                                width=width,
                                height=height,
                            )
                        elif response.status == 404:
                            return AcquiredImage(
                                success=False,
                                source_type=ImageSourceType.ORIGINAL,
                                error=f"HTTP 404: Image not found at {url}",
                            )
                        else:
                            if attempt < self.max_retries - 1:
                                await asyncio.sleep(1 * (attempt + 1))
                                continue
                            return AcquiredImage(
                                success=False,
                                source_type=ImageSourceType.ORIGINAL,
                                error=f"HTTP {response.status}",
                            )
                except asyncio.TimeoutError:
                    if attempt < self.max_retries - 1:
                        await asyncio.sleep(1 * (attempt + 1))
                        continue
                    return AcquiredImage(
                        success=False,
                        source_type=ImageSourceType.ORIGINAL,
                        error="Download timeout",
                    )
        except Exception as e:
            return AcquiredImage(success=False, source_type=ImageSourceType.ORIGINAL, error=str(e))

    def _build_search_query(self, asset: ImageAssetInfo) -> str | None:
        """Build a search query from asset metadata."""
        parts = []

        # Use title if available
        if asset.title:
            # Clean up the title, removing common non-descriptive words
            clean_title = re.sub(r"[^\w\s\'-]", " ", asset.title)
            # Remove common suffixes that hurt search
            clean_title = re.sub(r"\s+by\s+", " ", clean_title, flags=re.IGNORECASE)
            clean_title = re.sub(r"\s+\d{4}\s*$", "", clean_title)  # Remove years at end
            parts.append(clean_title.strip())

        # Also add alt text for more context
        if asset.alt:
            clean_alt = re.sub(r"[^\w\s\'-]", " ", asset.alt)
            # Take key words from alt, not the whole thing
            alt_words = clean_alt.split()[:6]  # First 6 words
            if alt_words:
                parts.append(" ".join(alt_words))

        # Use caption as additional context
        if asset.caption:
            clean_caption = re.sub(r"[^\w\s\'-]", " ", asset.caption)
            caption_words = clean_caption.split()[:4]
            if caption_words:
                parts.append(" ".join(caption_words))

        if not parts:
            return None

        # Combine and deduplicate words
        all_words = " ".join(parts).lower().split()
        seen = set()
        unique_words = []
        for word in all_words:
            if word not in seen and len(word) > 2:
                seen.add(word)
                unique_words.append(word)
                if len(unique_words) >= 6:  # Limit to 6 keywords
                    break

        query = " ".join(unique_words)

        # Add type-specific enhancers
        enhancers = self.SEARCH_ENHANCERS.get(asset.asset_type, [])
        if enhancers:
            query = f"{query} {enhancers[0]}"

        return query.strip()

    async def _search_wikimedia(
        self,
        query: str,
        asset: ImageAssetInfo,
    ) -> AcquiredImage:
        """Search Wikimedia Commons for an image."""
        try:
            session = await self._get_session()

            # Search for images
            params = {
                "action": "query",
                "format": "json",
                "list": "search",
                "srsearch": f"{query} filetype:bitmap",
                "srnamespace": "6",  # File namespace
                "srlimit": "5",
            }

            async with session.get(self.WIKIMEDIA_API, params=params) as response:
                if response.status != 200:
                    return AcquiredImage(
                        success=False,
                        source_type=ImageSourceType.WIKIMEDIA_SEARCH,
                        error=f"Wikimedia search failed: HTTP {response.status}",
                    )

                data = await response.json()
                results = data.get("query", {}).get("search", [])

                if not results:
                    return AcquiredImage(
                        success=False,
                        source_type=ImageSourceType.WIKIMEDIA_SEARCH,
                        error="No results found on Wikimedia Commons",
                    )

                # Try each result
                for result in results:
                    title = result.get("title", "")
                    if not title.startswith("File:"):
                        continue

                    # Get image info
                    image_result = await self._get_wikimedia_image(title)
                    if image_result.success:
                        return image_result

                return AcquiredImage(
                    success=False,
                    source_type=ImageSourceType.WIKIMEDIA_SEARCH,
                    error="Could not download any search results",
                )

        except Exception as e:
            return AcquiredImage(
                success=False, source_type=ImageSourceType.WIKIMEDIA_SEARCH, error=str(e)
            )

    async def _get_wikimedia_image(self, file_title: str) -> AcquiredImage:
        """Get image data from Wikimedia Commons."""
        try:
            session = await self._get_session()

            # Get image info including URL
            params = {
                "action": "query",
                "format": "json",
                "titles": file_title,
                "prop": "imageinfo",
                "iiprop": "url|size|mime|extmetadata",
                "iiurlwidth": "800",  # Get thumbnail up to 800px
            }

            async with session.get(self.WIKIMEDIA_API, params=params) as response:
                if response.status != 200:
                    return AcquiredImage(
                        success=False,
                        source_type=ImageSourceType.WIKIMEDIA_SEARCH,
                        error=f"Failed to get image info: HTTP {response.status}",
                    )

                data = await response.json()
                pages = data.get("query", {}).get("pages", {})

                for page_id, page_data in pages.items():
                    if page_id == "-1":
                        continue

                    imageinfo = page_data.get("imageinfo", [{}])[0]
                    thumb_url = imageinfo.get("thumburl") or imageinfo.get("url")

                    if not thumb_url:
                        continue

                    # Download the image
                    result = await self._download_from_url(thumb_url)
                    if result.success:
                        # Extract attribution
                        extmeta = imageinfo.get("extmetadata", {})
                        artist = extmeta.get("Artist", {}).get("value", "")
                        license_name = extmeta.get("LicenseShortName", {}).get("value", "")

                        attribution = None
                        if artist or license_name:
                            attribution = "Image from Wikimedia Commons"
                            if artist:
                                # Strip HTML tags
                                clean_artist = re.sub(r"<[^>]+>", "", artist)
                                attribution += f" by {clean_artist}"
                            if license_name:
                                attribution += f" ({license_name})"

                        return AcquiredImage(
                            success=True,
                            source_type=ImageSourceType.WIKIMEDIA_SEARCH,
                            data=result.data,
                            mime_type=result.mime_type,
                            new_url=thumb_url,
                            width=imageinfo.get("thumbwidth", result.width),
                            height=imageinfo.get("thumbheight", result.height),
                            attribution=attribution,
                        )

                return AcquiredImage(
                    success=False,
                    source_type=ImageSourceType.WIKIMEDIA_SEARCH,
                    error="Could not extract image URL",
                )

        except Exception as e:
            return AcquiredImage(
                success=False, source_type=ImageSourceType.WIKIMEDIA_SEARCH, error=str(e)
            )

    async def _generate_placeholder(self, asset: ImageAssetInfo) -> AcquiredImage:
        """Generate a placeholder image based on asset description."""
        try:
            # Create a simple SVG placeholder
            width = asset.width or 800
            height = asset.height or 600

            # Extract key text for the placeholder
            display_text = asset.title or asset.alt or "Image"
            if len(display_text) > 50:
                display_text = display_text[:47] + "..."

            # Choose color based on asset type
            colors = {
                "diagram": ("#E3F2FD", "#1976D2"),  # Blue
                "chart": ("#E8F5E9", "#388E3C"),  # Green
                "image": ("#FFF3E0", "#F57C00"),  # Orange
                "map": ("#F3E5F5", "#7B1FA2"),  # Purple
                "equation": ("#ECEFF1", "#455A64"),  # Gray
            }
            bg_color, text_color = colors.get(asset.asset_type, ("#F5F5F5", "#616161"))

            # Icon based on type
            icons = {
                "diagram": "&#x1F4CA;",  # Chart
                "chart": "&#x1F4C8;",  # Chart with upward trend
                "image": "&#x1F5BC;",  # Framed picture
                "map": "&#x1F5FA;",  # World map
                "equation": "&#x2211;",  # Sigma
            }
            icon = icons.get(asset.asset_type, "&#x1F5BC;")

            # Escape text for SVG
            safe_text = (
                display_text.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace('"', "&quot;")
            )

            svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect fill="{bg_color}" width="{width}" height="{height}"/>
  <rect fill="{bg_color}" stroke="{text_color}" stroke-width="2" x="10" y="10" width="{width - 20}" height="{height - 20}" rx="8"/>
  <text x="{width // 2}" y="{height // 2 - 30}" font-family="system-ui, sans-serif" font-size="48" fill="{text_color}" text-anchor="middle">{icon}</text>
  <text x="{width // 2}" y="{height // 2 + 30}" font-family="system-ui, sans-serif" font-size="18" fill="{text_color}" text-anchor="middle" font-weight="500">{safe_text}</text>
  <text x="{width // 2}" y="{height // 2 + 60}" font-family="system-ui, sans-serif" font-size="12" fill="{text_color}" text-anchor="middle" opacity="0.7">Placeholder - original image unavailable</text>
</svg>'''

            svg_bytes = svg.encode("utf-8")

            return AcquiredImage(
                success=True,
                source_type=ImageSourceType.GENERATED,
                data=svg_bytes,
                mime_type="image/svg+xml",
                width=width,
                height=height,
                attribution="Generated placeholder image",
            )

        except Exception as e:
            return AcquiredImage(success=False, source_type=ImageSourceType.GENERATED, error=str(e))

    def _is_valid_image(self, data: bytes) -> bool:
        """Check if data is a valid image."""
        if len(data) < 8:
            return False

        # Check magic bytes
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            return True
        if data[:2] == b"\xff\xd8":  # JPEG
            return True
        if data[:6] in (b"GIF87a", b"GIF89a"):
            return True
        if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
            return True
        if b"<svg" in data[:500]:  # SVG
            return True

        return False

    def _get_image_dimensions(self, data: bytes) -> tuple[int, int]:
        """Get image dimensions from data."""
        try:
            # PNG
            if data[:8] == b"\x89PNG\r\n\x1a\n":
                if len(data) >= 24:
                    width = int.from_bytes(data[16:20], "big")
                    height = int.from_bytes(data[20:24], "big")
                    return width, height

            # JPEG
            if data[:2] == b"\xff\xd8":
                # Find SOF marker
                i = 2
                while i < len(data) - 9:
                    if data[i] == 0xFF:
                        marker = data[i + 1]
                        if marker in (0xC0, 0xC1, 0xC2):  # SOF markers
                            height = int.from_bytes(data[i + 5 : i + 7], "big")
                            width = int.from_bytes(data[i + 7 : i + 9], "big")
                            return width, height
                        length = int.from_bytes(data[i + 2 : i + 4], "big")
                        i += 2 + length
                    else:
                        i += 1

            # GIF
            if data[:6] in (b"GIF87a", b"GIF89a"):
                if len(data) >= 10:
                    width = int.from_bytes(data[6:8], "little")
                    height = int.from_bytes(data[8:10], "little")
                    return width, height

        except Exception:
            pass

        return 0, 0

    async def acquire_all_images(
        self,
        assets: list[ImageAssetInfo],
        progress_callback: callable | None = None,
    ) -> dict[str, AcquiredImage]:
        """
        Acquire all images for a list of assets.

        Args:
            assets: List of image assets to acquire
            progress_callback: Optional callback(current, total, message)

        Returns:
            Dict mapping asset ID to AcquiredImage result
        """
        results = {}
        total = len(assets)

        for i, asset in enumerate(assets):
            if progress_callback:
                progress_callback(i, total, f"Acquiring {asset.title or asset.id}")

            result = await self.acquire_image(asset)
            results[asset.id] = result

            # Small delay to be nice to servers
            if i < total - 1:
                await asyncio.sleep(0.2)

        if progress_callback:
            progress_callback(total, total, "Image acquisition complete")

        return results


# Utility function for use during import
async def acquire_curriculum_images(
    media_collection: dict[str, Any],
    output_dir: Path,
    progress_callback: callable | None = None,
) -> dict[str, dict[str, Any]]:
    """
    Acquire all images from a UMCF media collection.

    Args:
        media_collection: UMCF media collection dict with 'embedded' and 'reference' lists
        output_dir: Directory to save acquired images
        progress_callback: Optional progress callback

    Returns:
        Dict mapping asset IDs to acquisition results with file paths
    """
    service = ImageAcquisitionService(cache_dir=output_dir / "images")

    try:
        # Collect all image assets
        assets = []

        for embedded in media_collection.get("embedded", []):
            if embedded.get("type") in ("image", "diagram", "chart", "slideImage"):
                assets.append(
                    ImageAssetInfo(
                        id=embedded.get("id", ""),
                        url=embedded.get("url"),
                        local_path=embedded.get("localPath"),
                        title=embedded.get("title"),
                        alt=embedded.get("alt"),
                        caption=embedded.get("caption"),
                        audio_description=embedded.get("audioDescription"),
                        asset_type=embedded.get("type", "image"),
                        width=embedded.get("dimensions", {}).get("width", 0),
                        height=embedded.get("dimensions", {}).get("height", 0),
                    )
                )

        for reference in media_collection.get("reference", []):
            if reference.get("type") in ("image", "diagram", "chart", "slideImage"):
                assets.append(
                    ImageAssetInfo(
                        id=reference.get("id", ""),
                        url=reference.get("url"),
                        local_path=reference.get("localPath"),
                        title=reference.get("title"),
                        alt=reference.get("alt"),
                        caption=reference.get("caption"),
                        audio_description=reference.get("audioDescription"),
                        asset_type=reference.get("type", "image"),
                        width=reference.get("dimensions", {}).get("width", 0),
                        height=reference.get("dimensions", {}).get("height", 0),
                    )
                )

        if not assets:
            return {}

        # Acquire all images
        results = await service.acquire_all_images(assets, progress_callback)

        # Save acquired images and return file paths
        output_data = {}
        images_dir = output_dir / "images"
        images_dir.mkdir(parents=True, exist_ok=True)

        for asset_id, result in results.items():
            if result.success and result.data:
                # Determine file extension
                ext_map = {
                    "image/jpeg": ".jpg",
                    "image/png": ".png",
                    "image/gif": ".gif",
                    "image/webp": ".webp",
                    "image/svg+xml": ".svg",
                }
                ext = ext_map.get(result.mime_type, ".jpg")

                # Save file
                file_path = images_dir / f"{asset_id}{ext}"
                file_path.write_bytes(result.data)

                output_data[asset_id] = {
                    "success": True,
                    "source_type": result.source_type.value,
                    "file_path": str(file_path),
                    "mime_type": result.mime_type,
                    "width": result.width,
                    "height": result.height,
                    "new_url": result.new_url,
                    "attribution": result.attribution,
                    "data_base64": base64.b64encode(result.data).decode("utf-8"),
                }
            else:
                output_data[asset_id] = {
                    "success": False,
                    "source_type": result.source_type.value,
                    "error": result.error,
                }

        return output_data

    finally:
        await service.close()
