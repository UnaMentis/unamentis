# SAT Preparation UMCF Extensions

This document specifies the UMCF schema extensions required to support SAT preparation content. These extensions build upon the base UMCF v1.1.0 specification and support the Digital SAT format (2024+).

## Extension Namespace

All SAT extensions use the `sat` namespace within UMCF content nodes.

```json
{
  "extensions": {
    "sat": {
      // SAT-specific fields
    }
  }
}
```

## Schema Extensions

### 1. Content Node Extensions

#### sat Object

Added to any content node (topic, segment, assessment):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `testVersion` | string | Yes | SAT version (e.g., "digital-2024") |
| `section` | enum | Yes | Test section |
| `domain` | string | Yes | Content domain within section |
| `skill` | string | No | Specific skill identifier |
| `difficultyIRT` | object | No | Item Response Theory parameters |
| `difficultyRange` | object | No | Min/max difficulty for content |
| `timeTarget` | number | No | Target completion time in seconds |
| `weight` | number | No | Relative importance (0.0-1.0) |
| `strategyTags` | array | No | Applicable strategies |
| `commonErrors` | array | No | Frequent mistake patterns |
| `adaptiveLevel` | enum | No | Module 1 or Module 2 appropriateness |
| `passageType` | enum | No | For RW questions |
| `collegeBoardAlignment` | string | No | Official skill code |

#### section Enum

```json
{
  "enum": ["reading_writing", "math"]
}
```

#### adaptiveLevel Enum

```json
{
  "enum": ["module_1", "module_2_easy", "module_2_hard", "any"]
}
```

| Level | Description | Score Impact |
|-------|-------------|--------------|
| `module_1` | Calibration questions | High (determines path) |
| `module_2_easy` | Lower difficulty second module | Lower ceiling |
| `module_2_hard` | Higher difficulty second module | Higher ceiling |
| `any` | Appropriate for any module | Variable |

#### passageType Enum (Reading/Writing)

```json
{
  "enum": ["literature", "history_social_science", "science", "humanities"]
}
```

### 2. Content Domain Taxonomy

#### Reading and Writing Domains

```json
{
  "readingWritingDomains": {
    "craft_and_structure": {
      "skills": [
        "words_in_context",
        "text_structure_purpose",
        "cross_text_connections"
      ],
      "weight": 0.28
    },
    "information_and_ideas": {
      "skills": [
        "central_ideas_details",
        "command_of_evidence_textual",
        "command_of_evidence_quantitative",
        "inferences"
      ],
      "weight": 0.26
    },
    "standard_english_conventions": {
      "skills": [
        "boundaries",
        "form_structure_sense"
      ],
      "weight": 0.26
    },
    "expression_of_ideas": {
      "skills": [
        "rhetorical_synthesis",
        "transitions"
      ],
      "weight": 0.20
    }
  }
}
```

#### Math Domains

```json
{
  "mathDomains": {
    "algebra": {
      "skills": [
        "linear_equations_one_variable",
        "linear_equations_two_variables",
        "linear_functions",
        "systems_linear_equations",
        "linear_inequalities"
      ],
      "weight": 0.35
    },
    "advanced_math": {
      "skills": [
        "equivalent_expressions",
        "nonlinear_equations_one_variable",
        "systems_equations_two_variables",
        "nonlinear_functions"
      ],
      "weight": 0.35
    },
    "problem_solving_data": {
      "skills": [
        "ratios_rates_proportions",
        "percentages",
        "one_variable_data",
        "two_variable_data",
        "probability_conditional",
        "inference_sample_statistics",
        "margin_of_error",
        "evaluating_statistical_claims"
      ],
      "weight": 0.15
    },
    "geometry_trig": {
      "skills": [
        "area_volume",
        "lines_angles_triangles",
        "right_triangles_trig",
        "circles"
      ],
      "weight": 0.15
    }
  }
}
```

### 3. Item Response Theory (IRT) Parameters

The Digital SAT uses IRT for scoring. Questions include these parameters:

```json
{
  "difficultyIRT": {
    "b": 0.5,
    "a": 1.2,
    "c": 0.0
  }
}
```

| Parameter | Name | Range | Description |
|-----------|------|-------|-------------|
| `b` | Difficulty | -3.0 to +3.0 | Higher = harder |
| `a` | Discrimination | 0.5 to 2.5 | Higher = better differentiator |
| `c` | Guessing | 0.0 to 0.25 | Probability of correct guess |

