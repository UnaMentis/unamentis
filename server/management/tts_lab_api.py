"""
TTS Lab API - Experimentation Interface

Provides endpoints for TTS model experimentation before batch processing:
- Generate test audio with specific configurations
- Save/load TTS configurations
- Compare different models and settings
- Prepare configurations for batch conversion

Supports all Kyutai models:
- Kyutai TTS 1.6B (delayed streams, 40+ voices)
- Kyutai Pocket TTS (100M, CPU-only)
- Fish Speech V1.5 (zero-shot cloning)
"""

import asyncio
import json
import logging
import os
import time
import uuid
from pathlib import Path
from typing import Any, Dict

import aiofiles
from aiohttp import web

logger = logging.getLogger(__name__)


# =============================================================================
# Configuration Storage
# =============================================================================

TTS_LAB_DIR = Path(__file__).parent / "tts_lab_configs"
TTS_LAB_DIR.mkdir(exist_ok=True)


def _safe_path(filename: str, base_dir: Path) -> Path:
    """Validate a file path is within base_dir (CodeQL-recognized sanitizer)."""
    candidate = base_dir / filename
    real_path = os.path.realpath(str(candidate))
    real_base = os.path.realpath(str(base_dir))
    if not real_base.endswith(os.sep):
        real_base += os.sep
    if not real_path.startswith(real_base) and real_path != real_base.rstrip(os.sep):
        raise ValueError("Path escapes allowed directory")
    return Path(real_path)


class TTSLabConfig:
    """TTS Lab configuration for experimentation."""

    def __init__(
        self,
        model: str,
        voice: str,
        cfg_coef: float = 2.0,
        n_q: int = 24,
        padding_between: int = 1,
        padding_bonus: int = 0,
        temperature: float = 1.0,
        top_p: float = 0.95,
        batch_size: int = 8,
    ):
        self.model = model
        self.voice = voice
        self.cfg_coef = cfg_coef
        self.n_q = n_q
        self.padding_between = padding_between
        self.padding_bonus = padding_bonus
        self.temperature = temperature
        self.top_p = top_p
        self.batch_size = batch_size

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "model": self.model,
            "voice": self.voice,
            "cfg_coef": self.cfg_coef,
            "n_q": self.n_q,
            "padding_between": self.padding_between,
            "padding_bonus": self.padding_bonus,
            "temperature": self.temperature,
            "top_p": self.top_p,
            "batch_size": self.batch_size,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTSLabConfig":
        """Create from dictionary."""
        return cls(
            model=data["model"],
            voice=data["voice"],
            cfg_coef=data.get("cfg_coef", 2.0),
            n_q=data.get("n_q", 24),
            padding_between=data.get("padding_between", 1),
            padding_bonus=data.get("padding_bonus", 0),
            temperature=data.get("temperature", 1.0),
            top_p=data.get("top_p", 0.95),
            batch_size=data.get("batch_size", 8),
        )


# =============================================================================
# Model Information
# =============================================================================

