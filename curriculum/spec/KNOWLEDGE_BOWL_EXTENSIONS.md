# Knowledge Bowl UMCF Extensions

This document specifies the UMCF schema extensions required to support Knowledge Bowl preparation content. These extensions build upon the base UMCF v1.1.0 specification.

## Extension Namespace

All Knowledge Bowl extensions use the `knowledgeBowl` namespace within UMCF content nodes.

```json
{
  "extensions": {
    "knowledgeBowl": {
      // Knowledge Bowl specific fields
    }
  }
}
```

## Schema Extensions

### 1. Content Node Extensions

#### knowledgeBowl Object

Added to any content node (topic, segment, assessment):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `competitionYear` | string | Yes | Academic year (e.g., "2024-2025") |
| `questionSource` | string | No | Origin of content (naqt, nsb, custom) |
| `difficultyTier` | enum | No | Competition level |
| `domain` | string | Yes | Primary subject domain |
| `category` | string | No | Subcategory within domain |
| `questionWeight` | number | No | Relative importance (0.0-1.0) |
| `speedTarget` | number | No | Target response time in seconds |
| `buzzable` | boolean | No | Whether question supports buzzing |
| `buzzPoints` | array | No | Clues that indicate buzz opportunity |
| `pyramidClues` | array | No | Progressive hint structure |
| `yearlyUpdate` | boolean | No | Content requires annual refresh |
| `retiredYear` | string | No | Year content became obsolete |

#### difficultyTier Enum

```json
{
  "enum": ["elementary", "middle_school", "jv", "varsity", "championship", "college"]
}
```

| Tier | Description | Typical Grade Level |
|------|-------------|---------------------|
| `elementary` | Basic recall questions | Grades 3-5 |
| `middle_school` | Standard middle school level | Grades 6-8 |
| `jv` | Junior varsity high school | Grades 9-10 |
| `varsity` | Standard varsity competition | Grades 11-12 |
| `championship` | State/national level difficulty | Advanced HS |
| `college` | College quiz bowl level | Undergraduate |

### 2. Assessment Extensions

#### Question Type Extensions

New assessment types for Knowledge Bowl:

##### Toss-Up Question

```json
{
  "type": "choice",
  "questionType": "toss_up",
  "knowledgeBowl": {
    "timeLimit": 10,
    "points": 10,
    "interruptible": true,
    "buzzTrigger": "key phrase that signals answer"
  }
}
```

##### Bonus Question

```json
{
  "type": "bonus",
  "knowledgeBowl": {
    "leadIn": "Introductory context for the bonus",
    "parts": [
      {
        "prompt": "Part 1 question",
        "answer": "Expected answer",
        "alternateAnswers": ["Alt 1", "Alt 2"],
        "points": 10
      }
    ],
    "totalPoints": 30,
    "conferenceTime": 5
  }
}
```

##### Pyramid Question

Progressive clue structure where earlier answers earn more points:

```json
{
  "type": "pyramid",
  "knowledgeBowl": {
    "clues": [
      {
        "text": "Most obscure clue",
        "revealPoints": 30,
        "difficulty": "expert"
      },
      {
        "text": "Moderately difficult clue",
        "revealPoints": 20,
        "difficulty": "hard"
      },
      {
        "text": "Standard difficulty clue",
        "revealPoints": 10,
        "difficulty": "medium"
      },
      {
        "text": "Giveaway clue",
        "revealPoints": 5,
        "difficulty": "easy"
      }
    ],
    "answer": "Correct answer",
    "alternateAnswers": ["Acceptable variants"],
    "pronounce": "Pronunciation guide if needed"
  }
}
```

##### Lightning Round

Rapid-fire questions in a single category:

```json
{
  "type": "lightning",
  "knowledgeBowl": {
    "category": "US Presidents",
    "timeLimit": 60,
    "questions": [
      {
        "prompt": "First president",
        "answer": "George Washington"
      },
      {
        "prompt": "16th president",
        "answer": "Abraham Lincoln"
      }
    ],
    "pointsPerCorrect": 10,
    "negativePoints": false
  }
}
```

### 3. Domain Classification

#### Domain Taxonomy

Standard domain identifiers for Knowledge Bowl content:

