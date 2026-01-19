# Training Data Acquisition Guide

## Purpose

This document provides instructions for gathering initial training data for academic competition modules (Knowledge Bowl, Quiz Bowl, Science Bowl). The focus is on **legitimate, high-quality, publicly available sources** that establish credibility and cannot be criticized as inaccurate or improperly sourced.

---

## Guiding Principles

### Legitimacy Requirements
- **Public domain or explicitly licensed for reuse** - No copyrighted material without permission
- **Official sources preferred** - Government, educational institutions, competition organizers
- **Traceable provenance** - Every question should have a documented source
- **Verifiable accuracy** - Facts must be checkable against authoritative references

### Quality Standards
- Factually accurate and up-to-date
- Appropriately difficult for target competition
- Well-written with clear, unambiguous answers
- Formatted correctly for the competition type

### Coverage Goals
- All major subject domains represented
- Range of difficulty levels (beginner through championship)
- Content appropriate for middle school through varsity levels

---

## TIER 1: GOLD STANDARD SOURCES (Start Here)

These sources are unimpeachable. They are official, public, and specifically intended for educational use.

### 1. U.S. Department of Energy Science Bowl

**Source:** https://science.osti.gov/wdts/nsb/Regional-Competitions/Resources

**What's Available:**
- Official sample questions released by DOE
- Questions from previous National Science Bowl competitions
- Both middle school and high school levels
- All Science Bowl categories covered

**How to Acquire:**
1. Navigate to the NSB Resources page
2. Download official sample question sets (PDF format)
3. Each set contains ~500 questions across all categories
4. Categories: Biology, Chemistry, Physics, Math, Earth and Space Science, Energy

**Legitimacy:** Federal government educational program. Explicitly provided for practice. Public domain (US government work).

**Format:** Tossup/bonus format, multiple choice and short answer

---

### 2. Quizbowlpackets.com Archive

**Source:** https://quizbowlpackets.com/

**What's Available:**
- Thousands of publicly released Quiz Bowl packets
- Questions from tournaments at all levels (middle school, high school, college)
- Multiple formats: NAQT-style, ACF-style, housewrites
- Searchable by year, difficulty, tournament

**How to Acquire:**
1. Browse the archive by year or tournament
2. Download packets (typically PDF or DOCX)
3. Packets are released by their authors after tournaments
4. Many are explicitly CC-licensed or public domain

**Legitimacy Check Required:**
- Verify each packet's license before use
- Prefer packets from established organizations (NAQT, ACF, PACE)
- Many housewrites are CC BY-SA or similar
- Check the packet's header/footer for licensing info

**What to Look For:**
- Packets marked "Released" or "Public"
- CC BY, CC BY-SA, or public domain declarations
- Packets from educational nonprofits (PACE, ACF)

---

### 3. QuizDB (Quiz Database)

**Source:** https://www.quizdb.org/

**What's Available:**
- Searchable database of Quiz Bowl questions
- Filterable by category, subcategory, difficulty, tournament
- Questions from publicly released packets
- API access available

**How to Acquire:**
1. Use the search interface to filter by:
   - Category (Literature, History, Science, Fine Arts, etc.)
   - Subcategory (American Literature, European History, Biology, etc.)
   - Difficulty (Middle School, Easy High School, Regular High School, Nationals, etc.)
2. Export results for processing
3. Source attribution is included with each question

**Legitimacy:** Aggregates questions from publicly released sources only. Provides source attribution.

**Best Use:** Filling specific category gaps, finding questions at specific difficulty levels

---

### 4. PACE NSC Sample Questions

**Source:** https://www.pace-nsc.org/resources/

**What's Available:**
- Sample packets from Partnership for Academic Competition Excellence
- NSC (National Scholastic Championship) sample questions
- Well-edited, professionally written content
- Explicitly released for practice

**How to Acquire:**
1. Check the PACE resources page
2. Download sample materials
3. These are explicitly intended for practice use

**Legitimacy:** PACE is a nonprofit educational organization. Materials explicitly released for practice.

---

### 5. Academic Competition Federation (ACF) Sample Questions

