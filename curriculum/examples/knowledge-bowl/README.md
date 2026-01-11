# Knowledge Bowl Curriculum Examples

This directory contains example UMCF curriculum files demonstrating Knowledge Bowl module features.

## Files

| File | Description |
|------|-------------|
| `science-physics-sample.json` | Physics topic with toss-ups, bonuses, pyramids, and lightning rounds |

## Usage

These examples demonstrate:

1. **Knowledge Bowl Extensions**: How to add `knowledgeBowl` namespace to UMCF nodes
2. **Question Types**: Toss-up, bonus, pyramid, and lightning round formats
3. **Buzz Points**: Strategic hints for when to buzz on questions
4. **Difficulty Tiers**: From JV to championship level content
5. **Speed Targets**: Per-topic response time goals
6. **Misconception Handling**: Common errors and corrections

## Validation

Validate examples against the schema:

```bash
# From curriculum directory
python -m jsonschema -i examples/knowledge-bowl/science-physics-sample.json spec/umcf-schema.json
```

## Creating New Content

1. Start with the base UMCF structure
2. Add `extensions.knowledgeBowl` to each content node
3. Include `competitionYear` and `domain` (required fields)
4. Add appropriate question types for each segment
5. Define buzz points for competition strategy

See `/curriculum/spec/KNOWLEDGE_BOWL_EXTENSIONS.md` for the complete extension specification.