#### Difficulty Scale Interpretation

| b Value | Difficulty | Approximate Score Range |
|---------|------------|------------------------|
| -2.0 to -1.0 | Easy | 400-500 |
| -1.0 to 0.0 | Below Average | 500-550 |
| 0.0 to 0.5 | Average | 550-600 |
| 0.5 to 1.0 | Above Average | 600-650 |
| 1.0 to 1.5 | Hard | 650-700 |
| 1.5 to 2.5 | Very Hard | 700-800 |

### 4. Assessment Extensions

#### SAT Question Format

```json
{
  "id": "sat-rw-craft-001",
  "type": "choice",
  "stem": "As used in the passage, 'acute' most nearly means",
  "passage": {
    "text": "The scientist made several acute observations...",
    "source": "Adapted from a research article",
    "wordCount": 85
  },
  "options": [
    { "id": "a", "text": "sharp", "correct": true },
    { "id": "b", "text": "severe" },
    { "id": "c", "text": "sudden" },
    { "id": "d", "text": "angular" }
  ],
  "extensions": {
    "sat": {
      "testVersion": "digital-2024",
      "section": "reading_writing",
      "domain": "craft_and_structure",
      "skill": "words_in_context",
      "difficultyIRT": { "b": -0.5, "a": 1.1 },
      "timeTarget": 45,
      "adaptiveLevel": "module_1",
      "passageType": "science",
      "strategyTags": ["context_clues", "substitution"],
      "errorAnalysis": {
        "b": "Common meaning but doesn't fit context",
        "c": "Related to medical 'acute' meaning",
        "d": "Geometric meaning of acute"
      }
    }
  }
}
```

#### Math Question with Grid-In

```json
{
  "id": "sat-math-algebra-grid-001",
  "type": "numeric_entry",
  "stem": "If 3x + 12 = 27, what is the value of x?",
  "correctAnswer": 5,
  "acceptableRange": null,
  "extensions": {
    "sat": {
      "testVersion": "digital-2024",
      "section": "math",
      "domain": "algebra",
      "skill": "linear_equations_one_variable",
      "difficultyIRT": { "b": -1.2, "a": 0.9 },
      "timeTarget": 35,
      "adaptiveLevel": "module_1",
      "strategyTags": ["isolation"],
      "calculatorRecommended": false,
      "commonErrors": ["forgot_to_subtract", "wrong_division"]
    }
  }
}
```

### 5. Strategy Content Extensions

```json
{
  "id": "strategy-poe-001",
  "nodeType": "segment",
  "title": "Process of Elimination",
  "extensions": {
    "sat": {
      "strategyType": "general",
      "applicableSections": ["reading_writing", "math"],
      "applicableQuestionTypes": ["choice"],
      "expectedImpact": {
        "accuracyIncrease": 0.15,
        "timeIncrease": 5
      },
      "prerequisiteStrategies": [],
      "practiceQuestionCount": 20
    }
  },
  "content": {
    "steps": [
      "Read the question and understand what's being asked",
      "Predict an answer before looking at choices",
      "Eliminate obviously wrong answers",
      "Compare remaining choices",
      "Select the best answer"
    ],
    "whenToUse": [
      "When unsure of the answer",
      "When multiple answers seem possible",
      "Always as a verification step"
    ],
    "commonMistakes": [
      "Eliminating correct answer too quickly",
      "Not reading all options",
      "Spending too long on elimination"
    ]
  }
}
```

### 6. Psychology/Mindset Extensions

```json
{
  "id": "psychology-anxiety-001",
  "nodeType": "segment",
  "title": "Managing Test Anxiety",
  "extensions": {
    "sat": {
      "psychologyType": "anxiety_management",
      "targetSymptoms": ["racing_thoughts", "physical_tension", "time_panic"],
      "techniques": ["breathing", "grounding", "reframing"],
      "practiceSchedule": "daily",
      "assessmentMethod": "self_report"
    }
  },
  "content": {
    "techniques": [
      {
        "name": "Box Breathing",
        "steps": ["Inhale 4 counts", "Hold 4 counts", "Exhale 4 counts", "Hold 4 counts"],
        "when": "Before test, between sections, during hard questions"
      }
    ]
  }
}
```

### 7. Timing and Pacing Extensions

