---
description: View and manage the accumulative commit message draft
---

# Commit Message Management

Check the argument passed to this command:

## If no argument (just `/commit-message`):
1. Read `.claude/draft-commit.md` and display the current accumulated notes
2. Format as a ready-to-use commit message:
   - First line: `type: summary`
   - Blank line
   - Body: bulleted list of changes
3. Remind user they can copy this for their commit
4. If the file doesn't exist or is empty, inform the user that no draft has been started yet

## If argument is "clear" (`/commit-message clear`):
1. Delete or empty `.claude/draft-commit.md`
2. Confirm the draft has been cleared
3. Typically done after committing

## After Viewing
Remind the user that per project policy, the human handles all commits.
The staged files can be committed with the formatted message above.
