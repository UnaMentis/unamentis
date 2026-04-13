# Curriculum Tab (Learning Tab - Curriculum Section)

**Version:** 1.1.0
**Last Updated:** 2026-01-20
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

The Curriculum section is part of the **Learning tab**, which uses a segmented control to switch between Curriculum and Modules. This document covers the Curriculum section; for specialized training modules like Knowledge Bowl, see the Modules section in [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md).

The Curriculum section enables users to browse, import, and manage learning content. Users can explore curricula, drill down to specific topics, and select content for voice sessions.

> **Note:** When the Modules feature flag is disabled, the Learning tab displays only the Curriculum section without the segmented control.

![Curriculum Empty State](screenshots/curriculum/curriculum-empty-iphone.png)

---

## View Hierarchy

```
Learning Tab → Curriculum Section
├── Curriculum List
│   ├── Empty State (no curricula loaded)
│   └── Curriculum Cards
│       └── Curriculum Detail
│           ├── Overview Section
│           ├── Topic List
│           │   └── Topic Detail
│           │       ├── Content Preview
│           │       ├── Visual Assets
│           │       └── Start Session Button
│           └── Curriculum Actions
└── Import Flow (Modal)
    ├── Source Selection
    ├── Content Selection
    ├── Import Progress
    └── Import Complete
```

---

## Curriculum List View

### Empty State

When no curricula are loaded:
- Large book icon
- "No Curriculum Loaded" heading
- "Import a curriculum to get started." subtext
- Primary "Import Curriculum" button

### Loaded State

Displays curriculum cards in a scrollable list:

```
┌──────────────────────────────────────┐
│ [Logo]      Curriculum      [?] [⊕]  │
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │
│ │ 📘 Introduction to Physics       │ │
│ │ 24 topics • 12 completed        │ │
│ │ ████████░░░░░░░░ 50%            │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ 📗 Calculus Fundamentals         │ │
│ │ 36 topics • 0 completed         │ │
│ │ ░░░░░░░░░░░░░░░░ 0%             │ │
│ └──────────────────────────────────┘ │
│                                      │
│  Session │ Curriculum │ ... │ More  │
└──────────────────────────────────────┘
```

### Curriculum Card Components

| Element | Description |
|---------|-------------|
| Icon | Subject-specific emoji or custom icon |
| Title | Curriculum name |
| Topic count | "N topics" |
| Progress | "N completed" with progress bar |
| Percentage | Completion percentage |

### List Actions

- **Pull to refresh**: Sync with server
- **Swipe left**: Archive curriculum
- **Long press**: Context menu (Archive, Delete, Export)
- **Tap card**: Navigate to detail

---

## Curriculum Detail View

### Header Section

```
┌──────────────────────────────────────┐
│ < Curriculum    [Share] [⋮]          │
├──────────────────────────────────────┤
│                                      │
│        📘 Introduction to Physics    │
│                                      │
│        24 topics • 6.5 hours         │
│        Last studied: 2 days ago      │
│                                      │
│   [▶️ Continue]  [Start Over]        │
│                                      │
├──────────────────────────────────────┤
```

### Topic List Section

Topics organized by module/chapter:

```
│ Module 1: Mechanics                  │
│ ├─ ✓ Newton's First Law             │
│ ├─ ✓ Newton's Second Law            │
│ ├─ ● Newton's Third Law (current)   │
│ └─ ○ Conservation of Momentum       │
│                                      │
│ Module 2: Thermodynamics            │
│ ├─ ○ Temperature and Heat           │
│ └─ ○ Laws of Thermodynamics         │
```

### Topic Status Icons

| Icon | Status | Description |
|------|--------|-------------|
| ✓ | Completed | Topic finished with passing confidence |
| ● | Current | Currently selected or in progress |
| ○ | Not started | No sessions on this topic |
| ⚠️ | Needs review | Confidence below threshold |

### Actions

| Action | Trigger | Result |
|--------|---------|--------|
| Continue | Tap "Continue" button | Resume last topic |
| Start Over | Tap "Start Over" | Reset progress, start fresh |
| Select Topic | Tap topic row | Set as current topic |
| Start Session | Tap "Start Session" in topic | Go to Session tab |

---

