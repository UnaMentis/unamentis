"""
Tests for the TTFA harness log parser.
"""

import json

from ttfa_harness.models import AudioPath, TTFAEventType
from ttfa_harness.parser import (
    collect_events_for_feature,
    events_to_result,
    group_events_by_activation,
    parse_log_line,
)


# ============================================================================
# parse_log_line
# ============================================================================


class TestParseLogLine:
    """Tests for parsing individual log lines into TTFAEvents."""

    def test_raw_activate_event(self):
        line = "[TTFA] ACTIVATE|session.chat|0.00|"
        event = parse_log_line(line)
        assert event is not None
        assert event.event_type == TTFAEventType.ACTIVATE
        assert event.feature_id == "session.chat"
        assert event.elapsed_ms == 0.0
        assert event.metadata == ""

    def test_raw_tts_first_event(self):
        line = "[TTFA] TTS_FIRST|kb.oral|123.45|"
        event = parse_log_line(line)
        assert event is not None
        assert event.event_type == TTFAEventType.TTS_FIRST
        assert event.feature_id == "kb.oral"
        assert event.elapsed_ms == 123.45

    def test_raw_audio_scheduled_event(self):
        line = "[TTFA] AUDIO_SCHEDULED|reading.play|200.50|"
        event = parse_log_line(line)
        assert event is not None
        assert event.event_type == TTFAEventType.AUDIO_SCHEDULED
        assert event.elapsed_ms == 200.50

    def test_raw_audio_playing_event(self):
        line = "[TTFA] AUDIO_PLAYING|session.curriculum|350.00|"
        event = parse_log_line(line)
        assert event is not None
        assert event.event_type == TTFAEventType.AUDIO_PLAYING
        assert event.elapsed_ms == 350.0

    def test_raw_cached_hit_event(self):
        line = "[TTFA] CACHED_HIT|reading.play|5.20|"
        event = parse_log_line(line)
        assert event is not None
        assert event.event_type == TTFAEventType.CACHED_HIT
        assert event.elapsed_ms == 5.20

    def test_raw_error_event_with_metadata(self):
        line = "[TTFA] ERROR|kb.oral|0.00|superseded by session.chat"
        event = parse_log_line(line)
        assert event is not None
        assert event.event_type == TTFAEventType.ERROR
        assert event.metadata == "superseded by session.chat"

    def test_ndjson_format_with_space_timestamp(self):
        """macOS log stream uses space-separated timestamps with no colon in tz offset."""
        ndjson = json.dumps(
            {
                "timestamp": "2024-01-15 10:30:00.123456-0800",
                "eventMessage": "[TTFA] ACTIVATE|session.chat|0.00|cold start",
                "subsystem": "com.unamentis.ttfa",
            }
        )
        event = parse_log_line(ndjson)
        assert event is not None
        assert event.event_type == TTFAEventType.ACTIVATE
        assert event.feature_id == "session.chat"
        assert event.metadata == "cold start"
        assert event.wall_timestamp is not None

    def test_ndjson_format_with_iso_timestamp(self):
        """Also handle proper ISO format timestamps."""
        ndjson = json.dumps(
            {
                "timestamp": "2024-01-15T10:30:00.123456-08:00",
                "eventMessage": "[TTFA] ACTIVATE|session.chat|0.00|",
            }
        )
        event = parse_log_line(ndjson)
        assert event is not None
        assert event.wall_timestamp is not None

    def test_ndjson_without_timestamp(self):
        ndjson = json.dumps(
            {
                "eventMessage": "[TTFA] TTS_FIRST|kb.oral|150.00|",
            }
        )
        event = parse_log_line(ndjson)
        assert event is not None
        assert event.event_type == TTFAEventType.TTS_FIRST
        assert event.wall_timestamp is None

    def test_non_ttfa_line_returns_none(self):
        assert parse_log_line("some random log line") is None
        assert parse_log_line("") is None
        assert parse_log_line("[INFO] Not a TTFA event") is None

    def test_non_ttfa_ndjson_returns_none(self):
        ndjson = json.dumps({"eventMessage": "Regular log message"})
        assert parse_log_line(ndjson) is None

    def test_invalid_json_returns_none(self):
        assert parse_log_line("{invalid json}") is None
        assert parse_log_line("{ broken: ") is None

    def test_unknown_event_type_returns_none(self):
        line = "[TTFA] UNKNOWN_EVENT|session.chat|0.00|"
        assert parse_log_line(line) is None

    def test_feature_id_with_dots_and_dashes(self):
        line = "[TTFA] ACTIVATE|kb.oral-v2.1|0.00|"
        event = parse_log_line(line)
        assert event is not None
        assert event.feature_id == "kb.oral-v2.1"

    def test_feature_id_with_numbers(self):
        line = "[TTFA] ACTIVATE|session2.chat|0.00|"
        event = parse_log_line(line)
        assert event is not None
        assert event.feature_id == "session2.chat"

    def test_metadata_with_special_characters(self):
        line = "[TTFA] ERROR|kb.oral|100.00|timeout after 15s: connection refused"
        event = parse_log_line(line)
        assert event is not None
        assert event.metadata == "timeout after 15s: connection refused"

    def test_ndjson_with_ttfa_embedded_in_larger_message(self):
        ndjson = json.dumps(
            {
                "eventMessage": "prefix text [TTFA] ACTIVATE|session.chat|0.00| suffix text",
            }
        )
        event = parse_log_line(ndjson)
        assert event is not None
        assert event.event_type == TTFAEventType.ACTIVATE

    def test_ndjson_invalid_timestamp_still_parses_event(self):
        ndjson = json.dumps(
            {
                "timestamp": "not-a-date",
                "eventMessage": "[TTFA] ACTIVATE|session.chat|0.00|",
            }
        )
        event = parse_log_line(ndjson)
        assert event is not None
        assert event.wall_timestamp is None


