# Audience-Adaptive Content Delivery: Research & Standards Review

**Document Type:** Fact-Finding / Investigative Research
**Date:** December 2024
**Status:** Design Phase - Research Complete

---

## Executive Summary

This document investigates existing standards, specifications, and best practices for:
1. Describing **who the learner is** (learner/audience profiles)
2. Describing **who content is intended for** (content metadata)
3. Adapting **how content is delivered** (AI prompting, TTS, pacing)

The key insight driving this research: **The curriculum defines WHAT to teach, but the audience defines HOW to teach it.** A basic fractions lesson requires fundamentally different delivery for a 12-year-old vs. a 40-year-old professional.

---

## 1. Learner Profile Standards

### 1.1 IMS Learner Information Package (LIP)

**Source:** [1EdTech LIP Specification](https://www.1edtech.org/standards/lip)

The Learner Information Package (LIP) is the foundational standard for describing learners. Released in 2001, it defines 12 core structures:

| Structure | Description |
|-----------|-------------|
| **Identification** | Name, contact info, demographics |
| **Goals** | Learning objectives, career goals |
| **Qualifications** | Degrees, certifications, licenses |
| **Activities** | Learning activities, work experience |
| **Competencies** | Skills, knowledge, abilities |
| **Interests** | Personal interests, hobbies |
| **Affiliations** | Organizations, memberships |
| **Accessibility** | Needs and preferences for access |
| **Transcripts** | Academic records |
| **Relationships** | Connections between learners |
| **Security Keys** | Authentication credentials |

**Relevance to VoiceLearn:** LIP provides a comprehensive model but is heavyweight for our use case. The **Accessibility** structure is most relevant.

---

### 1.2 IMS AccessForAll (ACCLIP)

**Source:** [1EdTech ACCLIP Information Model](https://www.imsglobal.org/accessibility/acclipv1p0/imsacclip_infov1p0.html)

ACCLIP extends LIP with the `<accessForAll>` element, which goes beyond disability to serve ALL users' needs and preferences.

**Key Categories:**

| Category | Elements |
|----------|----------|
| **Display** | How resources are presented (screen reader, braille, visual enhancement, text highlighting) |
| **Control** | How resources are operated (keyboard, mouse alternatives, voice control) |
| **Content** | Alternative/supplementary resources needed (captions, transcripts, sign language) |

**Key Insight:** ACCLIP uses a **functional approach** (what the user needs) rather than a **medical approach** (what disability they have). This is the correct model for VoiceLearn.

---

### 1.3 ISO/IEC 24751 AccessForAll

**Source:** [ISO/IEC 24751-2:2008](https://www.iso.org/standard/43603.html)

The international standard version of AccessForAll, structured in three parts:

- **Part 1:** Framework and definitions
- **Part 2:** Personal Needs and Preferences (PNP) - describes learner needs
- **Part 3:** Digital Resource Description (DRD) - labels resources

**Core Principle:** Accessibility through **dynamic matching** of individual needs/preferences with available resources. The system finds the best match rather than requiring all content to be universally accessible.

**Relevance to VoiceLearn:** We should adopt this matching model—define learner preferences, then match them to delivery parameters.

---

### 1.4 xAPI Agent Profile

**Source:** [xAPI Specification](https://github.com/adlnet/xAPI-Spec) | [Deep Dive: Agent Profile](https://xapi.com/blog/deep-dive-agent-profile/)

The Experience API (xAPI) provides:

- **Agent/Actor:** The learner performing actions
- **Agent Profile Resource:** Arbitrary key/document pairs associated with an Agent
- **Person Object:** Consolidates multiple identifiers for the same person

**Statement Structure:** `<actor> <verb> <object> with <result> in <context>`

**Relevance to VoiceLearn:** xAPI's Agent Profile could store audience profile as persistent learner metadata. The statement structure could track learning interactions for adaptive adjustments.

---

### 1.5 IEEE Enterprise Learner Records (P2997)

**Source:** [ADL Initiative - Enterprise Learner Records](https://adlnet.gov/news/2021/07/27/A-New-Data-Standard-for-Enterprise-Learner-Records/)

New standard to harmonize learner record metadata across education/training systems. Developed for DoD to create portable learner records.

**Relevance to VoiceLearn:** Future consideration for enterprise deployment and interoperability.

---

## 2. Content Audience Metadata Standards

### 2.1 IEEE Learning Object Metadata (LOM) 1484.12

**Source:** [IEEE 1484.12.1-2020](https://standards.ieee.org/ieee/1484.12.1/7699/) | [EduTech Wiki](https://edutechwiki.unige.ch/en/Learning_Object_Metadata_Standard)

LOM defines 76 data elements across 9 categories. The **Educational Category** is most relevant:

| Element | Description | Values |
|---------|-------------|--------|
| **5.1 Interactivity Type** | Predominant mode of learning | active, expositive, mixed |
| **5.2 Learning Resource Type** | Specific kind of resource | exercise, simulation, lecture, etc. |
| **5.3 Interactivity Level** | Degree of interactivity | very low, low, medium, high, very high |
| **5.4 Semantic Density** | Conciseness of content | very low → very high |
| **5.5 Intended End User Role** | Principal user | teacher, author, learner, manager |
| **5.6 Context** | Educational environment | school, higher education, training, other |
| **5.7 Typical Age Range** | Target age | "minimum-maximum" in years |
| **5.8 Difficulty** | How hard for typical learner | very easy, easy, medium, difficult, very difficult |
| **5.9 Typical Learning Time** | Time to work through | ISO 8601 duration |

**Key for VoiceLearn:** Elements 5.5-5.8 directly address audience. We should align with this vocabulary.

---

### 2.2 SCORM Metadata

**Source:** [SCORM.com - Metadata Structure](https://scorm.com/scorm-explained/technical-scorm/content-packaging/metadata-structure/)

SCORM adopts IEEE LOM (IMS 1.3 = IEEE 1484.12.1). Key educational metadata:

- **Learning Resource Type:** exercise, simulation, questionnaire, lecture, etc.
- **Intended End User Role:** teacher, author, learner, manager
- **Context:** school, higher education, training, other
- **Typical Age Range:** minimum–maximum years
- **Target Audience Level:** beginner/intermediate/advanced (extension)

**Relevance to VoiceLearn:** When importing SCORM content, we can extract audience metadata. Our VLCF format should support equivalent fields.

---

### 2.3 Dublin Core + DCMI Education

**Source:** [DCMI Metadata Terms](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/) | [Audience Education Level](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/terms/educationLevel/)

Dublin Core provides two key terms:

| Term | Definition |
|------|------------|
| **Audience** | A class of entity for whom the resource is intended |
| **Audience Education Level** | A class of agents defined by progression through an educational context |

**Important Note:** DCMI recommends using controlled vocabularies but doesn't prescribe specific ones. This allows local/national vocabulary development.

---

### 2.4 Schema.org / LRMI

**Source:** [Schema.org EducationalAudience](https://schema.org/EducationalAudience) | [Schema.org educationalLevel](https://schema.org/educationalLevel)

The Learning Resource Metadata Initiative (LRMI) extended Schema.org with education-specific terms:

```json
{
  "@type": "Course",
  "name": "Introduction to Fractions",
  "audience": {
    "@type": "EducationalAudience",
    "educationalRole": "student"
  },
  "educationalLevel": "4th grade",
  "typicalAgeRange": "9-10"
}
```

**Key Properties:**

| Property | Description |
|----------|-------------|
| `audience` | EducationalAudience with `educationalRole` (student, teacher, parent, etc.) |
| `educationalLevel` | Stage in curriculum ("beginner", "intermediate", "advanced" or curriculum reference) |
| `typicalAgeRange` | Age range as string (e.g., "10-12") |
| `teaches` | Competency or concept taught |
| `assesses` | What the resource assesses |

**Relevance to VoiceLearn:** Schema.org/LRMI is the most modern, web-friendly standard. Strong candidate for VLCF alignment.

---

## 3. Language Proficiency & Readability Standards

### 3.1 CEFR (Common European Framework of Reference)

**Source:** [Council of Europe CEFR](https://www.coe.int/en/web/common-european-framework-reference-languages/level-descriptions)

Six proficiency levels for language competence:

| Level | Category | Description |
|-------|----------|-------------|
| **A1** | Basic User | Beginner - basic phrases, simple interactions |
| **A2** | Basic User | Elementary - routine tasks, simple descriptions |
| **B1** | Independent | Intermediate - familiar topics, simple connected text |
| **B2** | Independent | Upper Intermediate - complex text, fluent interaction |
| **C1** | Proficient | Advanced - complex topics, flexible language use |
| **C2** | Proficient | Mastery - effortless understanding, precise expression |

**Key Insight:** C2 is NOT "native speaker" level—most native speakers fall into C1. C2 represents exceptional precision and flexibility.

**Relevance to VoiceLearn:** CEFR provides a well-researched, internationally recognized framework for vocabulary complexity. Could map to our audience profiles.

---

### 3.2 Flesch-Kincaid Readability

**Source:** [Wikipedia - Flesch-Kincaid](https://en.wikipedia.org/wiki/Flesch–Kincaid_readability_tests)

Two complementary metrics:

**Flesch Reading Ease (0-100):**
| Score | Difficulty | Audience |
|-------|------------|----------|
| 90-100 | Very Easy | 5th grade |
| 80-90 | Easy | 6th grade |
| 70-80 | Fairly Easy | 7th grade |
| 60-70 | Standard | 8th-9th grade |
| 50-60 | Fairly Difficult | 10th-12th grade |
| 30-50 | Difficult | College |
| 0-30 | Very Difficult | College graduate |

**Flesch-Kincaid Grade Level:** Direct mapping to U.S. grade levels.

**Formula Insights:**
- Sentence length and syllable count are the primary factors
- Vocabulary complexity (via syllables) has higher weight than sentence length
- Target general audiences at 8th grade level (~60-70 Reading Ease)

**Relevance to VoiceLearn:** We could use readability metrics to:
1. Analyze curriculum content complexity
2. Validate AI output matches target audience level
3. Guide AI to produce appropriately complex text

---

## 4. Speech Synthesis Standards

### 4.1 W3C SSML (Speech Synthesis Markup Language)

**Source:** [W3C SSML 1.1](https://www.w3.org/TR/speech-synthesis11/)

SSML provides standardized control over TTS output:

**Prosody Element Attributes:**

| Attribute | Description | Values |
|-----------|-------------|--------|
| `rate` | Speaking speed | x-slow, slow, medium, fast, x-fast, or percentage |
| `pitch` | Voice pitch | x-low, low, medium, high, x-high, or Hz value |
| `volume` | Loudness | silent, x-soft, soft, medium, loud, x-loud, or 0-100 |
| `contour` | Pitch variation | Complex pitch envelope |
| `range` | Pitch variability | How much pitch varies |
| `duration` | Segment length | Time value |

**Example:**
```xml
<speak>
  <prosody rate="slow" pitch="low">
    Welcome to today's lesson on fractions.
  </prosody>
</speak>
```

**Other Relevant Elements:**
- `<break>` - Pauses between phrases
- `<emphasis>` - Stress on words
- `<say-as>` - Pronunciation guidance (dates, numbers, etc.)

**Relevance to VoiceLearn:** SSML is the universal standard for TTS control. We should:
1. Generate SSML-annotated text for TTS services that support it
2. Map audience profiles to SSML prosody defaults
3. Use `<break>` strategically based on audience (longer pauses for younger/slower learners)

---

### 4.2 ElevenLabs Voice API

**Source:** [ElevenLabs TTS Documentation](https://elevenlabs.io/docs/capabilities/text-to-speech)

ElevenLabs provides rich voice control:

| Parameter | Range | Effect |
|-----------|-------|--------|
| `stability` | 0-1 | Higher = more consistent; Lower = more emotional range |
| `similarity_boost` | 0-1 | Voice cloning fidelity |
| `style` | 0-1 | Style exaggeration (newer models) |
| `speed` | 0.7-1.2 | Speaking rate multiplier |

**Voice Remixing:** Natural language prompts can adjust "delivery, cadence, tone, gender, and accents."

**Key Insight:** ElevenLabs excels at emotional expressiveness and naturalness. Good for younger audiences and story-based delivery.

---

### 4.3 OpenAI TTS

**Source:** [OpenAI TTS API](https://platform.openai.com/docs/guides/text-to-speech)

Simpler controls:
- Voice selection (alloy, echo, fable, onyx, nova, shimmer)
- Speed (0.25 to 4.0)

**Key Insight:** OpenAI's Realtime API adapts via prompts and handles barge-in well, making it better for interactive dialog. Less control over prosody.

---

## 5. LLM Prompting for Audience Adaptation

### 5.1 Core Principles

**Source:** [Prompt Engineering Guide](https://www.promptingguide.ai/) | [AWS - Prompt Engineering with Claude](https://aws.amazon.com/blogs/machine-learning/prompt-engineering-techniques-and-best-practices-learn-by-doing-with-anthropics-claude-3-on-amazon-bedrock/)

**Key Techniques:**

| Technique | Description | Example |
|-----------|-------------|---------|
| **Role/Persona Prompting** | Assign a specific identity | "You are a patient elementary school teacher" |
| **Audience Specification** | Define who you're speaking to | "Explain to a 10-year-old" |
| **Reading Level Anchoring** | Specify complexity | "Use 6th-grade vocabulary" |
| **Tone Setting** | Define emotional register | "Be warm and encouraging" |
| **Format Constraints** | Control output structure | "Use short sentences under 15 words" |

**The PARTS Framework:**
- **P**urpose - What is the goal?
- **A**udience - Who is this for?
- **R**equirements - What constraints apply?
- **T**ask - What specific action?
- **S**tyle - What tone/format?

---

### 5.2 Claude-Specific Considerations

**Source:** [Anthropic Claude Documentation](https://docs.anthropic.com/claude/docs/system-prompts)

Claude UI supports style presets: Normal, Concise, Explanatory, Formal, Scholarly Explorer, or custom.

**Key Behaviors:**
- Claude matches the tone of the prompt (formal prompt → formal response)
- Role prompting adjusts communication style significantly
- System prompts set persistent context for entire conversations
- `<userStyle>` tags can define custom tone/vocabulary instructions

**Recommended Structure:**
```
## ROLE
You are a [specific persona]

## AUDIENCE
You are speaking to [specific audience description]

## STYLE
- [Vocabulary constraints]
- [Sentence structure guidelines]
- [Tone and personality]

## CONSTRAINTS
- [What to avoid]
- [Length limits]
- [Format requirements]
```

---

### 5.3 Audience-Specific Prompt Patterns

Based on research, effective patterns for different audiences:

**For Children (6-12):**
```
You are a friendly, patient teacher explaining to a curious 10-year-old.
- Use simple words a child would know
- Keep sentences short (under 12 words)
- Use concrete examples from their world (school, games, friends)
- Be enthusiastic and encouraging
- Avoid abstract concepts without concrete grounding
```

**For Teens (13-17):**
```
You are an approachable mentor talking to a smart high schooler.
- Be authentic and direct - teens detect condescension
- Connect to relevance in their lives
- Respect their intelligence
- Don't try too hard to be "cool"
- Allow questioning and critical thinking
```

**For Adult Professionals:**
```
You are a knowledgeable colleague providing expert guidance.
- Be efficient and respect their time
- Use professional vocabulary appropriate to the domain
- Build on assumed foundational knowledge
- Focus on practical application
- Be direct without being curt
```

**For Corporate/Wide Audiences:**
```
You are a professional instructor creating training content.
- Use inclusive, neutral language
- Avoid cultural assumptions or region-specific references
- Maintain consistent professional register
- Don't assume specific background knowledge
- Be clear and accessible to diverse learners
```

---

## 6. Synthesis: Mapping Standards to VoiceLearn

### 6.1 Recommended Audience Profile Dimensions

Based on standards review, we recommend these dimensions for VoiceLearn:

| Dimension | Based On | Values |
|-----------|----------|--------|
| **Age Group** | LOM typicalAgeRange, Schema.org | Child (6-12), Teen (13-17), Young Adult (18-25), Adult (26-55), Senior (55+) |
| **Educational Context** | LOM Context, LRMI | K-12, Higher Ed, Professional, Corporate, Personal |
| **Language Proficiency** | CEFR | A1-C2 (mapped to vocabulary complexity) |
| **Audience Scope** | Custom (corporate need) | Individual, Small Group, Organization, Public |
| **Accessibility Needs** | ISO 24751 | Display, Control, Content preferences |

### 6.2 Recommended Delivery Parameter Mapping

| Audience Aspect | LLM Prompt Parameter | TTS Parameter |
|-----------------|---------------------|---------------|
| Age Group | Vocabulary level, example types, tone | Rate, pitch variability |
| Educational Context | Formality, jargon allowance | Voice selection |
| Language Proficiency | Sentence complexity, word choice | Rate (slower for lower proficiency) |
| Audience Scope | Inclusivity requirements, cultural neutrality | Professional/neutral voices |
| Accessibility | Content alternatives, structure | SSML breaks, rate |

### 6.3 Standards Alignment for VLCF

For our VoiceLearn Curriculum Format, we should consider adding:

```yaml
# In curriculum.yaml or topic metadata
audience:
  # Aligned with Schema.org/LRMI
  typicalAgeRange: "10-12"
  educationalLevel: "elementary"  # or CEFR-style: "B1"

  # Aligned with IEEE LOM
  intendedEndUserRole: "learner"  # learner, teacher, parent
  context: "school"               # school, higher_education, training, other
  difficulty: "medium"            # very_easy, easy, medium, difficult, very_difficult

  # Custom for delivery adaptation
  languageComplexity: "B1"        # CEFR level for vocabulary
  readabilityTarget: 70           # Flesch Reading Ease target
```

### 6.4 AI Instruction Generation Strategy

The system should generate AI instructions by:

1. **Start with role assignment** based on audience age and context
2. **Set vocabulary constraints** based on CEFR/Flesch targets
3. **Define tone** based on audience age and scope
4. **Add inclusivity requirements** if audience scope is wide
5. **Specify format constraints** (sentence length, structure)

### 6.5 TTS Adaptation Strategy

1. **Rate:** Map age group and language proficiency to SSML rate
   - Children/Seniors/Lower proficiency → `slow` or 0.85x
   - Young Adults → `medium` or 1.0x
   - Quick reference/review → `fast` or 1.1x

2. **Voice Selection:** Match personality to audience
   - Children → Warm, expressive voices
   - Corporate → Professional, neutral voices
   - Personal learning → Friendly, conversational voices

3. **Pauses:** Use SSML `<break>` based on audience
   - More frequent breaks for children and lower proficiency
   - Longer section breaks for complex content

---

## 7. Open Questions for Design Phase

1. **Profile vs. Curriculum:** Should audience be stored at the profile level (user setting) or curriculum level (content metadata), or both with merge rules?

2. **Override Hierarchy:** When curriculum specifies "intended for adults" but user profile says "child," which wins? Options:
   - Curriculum wins (content author knows best)
   - Profile wins (user knows their needs)
   - Warn user of mismatch
   - Hybrid (use curriculum difficulty but profile delivery style)

3. **Transcript Adaptation:** For curricula with fixed transcripts, how do we adapt delivery? Options:
   - TTS-only adaptation (rate, voice)
   - Post-processing text simplification via LLM
   - Flag as "not adaptable" and warn

4. **Validation:** Should we validate AI output readability against target? Could reject and regenerate if Flesch score is too far off.

5. **Progressive Adaptation:** Should we track user performance and auto-adjust difficulty? (IEEE P2247.2 Adaptive Instructional Systems addresses this)

---

## 8. References

### Standards Organizations
- [1EdTech (formerly IMS Global)](https://www.1edtech.org/)
- [IEEE Learning Technology Standards Committee](https://sagroups.ieee.org/ltsc/)
- [Dublin Core Metadata Initiative](https://www.dublincore.org/)
- [Schema.org](https://schema.org/)
- [W3C Speech API](https://www.w3.org/TR/speech-synthesis11/)

### Key Specifications
- [IMS LIP](https://www.1edtech.org/standards/lip)
- [IMS ACCLIP](https://www.imsglobal.org/accessibility/acclipv1p0/imsacclip_infov1p0.html)
- [IEEE LOM 1484.12](https://standards.ieee.org/ieee/1484.12.1/7699/)
- [ISO/IEC 24751](https://www.iso.org/standard/43603.html)
- [Schema.org EducationalAudience](https://schema.org/EducationalAudience)
- [CEFR Levels](https://www.coe.int/en/web/common-european-framework-reference-languages/level-descriptions)
- [xAPI Specification](https://github.com/adlnet/xAPI-Spec)

### TTS Documentation
- [W3C SSML 1.1](https://www.w3.org/TR/speech-synthesis11/)
- [ElevenLabs TTS](https://elevenlabs.io/docs/capabilities/text-to-speech)

### Prompt Engineering
- [Prompt Engineering Guide](https://www.promptingguide.ai/)
- [Anthropic Claude Documentation](https://docs.anthropic.com/claude/docs/system-prompts)

---

## 9. Next Steps

1. **Design Decision:** Choose which standards to formally align with (recommend Schema.org/LRMI + CEFR)
2. **VLCF Update:** Draft schema extensions for audience metadata
3. **Prompt Templates:** Create audience-specific prompt template library
4. **TTS Mapping:** Define explicit mappings from audience profiles to TTS parameters
5. **UI Design:** Design audience profile selection/configuration interface
