# SAT Preparation Curriculum Examples

This directory contains example UMCF curriculum files demonstrating SAT preparation module features.

## Files

| File | Description |
|------|-------------|
| `math-algebra-sample.json` | Algebra topic with linear equations, systems, and word problems |

## Key Features Demonstrated

### 1. SAT Extensions
- `testVersion`: Digital SAT 2024 format
- `section`: Reading/Writing or Math
- `domain`: Content domain (algebra, geometry, etc.)
- `skill`: Specific College Board skill codes
- `collegeBoardAlignment`: Official skill identifiers

### 2. IRT Difficulty Parameters
```json
"difficultyIRT": {
  "b": 0.5,
  "a": 1.2
}
```
- `b`: Difficulty (-3 to +3, higher = harder)
- `a`: Discrimination (how well it separates ability levels)

### 3. Adaptive Levels
- `module_1`: Calibration questions (critical for routing)
- `module_2_easy`: Lower difficulty second module
- `module_2_hard`: Higher difficulty second module
- `any`: Appropriate for any module

### 4. Error Analysis
Each incorrect answer includes explanation:
```json
"errorAnalysis": {
  "a": "Why students pick this wrong answer",
  "c": "Specific misconception this reveals"
}
```

### 5. Strategy Integration
Questions link to applicable strategies:
```json
"strategyTags": ["substitution", "back_solving", "elimination"]
```

### 6. Timing Targets
Per-question time targets for pacing:
```json
"timeTarget": 75  // seconds
```

## Usage

These examples demonstrate:

1. **Content Structure**: How to organize SAT content hierarchically
2. **Question Formatting**: Proper assessment structure with SAT metadata
3. **Difficulty Calibration**: Using IRT parameters for adaptive practice
4. **Strategy Linking**: Connecting content to test-taking strategies
5. **Error Analysis**: Documenting common mistakes for feedback

## Validation

Validate examples against the schema:

```bash
# From curriculum directory
python -m jsonschema -i examples/sat-prep/math-algebra-sample.json spec/umcf-schema.json
```

## Creating New Content

1. Start with the base UMCF structure
2. Add `extensions.sat` to each content node
3. Include `testVersion` and `section` (required fields)
4. Add IRT parameters for all assessments
5. Include error analysis for each distractor
6. Link applicable strategies

See `/curriculum/spec/SAT_EXTENSIONS.md` for the complete extension specification.

## Score Impact Reference

| Difficulty (b) | Approximate Score Level |
|----------------|------------------------|
| -2.0 to -1.0 | 400-500 |
| -1.0 to 0.0 | 500-550 |
| 0.0 to 0.5 | 550-600 |
| 0.5 to 1.0 | 600-650 |
| 1.0 to 1.5 | 650-700 |
| 1.5+ | 700-800 |
