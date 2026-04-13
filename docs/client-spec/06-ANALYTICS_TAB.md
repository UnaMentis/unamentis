# Analytics Tab

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Reference Implementation:** iOS (Swift/SwiftUI) | All clients should achieve feature parity

---

## Overview

The Analytics tab (accessed via More menu) displays metrics about learning sessions including usage statistics, performance latencies, and cost breakdowns. This helps users understand their learning patterns and system performance.

![Analytics Dashboard](screenshots/analytics/analytics-main-iphone.png)

---

## Dashboard Layout

```
┌──────────────────────────────────────┐
│ <         Analytics        [?] [↑]   │
├──────────────────────────────────────┤
│ ┌──────────┬──────────┬──────────┐  │
│ │    0     │   0:00   │  $0.00   │  │
│ │ Sessions │ Duration │   Cost   │  │
│ └──────────┴──────────┴──────────┘  │
├──────────────────────────────────────┤
│ ⏱ Latency                            │
│ ┌──────────────────────────────────┐ │
│ │ STT          0ms median   0ms p99│ │
│ │ LLM TTFT     0ms median   0ms p99│ │
│ │ TTS TTFB     0ms median   0ms p99│ │
│ │ End-to-End   0ms median   0ms p99│ │
│ └──────────────────────────────────┘ │
├──────────────────────────────────────┤
│ 💰 Cost Breakdown                    │
│ ┌──────────────────────────────────┐ │
│ │ STT                      $0.0000 │ │
│ │ TTS                      $0.0000 │ │
│ │ LLM                      $0.0000 │ │
│ │ Total                    $0.0000 │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

---

## Stats Cards

### Summary Statistics

Three primary stat cards at top:

| Card | Icon | Metric | Format |
|------|------|--------|--------|
| Sessions | Blue circle | Total session count | Integer |
| Duration | Orange clock | Total time spent | HH:MM or MM:SS |
| Cost | Green dollar | Total API costs | $X.XX |

### Time Period Selector

Stats can be filtered by period:

| Period | Description |
|--------|-------------|
| Today | Current day only |
| This Week | Last 7 days |
| This Month | Last 30 days |
| All Time | Complete history |

---

## Latency Metrics

### Metric Definitions

| Metric | Description |
|--------|-------------|
| **STT** | Speech-to-text transcription time |
| **LLM TTFT** | Time to first token from language model |
| **TTS TTFB** | Time to first byte of synthesized audio |
| **End-to-End** | Total turn latency (user done → AI starts) |

### Statistical Measures

| Measure | Description |
|---------|-------------|
| Median | 50th percentile (typical experience) |
| P99 | 99th percentile (worst case) |

### Performance Targets

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| STT | < 200ms | 200-500ms | > 500ms |
| LLM TTFT | < 500ms | 500-1000ms | > 1000ms |
| TTS TTFB | < 200ms | 200-400ms | > 400ms |
| End-to-End | < 1000ms | 1000-2000ms | > 2000ms |

### Visual Indicators

- **Green**: Within target
- **Yellow**: Warning range
- **Red**: Critical range

---

## Cost Breakdown

### Cost Categories

| Category | Description | Typical Rate |
|----------|-------------|--------------|
| STT | Speech-to-text API | $0.006/min |
| TTS | Text-to-speech API | $0.015/1K chars |
| LLM | Language model API | $0.01-0.03/1K tokens |

### Cost Display

- Individual category costs
- Total cost
- Cost per session average
- Projected monthly cost (based on usage)

### Cost Alerts

Optional alerts when:
- Session cost exceeds threshold
- Daily spending limit reached
- Monthly projection exceeds budget

---

## Detailed Analytics

### Session Analytics

Expandable section with deeper metrics:

| Metric | Description |
|--------|-------------|
| Avg session length | Mean duration |
| Avg turns per session | Conversation depth |
| Words per minute | Speaking pace |
| Completion rate | Sessions ended normally |

### Topic Analytics

Performance by topic:

| Metric | Description |
|--------|-------------|
| Most studied | Top topics by time |
| Confidence trend | Improvement over time |
| Review frequency | Times revisited |

### Provider Analytics

Breakdown by service provider:

| Provider | Metrics |
|----------|---------|
| AssemblyAI | Latency, accuracy, cost |
| Deepgram | Latency, accuracy, cost |
| OpenAI | Latency, token usage, cost |
| ElevenLabs | Latency, character usage, cost |

---

## Export Options

### Export Button (↑)

Share analytics data:

| Format | Content |
|--------|---------|
| CSV | Raw metrics data |
| PDF | Formatted report |
| JSON | Structured data |

### Report Contents

- Summary statistics
- Latency distributions
- Cost breakdown
- Session history summary
- Provider performance comparison

---

## Data Collection

### What's Collected

| Data | Purpose |
|------|---------|
| Session timestamps | Duration calculation |
| Turn latencies | Performance monitoring |
| API response times | Provider comparison |
| Token/character counts | Cost calculation |
| Error rates | Reliability tracking |

### Privacy

- All data stored locally by default
- Optional server sync for cross-device
- No personally identifiable information
- Data can be deleted via Clear History

---

## Accessibility

### VoiceOver

- Stats cards: "{Value} {metric}"
- Latency rows: "{metric}, {median} median, {p99} ninety-ninth percentile"
- Cost rows: "{category}, {amount}"

### Dynamic Type

- Numbers scale with system text size
- Charts adapt to larger fonts
- Maintains readability

### Color Blind Support

- Patterns supplement color coding
- Text labels always visible
- High contrast mode support

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - Accessing via More menu
- [05-HISTORY_TAB.md](05-HISTORY_TAB.md) - Session history
- [07-SETTINGS.md](07-SETTINGS.md) - Provider configuration