```json
{
  "pacingProfile": {
    "section": "reading_writing",
    "moduleTime": 1920,
    "questionCount": 27,
    "baseTimePerQuestion": 71,
    "adjustments": {
      "words_in_context": -25,
      "central_ideas": 15,
      "rhetorical_synthesis": 30,
      "boundaries": -20
    },
    "timeBankingStrategy": {
      "quickQuestionTarget": 40,
      "savedSecondsGoal": 120,
      "allocationToHard": 0.8
    }
  }
}
```

### 8. Score Tracking Extensions

```json
{
  "scoreTracking": {
    "practiceTestId": "pt-001",
    "date": "2024-01-15",
    "rawScores": {
      "readingWriting": 42,
      "math": 38
    },
    "scaledScores": {
      "readingWriting": 680,
      "math": 720
    },
    "totalScore": 1400,
    "moduleData": {
      "rw_module1": { "correct": 22, "total": 27, "avgTime": 65 },
      "rw_module2": { "difficulty": "hard", "correct": 20, "total": 27, "avgTime": 72 },
      "math_module1": { "correct": 19, "total": 22, "avgTime": 88 },
      "math_module2": { "difficulty": "hard", "correct": 19, "total": 22, "avgTime": 95 }
    },
    "skillBreakdown": {
      "algebra": { "correct": 14, "total": 16 },
      "geometry_trig": { "correct": 5, "total": 6 }
    },
    "errorAnalysis": [
      {
        "questionId": "q-123",
        "skill": "quadratics",
        "errorType": "sign_error",
        "timeSpent": 145
      }
    ]
  }
}
```

### 9. Study Plan Extensions

```json
{
  "studyPlan": {
    "studentId": "student_123",
    "targetScore": 1500,
    "currentScore": 1320,
    "testDate": "2024-06-15",
    "weeksRemaining": 12,
    "weeklyHours": 8,
    "phases": [
      {
        "name": "Foundation",
        "weeks": [1, 2, 3, 4],
        "focus": ["algebra", "reading_comprehension"],
        "hoursPerWeek": 8,
        "milestones": ["Complete algebra review", "POE mastery"]
      },
      {
        "name": "Strategy Integration",
        "weeks": [5, 6, 7, 8],
        "focus": ["timing", "advanced_math", "evidence_questions"],
        "hoursPerWeek": 10,
        "milestones": ["Consistent pacing", "Practice test 1400+"]
      },
      {
        "name": "Peak Performance",
        "weeks": [9, 10, 11, 12],
        "focus": ["hard_questions", "psychology", "full_tests"],
        "hoursPerWeek": 8,
        "milestones": ["Score stability", "Anxiety management"]
      }
    ],
    "dailySchedule": {
      "weekday": { "content": 30, "practice": 30, "review": 15 },
      "weekend": { "practice_test": 150, "review": 60 }
    }
  }
}
```