SUPPORTED_MODELS = {
    # Server TTS Models
    "fish-speech-v1.5": {
        "name": "Fish Speech V1.5",
        "type": "server",
        "parameters": "~2B (DualAR)",
        "release_date": "Late 2025",
        "provider": "fish-speech",
        "capabilities": [
            "Zero-shot voice cloning",
            "Multilingual (30+ languages)",
            "Industry-leading ELO (1339)",
            "Cross-lingual synthesis",
        ],
        "voices": ["default", "nova", "sarah"],
        "config_params": {
            "temperature": {"min": 0.1, "max": 2.0, "default": 1.0},
            "top_p": {"min": 0.1, "max": 1.0, "default": 0.95},
        },
        "sample_voice": "nova",
    },
    "kyutai-tts-1.6b": {
        "name": "Kyutai TTS 1.6B",
        "type": "server",
        "parameters": "1.6B",
        "release_date": "July 2025",
        "provider": "kyutai",
        "capabilities": [
            "40+ voices (including emotional)",
            "Delayed streams (low latency)",
            "Voice cloning",
            "Batch processing optimized",
        ],
        "voices": [
            "sarah",
            "john",
            "emma",
            "alex",
            "sarah-happy",
            "sarah-sad",
            "john-excited",
            "emma-calm",
        ],
        "config_params": {
            "cfg_coef": {"min": 1.0, "max": 5.0, "default": 2.0},
            "n_q": {"min": 8, "max": 32, "default": 24},
            "padding_between": {"min": 0, "max": 5, "default": 1},
            "padding_bonus": {"min": -3, "max": 3, "default": 0},
            "temperature": {"min": 0.1, "max": 2.0, "default": 1.0},
            "top_p": {"min": 0.1, "max": 1.0, "default": 0.95},
        },
        "sample_voice": "sarah",
    },
    "index-tts-2": {
        "name": "IndexTTS-2",
        "type": "server",
        "parameters": "Transformer",
        "release_date": "Late 2025",
        "provider": "index-tts",
        "capabilities": [
            "Zero-shot voice synthesis",
            "Precise duration control",
            "Emotional disentanglement",
            "Fine-grained timing",
        ],
        "voices": ["default", "narrator", "conversational"],
        "config_params": {
            "temperature": {"min": 0.1, "max": 2.0, "default": 1.0},
            "duration_scale": {"min": 0.5, "max": 2.0, "default": 1.0},
        },
        "sample_voice": "narrator",
    },
    "vibevoice-1.5b": {
        "name": "VibeVoice 1.5B",
        "type": "server",
        "parameters": "1.5B",
        "release_date": "Late 2025",
        "provider": "vibevoice",
        "capabilities": [
            "Microsoft official",
            "Up to 90 minutes",
            "Four distinct speakers",
            "Long-form generation",
        ],
        "voices": ["nova", "alloy", "echo", "shimmer"],
        "config_params": {
            "speed": {"min": 0.5, "max": 2.0, "default": 1.0},
        },
        "sample_voice": "nova",
    },
    # On-Device TTS Models
    "kyutai-pocket-tts": {
        "name": "Kyutai Pocket TTS",
        "type": "on-device",
        "parameters": "100M",
        "release_date": "Jan 13, 2026",
        "provider": "kyutai-pocket",
        "capabilities": [
            "Best WER (1.84%)",
            "Voice cloning from 5s",
            "CPU-only (no GPU)",
            "6x real-time speed",
        ],
        "voices": [
            "voice1",
            "voice2",
            "voice3",
            "voice4",
            "voice5",
            "voice6",
            "voice7",
            "voice8",
        ],
        "config_params": {
            "cfg_coef": {"min": 1.0, "max": 5.0, "default": 2.0},
            "n_q": {"min": 8, "max": 24, "default": 24},
            "temperature": {"min": 0.1, "max": 2.0, "default": 1.0},
        },
        "sample_voice": "voice1",
    },
    "neutts-air": {
        "name": "NeuTTS Air",
        "type": "on-device",
        "parameters": "0.5B",
        "release_date": "Late 2025",
        "provider": "neutts",
        "capabilities": [
            "Super-realistic TTS",
            "Instant voice cloning",
            "GGUF format",
            "Runs on Raspberry Pi",
        ],
        "voices": ["default", "narrator"],
        "config_params": {
            "temperature": {"min": 0.1, "max": 2.0, "default": 1.0},
        },
        "sample_voice": "default",
    },
    "kokoro-82m": {
        "name": "Kokoro 82M",
        "type": "on-device",
        "parameters": "82M",
        "release_date": "Late 2025",
        "provider": "kokoro",
        "capabilities": [
            "Only 82M parameters",
            "Quality comparable to larger models",
            "StyleTTS2/ISTFTNet based",
            "Extremely efficient",
        ],
        "voices": ["default", "natural", "expressive"],
        "config_params": {
            "temperature": {"min": 0.1, "max": 2.0, "default": 0.8},
            "style_weight": {"min": 0.0, "max": 1.0, "default": 0.5},
        },
        "sample_voice": "natural",
    },
}