```json
{
  "domains": {
    "science": {
      "categories": ["biology", "chemistry", "physics", "earth_science", "astronomy", "computer_science"]
    },
    "mathematics": {
      "categories": ["arithmetic", "algebra", "geometry", "trigonometry", "calculus", "statistics"]
    },
    "literature": {
      "categories": ["american", "british", "world", "poetry", "drama", "mythology"]
    },
    "history": {
      "categories": ["us_history", "world_history", "ancient", "medieval", "modern", "military"]
    },
    "social_studies": {
      "categories": ["geography", "government", "economics", "sociology", "psychology", "anthropology"]
    },
    "fine_arts": {
      "categories": ["visual_arts", "music", "theater", "dance", "architecture", "film"]
    },
    "current_events": {
      "categories": ["politics", "science_news", "culture", "sports", "technology", "business"]
    },
    "language": {
      "categories": ["grammar", "vocabulary", "etymology", "foreign_language", "linguistics"]
    },
    "religion_philosophy": {
      "categories": ["world_religions", "philosophy", "ethics", "mythology"]
    },
    "pop_culture": {
      "categories": ["entertainment", "media", "sports_culture", "games", "internet"]
    },
    "technology": {
      "categories": ["inventions", "engineering", "computing", "space_exploration"]
    },
    "miscellaneous": {
      "categories": ["general_trivia", "cross_domain", "puzzles", "wordplay"]
    }
  }
}
```

### 4. Performance Tracking Extensions

#### Speed Metrics

```json
{
  "speedMetrics": {
    "targetResponseTime": 3.0,
    "currentAverageTime": 4.2,
    "bestTime": 1.8,
    "timeDistribution": {
      "under2s": 0.15,
      "2to4s": 0.45,
      "4to6s": 0.30,
      "over6s": 0.10
    }
  }
}
```

#### Buzz Analytics

```json
{
  "buzzAnalytics": {
    "earlyBuzzes": 12,
    "optimalBuzzes": 45,
    "lateBuzzes": 23,
    "negs": 5,
    "buzzAccuracy": 0.85,
    "averageBuzzPoint": 0.65
  }
}
```

### 5. Competition Configuration

#### Competition Rules

```json
{
  "competitionConfig": {
    "organization": "naqt",
    "format": "high_school",
    "year": "2024-2025",
    "rules": {
      "tossupPoints": 10,
      "bonusParts": 3,
      "bonusPointsPerPart": 10,
      "negativePoints": -5,
      "powersEnabled": true,
      "powerPoints": 15,
      "powerWindow": 0.5
    },
    "rounds": {
      "written": {
        "questions": 60,
        "timeLimit": 900
      },
      "oral": {
        "tossups": 20,
        "bonuses": 20
      }
    }
  }
}
```

### 6. Content Freshness

#### Update Tracking

```json
{
  "freshness": {
    "contentType": "current_events",
    "sourceDate": "2024-01-15",
    "expirationDate": "2024-04-15",
    "updateFrequency": "weekly",
    "lastVerified": "2024-01-20",
    "verificationSource": "Associated Press",
    "autoRetire": true
  }
}
```

### 7. Study Session Configuration

#### Session Templates

```json
{
  "sessionTemplates": {
    "diagnostic": {
      "type": "diagnostic",
      "duration": 3600,
      "questionsPerDomain": 5,
      "difficultyMix": {
        "easy": 0.3,
        "medium": 0.5,
        "hard": 0.2
      },
      "timedResponses": false
    },
    "targeted_remediation": {
      "type": "remediation",
      "duration": 1800,
      "focusDomains": 3,
      "adaptiveDifficulty": true,
      "includeExplanations": true
    },
    "speed_drill": {
      "type": "speed",
      "duration": 900,
      "questionCount": 30,
      "progressiveTimeReduction": true,
      "startingTime": 10,
      "minimumTime": 3
    },
    "competition_simulation": {
      "type": "simulation",
      "format": "naqt_standard",
      "rounds": ["written", "oral"],
      "aiOpponent": true,
      "opponentDifficulty": "varsity"
    }
  }
}
```

