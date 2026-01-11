# TTS Resource Pool
# Priority-based TTS generation with concurrency limits

import asyncio
import logging
from dataclasses import dataclass
from enum import IntEnum
from typing import Optional, Tuple, Callable, Awaitable

import aiohttp

logger = logging.getLogger(__name__)


class Priority(IntEnum):
    """Priority levels for TTS generation requests.

    Higher values = higher priority.
    """
    SCHEDULED = 1   # Background pre-generation for deployments
    PREFETCH = 5    # Near-future prefetch during playback
    LIVE = 10       # User actively waiting for audio


# TTS server URLs (default ports)
TTS_SERVERS = {
    "vibevoice": "http://localhost:8880/v1/audio/speech",
    "piper": "http://localhost:11402/v1/audio/speech",
    "chatterbox": "http://localhost:8004/v1/audio/speech",
}

# Sample rates by provider
SAMPLE_RATES = {
    "vibevoice": 24000,
    "piper": 22050,
    "chatterbox": 24000,
}


@dataclass
class GenerationResult:
    """Result of a TTS generation request."""
    audio_data: bytes
    sample_rate: int
    duration_seconds: float


class TTSResourcePool:
    """Manages TTS generation with priority and concurrency limits.

    Features:
    - Separate concurrency limits for live vs background requests
    - Live users never starved by background pre-generation
    - Rate limiting to avoid overwhelming TTS servers
    - Statistics tracking

    Usage:
        pool = TTSResourcePool()
        result = await pool.generate_with_priority(
            text="Hello world",
            voice_id="nova",
            provider="vibevoice",
            priority=Priority.LIVE
        )
    """

    def __init__(
        self,
        max_concurrent_live: int = 7,
        max_concurrent_background: int = 3,
        request_timeout: float = 30.0,
    ):
        """Initialize resource pool.

        Args:
            max_concurrent_live: Max concurrent LIVE priority requests (default 7)
            max_concurrent_background: Max concurrent background requests (default 3)
            request_timeout: Timeout for TTS requests in seconds (default 30)
        """
        self.max_concurrent_live = max_concurrent_live
        self.max_concurrent_background = max_concurrent_background
        self.request_timeout = request_timeout

        # Separate semaphores for live and background
        self._live_semaphore = asyncio.Semaphore(max_concurrent_live)
        self._background_semaphore = asyncio.Semaphore(max_concurrent_background)

        # Statistics
        self._live_requests = 0
        self._background_requests = 0
        self._live_in_flight = 0
        self._background_in_flight = 0
        self._errors = 0

        # Optional: custom TTS server URLs (can be overridden)
        self.tts_servers = dict(TTS_SERVERS)
        self.sample_rates = dict(SAMPLE_RATES)

    async def generate_with_priority(
        self,
        text: str,
        voice_id: str,
        provider: str,
        speed: float = 1.0,
        chatterbox_config: Optional[dict] = None,
        priority: Priority = Priority.LIVE,
    ) -> Tuple[bytes, int, float]:
        """Generate TTS audio with priority-based queuing.

        Args:
            text: Text to synthesize
            voice_id: Voice identifier
            provider: TTS provider name (vibevoice, piper, chatterbox)
            speed: Speech speed multiplier
            chatterbox_config: Optional Chatterbox-specific parameters
            priority: Request priority (LIVE, PREFETCH, SCHEDULED)

        Returns:
            Tuple of (audio_bytes, sample_rate, duration_seconds)

        Raises:
            ValueError: If provider is unknown
            Exception: If TTS generation fails
        """
        # Select semaphore based on priority
        if priority >= Priority.LIVE:
            semaphore = self._live_semaphore
            is_live = True
        else:
            semaphore = self._background_semaphore
            is_live = False

        # Acquire semaphore and generate
        async with semaphore:
            if is_live:
                self._live_in_flight += 1
                self._live_requests += 1
            else:
                self._background_in_flight += 1
                self._background_requests += 1

            try:
                result = await self._generate_tts(
                    text=text,
                    voice_id=voice_id,
                    provider=provider,
                    speed=speed,
                    chatterbox_config=chatterbox_config,
                )
                return result.audio_data, result.sample_rate, result.duration_seconds
            except Exception as e:
                self._errors += 1
                raise
            finally:
                if is_live:
                    self._live_in_flight -= 1
                else:
                    self._background_in_flight -= 1

    async def _generate_tts(
        self,
        text: str,
        voice_id: str,
        provider: str,
        speed: float,
        chatterbox_config: Optional[dict],
    ) -> GenerationResult:
        """Internal: Generate TTS audio from provider.

        Args:
            text: Text to synthesize
            voice_id: Voice identifier
            provider: TTS provider name
            speed: Speech speed multiplier
            chatterbox_config: Optional Chatterbox-specific parameters

        Returns:
            GenerationResult with audio data and metadata
        """
        tts_url = self.tts_servers.get(provider)
        if not tts_url:
            raise ValueError(f"Unknown TTS provider: {provider}")

        sample_rate = self.sample_rates.get(provider, 24000)

        # Build request payload (OpenAI-compatible format)
        payload = {
            "model": "tts-1",
            "input": text,
            "voice": voice_id,
            "response_format": "wav",
            "speed": speed,
        }

        # Add Chatterbox-specific params
        if provider == "chatterbox" and chatterbox_config:
            if "exaggeration" in chatterbox_config:
                payload["exaggeration"] = chatterbox_config["exaggeration"]
            if "cfg_weight" in chatterbox_config:
                payload["cfg_weight"] = chatterbox_config["cfg_weight"]
            if "language" in chatterbox_config:
                payload["language"] = chatterbox_config["language"]

        timeout = aiohttp.ClientTimeout(total=self.request_timeout)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            try:
                async with session.post(tts_url, json=payload) as resp:
                    if resp.status != 200:
                        error_text = await resp.text()
                        logger.error(f"TTS request failed ({resp.status}): {error_text}")
                        raise Exception(f"TTS server returned {resp.status}: {error_text}")

                    audio_data = await resp.read()

                    # Estimate duration from WAV data
                    # WAV header is 44 bytes, 16-bit samples = 2 bytes per sample
                    data_size = len(audio_data) - 44
                    samples = data_size // 2
                    duration = samples / sample_rate

                    return GenerationResult(
                        audio_data=audio_data,
                        sample_rate=sample_rate,
                        duration_seconds=duration,
                    )

            except aiohttp.ClientError as e:
                logger.error(f"TTS request error: {e}")
                raise Exception(f"TTS server connection failed: {e}")

    def get_stats(self) -> dict:
        """Get resource pool statistics.

        Returns:
            Dictionary with pool statistics
        """
        return {
            "live_requests": self._live_requests,
            "background_requests": self._background_requests,
            "live_in_flight": self._live_in_flight,
            "background_in_flight": self._background_in_flight,
            "live_available": self.max_concurrent_live - self._live_in_flight,
            "background_available": self.max_concurrent_background - self._background_in_flight,
            "errors": self._errors,
            "max_concurrent_live": self.max_concurrent_live,
            "max_concurrent_background": self.max_concurrent_background,
        }

    def configure_server(self, provider: str, url: str, sample_rate: int = 24000) -> None:
        """Configure a TTS server URL.

        Args:
            provider: Provider name
            url: Server URL
            sample_rate: Audio sample rate (default 24000)
        """
        self.tts_servers[provider] = url
        self.sample_rates[provider] = sample_rate
        logger.info(f"Configured TTS server: {provider} -> {url} ({sample_rate}Hz)")
