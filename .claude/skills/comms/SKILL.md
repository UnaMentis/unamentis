---
name: comms
description: Post to Slack channels and manage Trello cards with natural language
---

# /comms - Slack & Trello Communications Skill

Post messages to Slack channels and create/update Trello cards with natural language commands.

## Usage

```
/comms [message or instruction]
```

## Key Rules

### Trello Comments
**Always prefix Trello comments with "From Claude Code: "**

Example: If asked to add comment "Fixed the bug", post:
```
From Claude Code: Fixed the bug
```

### Fuzzy Matching
Match user input to channels/boards using aliases. Examples:
- "android" -> tech-android (Slack) or Android list (Trello)
- "ios" -> tech-ios (Slack) or IOS App list (Trello)
- "server" -> tech-server (Slack) or Server list (Trello)

### Smart Defaults
- Tech topics without channel specified -> tech-general
- Tech topics without board specified -> Tech Work board
- Business/org topics -> Org-Business Work board

## Example Commands

| User Says | Action |
|-----------|--------|
| "post to android: feature complete" | Post to tech-android channel |
| "create card on ios list: Fix crash bug" | Create card on Tech Work -> IOS App list |
| "add comment to card X: resolved" | Add "From Claude Code: resolved" to card |
| "tell server channel build is ready" | Post to tech-server channel |
| "create website card: update pricing" | Create card on Org-Business Work -> Website list |

## Resources

See [RESOURCES.md](RESOURCES.md) for complete channel/board mappings with IDs.

## MCP Tools Used

### Slack
- `mcp__slack__slack_post_message` - Post to channel
- `mcp__slack__slack_reply_to_thread` - Reply in thread
- `mcp__slack__slack_get_channel_history` - Read messages
- `mcp__slack__slack_add_reaction` - Add emoji reaction

### Trello
- `mcp__trello__add_card_to_list` - Create card
- `mcp__trello__add_comment` - Add comment (remember prefix!)
- `mcp__trello__update_card_details` - Update card
- `mcp__trello__move_card` - Move card between lists
- `mcp__trello__get_cards_by_list_id` - List cards

## Workflow

1. Parse user intent (Slack, Trello, or both)
2. Resolve channel/board/list using fuzzy matching
3. Execute appropriate MCP tool(s)
4. Confirm action to user
