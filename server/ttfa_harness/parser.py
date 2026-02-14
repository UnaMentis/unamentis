"""
UnaMentis TTFA Harness - Log Parser

Parses structured TTFA events from the xcrun simctl log stream output.
The in-app TTFAInstrumentation actor emits events in this format:
    [TTFA] EVENT|feature_id|elapsed_ms|metadata
"""

import json
import logging
import re
from datetime import datetime
from typing import Optional, List

from .models import TTFAEvent, TTFAEventType, TTFAResult, AudioPath

logger = logging.getLogger("ttfa_harness.parser")

# Pattern to match TTFA events in log output.
# os_log ndjson format wraps the message in a JSON object with an "eventMessage" field.
# The message itself looks like: [TTFA] ACTIVATE|session.chat|0.00|
TTFA_PATTERN = re.compile(
    r"\[TTFA\]\s*"
    r"(?P<event>[A-Z_]+)\|"
    r"(?P<feature>[a-z0-9._-]+)\|"
    r"(?P<elapsed>[0-9.]+)\|"
    r"(?P<metadata>.*)"
)


def parse_log_line(line: str) -> Optional[TTFAEvent]:
    """
    Parse a single log line into a TTFAEvent, or None if not a TTFA event.

    Handles both raw text lines and ndjson-formatted log output.
    """
    message = line
    ndjson_data = None

    # Try to extract eventMessage from ndjson format
    if line.startswith("{"):
        try:
            ndjson_data = json.loads(line)
            message = ndjson_data.get("eventMessage", "")
        except json.JSONDecodeError:
            return None

    match = TTFA_PATTERN.search(message)
    if not match:
        return None

    event_str = match.group("event")
    try:
        event_type = TTFAEventType(event_str)
    except ValueError:
        logger.warning("Unknown TTFA event type: %s", event_str)
        return None

    # Parse wall timestamp from ndjson if available (reuses already-parsed data)
    wall_timestamp = None
    if ndjson_data is not None:
        try:
            ts_str = ndjson_data.get("timestamp", "")
            if ts_str:
                # macOS log timestamps are ISO-ish: "2024-01-15 10:30:00.123456-0800"
                wall_timestamp = datetime.fromisoformat(ts_str.replace(" ", "T"))
        except ValueError:
            pass

    return TTFAEvent(
        event_type=event_type,
        feature_id=match.group("feature"),
        elapsed_ms=float(match.group("elapsed")),
        metadata=match.group("metadata").strip(),
        wall_timestamp=wall_timestamp,
    )


def events_to_result(
    events: List[TTFAEvent],
    scenario_id: str,
    scenario_name: str,
    audio_path: AudioPath,
    repetition: int,
) -> TTFAResult:
    """
    Convert a sequence of TTFA events (from one activation cycle) into a TTFAResult.

    The events should start with ACTIVATE and end with AUDIO_PLAYING (or ERROR).
    Elapsed times in the events are already relative to ACTIVATE (computed in-app).
    """
    result = TTFAResult(
        scenario_id=scenario_id,
        scenario_name=scenario_name,
        audio_path=audio_path,
        repetition=repetition,
    )

    for event in events:
        if event.event_type == TTFAEventType.TTS_FIRST:
            result.activate_to_tts_first_ms = event.elapsed_ms
        elif event.event_type == TTFAEventType.AUDIO_SCHEDULED:
            result.activate_to_audio_scheduled_ms = event.elapsed_ms
        elif event.event_type == TTFAEventType.AUDIO_PLAYING:
            result.activate_to_audio_playing_ms = event.elapsed_ms
        elif event.event_type == TTFAEventType.CACHED_HIT:
            result.was_cached = True
        elif event.event_type == TTFAEventType.ERROR:
            result.errors.append(event.metadata or "Unknown error")

    return result


def group_events_by_activation(events: List[TTFAEvent]) -> List[List[TTFAEvent]]:
    """
    Group events into activation cycles.

    Each ACTIVATE event starts a new group. All subsequent events until the
    next ACTIVATE (or end of list) belong to that group. Events arriving
    before the first ACTIVATE are discarded as orphans.
    """
    groups: List[List[TTFAEvent]] = []
    current_group: List[TTFAEvent] = []
    seen_activate = False

    for event in events:
        if event.event_type == TTFAEventType.ACTIVATE:
            if current_group:
                groups.append(current_group)
            current_group = [event]
            seen_activate = True
        elif seen_activate:
            current_group.append(event)
        # else: discard orphan events before first ACTIVATE

    if current_group and seen_activate:
        groups.append(current_group)

    return groups


def collect_events_for_feature(
    all_events: List[TTFAEvent],
    feature_id: str,
) -> List[List[TTFAEvent]]:
    """
    Extract all activation cycles for a specific feature.

    Returns a list of event groups, one per activation of the given feature.
    """
    groups = group_events_by_activation(all_events)
    return [g for g in groups if g and g[0].feature_id == feature_id]
