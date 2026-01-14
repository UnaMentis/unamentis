"""
TTS API routes with caching support.

Provides a general TTS endpoint that:
- Accepts text and voice parameters
- Checks cache first, generates on miss
- Returns audio with cache status headers
- Supports all TTS backends (VibeVoice, Piper, Chatterbox)
- Uses resource pool for priority-based generation
"""

import asyncio
import json as json_module
import logging

import aiofiles
from aiohttp import web

from modules_api import validate_module_id, get_module_content_path
from tts_cache import TTSCache, TTSCacheKey, TTSResourcePool, Priority

logger = logging.getLogger(__name__)

# Sample rates by provider (for fallback)
SAMPLE_RATES = {
    "vibevoice": 24000,
    "piper": 22050,
    "chatterbox": 24000,
}

# Valid providers
VALID_PROVIDERS = {"vibevoice", "piper", "chatterbox"}


# =============================================================================
# TTS Generation Endpoint
# =============================================================================


async def handle_tts_request(request: web.Request) -> web.Response:
    """
    POST /api/tts

    Generate TTS audio with caching.

    Request body:
    {
        "text": "Hello, welcome to the lesson.",
        "voice_id": "nova",
        "tts_provider": "vibevoice",
        "speed": 1.0,
        "chatterbox_config": {
            "exaggeration": 0.5,
            "cfg_weight": 0.5,
            "language": "en"
        },
        "skip_cache": false
    }

    Response:
    - Content-Type: audio/wav
    - X-TTS-Cache-Status: hit|miss|bypass
    - X-TTS-Duration-Seconds: 3.5
    - X-TTS-Sample-Rate: 24000
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON body"},
            status=400,
        )

    text = data.get("text")
    if not text or not text.strip():
        return web.json_response(
            {"error": "Missing or empty 'text' field"},
            status=400,
        )

    voice_id = data.get("voice_id", "nova")
    provider = data.get("tts_provider", "vibevoice")
    speed = data.get("speed", 1.0)
    chatterbox_config = data.get("chatterbox_config", {})
    skip_cache = data.get("skip_cache", False)

    # Validate provider
    if provider not in VALID_PROVIDERS:
        return web.json_response(
            {"error": f"Unknown provider '{provider}'. Valid: {list(VALID_PROVIDERS)}"},
            status=400,
        )

    cache: TTSCache = request.app.get("tts_cache")
    resource_pool: TTSResourcePool = request.app.get("tts_resource_pool")

    if not resource_pool:
        return web.json_response(
            {"error": "TTS resource pool not initialized"},
            status=503,
        )

    # If no cache, generate directly with LIVE priority
    if not cache:
        try:
            audio_data, sample_rate, duration = await resource_pool.generate_with_priority(
                text=text,
                voice_id=voice_id,
                provider=provider,
                speed=speed,
                chatterbox_config=chatterbox_config,
                priority=Priority.LIVE,
            )
            return web.Response(
                body=audio_data,
                content_type="audio/wav",
                headers={
                    "X-TTS-Cache-Status": "bypass",
                    "X-TTS-Duration-Seconds": str(round(duration, 2)),
                    "X-TTS-Sample-Rate": str(sample_rate),
                },
            )
        except Exception as e:
            return web.json_response(
                {"error": str(e)},
                status=503,
            )

    # Build cache key
    key = TTSCacheKey.from_request(
        text=text,
        voice_id=voice_id,
        provider=provider,
        speed=speed,
        exaggeration=chatterbox_config.get("exaggeration"),
        cfg_weight=chatterbox_config.get("cfg_weight"),
        language=chatterbox_config.get("language"),
    )

    # Check cache first (unless skip_cache)
    if not skip_cache:
        cached = await cache.get(key)
        if cached:
            # Get entry for metadata
            hash_key = key.to_hash()
            async with cache._lock:
                entry = cache.index.get(hash_key)
                sample_rate = entry.sample_rate if entry else SAMPLE_RATES.get(provider, 24000)
                duration = entry.duration_seconds if entry else 0

            return web.Response(
                body=cached,
                content_type="audio/wav",
                headers={
                    "X-TTS-Cache-Status": "hit",
                    "X-TTS-Duration-Seconds": str(round(duration, 2)),
                    "X-TTS-Sample-Rate": str(sample_rate),
                },
            )

    # Cache miss - generate audio with LIVE priority (user is waiting)
    try:
        audio_data, sample_rate, duration = await resource_pool.generate_with_priority(
            text=text,
            voice_id=voice_id,
            provider=provider,
            speed=speed,
            chatterbox_config=chatterbox_config,
            priority=Priority.LIVE,
        )
    except Exception as e:
        return web.json_response(
            {"error": str(e)},
            status=503,
        )

    # Store in cache (fire and forget)
    asyncio.create_task(
        cache.put(key, audio_data, sample_rate, duration)
    )

    return web.Response(
        body=audio_data,
        content_type="audio/wav",
        headers={
            "X-TTS-Cache-Status": "miss",
            "X-TTS-Duration-Seconds": str(round(duration, 2)),
            "X-TTS-Sample-Rate": str(sample_rate),
        },
    )


# =============================================================================
# Cache Statistics Endpoint
# =============================================================================


async def handle_get_cache_stats(request: web.Request) -> web.Response:
    """
    GET /api/tts/cache/stats

    Get TTS cache and resource pool statistics.
    """
    cache: TTSCache = request.app.get("tts_cache")
    resource_pool: TTSResourcePool = request.app.get("tts_resource_pool")

    if not cache:
        return web.json_response(
            {"error": "TTS cache not initialized"},
            status=503,
        )

    stats = await cache.get_stats()
    response = {
        "status": "ok",
        "cache": stats.to_dict(),
    }

    # Include resource pool stats if available
    if resource_pool:
        response["resource_pool"] = resource_pool.get_stats()

    return web.json_response(response)


# =============================================================================
# Cache Management Endpoints
# =============================================================================


async def handle_clear_cache(request: web.Request) -> web.Response:
    """
    DELETE /api/tts/cache?confirm=true

    Clear entire TTS cache.
    """
    confirm = request.query.get("confirm")
    if confirm != "true":
        return web.json_response(
            {"error": "Must include ?confirm=true to clear cache"},
            status=400,
        )

    cache: TTSCache = request.app.get("tts_cache")
    if not cache:
        return web.json_response(
            {"error": "TTS cache not initialized"},
            status=503,
        )

    count = await cache.clear()
    return web.json_response({
        "status": "ok",
        "entries_removed": count,
    })


async def handle_evict_expired(request: web.Request) -> web.Response:
    """
    DELETE /api/tts/cache/expired

    Remove expired entries from cache.
    """
    cache: TTSCache = request.app.get("tts_cache")
    if not cache:
        return web.json_response(
            {"error": "TTS cache not initialized"},
            status=503,
        )

    count = await cache.evict_expired()
    return web.json_response({
        "status": "ok",
        "entries_removed": count,
    })


async def handle_evict_lru(request: web.Request) -> web.Response:
    """
    POST /api/tts/cache/evict

    Force LRU eviction to target size.

    Request body:
    {
        "target_size_mb": 1000
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON body"},
            status=400,
        )

    target_mb = data.get("target_size_mb")
    if not target_mb or target_mb < 0:
        return web.json_response(
            {"error": "Missing or invalid 'target_size_mb'"},
            status=400,
        )

    cache: TTSCache = request.app.get("tts_cache")
    if not cache:
        return web.json_response(
            {"error": "TTS cache not initialized"},
            status=503,
        )

    target_bytes = int(target_mb * 1024 * 1024)
    count = await cache.evict_lru(target_bytes)
    return web.json_response({
        "status": "ok",
        "entries_removed": count,
    })