**Source:** https://acf-quizbowl.com/

**What's Available:**
- Sample packets from ACF tournaments
- College-level questions (can be adapted down)
- High editorial standards
- Explicitly released materials

**How to Acquire:**
1. Check ACF website for released materials
2. Past tournaments often have packets released afterward
3. Follow ACF's licensing requirements

**Legitimacy:** Educational nonprofit. Released materials explicitly intended for practice.

---

## TIER 2: OFFICIAL STATE COMPETITION ARCHIVES

These require more effort to access but are authoritative for their specific competitions.

### Knowledge Bowl State Archives

**Minnesota Service Cooperatives:**
- Contact: Monica Thompson, Lakes Country Service Cooperative
- State coordinator controls question distribution
- Past questions may be available through regional coordinators
- **Action:** Reach out formally to request access to retired question sets for educational software

**Washington (ESDs):**
- Contact: Chris Cloke, Wenatchee Schools (State Coordinator)
- Questions distributed through 9 Educational Service Districts
- **Action:** Contact state coordinator about educational licensing

**Colorado Knowledge Bowl Foundation:**
- Source: https://www.coloradokb.org/
- Tournament documents available
- **Action:** Check what's publicly available, contact for additional access

**Important:** These sources may require formal agreements. They're legitimate but not necessarily public. Establish relationships before assuming availability.

---

### Question Authorities

**Source:** https://questionauthorities.com/ (Commercial)

**What They Provide:**
- Official question supplier for MN, WA, CO Knowledge Bowl
- 27 question writers
- High editorial standards

**Licensing:** This is a commercial provider. Would require licensing agreement and payment for use.

**Status:** Not a free source, but the most authoritative for Knowledge Bowl content. Consider for future phases when budget allows.

---

## TIER 3: EDUCATIONAL REFERENCE SOURCES

For creating original questions or verifying facts, use these authoritative references.

### General Knowledge Verification

| Domain | Primary Reference | Notes |
|--------|------------------|-------|
| **History** | Library of Congress, Britannica | For dates, events, names |
| **Science** | NIST, NASA, peer-reviewed journals | For facts, measurements |
| **Literature** | Norton Anthology contents lists, Project Gutenberg | For titles, authors, plots |
| **Geography** | USGS, CIA World Factbook | For locations, statistics |
| **Arts** | Metropolitan Museum, major museum collections | For artworks, artists |
| **Math** | Standard textbooks, Wolfram Alpha | For formulas, proofs |
| **Current Events** | AP, Reuters, major news archives | For events (with dates) |

### Subject-Specific Canons

These define "what's important" in each domain:

**Literature:**
- Great Books lists
- Norton Anthology tables of contents
- Common Core reading lists (for HS level appropriateness)
- Newbery/Caldecott winners (for younger levels)

**History:**
- AP US History curriculum framework
- AP World History curriculum framework
- State history standards (for regional content)

**Science:**
- NGSS standards (Next Generation Science Standards)
- AP Science curriculum frameworks
- NSB category specifications

**Fine Arts:**
- AP Art History image list
- Major museum permanent collections
- Standard music history textbook topics

---

## DATA COLLECTION INSTRUCTIONS

### Phase 1: Quiz Bowl Content (Largest Available Pool)

**Task:** Collect publicly released Quiz Bowl questions from legitimate sources.

**Steps:**
1. Download packets from quizbowlpackets.com that are:
   - Marked as released/public
   - From 2015 or later (for freshness)
   - From established tournaments (NAQT, ACF, PACE, state championships)

2. For each packet, record:
   - Source tournament and year
   - License/release status
   - Difficulty level
   - Categories covered

3. Parse questions into structured format:
   - Tossup text (with power mark position if present)
   - Answer (with acceptable alternates)
   - Category and subcategory
   - Source attribution

4. Priority categories for coverage:
   - Literature (20%)
   - History (20%)
   - Science (20%)
   - Fine Arts (15%)
   - Social Science/Philosophy/Religion (10%)
   - Geography (10%)
   - Other (5%)

**Target:** 10,000+ questions with verified licensing

---