# Reference text for TTS model samples - designed to test various TTS capabilities
TTS_REFERENCE_TEXT = """The quick mathematician, Dr. Sarah Chen, carefully examined the peculiar equation. "Could this really be correct?" she wondered aloud, her eyes widening with excitement. After seventeen years of research, breakthrough discoveries still thrilled her. Numbers, equations, and the elegant beauty of mathematics had always been her true passion."""

# Directory for generated samples
SAMPLES_DIR = Path(__file__).parent.parent / "web" / "public" / "audio" / "tts-samples"

# Mapping from Voice Lab model IDs to actual TTS providers
# (Some models may not have real providers yet)
MODEL_TO_PROVIDER = {
    "fish-speech-v1.5": None,  # Not yet integrated
    "kyutai-tts-1.6b": None,  # Not yet integrated
    "index-tts-2": None,  # Not yet integrated
    "vibevoice-1.5b": "vibevoice",  # Available
    "kyutai-pocket-tts": None,  # On-device only
    "neutts-air": None,  # On-device only
    "kokoro-82m": None,  # On-device only
}


# =============================================================================
# API Endpoints
# =============================================================================


async def handle_list_models(request: web.Request) -> web.Response:
    """
    GET /api/tts-lab/models

    List all supported TTS models with their capabilities.

    Response:
    {
        "models": [
            {
                "id": "kyutai-tts-1.6b",
                "name": "Kyutai TTS 1.6B",
                "parameters": "1.6B",
                "release_date": "July 2025",
                "capabilities": [...],
                "voices": [...],
                "config_params": {...}
            }
        ]
    }
    """
    models = []
    for model_id, info in SUPPORTED_MODELS.items():
        models.append({"id": model_id, **info})

    return web.json_response({"models": models})


