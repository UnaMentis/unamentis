# To-Do Tab

**Version:** 1.0.0
**Last Updated:** 2026-01-16
**Platform:** iOS (Swift/SwiftUI)

---

## Overview

The To-Do tab helps users manage learning goals, track topics to study, and organize their learning journey. Items can be manually created or AI-suggested based on session performance.

![To-Do Empty State](screenshots/todo/todo-empty-iphone.png)

---

## View Structure

```
To-Do Tab
├── Filter Bar
├── To-Do List
│   ├── Empty State
│   └── To-Do Items (grouped by status)
├── Add Item (+ button)
└── Item Detail (sheet)
```

---

## List View

### Header

```
┌──────────────────────────────────────┐
│ [Logo]        To-Do        [?] [≡] [+] │
├──────────────────────────────────────┤
│  [All] [Active] [Completed]          │  ← Filter Pills
├──────────────────────────────────────┤
```

### Empty State

When no to-do items exist:
- Checklist icon with checkmark
- "No To-Do Items" heading
- "Add learning goals, curricula, or topics to track your progress." subtext
- "+ Add Item" button

### Populated List

Items grouped by status with section headers:

```
│ Active (3)                           │
│ ┌──────────────────────────────────┐ │
│ │ ○ Review Newton's Laws           │ │
│ │   Physics • Due tomorrow         │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ ○ Complete Calculus Chapter 3    │ │
│ │   Math • No due date             │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Completed Today (1)                  │
│ ┌──────────────────────────────────┐ │
│ │ ✓ Intro to Thermodynamics        │ │
│ │   Physics • Completed 2h ago     │ │
│ └──────────────────────────────────┘ │
```

---

## To-Do Item Structure

### Item Properties

| Property | Type | Description |
|----------|------|-------------|
| Title | String | Item description |
| Type | Enum | Topic, Curriculum, Goal, Custom |
| Status | Enum | Pending, In Progress, Completed |
| Priority | Enum | Low, Medium, High |
| Due Date | Date? | Optional deadline |
| Curriculum | Reference? | Linked curriculum |
| Topic | Reference? | Linked topic |
| Notes | String? | Additional notes |
| AI Suggested | Bool | Whether AI suggested this item |

### Item Types

| Type | Icon | Description |
|------|------|-------------|
| Topic | 📄 | Specific topic to study |
| Curriculum | 📚 | Entire curriculum to complete |
| Goal | 🎯 | Custom learning goal |
| Review | 🔄 | AI-suggested review item |

### Status Indicators

| Status | Visual | Description |
|--------|--------|-------------|
| Pending | ○ Empty circle | Not started |
| In Progress | ◐ Half circle | Currently working on |
| Completed | ✓ Checkmark | Finished |

---

## Filters

### Filter Pills

Quick filters at top of list:

| Filter | Shows |
|--------|-------|
| All | All items regardless of status |
| Active | Pending and In Progress items |
| Completed | Completed items only |

### Advanced Filters (≡ button)

| Filter | Options |
|--------|---------|
| Type | All, Topic, Curriculum, Goal, Review |
| Priority | All, High, Medium, Low |
| Due Date | All, Overdue, Today, This Week, No Date |
| Curriculum | All, or specific curriculum |
| AI Suggested | All, AI Only, Manual Only |

### Sort Options

| Sort | Description |
|------|-------------|
| Due Date | Soonest first, no date last |
| Priority | High → Medium → Low |
| Recently Added | Newest first |
| Alphabetical | A-Z by title |

---

## CRUD Operations

### Create Item

Tap + button to add new item:

```
┌──────────────────────────────────────┐
│ Cancel       Add To-Do         Save  │
├──────────────────────────────────────┤
│                                      │
│ Title                                │
│ ┌──────────────────────────────────┐ │
│ │ Review calculus derivatives      │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Type                                 │
│ [Topic ▼]                            │
│                                      │
│ Link to Curriculum                   │
│ [Calculus Fundamentals ▼]            │
│                                      │
│ Link to Topic                        │
│ [Derivatives ▼]                      │
│                                      │
│ Priority                             │
│ [○ Low] [● Medium] [○ High]          │
│                                      │
│ Due Date                             │
│ [None] [Tomorrow] [Custom...]        │
│                                      │
│ Notes                                │
│ ┌──────────────────────────────────┐ │
│ │                                  │ │
│ └──────────────────────────────────┘ │
│                                      │
└──────────────────────────────────────┘
```

### Read/View Item

Tap item to view details in sheet:
- All item properties displayed
- Edit button to modify
- Delete button (with confirmation)
- "Start Session" if linked to topic

### Update Item

- Tap checkbox to toggle completion
- Swipe right to mark complete
- Tap item → Edit to modify details
- Long press for quick actions

### Delete Item

- Swipe left to delete
- Confirmation required for non-completed items
- Completed items delete immediately

---

## AI Suggestions

### How Suggestions Work

The AI suggests to-do items based on:
1. **Session performance**: Topics with low confidence scores
2. **Time since review**: Topics not studied recently
3. **Curriculum progress**: Next logical topics
4. **Spaced repetition**: Optimal review intervals

### Suggestion Display

AI-suggested items have special styling:
- "✨ Suggested" badge
- Lighter background
- "Why?" info button explaining the suggestion

### Accepting/Dismissing Suggestions

| Action | Result |
|--------|--------|
| Tap | View suggestion details |
| Accept | Convert to regular to-do item |
| Dismiss | Remove suggestion (can reappear later) |
| Dismiss Forever | Never suggest this item again |

---

## Quick Actions

### Swipe Actions

| Direction | Action |
|-----------|--------|
| Swipe Right | Mark complete |
| Swipe Left | Delete |

### Long Press Menu

- Edit
- Mark Complete/Incomplete
- Change Priority
- Start Session (if linked)
- Delete

### Batch Operations

Select multiple items for batch actions:
- Mark all complete
- Delete selected
- Change priority
- Set due date

---

## Notifications

### Due Date Reminders

| Timing | Notification |
|--------|--------------|
| Day before | "'{Title}' is due tomorrow" |
| Day of | "'{Title}' is due today" |
| Overdue | "'{Title}' is overdue" |

### Notification Settings

Users can configure:
- Enable/disable reminders
- Reminder timing (day before, day of, both)
- Quiet hours

---

## Integration with Other Tabs

### From Curriculum Tab

- "Add to To-Do" action on topics
- Auto-creates linked to-do item

### From Session Tab

- Session completion can auto-complete linked to-do
- Low confidence triggers review suggestion

### From History Tab

- "Review this topic" creates to-do item

---

## Accessibility

### VoiceOver

- Item: "{Title}, {type}, {priority} priority, {status}"
- Due date: "Due {date}" or "No due date"
- Suggestions: "AI suggested. {reason}"

### Dynamic Type

- List items scale with system text size
- Maintains tap targets
- Truncates long titles with ellipsis

### Reduce Motion

- Swipe actions work without animation
- Completion checkmark appears instantly

---

## Related Documentation

- [01-NAVIGATION_ARCHITECTURE.md](01-NAVIGATION_ARCHITECTURE.md) - App navigation
- [03-CURRICULUM_TAB.md](03-CURRICULUM_TAB.md) - Linking to curricula
- [02-SESSION_TAB.md](02-SESSION_TAB.md) - Starting sessions from to-dos