# ============================================================================
# events_to_result
# ============================================================================


class TestEventsToResult:
    """Tests for converting event sequences to TTFAResult."""

    def _make_event(
        self, event_type, feature_id="session.chat", elapsed_ms=0.0, metadata=""
    ):
        from ttfa_harness.models import TTFAEvent

        return TTFAEvent(
            event_type=event_type,
            feature_id=feature_id,
            elapsed_ms=elapsed_ms,
            metadata=metadata,
        )

    def test_full_streaming_sequence(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, elapsed_ms=0.0),
            self._make_event(TTFAEventType.TTS_FIRST, elapsed_ms=150.0),
            self._make_event(TTFAEventType.AUDIO_SCHEDULED, elapsed_ms=200.0),
            self._make_event(TTFAEventType.AUDIO_PLAYING, elapsed_ms=210.0),
        ]
        result = events_to_result(
            events,
            scenario_id="session-cold-start",
            scenario_name="Session Cold Start",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.scenario_id == "session-cold-start"
        assert result.activate_to_tts_first_ms == 150.0
        assert result.activate_to_audio_scheduled_ms == 200.0
        assert result.activate_to_audio_playing_ms == 210.0
        assert result.ttfa_ms == 210.0
        assert result.passes_target is True
        assert result.was_cached is False
        assert result.errors == []

    def test_cached_sequence(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, elapsed_ms=0.0),
            self._make_event(TTFAEventType.CACHED_HIT, elapsed_ms=5.0),
            self._make_event(TTFAEventType.AUDIO_SCHEDULED, elapsed_ms=8.0),
            self._make_event(TTFAEventType.AUDIO_PLAYING, elapsed_ms=10.0),
        ]
        result = events_to_result(
            events,
            scenario_id="reading-cached",
            scenario_name="Reading List Play (cached)",
            audio_path=AudioPath.CACHED,
            repetition=1,
        )
        assert result.ttfa_ms == 10.0
        assert result.was_cached is True
        assert result.activate_to_tts_first_ms is None

    def test_error_sequence(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, elapsed_ms=0.0),
            self._make_event(
                TTFAEventType.ERROR, elapsed_ms=5000.0, metadata="TTS timeout"
            ),
        ]
        result = events_to_result(
            events,
            scenario_id="session-cold-start",
            scenario_name="Session Cold Start",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.ttfa_ms is None
        assert result.passes_target is False
        assert result.errors == ["TTS timeout"]

    def test_empty_events(self):
        result = events_to_result(
            [],
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.ttfa_ms is None
        assert result.passes_target is False

    def test_failing_target(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, elapsed_ms=0.0),
            self._make_event(TTFAEventType.AUDIO_PLAYING, elapsed_ms=1500.0),
        ]
        result = events_to_result(
            events,
            scenario_id="slow-scenario",
            scenario_name="Slow Scenario",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.ttfa_ms == 1500.0
        assert result.passes_target is False

    def test_exactly_at_target(self):
        """TTFA at exactly 1000ms should fail (target is LESS than 1000ms)."""
        events = [
            self._make_event(TTFAEventType.ACTIVATE, elapsed_ms=0.0),
            self._make_event(TTFAEventType.AUDIO_PLAYING, elapsed_ms=1000.0),
        ]
        result = events_to_result(
            events,
            scenario_id="edge-case",
            scenario_name="Edge Case",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.passes_target is False

    def test_just_under_target(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, elapsed_ms=0.0),
            self._make_event(TTFAEventType.AUDIO_PLAYING, elapsed_ms=999.99),
        ]
        result = events_to_result(
            events,
            scenario_id="edge-case",
            scenario_name="Edge Case",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.passes_target is True


# ============================================================================
# group_events_by_activation
# ============================================================================


class TestGroupEventsByActivation:
    """Tests for grouping events into activation cycles."""

    def _make_event(self, event_type, feature_id="session.chat", elapsed_ms=0.0):
        from ttfa_harness.models import TTFAEvent

        return TTFAEvent(
            event_type=event_type,
            feature_id=feature_id,
            elapsed_ms=elapsed_ms,
        )

    def test_single_activation_cycle(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE),
            self._make_event(TTFAEventType.TTS_FIRST, elapsed_ms=100.0),
            self._make_event(TTFAEventType.AUDIO_PLAYING, elapsed_ms=200.0),
        ]
        groups = group_events_by_activation(events)
        assert len(groups) == 1
        assert len(groups[0]) == 3

    def test_multiple_activation_cycles(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, feature_id="session.chat"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, feature_id="session.chat"),
            self._make_event(TTFAEventType.ACTIVATE, feature_id="kb.oral"),
            self._make_event(TTFAEventType.TTS_FIRST, feature_id="kb.oral"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, feature_id="kb.oral"),
        ]
        groups = group_events_by_activation(events)
        assert len(groups) == 2
        assert len(groups[0]) == 2
        assert len(groups[1]) == 3

    def test_orphan_events_before_first_activate(self):
        events = [
            self._make_event(TTFAEventType.TTS_FIRST),  # Orphan
            self._make_event(TTFAEventType.AUDIO_PLAYING),  # Orphan
            self._make_event(TTFAEventType.ACTIVATE),
            self._make_event(TTFAEventType.AUDIO_PLAYING),
        ]
        groups = group_events_by_activation(events)
        assert len(groups) == 1
        assert groups[0][0].event_type == TTFAEventType.ACTIVATE

    def test_empty_events(self):
        groups = group_events_by_activation([])
        assert len(groups) == 0

    def test_only_activate_events(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, feature_id="a"),
            self._make_event(TTFAEventType.ACTIVATE, feature_id="b"),
        ]
        groups = group_events_by_activation(events)
        assert len(groups) == 2
        assert len(groups[0]) == 1
        assert len(groups[1]) == 1

    def test_single_activate_no_followup(self):
        events = [self._make_event(TTFAEventType.ACTIVATE)]
        groups = group_events_by_activation(events)
        assert len(groups) == 1
        assert len(groups[0]) == 1