## Topic Detail View

### Content Preview

Shows topic overview before starting:
- Topic title and description
- Estimated duration
- Prerequisite topics (if any)
- Key concepts list
- Visual asset previews

### Visual Assets Gallery

Displays images, diagrams, and media associated with the topic:
- Thumbnail grid view
- Tap to preview full-size
- Assets available during session

### Start Session

Prominent button to begin voice session with this topic:
- Sets topic as active
- Navigates to Session tab
- Initializes session with topic context

---

## Import Flow

### Step 1: Source Selection

Available import sources:

| Source | Type | Description |
|--------|------|-------------|
| Brilliant | API | Brilliant.org courses |
| Khan Academy | API | Khan Academy content |
| File | Local | UMCF JSON/ZIP files |
| URL | Remote | UMCF file from URL |
| Sample | Built-in | Demo curriculum |

### Step 2: Content Selection

For API sources, browse and select:
- Course categories
- Individual courses
- Specific modules (optional)

### Step 3: Import Progress

Shows real-time import status:

```
┌──────────────────────────────────────┐
│         Importing Curriculum         │
├──────────────────────────────────────┤
│                                      │
│  📘 Introduction to Physics          │
│                                      │
│  ████████████░░░░░░░░ 60%           │
│                                      │
│  Downloading content...              │
│  12 of 20 topics imported            │
│                                      │
│           [Cancel Import]            │
│                                      │
└──────────────────────────────────────┘
```

### Step 4: Import Complete

Success state with options:
- View imported curriculum
- Import another
- Done

Error handling:
- Partial import recovery
- Retry failed items
- Skip and continue

---

## Progress Tracking

### Completion Criteria

A topic is considered "complete" when:
1. User has completed at least one session
2. AI confidence assessment passes threshold
3. No critical concepts flagged for review

### Progress Persistence

| Data | Storage | Sync |
|------|---------|------|
| Completion status | Core Data | Server sync |
| Last accessed | Core Data | Server sync |
| Session history | Core Data | Server sync |
| Confidence scores | Core Data | Server sync |

### Progress Display

- **List view**: Progress bar per curriculum
- **Detail view**: Topic-level completion
- **Session tab**: Current topic indicator

---

## Curriculum Management

### Archive

- Hides curriculum from main list
- Preserves all data and progress
- Accessible via "Archived" filter
- Can be restored at any time

### Delete

- Permanently removes curriculum
- Deletes all associated sessions
- Requires confirmation
- Cannot be undone

### Export

- Exports curriculum as UMCF file
- Includes progress data (optional)
- Share via standard iOS share sheet

---

## Search and Filter

### Search

- Full-text search across titles
- Searches topics within curricula
- Results update as you type

### Filters

| Filter | Options |
|--------|---------|
| Status | All, In Progress, Completed, Not Started |
| Source | All, Brilliant, Khan Academy, Local |
| Subject | All, Math, Science, Language, etc. |

### Sort

| Sort Option | Description |
|-------------|-------------|
| Last Accessed | Most recently studied first |
| Progress | By completion percentage |
| Alphabetical | A-Z by title |
| Date Added | Newest first |

---

## Offline Support

### Cached Content

- Curriculum metadata always available
- Topic list and descriptions cached
- Visual assets cached on demand
- Last N sessions cached

### Offline Indicators

- Cloud icon with slash for unavailable content
- "Available offline" badge for cached curricula
- Download button for full offline access

### Sync Behavior

- Auto-sync on app launch (if online)
- Pull-to-refresh triggers sync
- Background sync for progress updates
- Conflict resolution: server wins for content, merge for progress

---

## Accessibility

### VoiceOver

- Curriculum cards: "{Title}, {N} topics, {percent} complete"
- Progress bars: "{percent} complete"
- Topic list: "{Topic name}, {status}"

### Dynamic Type

- Card layouts adapt to larger text
- Minimum tap targets maintained
- Scrollable content areas expand

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - App navigation
- [02-SESSION_TAB.md](02-SESSION_TAB.md) - Starting sessions
- [Server API: Curricula](../api-spec/02-CURRICULA.md) - Curriculum endpoints
- [Server API: Import](../api-spec/05-IMPORT.md) - Import endpoints