## JSON Schema Fragment

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "satExtension": {
      "type": "object",
      "properties": {
        "testVersion": {
          "type": "string",
          "pattern": "^digital-\\d{4}$",
          "description": "SAT test version"
        },
        "section": {
          "type": "string",
          "enum": ["reading_writing", "math"],
          "description": "Test section"
        },
        "domain": {
          "type": "string",
          "description": "Content domain"
        },
        "skill": {
          "type": "string",
          "description": "Specific skill identifier"
        },
        "difficultyIRT": {
          "$ref": "#/definitions/irtParameters"
        },
        "difficultyRange": {
          "type": "object",
          "properties": {
            "min": { "type": "number" },
            "max": { "type": "number" }
          }
        },
        "timeTarget": {
          "type": "number",
          "minimum": 0,
          "description": "Target time in seconds"
        },
        "weight": {
          "type": "number",
          "minimum": 0,
          "maximum": 1,
          "description": "Relative importance"
        },
        "strategyTags": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Applicable strategies"
        },
        "commonErrors": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Common mistake patterns"
        },
        "adaptiveLevel": {
          "type": "string",
          "enum": ["module_1", "module_2_easy", "module_2_hard", "any"]
        },
        "passageType": {
          "type": "string",
          "enum": ["literature", "history_social_science", "science", "humanities"]
        },
        "collegeBoardAlignment": {
          "type": "string",
          "description": "Official College Board skill code"
        },
        "calculatorRecommended": {
          "type": "boolean",
          "default": true
        },
        "errorAnalysis": {
          "type": "object",
          "additionalProperties": { "type": "string" },
          "description": "Explanation for each wrong answer"
        }
      },
      "required": ["testVersion", "section"]
    },
    "irtParameters": {
      "type": "object",
      "properties": {
        "b": {
          "type": "number",
          "minimum": -3,
          "maximum": 3,
          "description": "Difficulty parameter"
        },
        "a": {
          "type": "number",
          "minimum": 0,
          "maximum": 3,
          "description": "Discrimination parameter"
        },
        "c": {
          "type": "number",
          "minimum": 0,
          "maximum": 0.5,
          "default": 0,
          "description": "Guessing parameter"
        }
      }
    },
    "satPassage": {
      "type": "object",
      "properties": {
        "text": {
          "type": "string",
          "description": "Passage text"
        },
        "source": {
          "type": "string",
          "description": "Attribution"
        },
        "wordCount": {
          "type": "integer",
          "minimum": 25,
          "maximum": 150
        },
        "type": {
          "$ref": "#/definitions/passageType"
        }
      },
      "required": ["text"]
    },
    "strategyContent": {
      "type": "object",
      "properties": {
        "strategyType": {
          "type": "string",
          "enum": ["general", "reading_writing", "math", "timing", "psychology"]
        },
        "applicableSections": {
          "type": "array",
          "items": { "type": "string" }
        },
        "applicableQuestionTypes": {
          "type": "array",
          "items": { "type": "string" }
        },
        "expectedImpact": {
          "type": "object",
          "properties": {
            "accuracyIncrease": { "type": "number" },
            "timeIncrease": { "type": "number" }
          }
        },
        "prerequisiteStrategies": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "psychologyContent": {
      "type": "object",
      "properties": {
        "psychologyType": {
          "type": "string",
          "enum": ["anxiety_management", "focus_training", "confidence_building", "mistake_recovery"]
        },
        "targetSymptoms": {
          "type": "array",
          "items": { "type": "string" }
        },
        "techniques": {
          "type": "array",
          "items": { "type": "string" }
        },
        "practiceSchedule": {
          "type": "string",
          "enum": ["daily", "weekly", "before_tests"]
        }
      }
    }
  }
}
```

## Validation Rules

### Required Fields

1. All SAT content nodes MUST include `testVersion` and `section`
2. Assessment items MUST include `difficultyIRT` with at least `b` parameter
3. Reading/Writing questions with passages MUST include `passageType`
4. All timed assessments MUST include `timeTarget`

### Content Quality Rules

1. Passage word counts MUST be 25-150 words (Digital SAT format)
2. Answer choices MUST have exactly 4 options (A, B, C, D)
3. `errorAnalysis` SHOULD explain why each distractor is wrong
4. `strategyTags` SHOULD be consistent with strategy curriculum

### Adaptive Level Rules

1. Module 1 questions should span the full difficulty range
2. Module 2 Easy questions should have `b` < 0.5
3. Module 2 Hard questions should have `b` > 0.5
4. Practice tests MUST include proper adaptive routing logic

### Timing Rules

1. `timeTarget` should be realistic for the question type
2. Total module time targets should not exceed section limits
3. Pacing profiles should account for all question types

## Migration from Base UMCF

Existing UMCF content can be extended for SAT by adding the `sat` namespace:

```json
// Before (base UMCF)
{
  "id": "algebra-linear-001",
  "nodeType": "segment",
  "title": "Linear Equations"
}

// After (with SAT extensions)
{
  "id": "algebra-linear-001",
  "nodeType": "segment",
  "title": "Linear Equations",
  "extensions": {
    "sat": {
      "testVersion": "digital-2024",
      "section": "math",
      "domain": "algebra",
      "skill": "linear_equations_one_variable",
      "weight": 0.08,
      "collegeBoardAlignment": "PAM.A.1"
    }
  }
}
```

## Score Conversion Reference

### Reading and Writing

| Raw Score | Scaled Score (Approx) |
|-----------|----------------------|
| 54 | 800 |
| 50 | 750 |
| 45 | 700 |
| 40 | 650 |
| 35 | 600 |
| 30 | 550 |
| 25 | 500 |
| 20 | 450 |

### Math

| Raw Score | Scaled Score (Approx) |
|-----------|----------------------|
| 44 | 800 |
| 40 | 750 |
| 36 | 700 |
| 32 | 650 |
| 28 | 600 |
| 24 | 550 |
| 20 | 500 |
| 16 | 450 |

Note: Actual conversion varies by test form.

## Versioning

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | January 2025 | Initial SAT extensions for Digital SAT 2024 |

---

*This specification extends UMCF v1.1.0 and should be read in conjunction with the base UMCF Specification.*
