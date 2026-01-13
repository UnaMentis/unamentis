# UMCF Curriculum Generation Prompt

This document provides a comprehensive prompt for guiding AI models to generate high-quality, fully-compliant UMCF (UnaMentis Curriculum Format) curriculum files.

## How to Use This Prompt

### Step-by-Step Instructions

1. **Copy the entire prompt** from the [Complete Prompt](#complete-prompt) section below
2. **Add your curriculum specification** before the prompt, describing:
   - The subject/topic you want to cover
   - Target audience (age, education level, prerequisites)
   - Desired depth and scope
   - Any specific standards to align with
   - Special requirements (compliance, certification, etc.)
3. **Submit to your AI model** (Claude, GPT-4, etc.)
4. **Review the output** for accuracy and completeness
5. **Validate the JSON** using a JSON validator
6. **Save with `.umcf` extension**

### Example Usage

Here's how to structure your request:

```
Create a UMCF curriculum for:

TOPIC: Introduction to Machine Learning
AUDIENCE: College undergraduates with Python programming experience
SCOPE: 8-week course covering fundamentals through practical applications
DEPTH: Intermediate level
STANDARDS: Align with ACM Computing Curricula 2020
SPECIAL REQUIREMENTS: Include code examples in Python, emphasize hands-on projects

[PASTE THE COMPLETE PROMPT HERE]
```

### Tips for Best Results

1. **Be specific about scope**: "3 modules covering X, Y, Z" is better than "comprehensive course"
2. **Specify time constraints**: "Each lesson should be 30-45 minutes" helps calibrate content density
3. **Name prerequisites explicitly**: "Requires knowledge of calculus and linear algebra"
4. **Request specific features**: "Include Socratic checkpoints after each major concept"
5. **Provide example content** if you have specific topics or examples to include

### Output Expectations

The AI will generate:
- A complete, valid JSON file in UMCF format
- Hierarchical content structure (curriculum > units > modules > topics > subtopics)
- Learning objectives with Bloom's taxonomy levels
- Full transcripts with speaking notes for voice delivery
- Checkpoints for comprehension verification
- Assessments aligned to objectives
- Glossary terms with pronunciations
- Examples and misconceptions
- Media placeholders where visual aids would help

### Post-Generation Checklist

After receiving the output:

- [ ] Validate JSON syntax (use `python -m json.tool < output.umcf`)
- [ ] Verify all required fields are present
- [ ] Check that `formatIdentifier` equals `"umcf"`
- [ ] Confirm learning objectives align with content
- [ ] Review transcripts for voice-appropriate language
- [ ] Verify pronunciation guides for technical terms
- [ ] Check that assessments match stated objectives
- [ ] Review misconceptions for accuracy
- [ ] Ensure media placeholders have proper alt text

---

## Complete Prompt

Copy everything below this line:

---

**CRITICAL OUTPUT REQUIREMENT**: Your response must be ONLY valid JSON. No markdown, no explanations, no code fences. Start with `{` and end with `}`. The output will be saved directly as a `.umcf` file.

---

You are an expert curriculum designer specializing in voice-native educational content. Your task is to create a complete, production-ready curriculum in UMCF (UnaMentis Curriculum Format) v1.1.0 based on the user's specification provided above this prompt.

## Your Task

Read the curriculum specification the user provided (topic, audience, scope, etc.) and generate a complete UMCF document that:
1. Covers all topics the user specified
2. Targets the audience level they described
3. Matches the scope and depth they requested
4. Includes any special requirements they mentioned

## Handling Source Material

Users may provide varied inputs: topic descriptions, pasted text, documents, URLs, or partial outlines. Your job is to transform whatever they provide into valid UMCF that enables effective tutoring.

**Guiding Principle**: The UMCF format is your north star. Every decision serves one goal: creating content that successfully teaches the learner.

**When the source material is ambiguous or incomplete:**

1. **Fit it to UMCF**: If content could go in multiple places, choose the structure that best supports learning progression. A concept that could be a topic or subtopic? Pick based on complexity and time needed.

2. **Fill gaps pedagogically**: If the source lacks examples, assessments, or checkpoints, generate appropriate ones. The format requires them; the learner needs them.

3. **Flag what you cannot infer**: If critical information is missing (target audience, prerequisites, scope), state your assumptions clearly in the `description` field: "Assuming undergraduate-level audience based on content complexity."

4. **Decline gracefully**: If the source material is truly unsuitable (no teachable content, just metadata, or completely off-topic), output a minimal valid UMCF with a description explaining why full curriculum generation isn't possible and what the user should provide instead.

**Do not ask clarifying questions in your output.** Make reasonable decisions, document assumptions, and produce valid UMCF. The user can iterate.

## UMCF Format Requirements

UMCF is a JSON-based curriculum format designed specifically for conversational AI tutoring. It supports:
- Voice-first learning with pronunciation guides and speaking notes
- Unlimited hierarchical depth (curriculum > unit > module > topic > subtopic > lesson > section > segment)
- Checkpoints for comprehension verification
- Spaced retrieval for long-term retention
- Misconception detection and remediation
- Standards traceability to educational frameworks

## Required Document Structure

Your output MUST be valid JSON with this top-level structure:

```json
{
  "formatIdentifier": "umcf",
  "schemaVersion": "1.1.0",
  "id": {
    "catalog": "UUID",
    "value": "<generate-unique-uuid>"
  },
  "title": "<curriculum-title>",
  "description": "<comprehensive-description>",
  "version": {
    "number": "1.0.0",
    "date": "<current-iso-datetime>",
    "changelog": "Initial release"
  },
  "lifecycle": {
    "status": "draft",
    "contributors": [...],
    "created": "<current-iso-datetime>",
    "modified": "<current-iso-datetime>"
  },
  "metadata": {
    "language": "en",
    "keywords": [...],
    "structureType": "hierarchical",
    "aggregationLevel": 4
  },
  "educational": {...},
  "rights": {...},
  "sourceProvenance": {...},
  "content": [...],
  "glossary": {...}
}
```

## Content Node Structure

Every content node MUST include:

```json
{
  "id": { "catalog": "internal", "value": "<unique-id>" },
  "title": "<node-title>",
  "type": "<curriculum|unit|module|topic|subtopic|lesson|section|segment>",
  "orderIndex": <integer>,
  "description": "<node-description>",
  "learningObjectives": [...],
  "timeEstimates": {...},
  "children": [...]
}
```

## Learning Objectives Format

Each learning objective MUST follow this structure:

```json
{
  "id": { "catalog": "internal", "value": "obj-<unique>" },
  "statement": "<full-objective-statement>",
  "abbreviatedStatement": "<short-version>",
  "bloomsLevel": "<remember|understand|apply|analyze|evaluate|create>",
  "verificationCriteria": "<how-to-verify-mastery>",
  "assessmentIds": ["<linked-assessment-ids>"]
}
```

## Transcript Format (CRITICAL for Voice)

For leaf nodes (topics/subtopics that contain actual teaching content), include a complete transcript:

```json
{
  "transcript": {
    "segments": [
      {
        "id": "seg-<unique>",
        "type": "<introduction|lecture|explanation|example|checkpoint|transition|summary|conclusion>",
        "content": "<what-the-tutor-says>",
        "speakingNotes": {
          "pace": "<slow|normal|fast>",
          "emphasis": ["<words-to-emphasize>"],
          "pauseAfter": <true|false>,
          "pauseDuration": <seconds>,
          "emotionalTone": "<neutral|encouraging|serious|curious|excited>"
        },
        "glossaryRefs": ["<term-ids-mentioned>"]
      }
    ],
    "totalDuration": "<ISO-8601-duration>",
    "pronunciationGuide": {
      "<term>": {
        "ipa": "<IPA-pronunciation>",
        "respelling": "<phonetic-respelling>",
        "language": "<language-code>"
      }
    },
    "voiceProfile": {
      "tone": "conversational",
      "pace": "moderate"
    }
  }
}
```

## Concrete Example: A Complete Topic

Here is a filled-in example of a single topic to show expected output quality:

```json
{
  "id": { "catalog": "internal", "value": "topic-variables" },
  "title": "Understanding Variables",
  "type": "topic",
  "orderIndex": 0,
  "description": "Learn what variables are and how to use them to store information",
  "learningObjectives": [
    {
      "id": { "catalog": "internal", "value": "obj-var-1" },
      "statement": "Define what a variable is and explain its purpose in programming",
      "abbreviatedStatement": "Define variables",
      "bloomsLevel": "understand",
      "verificationCriteria": "Student can explain variables using an analogy",
      "assessmentIds": ["q-var-1"]
    }
  ],
  "timeEstimates": {
    "introductory": "PT10M"
  },
  "transcript": {
    "segments": [
      {
        "id": "seg-var-intro",
        "type": "introduction",
        "content": "Today we're going to learn about variables. Think of a variable like a labeled box where you can store things. You give the box a name, and then you can put something inside it, take it out, or swap it for something else.",
        "speakingNotes": {
          "pace": "slow",
          "emphasis": ["labeled box", "store things"],
          "pauseAfter": true,
          "pauseDuration": 2,
          "emotionalTone": "encouraging"
        },
        "glossaryRefs": ["term-variable"]
      },
      {
        "id": "seg-var-check",
        "type": "checkpoint",
        "content": "So if I said a variable is like a labeled box, can you think of what the label represents?",
        "checkpoint": {
          "type": "comprehension_check",
          "prompt": "What does the label on our box represent?",
          "expectedResponsePatterns": ["name", "identifier", "what we call it"],
          "transitions": {
            "understood": {
              "nextSegment": "seg-var-example",
              "feedbackText": "Exactly! The label is the variable's name."
            },
            "confused": {
              "nextSegment": "seg-var-clarify",
              "feedbackText": "Let me explain that differently."
            }
          },
          "fallbackBehavior": "escalate_to_llm"
        }
      }
    ],
    "totalDuration": "PT10M",
    "pronunciationGuide": {
      "variable": {
        "ipa": "/ˈvɛəriəbl/",
        "respelling": "VAIR-ee-uh-bul"
      }
    },
    "voiceProfile": {
      "tone": "conversational",
      "pace": "moderate"
    }
  },
  "assessments": [
    {
      "id": { "catalog": "internal", "value": "q-var-1" },
      "type": "choice",
      "title": "Variable Purpose",
      "prompt": "What is the main purpose of a variable?",
      "spokenPrompt": "What is the main purpose of a variable in programming?",
      "choices": [
        { "id": "a", "text": "To store and retrieve data", "correct": true, "feedback": "Correct! Variables hold data so you can use it later." },
        { "id": "b", "text": "To make the code run faster", "correct": false, "feedback": "Variables don't affect speed directly." },
        { "id": "c", "text": "To add colors to the screen", "correct": false, "feedback": "That's not what variables do." }
      ],
      "difficulty": 0.2,
      "objectivesAssessed": ["obj-var-1"]
    }
  ],
  "misconceptions": [
    {
      "id": "misc-var-1",
      "misconception": "Variables can only hold numbers",
      "triggerPhrases": ["only numbers", "just for math"],
      "correction": "Variables can hold many types of data including text, numbers, and more complex information.",
      "spokenCorrection": "Actually, variables can hold lots of different things, not just numbers. They can store text, true or false values, and even collections of items.",
      "severity": "moderate"
    }
  ],
  "glossaryTerms": [
    {
      "id": "term-variable",
      "term": "variable",
      "pronunciation": "/ˈvɛəriəbl/",
      "definition": "A named storage location in a program that holds a value which can be changed during execution",
      "spokenDefinition": "A variable is like a labeled container in your program where you store information that you can change later",
      "simpleDefinition": "A named box that holds information"
    }
  ]
}
```

This example shows the level of detail expected: conversational transcript, speaking notes, checkpoints, aligned assessments, and glossary integration.

## Checkpoint Format

Insert checkpoints after major concepts to verify understanding:

```json
{
  "checkpoint": {
    "type": "<simple_confirmation|comprehension_check|knowledge_check|application_check|teachback>",
    "prompt": "<question-for-learner>",
    "expectedResponsePatterns": ["<keywords-indicating-understanding>"],
    "transitions": {
      "understood": {
        "nextSegment": "<segment-id>",
        "feedbackText": "<positive-feedback>"
      },
      "confused": {
        "nextSegment": "<review-segment-id>",
        "feedbackText": "<supportive-feedback>"
      }
    },
    "fallbackBehavior": "escalate_to_llm"
  }
}
```

For teachback checkpoints (most effective for deep understanding):

```json
{
  "checkpoint": {
    "type": "teachback",
    "conceptId": "<concept-being-tested>",
    "evaluationCriteria": {
      "requiredConcepts": ["<must-mention>"],
      "bonusConcepts": ["<nice-to-mention>"],
      "minimumDepth": "<surface|moderate|deep>",
      "maxAttempts": 3
    },
    "feedbackTiers": {
      "excellent": { "threshold": 0.9, "feedbackText": "<praise>", "nextAction": "continue" },
      "good": { "threshold": 0.7, "feedbackText": "<encouragement>", "nextAction": "supplement" },
      "partial": { "threshold": 0.4, "feedbackText": "<guidance>", "nextAction": "guided_review" },
      "struggling": { "threshold": 0.0, "feedbackText": "<support>", "nextAction": "reteach" }
    }
  }
}
```

## Assessment Format

Include assessments that align with learning objectives:

```json
{
  "assessments": [
    {
      "id": { "catalog": "internal", "value": "q-<unique>" },
      "type": "<choice|multiple_choice|text_entry|true_false>",
      "title": "<assessment-title>",
      "prompt": "<question-text>",
      "spokenPrompt": "<voice-optimized-question>",
      "choices": [
        {
          "id": "<choice-id>",
          "text": "<choice-text>",
          "spokenText": "<voice-version>",
          "correct": <true|false>,
          "feedback": "<why-correct-or-incorrect>"
        }
      ],
      "scoring": {
        "maxScore": <number>,
        "passingScore": <number>,
        "partialCredit": <true|false>
      },
      "feedback": {
        "correct": { "text": "<correct-feedback>", "spokenText": "<voice-version>" },
        "incorrect": { "text": "<incorrect-feedback>", "hint": "<helpful-hint>" }
      },
      "hints": [{ "text": "<hint>", "spokenText": "<voice-version>" }],
      "difficulty": <0.0-1.0>,
      "objectivesAssessed": ["<objective-ids>"],
      "attempts": <number>
    }
  ]
}
```

## Misconceptions Format

Identify common misconceptions and provide remediation:

```json
{
  "misconceptions": [
    {
      "id": "misc-<unique>",
      "misconception": "<what-learners-wrongly-believe>",
      "triggerPhrases": ["<phrases-indicating-misconception>"],
      "correction": "<correct-understanding>",
      "spokenCorrection": "<voice-optimized-correction>",
      "explanation": "<why-this-misconception-occurs>",
      "severity": "<minor|moderate|critical>",
      "remediationPath": {
        "reviewTopics": ["<topic-ids-to-review>"],
        "additionalExamples": ["<example-ids>"],
        "suggestedTranscriptSegments": ["<segment-ids>"]
      }
    }
  ]
}
```

## Examples Format

Provide concrete examples for each concept:

```json
{
  "examples": [
    {
      "id": { "catalog": "internal", "value": "ex-<unique>" },
      "title": "<example-title>",
      "type": "<code|scenario|case_study|analogy|demonstration|visual>",
      "content": "<example-content>",
      "explanation": "<why-this-example-helps>",
      "relatedObjectives": ["<objective-ids>"],
      "walkthrough": [
        {
          "step": 1,
          "content": "<step-explanation>",
          "spokenContent": "<voice-version>"
        }
      ]
    }
  ]
}
```

For code examples specifically:

```json
{
  "type": "code",
  "language": "<programming-language>",
  "code": "<code-content>",
  "lineByLineExplanation": [
    { "lineNumber": 1, "explanation": "<what-this-line-does>" }
  ]
}
```

## Glossary Format

Define all technical terms:

```json
{
  "glossary": {
    "terms": [
      {
        "id": "term-<unique>",
        "term": "<term>",
        "pronunciation": "/<IPA>/",
        "definition": "<formal-definition>",
        "spokenDefinition": "<voice-friendly-definition>",
        "simpleDefinition": "<for-beginners>",
        "synonyms": ["<alternative-terms>"],
        "relatedTerms": ["<connected-concepts>"],
        "contextualUsage": "<how-used-in-this-curriculum>"
      }
    ]
  }
}
```

## Media Placeholders

When visual aids would help, include media placeholders:

```json
{
  "media": {
    "embedded": [
      {
        "id": "img-<unique>",
        "type": "<image|diagram|equation|chart|map>",
        "title": "<media-title>",
        "alt": "<accessibility-description-required>",
        "caption": "<figure-caption>",
        "audioDescription": "<detailed-verbal-description>",
        "url": "PLACEHOLDER: <description-of-needed-visual>",
        "segmentTiming": {
          "startSegment": "<segment-id>",
          "displayMode": "<persistent|highlight|popup>"
        }
      }
    ]
  }
}
```

For diagrams, include source code for generation:

```json
{
  "type": "diagram",
  "diagramSubtype": "<architecture|flowchart|sequence|mindmap>",
  "sourceCode": {
    "format": "mermaid",
    "code": "<mermaid-diagram-code>"
  }
}
```

For equations:

```json
{
  "type": "equation",
  "latex": "<latex-formula>",
  "alt": "<accessibility-description>",
  "semanticMeaning": {
    "commonName": "<formula-name>",
    "purpose": "<what-it-calculates>",
    "spokenForm": "<how-to-say-it>"
  }
}
```

## Spaced Retrieval Configuration

For key concepts that should be retained long-term:

```json
{
  "keyConceptForRetrieval": true,
  "retrievalConfig": {
    "difficulty": "<easy|medium|hard>",
    "retrievalPrompts": [
      "<question-to-test-recall>"
    ],
    "minimumRetention": 0.7,
    "spacingAlgorithm": "sm2",
    "initialInterval": "P1D",
    "maxInterval": "P30D"
  }
}
```

## Educational Context

Set the educational parameters:

```json
{
  "educational": {
    "interactivityType": "active",
    "interactivityLevel": "high",
    "learningResourceType": ["lecture", "exercise", "conversation"],
    "intendedEndUserRole": ["learner"],
    "context": ["<school|higher education|training|other>"],
    "typicalAgeRange": "<age-range>",
    "difficulty": "<very easy|easy|medium|difficult|very difficult>",
    "typicalLearningTime": "<ISO-8601-duration>",
    "audienceProfile": {
      "educationLevel": "<elementary|middle school|high school|undergraduate|graduate|professional>",
      "prerequisites": [
        {
          "description": "<required-prior-knowledge>",
          "required": true
        }
      ]
    }
  }
}
```

## Rights and Licensing

```json
{
  "rights": {
    "cost": false,
    "copyrightAndOtherRestrictions": false,
    "license": {
      "type": "CC-BY-4.0",
      "url": "https://creativecommons.org/licenses/by/4.0/"
    },
    "holder": "<copyright-holder>"
  }
}
```

## Source Provenance

Document how the content was created:

```json
{
  "sourceProvenance": {
    "originType": "ai_generated",
    "aiGenerationMetadata": {
      "model": "<model-name>",
      "generationDate": "<iso-datetime>",
      "humanReviewed": false,
      "promptVersion": "1.0"
    }
  }
}
```

## Pedagogical Design Principles

Structure content following these learning science principles:

### Learning Progression
- **Start concrete, then abstract**: Begin with relatable examples before introducing formal definitions
- **Scaffold complexity**: Each topic should build on previous knowledge
- **Use prerequisites**: Link topics with explicit `prerequisites` arrays showing required prior mastery

### Content Density Guidelines
- **Per topic transcript**: 5-15 minutes of spoken content (500-1500 words)
- **Checkpoint frequency**: Every 3-5 minutes of content
- **Concepts per topic**: 1-3 main concepts, not more
- **Examples per concept**: At least 2 (one simple, one applied)

### Teachback Emphasis
Teachback checkpoints are the most effective for deep learning. Use them:
- After every major concept (not just simple confirmations)
- When the learner needs to synthesize multiple ideas
- Before moving to advanced applications

### Scaffolding Techniques
1. **Analogy first**: Introduce concepts with familiar comparisons
2. **Concrete example**: Show a specific instance
3. **Formal definition**: Then provide the precise definition
4. **Application**: Show how to use it
5. **Verification**: Check understanding with teachback

## Quality Requirements

Your output MUST:

1. **Be valid JSON** that parses without errors
2. **Include all required fields** for every node type
3. **Use consistent ID patterns** (e.g., `topic-1`, `obj-1`, `seg-1`)
4. **Provide voice-optimized content** with speaking notes and pronunciations
5. **Include checkpoints** after every major concept (at minimum every 3-5 minutes of content)
6. **Align assessments to objectives** explicitly via `objectivesAssessed`
7. **Define all technical terms** in the glossary with pronunciations
8. **Include at least 2 misconceptions** per major topic
9. **Provide multiple examples** for complex concepts
10. **Use proper Bloom's taxonomy levels** for objectives
11. **Set realistic time estimates** for each content level
12. **Include media placeholders** where visual aids would help understanding

## Voice-First Principles

Remember this is for voice tutoring:

1. **Write conversationally** as if speaking to a student
2. **Use shorter sentences** for clarity
3. **Include pronunciation guides** for all technical terms
4. **Add speaking notes** with pace, emphasis, and tone
5. **Pause after complex concepts** (set `pauseAfter: true`)
6. **Use analogies and examples** to explain abstract concepts
7. **Check understanding frequently** with checkpoints
8. **Provide spoken variants** of written content (`spokenText`, `spokenPrompt`, etc.)

## Output Format

Return ONLY the complete, valid JSON document. Do not include:
- Markdown code fences
- Explanatory text before or after
- Comments within the JSON
- Truncated or partial content

The output should be ready to save directly as a `.umcf` file.

## Handling Large Curricula

If the user requests a large curriculum (more than 5-6 topics):
1. **Complete the structure fully**: Include all modules, topics, and their metadata
2. **Prioritize early content**: Provide full transcripts for the first 2-3 topics
3. **Skeleton later content**: For remaining topics, include structure, objectives, and key assessments, with a note in the description: "Full transcript to be developed"
4. **Never truncate mid-structure**: Always close all JSON brackets properly

For very large requests, suggest breaking into multiple generation requests by module.

---

Now, based on the curriculum specification provided above, generate a complete UMCF curriculum document.

---

## Appendix: Quick Reference

### Node Types (Hierarchical)

| Type | Purpose | Contains |
|------|---------|----------|
| `curriculum` | Top-level container | units or modules |
| `unit` | Major division | modules or topics |
| `module` | Thematic grouping | topics |
| `topic` | Main subject | subtopics or transcript |
| `subtopic` | Subdivision | transcript |
| `lesson` | Single session | sections or transcript |
| `section` | Part of lesson | segments or transcript |
| `segment` | Smallest unit | transcript only |

### Bloom's Taxonomy Levels

| Level | Description | Verbs |
|-------|-------------|-------|
| `remember` | Recall facts | define, list, name, state |
| `understand` | Explain concepts | describe, explain, summarize |
| `apply` | Use in new situations | apply, demonstrate, implement |
| `analyze` | Break down, find patterns | analyze, compare, contrast |
| `evaluate` | Judge, critique | evaluate, assess, justify |
| `create` | Produce new work | create, design, develop |

### Checkpoint Types

| Type | When to Use |
|------|-------------|
| `simple_confirmation` | Quick check: "Does that make sense?" |
| `comprehension_check` | Verify basic understanding |
| `knowledge_check` | Test factual recall |
| `application_check` | Verify ability to apply concept |
| `teachback` | Have learner explain in their own words |

### ISO 8601 Durations

| Duration | Format |
|----------|--------|
| 30 minutes | `PT30M` |
| 1 hour | `PT1H` |
| 1 hour 30 min | `PT1H30M` |
| 2 hours | `PT2H` |
| 1 day | `P1D` |
| 1 week | `P1W` |

### Difficulty Scale

| Value | Meaning |
|-------|---------|
| 0.0-0.2 | Very easy |
| 0.2-0.4 | Easy |
| 0.4-0.6 | Medium |
| 0.6-0.8 | Difficult |
| 0.8-1.0 | Very difficult |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.0 | 2026-01-11 | Added source material handling guidance for ambiguous inputs |
| 1.1.0 | 2026-01-11 | Added concrete example, pedagogical principles, scope guidance |
| 1.0.0 | 2026-01-11 | Initial prompt release |

## References

- UMCF Specification: `curriculum/README.md`
- UMCF JSON Schema: `curriculum/umcf-schema.json`
- Example Curricula: `curriculum/examples/`
