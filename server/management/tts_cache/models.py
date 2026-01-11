# TTS Cache Models
# Data classes for TTS caching system

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Dict, Optional
import hashlib
import unicodedata
import re


@dataclass(frozen=True)
class TTSCacheKey:
    """Immutable cache key for TTS audio.

    Includes all parameters that affect audio output to ensure
    different voice configurations produce different cache entries.
    """
    text_hash: str           # SHA-256 of normalized text (first 16 chars)
    voice_id: str            # e.g., "nova", "shimmer"
    tts_provider: str        # "vibevoice", "piper", "chatterbox"
    speed: float = 1.0
    # Chatterbox-specific (optional)
    exaggeration: Optional[float] = None
    cfg_weight: Optional[float] = None
    language: Optional[str] = None  # For multilingual Chatterbox

    def to_hash(self) -> str:
        """Generate unique filename hash for this key."""
        # Combine all key components into a single string
        components = [
            self.text_hash,
            self.voice_id,
            self.tts_provider,
            f"{self.speed:.2f}",
        ]
        if self.exaggeration is not None:
            components.append(f"ex{self.exaggeration:.2f}")
        if self.cfg_weight is not None:
            components.append(f"cfg{self.cfg_weight:.2f}")
        if self.language is not None:
            components.append(f"lang{self.language}")

        combined = "|".join(components)
        return hashlib.sha256(combined.encode()).hexdigest()[:16]

    @classmethod
    def normalize_text(cls, text: str) -> str:
        """Normalize text for consistent hashing.

        - Strip leading/trailing whitespace
        - Normalize unicode (NFC)
        - Collapse multiple spaces to single space
        - Lowercase for case-insensitive matching
        """
        text = text.strip()
        text = unicodedata.normalize("NFC", text)
        text = re.sub(r"\s+", " ", text)
        # Don't lowercase - TTS may treat case differently
        return text

    @classmethod
    def hash_text(cls, text: str) -> str:
        """Generate SHA-256 hash of normalized text (first 16 chars)."""
        normalized = cls.normalize_text(text)
        return hashlib.sha256(normalized.encode()).hexdigest()[:16]

    @classmethod
    def from_request(
        cls,
        text: str,
        voice_id: str,
        provider: str,
        speed: float = 1.0,
        exaggeration: Optional[float] = None,
        cfg_weight: Optional[float] = None,
        language: Optional[str] = None,
    ) -> "TTSCacheKey":
        """Create cache key from TTS request parameters."""
        text_hash = cls.hash_text(text)

        # Round speed to 2 decimal places for consistent matching
        speed = round(speed, 2)

        # Only include Chatterbox params if provider is chatterbox
        if provider != "chatterbox":
            exaggeration = None
            cfg_weight = None
            language = None
        else:
            if exaggeration is not None:
                exaggeration = round(exaggeration, 2)
            if cfg_weight is not None:
                cfg_weight = round(cfg_weight, 2)

        return cls(
            text_hash=text_hash,
            voice_id=voice_id,
            tts_provider=provider,
            speed=speed,
            exaggeration=exaggeration,
            cfg_weight=cfg_weight,
            language=language,
        )

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        d = {
            "text_hash": self.text_hash,
            "voice_id": self.voice_id,
            "tts_provider": self.tts_provider,
            "speed": self.speed,
        }
        if self.exaggeration is not None:
            d["exaggeration"] = self.exaggeration
        if self.cfg_weight is not None:
            d["cfg_weight"] = self.cfg_weight
        if self.language is not None:
            d["language"] = self.language
        return d

    @classmethod
    def from_dict(cls, d: Dict) -> "TTSCacheKey":
        """Create from dictionary (JSON deserialization)."""
        return cls(
            text_hash=d["text_hash"],
            voice_id=d["voice_id"],
            tts_provider=d["tts_provider"],
            speed=d.get("speed", 1.0),
            exaggeration=d.get("exaggeration"),
            cfg_weight=d.get("cfg_weight"),
            language=d.get("language"),
        )