async def handle_put_cache_entry(request: web.Request) -> web.Response:
    """
    PUT /api/tts/cache

    Add an entry directly to the cache (for testing/development).

    Request body:
    {
        "text": "Text to cache",
        "voice_id": "nova",
        "tts_provider": "vibevoice",
        "speed": 1.0,
        "audio_base64": "base64-encoded-audio-data",
        "sample_rate": 24000,
        "duration_seconds": 2.5,
        "exaggeration": null,
        "cfg_weight": null,
        "language": null
    }
    """
    import base64

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON body"},
            status=400,
        )

    text = data.get("text")
    if not text:
        return web.json_response(
            {"error": "Missing required field 'text'"},
            status=400,
        )

    audio_b64 = data.get("audio_base64")
    if not audio_b64:
        return web.json_response(
            {"error": "Missing required field 'audio_base64'"},
            status=400,
        )

    try:
        audio_data = base64.b64decode(audio_b64)
    except Exception:
        return web.json_response(
            {"error": "Invalid base64 in 'audio_base64'"},
            status=400,
        )

    voice_id = data.get("voice_id", "nova")
    provider = data.get("tts_provider", "vibevoice")
    speed = data.get("speed", 1.0)
    sample_rate = data.get("sample_rate", 24000)
    duration = data.get("duration_seconds", 1.0)
    exaggeration = data.get("exaggeration")
    cfg_weight = data.get("cfg_weight")
    language = data.get("language")

    cache: TTSCache = request.app.get("tts_cache")
    if not cache:
        return web.json_response(
            {"error": "TTS cache not initialized"},
            status=503,
        )

    # Build cache key
    key = TTSCacheKey.from_request(
        text=text,
        voice_id=voice_id,
        provider=provider,
        speed=speed,
        exaggeration=exaggeration,
        cfg_weight=cfg_weight,
        language=language,
    )

    # Store in cache
    await cache.put(key, audio_data, sample_rate, duration)

    return web.json_response({
        "status": "ok",
        "hash": key.to_hash()[:16],
        "size_bytes": len(audio_data),
    })