## JSON Schema Fragment

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "knowledgeBowlExtension": {
      "type": "object",
      "properties": {
        "competitionYear": {
          "type": "string",
          "pattern": "^\\d{4}-\\d{4}$",
          "description": "Academic competition year"
        },
        "questionSource": {
          "type": "string",
          "enum": ["naqt", "nsb", "qb_packets", "custom", "ai_generated"],
          "description": "Origin of the question content"
        },
        "difficultyTier": {
          "type": "string",
          "enum": ["elementary", "middle_school", "jv", "varsity", "championship", "college"],
          "description": "Competition difficulty level"
        },
        "domain": {
          "type": "string",
          "enum": ["science", "mathematics", "literature", "history", "social_studies", "fine_arts", "current_events", "language", "religion_philosophy", "pop_culture", "technology", "miscellaneous"],
          "description": "Primary subject domain"
        },
        "category": {
          "type": "string",
          "description": "Subcategory within domain"
        },
        "questionWeight": {
          "type": "number",
          "minimum": 0,
          "maximum": 1,
          "description": "Relative importance in competition"
        },
        "speedTarget": {
          "type": "number",
          "minimum": 0,
          "description": "Target response time in seconds"
        },
        "buzzable": {
          "type": "boolean",
          "default": true,
          "description": "Whether question supports mid-read buzzing"
        },
        "buzzPoints": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Phrases that indicate good buzz opportunity"
        },
        "pyramidClues": {
          "type": "array",
          "items": {
            "$ref": "#/definitions/pyramidClue"
          },
          "description": "Progressive clue structure"
        },
        "yearlyUpdate": {
          "type": "boolean",
          "default": false,
          "description": "Content requires annual refresh"
        },
        "retiredYear": {
          "type": "string",
          "pattern": "^\\d{4}$",
          "description": "Year content became obsolete"
        }
      },
      "required": ["competitionYear", "domain"]
    },
    "pyramidClue": {
      "type": "object",
      "properties": {
        "text": {
          "type": "string",
          "description": "Clue text"
        },
        "revealPoints": {
          "type": "integer",
          "description": "Points awarded if answered at this clue"
        },
        "difficulty": {
          "type": "string",
          "enum": ["expert", "hard", "medium", "easy", "giveaway"]
        }
      },
      "required": ["text", "revealPoints"]
    },
    "bonusPart": {
      "type": "object",
      "properties": {
        "prompt": {
          "type": "string",
          "description": "Question prompt"
        },
        "answer": {
          "type": "string",
          "description": "Expected answer"
        },
        "alternateAnswers": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Acceptable alternate answers"
        },
        "points": {
          "type": "integer",
          "default": 10,
          "description": "Points for correct answer"
        }
      },
      "required": ["prompt", "answer"]
    },
    "speedMetrics": {
      "type": "object",
      "properties": {
        "targetResponseTime": {
          "type": "number",
          "description": "Target time in seconds"
        },
        "currentAverageTime": {
          "type": "number",
          "description": "Current average response time"
        },
        "bestTime": {
          "type": "number",
          "description": "Fastest recorded response"
        },
        "timeDistribution": {
          "type": "object",
          "additionalProperties": {
            "type": "number"
          },
          "description": "Distribution of response times"
        }
      }
    },
    "buzzAnalytics": {
      "type": "object",
      "properties": {
        "earlyBuzzes": {
          "type": "integer",
          "description": "Buzzes before optimal point"
        },
        "optimalBuzzes": {
          "type": "integer",
          "description": "Buzzes at optimal timing"
        },
        "lateBuzzes": {
          "type": "integer",
          "description": "Buzzes after optimal point"
        },
        "negs": {
          "type": "integer",
          "description": "Incorrect early buzzes"
        },
        "buzzAccuracy": {
          "type": "number",
          "minimum": 0,
          "maximum": 1,
          "description": "Accuracy when buzzing"
        },
        "averageBuzzPoint": {
          "type": "number",
          "minimum": 0,
          "maximum": 1,
          "description": "Average point in question when buzzing"
        }
      }
    }
  }
}
```

## Validation Rules

### Required Fields

1. All Knowledge Bowl content nodes MUST include `competitionYear`
2. All content nodes MUST include `domain`
3. All assessment items MUST include `timeLimit` in the knowledgeBowl extension
4. Pyramid questions MUST include at least 3 clues
5. Bonus questions MUST include at least 2 parts

### Content Freshness Rules

1. Current events content MUST have `expirationDate` set
2. Content with `yearlyUpdate: true` MUST be reviewed each competition year
3. Retired content MUST have `retiredYear` set and MUST NOT appear in active study sessions

### Competition Accuracy Rules

1. Point values MUST match the specified competition organization's rules
2. Time limits MUST be realistic for the competition format
3. Domain weights SHOULD reflect actual competition distribution

## Migration from Base UMCF

Existing UMCF content can be extended for Knowledge Bowl by adding the `knowledgeBowl` namespace:

```json
// Before (base UMCF)
{
  "id": "physics-001",
  "nodeType": "segment",
  "title": "Newton's Laws"
}

// After (with Knowledge Bowl extensions)
{
  "id": "physics-001",
  "nodeType": "segment",
  "title": "Newton's Laws",
  "extensions": {
    "knowledgeBowl": {
      "competitionYear": "2024-2025",
      "domain": "science",
      "category": "physics",
      "difficultyTier": "varsity",
      "speedTarget": 4.0
    }
  }
}
```

## Versioning

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | January 2025 | Initial Knowledge Bowl extensions |

---

*This specification extends UMCF v1.1.0 and should be read in conjunction with the base UMCF Specification.*