### Phase 2: Science Bowl Content

**Task:** Collect official Science Bowl questions.

**Steps:**
1. Download all available DOE sample sets
2. Parse into structured format:
   - Question text
   - Answer
   - Category (BIOLOGY, CHEMISTRY, PHYSICS, MATH, EARTH SCIENCE, ENERGY)
   - Format (tossup vs bonus, multiple choice vs short answer)
   - Level (middle school vs high school)

3. Supplement with:
   - State Science Olympiad sample materials (where publicly available)
   - Science competition archives from educational organizations

**Target:** 3,000+ questions with DOE/official provenance

---

### Phase 3: Knowledge Bowl Adaptation

**Task:** Adapt Quiz Bowl content for Knowledge Bowl format and pursue official KB sources.

**Steps:**
1. Transform compatible Quiz Bowl questions:
   - Shorten pyramidal questions for KB's shorter format
   - Convert to team-answerable format
   - Adjust difficulty for KB population

2. Reach out to state coordinators:
   - Request access to retired question sets
   - Propose educational licensing arrangement
   - Offer attribution in return for access

3. Create original content:
   - Use Tier 3 reference sources
   - Focus on gaps in adapted content
   - Emphasize KB-specific topics (state history, etc.)

**Target:** 5,000+ KB-appropriate questions

---

## OUTPUT FORMAT

For each collected question, record:

```json
{
  "id": "unique-identifier",
  "text": "Full question text",
  "answer": {
    "primary": "Main acceptable answer",
    "alternates": ["Other acceptable answers"],
    "prompt": ["Answers that require 'be more specific'"]
  },
  "category": "Primary category",
  "subcategory": "Specific subcategory",
  "difficulty": "middle_school | easy_hs | regular_hs | hard_hs | collegiate",
  "source": {
    "name": "Tournament or source name",
    "year": 2024,
    "license": "CC BY-SA | public_domain | released | etc",
    "url": "Link to original if available"
  },
  "format": {
    "original": "quiz_bowl_tossup | science_bowl_tossup | kb_oral | etc",
    "pyramidal": true,
    "power_mark_index": 245
  },
  "verification": {
    "fact_checked": false,
    "checker": null,
    "date": null
  }
}
```

---

## SOURCES TO AVOID (For Now)

These may become viable later with proper validation, but avoid for initial dataset:

| Source Type | Risk | Future Possibility |
|-------------|------|-------------------|
| **Scraped web content** | Accuracy unknown, no provenance | After validation pipeline exists |
| **AI-generated without review** | May contain errors | After human review process |
| **Unlicensed commercial content** | Legal risk | After licensing agreements |
| **User-contributed without vetting** | Quality varies | After community review system |
| **Foreign language translations** | Translation quality | After native speaker review |
| **Very old content (pre-2000)** | May be factually outdated | After freshness verification |

---

## SUCCESS CRITERIA

### Minimum Viable Dataset

| Competition | Questions | Categories | Difficulty Levels |
|-------------|-----------|------------|-------------------|
| Quiz Bowl | 10,000 | All major (Lit, Hist, Sci, Arts, etc.) | MS through Nationals |
| Science Bowl | 3,000 | All 6 categories | MS and HS |
| Knowledge Bowl | 5,000 | All KB categories | JH through Varsity |

### Quality Gates

Before any question enters the training set:
- [ ] Source documented and legitimate
- [ ] License permits educational use
- [ ] Answer verified against authoritative reference
- [ ] No known factual errors
- [ ] Appropriate difficulty level assigned
- [ ] Category/subcategory correctly tagged

---

## NEXT STEPS

1. **Immediate:** Begin Quiz Bowl packet collection from quizbowlpackets.com
2. **Immediate:** Download all DOE Science Bowl sample materials
3. **Week 1:** Parse and structure collected content
4. **Week 2:** Begin outreach to KB state coordinators
5. **Ongoing:** Fact-check and verify collected content
6. **Future:** Establish licensing relationship with Question Authorities

---

*This document provides instructions for legitimate data acquisition. All sources should be verified for licensing compliance before commercial use.*