async def handle_get_cache_entry(request: web.Request) -> web.Response:
    """
    GET /api/tts/cache?text=...&voice_id=...&tts_provider=...&speed=...

    Get a cached audio entry directly (cache lookup only, no generation).
    """
    text = request.query.get("text")
    if not text:
        return web.json_response(
            {"error": "Missing required query parameter 'text'"},
            status=400,
        )

    voice_id = request.query.get("voice_id", "nova")
    provider = request.query.get("tts_provider", "vibevoice")
    speed = float(request.query.get("speed", "1.0"))
    exaggeration = request.query.get("exaggeration")
    cfg_weight = request.query.get("cfg_weight")
    language = request.query.get("language")

    if exaggeration:
        exaggeration = float(exaggeration)
    if cfg_weight:
        cfg_weight = float(cfg_weight)

    cache: TTSCache = request.app.get("tts_cache")
    if not cache:
        return web.json_response(
            {"error": "TTS cache not initialized"},
            status=503,
        )

    # Build cache key
    key = TTSCacheKey.from_request(
        text=text,
        voice_id=voice_id,
        provider=provider,
        speed=speed,
        exaggeration=exaggeration,
        cfg_weight=cfg_weight,
        language=language,
    )

    # Lookup in cache
    audio = await cache.get(key)
    if audio is None:
        return web.json_response(
            {"error": "Cache miss", "hash": key.to_hash()[:16]},
            status=404,
        )

    # Get entry metadata
    hash_key = key.to_hash()
    async with cache._lock:
        entry = cache.index.get(hash_key)
        sample_rate = entry.sample_rate if entry else 24000
        duration = entry.duration_seconds if entry else 0.0

    return web.Response(
        body=audio,
        content_type="audio/wav",
        headers={
            "X-TTS-Cache-Status": "hit",
            "X-TTS-Duration-Seconds": str(round(duration, 2)),
            "X-TTS-Sample-Rate": str(sample_rate),
        },
    )


# =============================================================================
# Prefetch Endpoints
# =============================================================================