async def handle_generate_test_audio(request: web.Request) -> web.Response:
    """
    POST /api/tts-lab/generate

    Generate test audio with specific configuration.

    Request body:
    {
        "text": "The French Revolution began in 1789...",
        "config": {
            "model": "kyutai-tts-1.6b",
            "voice": "sarah",
            "cfg_coef": 2.0,
            "n_q": 24,
            "padding_between": 1,
            "padding_bonus": 0,
            "temperature": 1.0,
            "top_p": 0.95
        }
    }

    Response:
    {
        "id": "audio-uuid",
        "url": "/api/tts-lab/audio/audio-uuid.wav",
        "duration": 4.5,
        "config": {...},
        "generated_at": "2026-01-19T12:00:00Z"
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON body"}, status=400)

    text = data.get("text")
    if not text or not text.strip():
        return web.json_response({"error": "Missing or empty 'text' field"}, status=400)

    config_data = data.get("config")
    if not config_data:
        return web.json_response({"error": "Missing 'config' field"}, status=400)

    try:
        config = TTSLabConfig.from_dict(config_data)
    except (KeyError, ValueError) as e:
        return web.json_response({"error": f"Invalid config: {e}"}, status=400)

    # Validate model
    if config.model not in SUPPORTED_MODELS:
        return web.json_response(
            {
                "error": f"Unsupported model '{config.model}'. Supported: {list(SUPPORTED_MODELS.keys())}"
            },
            status=400,
        )

    # TODO: Actual TTS generation
    # For now, simulate generation
    audio_id = str(uuid.uuid4())
    duration = len(text) / 15.0  # Rough estimate: 15 chars/second

    # Simulate processing time
    await asyncio.sleep(0.5)

    result = {
        "id": audio_id,
        "url": f"/api/tts-lab/audio/{audio_id}.wav",
        "duration": round(duration, 1),
        "config": config.to_dict(),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    return web.json_response(result)


async def handle_save_config(request: web.Request) -> web.Response:
    """
    POST /api/tts-lab/config

    Save TTS configuration for batch processing.

    Request body:
    {
        "name": "KB Questions - Sarah Voice",
        "description": "Standard configuration for Knowledge Bowl",
        "config": {
            "model": "kyutai-tts-1.6b",
            "voice": "sarah",
            "cfg_coef": 2.0,
            "n_q": 24,
            "batch_size": 8
        }
    }

    Response:
    {
        "id": "config-uuid",
        "name": "KB Questions - Sarah Voice",
        "saved_at": "2026-01-19T12:00:00Z"
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON body"}, status=400)

    name = data.get("name")
    if not name or not name.strip():
        return web.json_response({"error": "Missing 'name' field"}, status=400)

    config_data = data.get("config")
    if not config_data:
        return web.json_response({"error": "Missing 'config' field"}, status=400)

    try:
        config = TTSLabConfig.from_dict(config_data)
    except (KeyError, ValueError) as e:
        return web.json_response({"error": f"Invalid config: {e}"}, status=400)

    config_id = str(uuid.uuid4())
    config_file = TTS_LAB_DIR / f"{config_id}.json"

    saved_config = {
        "id": config_id,
        "name": name,
        "description": data.get("description", ""),
        "config": config.to_dict(),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    async with aiofiles.open(config_file, "w") as f:
        await f.write(json.dumps(saved_config, indent=2))

    logger.info(f"Saved TTS Lab config: {name} (ID: {config_id})")

    return web.json_response(
        {
            "id": config_id,
            "name": name,
            "saved_at": saved_config["created_at"],
        }
    )


async def handle_list_configs(request: web.Request) -> web.Response:
    """
    GET /api/tts-lab/configs

    List all saved TTS configurations.

    Response:
    {
        "configs": [
            {
                "id": "config-uuid",
                "name": "KB Questions - Sarah Voice",
                "description": "...",
                "config": {...},
                "created_at": "2026-01-19T12:00:00Z"
            }
        ]
    }
    """
    configs = []

    for config_file in TTS_LAB_DIR.glob("*.json"):
        try:
            async with aiofiles.open(config_file, "r") as f:
                content = await f.read()
                config_data = json.loads(content)
                configs.append(config_data)
        except Exception as e:
            logger.warning(f"Failed to load config {config_file}: {e}")

    # Sort by created_at descending
    configs.sort(key=lambda x: x.get("created_at", ""), reverse=True)

    return web.json_response({"configs": configs})


async def handle_get_config(request: web.Request) -> web.Response:
    """
    GET /api/tts-lab/config/{config_id}

    Get a specific TTS configuration.

    Response:
    {
        "id": "config-uuid",
        "name": "KB Questions - Sarah Voice",
        "description": "...",
        "config": {...},
        "created_at": "2026-01-19T12:00:00Z"
    }
    """
    config_id = request.match_info["config_id"]
    try:
        config_file = _safe_path(f"{config_id}.json", TTS_LAB_DIR)
    except ValueError:
        return web.json_response({"error": "Invalid config_id"}, status=400)

    if not config_file.exists():
        return web.json_response({"error": "Configuration not found"}, status=404)

    try:
        async with aiofiles.open(config_file, "r") as f:
            content = await f.read()
            config_data = json.loads(content)
        return web.json_response(config_data)
    except Exception as e:
        logger.error(f"Failed to load config {config_id}: {e}")
        return web.json_response({"error": "Failed to load configuration"}, status=500)


async def handle_delete_config(request: web.Request) -> web.Response:
    """
    DELETE /api/tts-lab/config/{config_id}

    Delete a saved TTS configuration.

    Response:
    {
        "success": true,
        "deleted_id": "config-uuid"
    }
    """
    config_id = request.match_info["config_id"]
    try:
        config_file = _safe_path(f"{config_id}.json", TTS_LAB_DIR)
    except ValueError:
        return web.json_response({"error": "Invalid config_id"}, status=400)

    if not config_file.exists():
        return web.json_response({"error": "Configuration not found"}, status=404)

    try:
        config_file.unlink()
        logger.info(f"Deleted TTS Lab config: {config_id}")
        return web.json_response({"success": True, "deleted_id": config_id})
    except Exception as e:
        logger.error(f"Failed to delete config {config_id}: {e}")
        return web.json_response(
            {"error": "Failed to delete configuration"}, status=500
        )


async def handle_validate_config(request: web.Request) -> web.Response:
    """
    POST /api/tts-lab/validate

    Validate a TTS configuration without generating audio.

    Request body:
    {
        "config": {
            "model": "kyutai-tts-1.6b",
            "voice": "sarah",
            "cfg_coef": 2.0,
            "n_q": 24
        }
    }

    Response:
    {
        "valid": true,
        "errors": [],
        "warnings": ["CFG coefficient above 3.0 may reduce quality"]
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON body"}, status=400)

    config_data = data.get("config")
    if not config_data:
        return web.json_response({"error": "Missing 'config' field"}, status=400)

    errors = []
    warnings = []

    # Validate model
    model = config_data.get("model")
    if not model:
        errors.append("Missing 'model' field")
    elif model not in SUPPORTED_MODELS:
        errors.append(f"Unsupported model: {model}")
    else:
        model_info = SUPPORTED_MODELS[model]

        # Validate voice
        voice = config_data.get("voice")
        if not voice:
            errors.append("Missing 'voice' field")
        elif voice not in model_info["voices"]:
            errors.append(
                f"Voice '{voice}' not available for {model_info['name']}. "
                f"Available: {', '.join(model_info['voices'])}"
            )

        # Validate config parameters
        for param, limits in model_info.get("config_params", {}).items():
            value = config_data.get(param)
            if value is not None:
                min_val = limits.get("min")
                max_val = limits.get("max")
                default_val = limits.get("default")

                if min_val is not None and value < min_val:
                    errors.append(f"{param} below minimum: {value} < {min_val}")
                if max_val is not None and value > max_val:
                    errors.append(f"{param} above maximum: {value} > {max_val}")

                # Warnings for non-default values
                if default_val is not None and abs(value - default_val) > 0.01:
                    if param == "cfg_coef" and value > 3.0:
                        warnings.append(
                            "CFG coefficient above 3.0 may reduce naturalness"
                        )
                    elif param == "n_q" and value < 16:
                        warnings.append(
                            "Low quantization levels (<16) may reduce quality"
                        )
                    elif param == "temperature" and value > 1.5:
                        warnings.append(
                            "High temperature (>1.5) may reduce consistency"
                        )

    return web.json_response(
        {
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings,
        }
    )


async def handle_generate_samples(request: web.Request) -> web.Response:
    """
    POST /api/tts-lab/samples/generate

    Generate reference audio samples for TTS models.

    Request body (optional):
    {
        "model_ids": ["vibevoice-1.5b"],  // Optional, generates all if omitted
        "force": false  // Regenerate even if sample exists
    }

    Response:
    {
        "status": "completed",
        "generated": ["vibevoice-1.5b"],
        "skipped": ["fish-speech-v1.5"],
        "errors": {"kokoro-82m": "Provider not available"}
    }
    """
    try:
        data = await request.json()
    except Exception:
        data = {}

    model_ids = data.get("model_ids")
    force = data.get("force", False)

    # Default to all models
    if not model_ids:
        model_ids = list(SUPPORTED_MODELS.keys())

    # Ensure samples directory exists
    SAMPLES_DIR.mkdir(parents=True, exist_ok=True)

    # Get TTS resource pool from app
    from tts_cache import TTSResourcePool, Priority

    resource_pool: TTSResourcePool = request.app.get("tts_resource_pool")

    generated = []
    skipped = []
    errors = {}

    for model_id in model_ids:
        if model_id not in SUPPORTED_MODELS:
            errors[model_id] = f"Unknown model: {model_id}"
            continue

        model_info = SUPPORTED_MODELS[model_id]
        try:
            sample_path = _safe_path(f"{model_id}.opus", SAMPLES_DIR)
        except ValueError:
            errors[model_id] = f"Invalid model_id: {model_id}"
            continue

        # Skip if exists and not forcing
        if sample_path.exists() and not force:
            skipped.append(model_id)
            logger.info(f"Sample already exists for {model_id}, skipping")
            continue

        # Get provider mapping
        provider = MODEL_TO_PROVIDER.get(model_id)
        if not provider:
            errors[model_id] = f"No TTS provider available for {model_id}"
            logger.warning(f"No provider for model {model_id}")
            continue

        if not resource_pool:
            errors[model_id] = "TTS resource pool not initialized"
            continue

        try:
            # Generate audio using resource pool
            voice_id = model_info.get("sample_voice", "nova")
            logger.info(
                f"Generating sample for {model_id} with voice {voice_id} using {provider}"
            )

            (
                audio_data,
                sample_rate,
                duration,
            ) = await resource_pool.generate_with_priority(
                text=TTS_REFERENCE_TEXT,
                voice_id=voice_id,
                provider=provider,
                speed=1.0,
                chatterbox_config={},
                priority=Priority.SCHEDULED,
            )

            # Save the audio file
            async with aiofiles.open(sample_path, "wb") as f:
                await f.write(audio_data)

            generated.append(model_id)
            logger.info(
                f"Generated sample for {model_id}: {len(audio_data)} bytes, {duration:.1f}s"
            )

        except Exception as e:
            errors[model_id] = str(e)
            logger.error(f"Failed to generate sample for {model_id}: {e}")

    return web.json_response(
        {
            "status": "completed",
            "reference_text": TTS_REFERENCE_TEXT,
            "samples_dir": str(SAMPLES_DIR),
            "generated": generated,
            "skipped": skipped,
            "errors": errors,
        }
    )


async def handle_get_sample_status(request: web.Request) -> web.Response:
    """
    GET /api/tts-lab/samples

    Get status of generated samples for all models.

    Response:
    {
        "reference_text": "The quick mathematician...",
        "samples": {
            "vibevoice-1.5b": {"available": true, "size_bytes": 102400, "path": "..."},
            "fish-speech-v1.5": {"available": false, "reason": "No provider"}
        }
    }
    """
    samples = {}

    for model_id, model_info in SUPPORTED_MODELS.items():
        sample_path = SAMPLES_DIR / f"{model_id}.opus"
        provider = MODEL_TO_PROVIDER.get(model_id)

        if sample_path.exists():
            stat = sample_path.stat()
            samples[model_id] = {
                "available": True,
                "size_bytes": stat.st_size,
                "url": f"/audio/tts-samples/{model_id}.opus",
            }
        elif not provider:
            samples[model_id] = {
                "available": False,
                "reason": f"No TTS provider for {model_info['type']} model",
            }
        else:
            samples[model_id] = {
                "available": False,
                "reason": "Sample not yet generated",
            }

    return web.json_response(
        {
            "reference_text": TTS_REFERENCE_TEXT,
            "samples_dir": str(SAMPLES_DIR),
            "samples": samples,
        }
    )


# =============================================================================
# Route Registration
# =============================================================================


def register_tts_lab_routes(app: web.Application) -> None:
    """Register TTS Lab API routes."""
    from feature_flag_guard import guarded_routes
    from feature_flag_keys import FlagKeys

    router = guarded_routes(app, FlagKeys.TTS_LAB)
    router.add_get("/api/tts-lab/models", handle_list_models)
    router.add_post("/api/tts-lab/generate", handle_generate_test_audio)
    router.add_post("/api/tts-lab/config", handle_save_config)
    router.add_get("/api/tts-lab/configs", handle_list_configs)
    router.add_get("/api/tts-lab/config/{config_id}", handle_get_config)
    router.add_delete("/api/tts-lab/config/{config_id}", handle_delete_config)
    router.add_post("/api/tts-lab/validate", handle_validate_config)

    # Sample generation endpoints
    router.add_get("/api/tts-lab/samples", handle_get_sample_status)
    router.add_post("/api/tts-lab/samples/generate", handle_generate_samples)

    logger.info("Registered TTS Lab API routes")