@dataclass
class TTSCacheEntry:
    """Metadata for a cached TTS audio file."""
    key: TTSCacheKey
    file_path: str
    size_bytes: int
    sample_rate: int          # 22050 for Piper, 24000 for VibeVoice/Chatterbox
    duration_seconds: float
    created_at: datetime
    last_accessed_at: datetime
    access_count: int = 1
    ttl_seconds: int = 30 * 24 * 60 * 60  # 30 days default

    @property
    def is_expired(self) -> bool:
        """Check if entry has exceeded its TTL."""
        expiry = self.created_at + timedelta(seconds=self.ttl_seconds)
        return datetime.now() > expiry

    @property
    def age_seconds(self) -> float:
        """Age of entry in seconds since creation."""
        return (datetime.now() - self.created_at).total_seconds()

    def touch(self) -> None:
        """Update last access time and increment count."""
        self.last_accessed_at = datetime.now()
        self.access_count += 1

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "key": self.key.to_dict(),
            "file_path": self.file_path,
            "size_bytes": self.size_bytes,
            "sample_rate": self.sample_rate,
            "duration_seconds": self.duration_seconds,
            "created_at": self.created_at.isoformat(),
            "last_accessed_at": self.last_accessed_at.isoformat(),
            "access_count": self.access_count,
            "ttl_seconds": self.ttl_seconds,
        }

    @classmethod
    def from_dict(cls, d: Dict) -> "TTSCacheEntry":
        """Create from dictionary (JSON deserialization)."""
        return cls(
            key=TTSCacheKey.from_dict(d["key"]),
            file_path=d["file_path"],
            size_bytes=d["size_bytes"],
            sample_rate=d["sample_rate"],
            duration_seconds=d["duration_seconds"],
            created_at=datetime.fromisoformat(d["created_at"]),
            last_accessed_at=datetime.fromisoformat(d["last_accessed_at"]),
            access_count=d.get("access_count", 1),
            ttl_seconds=d.get("ttl_seconds", 30 * 24 * 60 * 60),
        )


@dataclass
class TTSCacheStats:
    """Cache statistics for monitoring."""
    total_entries: int = 0
    total_size_bytes: int = 0
    max_size_bytes: int = 2 * 1024 * 1024 * 1024  # 2GB default
    hits: int = 0
    misses: int = 0
    eviction_count: int = 0
    prefetch_count: int = 0
    prefetch_hits: int = 0
    entries_by_provider: Dict[str, int] = field(default_factory=dict)

    @property
    def hit_rate(self) -> float:
        """Calculate cache hit rate as percentage."""
        total = self.hits + self.misses
        if total == 0:
            return 0.0
        return (self.hits / total) * 100

    @property
    def utilization_percent(self) -> float:
        """Calculate cache utilization as percentage of max size."""
        if self.max_size_bytes == 0:
            return 0.0
        return (self.total_size_bytes / self.max_size_bytes) * 100

    @property
    def total_size_formatted(self) -> str:
        """Human-readable size string."""
        size = self.total_size_bytes
        for unit in ["B", "KB", "MB", "GB"]:
            if size < 1024:
                return f"{size:.1f} {unit}"
            size /= 1024
        return f"{size:.1f} TB"

    def record_hit(self) -> None:
        """Record a cache hit."""
        self.hits += 1

    def record_miss(self) -> None:
        """Record a cache miss."""
        self.misses += 1

    def record_eviction(self, count: int = 1) -> None:
        """Record evictions."""
        self.eviction_count += count

    def record_prefetch(self) -> None:
        """Record a prefetch operation."""
        self.prefetch_count += 1

    def record_prefetch_hit(self) -> None:
        """Record when a prefetched entry was used."""
        self.prefetch_hits += 1

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON/API response."""
        return {
            "total_entries": self.total_entries,
            "total_size_bytes": self.total_size_bytes,
            "total_size_formatted": self.total_size_formatted,
            "max_size_bytes": self.max_size_bytes,
            "utilization_percent": round(self.utilization_percent, 1),
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate": round(self.hit_rate, 1),
            "eviction_count": self.eviction_count,
            "prefetch_count": self.prefetch_count,
            "prefetch_hits": self.prefetch_hits,
            "entries_by_provider": self.entries_by_provider,
        }