async def handle_prefetch_topic(request: web.Request) -> web.Response:
    """
    POST /api/tts/prefetch/topic

    Start prefetching TTS for a curriculum topic.

    Request body:
    {
        "curriculum_id": "physics-101",
        "topic_id": "intro-quantum",
        "voice_id": "nova",
        "tts_provider": "vibevoice"
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON body"},
            status=400,
        )

    curriculum_id = data.get("curriculum_id")
    topic_id = data.get("topic_id")

    if not curriculum_id or not topic_id:
        return web.json_response(
            {"error": "Missing curriculum_id or topic_id"},
            status=400,
        )

    prefetcher = request.app.get("tts_prefetcher")
    if not prefetcher:
        return web.json_response(
            {"error": "TTS prefetcher not initialized"},
            status=503,
        )

    voice_id = data.get("voice_id", "nova")
    provider = data.get("tts_provider", "vibevoice")

    # Get curriculum segments from state
    from server import state

    curriculum = state.curriculum_raw.get(curriculum_id)
    if not curriculum:
        return web.json_response(
            {"error": f"Curriculum not found: {curriculum_id}"},
            status=404,
        )

    # Find topic and extract segments
    segments = []
    content = curriculum.get("content", [])
    if content and content[0].get("children"):
        for topic in content[0]["children"]:
            if topic.get("id") == topic_id:
                transcript = topic.get("transcript", {})
                for seg in transcript.get("segments", []):
                    if seg.get("content"):
                        segments.append(seg["content"])
                break

    if not segments:
        return web.json_response(
            {"error": f"Topic not found or has no segments: {topic_id}"},
            status=404,
        )

    job_id = await prefetcher.prefetch_topic(
        curriculum_id=curriculum_id,
        topic_id=topic_id,
        segments=segments,
        voice_id=voice_id,
        provider=provider,
    )

    return web.json_response({
        "status": "started",
        "job_id": job_id,
        "total_segments": len(segments),
    })


async def handle_prefetch_status(request: web.Request) -> web.Response:
    """
    GET /api/tts/prefetch/status/{job_id}

    Get status of a prefetch job.
    """
    job_id = request.match_info.get("job_id")
    if not job_id:
        return web.json_response(
            {"error": "Missing job_id"},
            status=400,
        )

    prefetcher = request.app.get("tts_prefetcher")
    if not prefetcher:
        return web.json_response(
            {"error": "TTS prefetcher not initialized"},
            status=503,
        )

    progress = prefetcher.get_progress(job_id)
    if not progress:
        return web.json_response(
            {"error": f"Job not found: {job_id}"},
            status=404,
        )

    return web.json_response({
        "job_id": job_id,
        "status": progress["status"],
        "progress": progress,
    })


async def handle_cancel_prefetch(request: web.Request) -> web.Response:
    """
    DELETE /api/tts/prefetch/{job_id}

    Cancel a prefetch job.
    """
    job_id = request.match_info.get("job_id")
    if not job_id:
        return web.json_response(
            {"error": "Missing job_id"},
            status=400,
        )

    prefetcher = request.app.get("tts_prefetcher")
    if not prefetcher:
        return web.json_response(
            {"error": "TTS prefetcher not initialized"},
            status=503,
        )

    cancelled = await prefetcher.cancel(job_id)
    return web.json_response({
        "status": "cancelled" if cancelled else "not_found",
        "job_id": job_id,
    })


# =============================================================================
# Knowledge Bowl Audio Endpoints
# =============================================================================


async def handle_kb_audio_get(request: web.Request) -> web.Response:
    """
    GET /api/kb/audio/{question_id}/{segment}

    Serve pre-generated KB audio for a question segment.

    Path params:
        question_id: Question identifier (e.g., "sci-phys-001")
        segment: Segment type ("question", "answer", "hint", "explanation")

    Query params:
        hint_index: Index for hint segments (default: 0)
        module_id: Module identifier (default: "knowledge-bowl")

    Response:
        Content-Type: audio/wav
        X-KB-Cache-Status: hit|miss
        X-KB-Duration-Seconds: 8.5
    """
    question_id = request.match_info.get("question_id")
    segment = request.match_info.get("segment")
    module_id = request.query.get("module_id", "knowledge-bowl")

    # Validate module_id to prevent path traversal
    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400,
        )

    # Parse and validate hint_index
    try:
        hint_index = int(request.query.get("hint_index", "0"))
        if hint_index < 0:
            return web.json_response(
                {"error": "hint_index must be non-negative"},
                status=400,
            )
    except ValueError:
        return web.json_response(
            {"error": "Invalid hint_index format"},
            status=400,
        )

    if not question_id or not segment:
        return web.json_response(
            {"error": "Missing question_id or segment"},
            status=400,
        )

    valid_segments = {"question", "answer", "hint", "explanation"}
    if segment not in valid_segments:
        return web.json_response(
            {"error": f"Invalid segment type. Valid: {list(valid_segments)}"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    audio = await kb_audio.get_audio(
        module_id=module_id,
        question_id=question_id,
        segment_type=segment,
        hint_index=hint_index,
    )

    if audio is None:
        return web.json_response(
            {"error": "Audio not found", "question_id": question_id, "segment": segment},
            status=404,
        )

    # Estimate duration from file size
    duration = kb_audio._estimate_duration(len(audio))

    return web.Response(
        body=audio,
        content_type="audio/wav",
        headers={
            "X-KB-Cache-Status": "hit",
            "X-KB-Duration-Seconds": str(round(duration, 2)),
            "X-KB-Sample-Rate": "24000",
        },
    )


async def handle_kb_audio_batch(request: web.Request) -> web.Response:
    """
    POST /api/kb/audio/batch

    Get metadata for multiple audio segments (for client prefetching).

    Request body:
    {
        "module_id": "knowledge-bowl",
        "question_ids": ["sci-phys-001", "sci-phys-002"],
        "segments": ["question", "answer", "explanation"]
    }

    Response:
    {
        "segments": {
            "sci-phys-001": {
                "question": {"available": true, "duration": 8.5, "size": 204800},
                "answer": {"available": true, "duration": 1.1, "size": 25600}
            }
        },
        "total_size_bytes": 2097152,
        "available_count": 6,
        "missing_count": 0
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON body"},
            status=400,
        )

    module_id = data.get("module_id", "knowledge-bowl")
    question_ids = data.get("question_ids", [])
    segments = data.get("segments", ["question", "answer", "explanation"])

    # Validate module_id to prevent path traversal
    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400,
        )

    if not question_ids:
        return web.json_response(
            {"error": "Missing question_ids"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    manifest = await kb_audio.get_manifest(module_id)

    result = {"segments": {}}
    total_size = 0
    available_count = 0
    missing_count = 0

    for qid in question_ids:
        result["segments"][qid] = {}

        for seg in segments:
            if manifest and qid in manifest.segments and seg in manifest.segments[qid]:
                entry = manifest.segments[qid][seg]
                result["segments"][qid][seg] = {
                    "available": True,
                    "duration": entry.duration_seconds,
                    "size": entry.size_bytes,
                }
                total_size += entry.size_bytes
                available_count += 1
            else:
                result["segments"][qid][seg] = {
                    "available": False,
                    "duration": 0,
                    "size": 0,
                }
                missing_count += 1

    result["total_size_bytes"] = total_size
    result["available_count"] = available_count
    result["missing_count"] = missing_count

    return web.json_response(result)


async def handle_kb_prefetch(request: web.Request) -> web.Response:
    """
    POST /api/kb/prefetch

    Trigger pre-generation of all TTS audio for a KB module.

    Request body:
    {
        "module_id": "knowledge-bowl",
        "voice_id": "nova",
        "provider": "vibevoice",
        "force_regenerate": false
    }

    Response:
    {
        "status": "started",
        "job_id": "kb_prefetch_abc123",
        "total_segments": 200
    }
    """
    import json as json_module

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON body"},
            status=400,
        )

    module_id = data.get("module_id", "knowledge-bowl")
    voice_id = data.get("voice_id", "nova")
    provider = data.get("provider", "vibevoice")
    force_regenerate = data.get("force_regenerate", False)

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    # Load module content using validated path
    try:
        content_path = get_module_content_path(module_id)
    except ValueError as e:
        return web.json_response(
            {"error": str(e)},
            status=400,
        )

    if not content_path.exists():
        return web.json_response(
            {"error": f"Module content not found: {module_id}"},
            status=404,
        )

    try:
        async with aiofiles.open(content_path) as f:
            content = await f.read()
            module_content = json_module.loads(content)
    except Exception as e:
        return web.json_response(
            {"error": f"Failed to load module content: {e}"},
            status=500,
        )

    # Extract segments to get count
    segments = kb_audio.extract_segments(module_content)

    # Start prefetch job
    job_id = await kb_audio.prefetch_module(
        module_id=module_id,
        module_content=module_content,
        voice_id=voice_id,
        provider=provider,
        force_regenerate=force_regenerate,
    )

    return web.json_response({
        "status": "started",
        "job_id": job_id,
        "total_segments": len(segments),
        "module_id": module_id,
    })


async def handle_kb_prefetch_status(request: web.Request) -> web.Response:
    """
    GET /api/kb/prefetch/{job_id}

    Get status of a KB prefetch job.
    """
    job_id = request.match_info.get("job_id")
    if not job_id:
        return web.json_response(
            {"error": "Missing job_id"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    progress = kb_audio.get_progress(job_id)
    if not progress:
        return web.json_response(
            {"error": f"Job not found: {job_id}"},
            status=404,
        )

    return web.json_response(progress)


async def handle_kb_manifest(request: web.Request) -> web.Response:
    """
    GET /api/kb/manifest/{module_id}

    Get the audio manifest for a KB module.
    """
    module_id = request.match_info.get("module_id")
    if not module_id:
        return web.json_response(
            {"error": "Missing module_id"},
            status=400,
        )

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    manifest = await kb_audio.get_manifest(module_id)
    if not manifest:
        return web.json_response(
            {"error": f"No manifest found for module: {module_id}"},
            status=404,
        )

    return web.json_response(manifest.to_dict())


async def handle_kb_coverage(request: web.Request) -> web.Response:
    """
    GET /api/kb/coverage/{module_id}

    Get audio coverage status for a KB module.
    """
    module_id = request.match_info.get("module_id")
    if not module_id:
        return web.json_response(
            {"error": "Missing module_id"},
            status=400,
        )

    if not validate_module_id(module_id):
        return web.json_response(
            {"error": f"Invalid module_id: {module_id}"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    # Load module content using validated path
    try:
        content_path = get_module_content_path(module_id)
    except ValueError as e:
        return web.json_response(
            {"error": str(e)},
            status=400,
        )

    if not content_path.exists():
        return web.json_response(
            {"error": f"Module content not found: {module_id}"},
            status=404,
        )

    try:
        async with aiofiles.open(content_path) as f:
            content = await f.read()
            module_content = json_module.loads(content)
    except Exception as e:
        return web.json_response(
            {"error": f"Failed to load module content: {e}"},
            status=500,
        )

    coverage = kb_audio.get_coverage_status(module_id, module_content)
    return web.json_response(coverage.to_dict())


async def handle_kb_feedback_audio(request: web.Request) -> web.Response:
    """
    GET /api/kb/feedback/{feedback_type}

    Get pre-generated feedback audio (correct/incorrect).
    """
    feedback_type = request.match_info.get("feedback_type")
    if feedback_type not in ("correct", "incorrect"):
        return web.json_response(
            {"error": "Invalid feedback type. Valid: correct, incorrect"},
            status=400,
        )

    kb_audio = request.app.get("kb_audio_manager")
    if not kb_audio:
        return web.json_response(
            {"error": "KB audio manager not initialized"},
            status=503,
        )

    audio = await kb_audio.get_feedback_audio(feedback_type)
    if audio is None:
        return web.json_response(
            {"error": f"Feedback audio not found: {feedback_type}"},
            status=404,
        )

    return web.Response(
        body=audio,
        content_type="audio/wav",
        headers={
            "X-KB-Cache-Status": "hit",
        },
    )


# =============================================================================
# Route Registration
# =============================================================================


def register_tts_routes(app: web.Application):
    """Register all TTS API routes on the application."""

    logger.info("Registering TTS API routes...")

    # TTS generation
    app.router.add_post("/api/tts", handle_tts_request)

    # Cache management
    app.router.add_get("/api/tts/cache/stats", handle_get_cache_stats)
    app.router.add_get("/api/tts/cache", handle_get_cache_entry)
    app.router.add_put("/api/tts/cache", handle_put_cache_entry)
    app.router.add_delete("/api/tts/cache", handle_clear_cache)
    app.router.add_delete("/api/tts/cache/expired", handle_evict_expired)
    app.router.add_post("/api/tts/cache/evict", handle_evict_lru)

    # Prefetch
    app.router.add_post("/api/tts/prefetch/topic", handle_prefetch_topic)
    app.router.add_get("/api/tts/prefetch/status/{job_id}", handle_prefetch_status)
    app.router.add_delete("/api/tts/prefetch/{job_id}", handle_cancel_prefetch)

    # Knowledge Bowl audio endpoints
    app.router.add_get("/api/kb/audio/{question_id}/{segment}", handle_kb_audio_get)
    app.router.add_post("/api/kb/audio/batch", handle_kb_audio_batch)
    app.router.add_post("/api/kb/prefetch", handle_kb_prefetch)
    app.router.add_get("/api/kb/prefetch/{job_id}", handle_kb_prefetch_status)
    app.router.add_get("/api/kb/manifest/{module_id}", handle_kb_manifest)
    app.router.add_get("/api/kb/coverage/{module_id}", handle_kb_coverage)
    app.router.add_get("/api/kb/feedback/{feedback_type}", handle_kb_feedback_audio)

    logger.info("TTS API routes registered")