# ============================================================================
# collect_events_for_feature
# ============================================================================


class TestCollectEventsForFeature:
    """Tests for filtering event groups by feature ID."""

    def _make_event(self, event_type, feature_id, elapsed_ms=0.0):
        from ttfa_harness.models import TTFAEvent

        return TTFAEvent(
            event_type=event_type,
            feature_id=feature_id,
            elapsed_ms=elapsed_ms,
        )

    def test_filter_single_feature(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, "session.chat"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, "session.chat"),
            self._make_event(TTFAEventType.ACTIVATE, "kb.oral"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, "kb.oral"),
        ]
        groups = collect_events_for_feature(events, "kb.oral")
        assert len(groups) == 1
        assert groups[0][0].feature_id == "kb.oral"

    def test_filter_no_match(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, "session.chat"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, "session.chat"),
        ]
        groups = collect_events_for_feature(events, "nonexistent")
        assert len(groups) == 0

    def test_multiple_activations_of_same_feature(self):
        events = [
            self._make_event(TTFAEventType.ACTIVATE, "kb.oral"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, "kb.oral"),
            self._make_event(TTFAEventType.ACTIVATE, "session.chat"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, "session.chat"),
            self._make_event(TTFAEventType.ACTIVATE, "kb.oral"),
            self._make_event(TTFAEventType.AUDIO_PLAYING, "kb.oral"),
        ]
        groups = collect_events_for_feature(events, "kb.oral")
        assert len(groups) == 2
