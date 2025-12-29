# Global Open Educational Resources Landscape

This document provides a comprehensive analysis of open educational resources (OER) available globally with compatible licensing (Creative Commons or similar open licenses) for integration into UnaMentis curriculum importers.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Licensing Overview](#licensing-overview)
3. [United Kingdom & Ireland](#united-kingdom--ireland)
4. [European Union](#european-union)
5. [Canada](#canada)
6. [Australia & New Zealand](#australia--new-zealand)
7. [Asia](#asia)
8. [Africa](#africa)
9. [United States (Reference)](#united-states-reference)
10. [Global Aggregators](#global-aggregators)
11. [Integration Methods](#integration-methods)
12. [Priority Recommendations](#priority-recommendations)

---

## Executive Summary

This landscape analysis identifies **40+ open educational resource providers** globally that offer content under Creative Commons or equivalent open licenses. The focus is on:

- English-language content (primary)
- Compatible licensing (CC BY, CC BY-SA, CC BY-NC-SA, CC0)
- Technical integration possibilities (APIs, bulk download, standard formats)
- Quality and breadth of content

**Key Finding:** While the US dominates OER production (MIT OCW, OpenStax, Khan Academy), there are substantial high-quality sources in the UK, EU, Canada, Australia, and India that are underutilized. Many of these offer more permissive licensing than US sources.

---

## Licensing Overview

### Compatible Licenses (Ranked by Openness)

| License | Commercial Use | Derivatives | ShareAlike | Suitable |
|---------|---------------|-------------|------------|----------|
| **CC0 (Public Domain)** | Yes | Yes | No | Ideal |
| **CC BY 4.0** | Yes | Yes | No | Ideal |
| **CC BY-SA 4.0** | Yes | Yes | Yes | Good |
| **CC BY-NC 4.0** | No | Yes | No | Acceptable |
| **CC BY-NC-SA 4.0** | No | Yes | Yes | Acceptable |
| CC BY-ND | Yes | No | No | Not Suitable |
| CC BY-NC-ND | No | No | No | Not Suitable |

**UnaMentis Position:** As an open-source educational project, we can use NC (NonCommercial) licensed content. ND (NoDerivatives) licenses are NOT suitable as we need to transform content for voice delivery.

### Attribution Requirements

All Creative Commons licenses require attribution. UnaMentis must:
1. Credit the original creator/institution
2. Provide a link to the license
3. Indicate if changes were made
4. Link to the original source where practical

---

## United Kingdom & Ireland

### Tier 1: Primary Sources

#### OpenLearn (The Open University)
- **URL:** https://www.open.edu/openlearn/
- **License:** CC BY-NC-SA 4.0
- **Content:** 900+ free courses, 10,000+ study hours, 35,000 pages
- **Subjects:** All disciplines, university-level
- **Languages:** English
- **Integration:**
  - Download formats: Word, PDF, ePub, IMS Common Cartridge
  - RSS feeds available
  - No public API, but CC export supported
- **Terms of Use:** https://www.open.edu/openlearn/about-openlearn/frequently-asked-questions-on-openlearn
- **Notes:** UK's largest OER provider. Content derived from OU's paid courses. High quality, well-structured.

#### OpenLearn Create
- **URL:** https://www.open.edu/openlearncreate/
- **License:** CC BY-NC-SA (varies by content)
- **Content:** 450+ courses from various organizations
- **Platform:** Moodle-based, supports Open Badges
- **Integration:** Moodle export formats, H5P support
- **Notes:** User-contributed content, quality varies. Good for community-created materials.

#### University of Oxford - OpenSpires
- **URL:** https://podcasts.ox.ac.uk/open
- **License:** CC BY-NC-SA 2.0 UK
- **Content:** Thousands of audio/video lectures
- **Subjects:** All disciplines, emphasis on humanities
- **Integration:** Podcast feeds, direct download
- **Terms:** https://podcasts.ox.ac.uk/open/faq
- **Notes:** High-prestige content, excellent for advanced topics. Includes Great Writers Inspire, WWI Centenary resources.

#### JISC / UK OER Programme
- **URL:** https://www.jisc.ac.uk/
- **Content:** Aggregator of UK higher education OER
- **Notes:** Funded UK OER development 2009-2012. Legacy resources still available through various UK universities.

### Tier 2: Secondary Sources

#### FutureLearn (Limited OER)
- **URL:** https://www.futurelearn.com/
- **License:** CC BY-NC-ND 3.0 (restrictive)
- **Warning:** Most content is NOT openly licensed. Only specific courses marked as CC are usable.
- **Terms:** https://www.futurelearn.com/info/terms
- **Notes:** NOT recommended due to ND restriction preventing adaptation for voice delivery.

#### University of Edinburgh - Open.Ed
- **URL:** https://open.ed.ac.uk/
- **License:** CC BY (varies)
- **Content:** OER guides and selected course materials
- **Integration:** Web-based, manual download
- **Notes:** Good guidance documents but limited course content.

---

## European Union

### EU-Wide Initiatives

#### OERSI (German OER Search Index)
- **URL:** https://oersi.org/
- **License:** Aggregates CC-licensed content
- **Content:** Search index for German higher education OER
- **Languages:** Primarily German, some English
- **Integration:** Search API available
- **Notes:** Germany's national OER strategy explicitly endorses CC BY, CC BY-SA, CC0.

#### Una Europa OER Toolkit
- **URL:** https://www.una-europa.eu/knowledge-hub/toolkits/oer/guidance
- **License:** CC BY recommended
- **Content:** Guidelines and shared resources from European university alliance
- **Notes:** Policy framework rather than content repository.

### Netherlands

#### Wikiwijs
- **URL:** https://www.wikiwijs.nl/
- **License:** CC BY or CC BY-SA
- **Content:** 26,000+ published lessons
- **Scope:** Primary through higher education
- **Languages:** Dutch (primary), some English
- **Platform:** Connexions-based
- **Integration:**
  - Open Onderwijs API: https://openstate.eu/en/projects/open-education/open-education-api/
  - Standard export formats
- **Terms:** https://www.wikiwijs.nl/
- **Notes:** Government-funded, high quality. Pioneer in national OER policy.

### Germany

#### Hamburg Open Online University (HOOU)
- **URL:** https://www.hoou.de/
- **License:** CC BY-SA (standard)
- **Content:** Courses in computer science, philosophy, psychology, social sciences, technology
- **Languages:** German, some English
- **Integration:** Web-based
- **Notes:** Multi-university collaboration in Hamburg.

#### TIB AV-Portal
- **URL:** https://av.tib.eu/
- **License:** Various CC licenses
- **Content:** Scientific/technical videos
- **Languages:** German and English
- **Notes:** Technical Information Library Hannover. Strong in STEM.

### Spain

#### Procomun
- **URL:** https://procomun.educalab.es/
- **License:** Creative Commons
- **Content:** 74,000+ resources, 300 learning itineraries, 100,000 digital assets
- **Languages:** Spanish (primary)
- **Standards:** LOM-ES metadata, Linked Open Data compatible
- **Integration:** Semantic web, LOD Cloud connected
- **Notes:** Government-funded, uses eXeLearning. Limited English content.

### France

#### France Universite Numerique (FUN)
- **URL:** https://www.fun-mooc.fr/
- **License:** Varies by course
- **Languages:** French (primary), some English
- **Notes:** MOOC platform, not all content openly licensed. Check individual courses.

### Norway

#### NDLA (Norwegian Digital Learning Arena)
- **URL:** https://ndla.no/
- **License:** CC BY-SA
- **Content:** Complete upper secondary curriculum
- **Languages:** Norwegian (primary)
- **Notes:** Government-funded, comprehensive but Norwegian-language focused.

---

## Canada

### Tier 1: Primary Sources

#### BCcampus OpenEd
- **URL:** https://open.bccampus.ca/
- **Textbook Collection:** https://opentextbc.ca/
- **License:** CC BY 4.0 (standard)
- **Content:** 300+ open textbooks
- **Subjects:** All disciplines, higher education focus
- **Languages:** English, some French
- **Integration:**
  - Pressbooks platform
  - Multiple download formats (PDF, ePub, web, editable)
  - No public API, but bulk download available
- **Terms:** https://open.bccampus.ca/what-is-open-education/what-are-open-textbooks/
- **Notes:** **Highly recommended.** BC government funded, 90% of BC post-secondary institutions have adopted. Very permissive CC BY licensing.

#### eCampusOntario Open Library
- **URL:** https://openlibrary.ecampusontario.ca/
- **License:** CC BY 4.0 (primary)
- **Content:** 250+ open textbooks and resources
- **Languages:** English, French
- **Integration:** Pressbooks platform, standard formats
- **Notes:** Partnership with BCcampus. Ontario government funded.

#### eCampusOntario H5P Studio
- **URL:** https://h5pstudio.ecampusontario.ca/
- **License:** CC BY
- **Content:** Interactive learning objects
- **Integration:** H5P standard, LTI compatible
- **Notes:** Excellent for interactive content.

### Tier 2: Secondary Sources

#### Athabasca University
- **URL:** https://www.athabascau.ca/
- **License:** Varies
- **Notes:** Canada's open university. Some OER available but not systematically.

---

## Australia & New Zealand

### Australia

#### CAUL OER Collective
- **URL:** https://caul.libguides.com/oer-collective-publishing-workflow/home
- **License:** CC BY (recommended)
- **Content:** Open textbooks from Australian universities
- **Integration:** Pressbooks platform
- **Notes:** Council of Australian University Librarians initiative. Growing collection.

#### University of Southern Queensland OER
- **URL:** Various via OER Commons
- **Content:** Notable for Australian-context adaptations
- **Examples:**
  - The Australian Handbook for Careers in Psychological Science (adapted from Canadian version)
  - Reconciliation and intercultural education resources
- **Notes:** Leaders in contextualization of international OER for Australian needs.

### New Zealand

#### OERu (OER Universitas)
- **URL:** https://oeru.org/
- **License:** CC BY or CC BY-SA (strictly)
- **Content:** Full university courses with credit pathways
- **Languages:** English
- **Integration:** Open file formats, open-source delivery
- **Accreditation:** Credentials from recognized institutions
- **Notes:** **Highly recommended.** International network providing free pathways to formal credentials. All content strictly OER-compliant.

#### OER NZ
- **URL:** Via New Zealand Ministry of Education
- **License:** NZGOAL framework (CC recommended)
- **Content:** K-12 educational resources
- **Notes:** Government policy requires CC licensing for publicly funded resources.

#### Otago Polytechnic
- **URL:** https://www.op.ac.nz/
- **License:** CC BY (institutional default)
- **Notes:** First tertiary institution worldwide to adopt default CC BY policy. Pioneer in open education.

---

## Asia

### India

#### NPTEL (National Programme on Technology Enhanced Learning)
- **URL:** https://nptel.ac.in/
- **SWAYAM Portal:** https://swayam.gov.in/
- **License:** **CC BY-SA** (changed from CC BY-SA-NC in 2014)
- **Content:**
  - 2,700+ courses
  - 471 million+ web views
  - 819 million+ YouTube views
- **Subjects:** Engineering, sciences, management (IIT-level)
- **Languages:** English (primary), Hindi
- **Integration:**
  - YouTube channel
  - Web portal
  - No documented public API
- **Terms:** https://nptel.ac.in/
- **Notes:** **Highly recommended.** World's largest engineering OER repository. IIT quality. Very permissive CC BY-SA allows commercial use.

### Japan

#### Japan OCW Consortium (JOCW)
- **URL:** https://www.jocw.jp/
- **License:** CC BY-NC-SA (typical)
- **Content:** University course materials from Japanese institutions
- **Languages:** Japanese (primary), some English
- **Notes:** Based on MIT OCW model. Limited English content but growing.

#### University of Tokyo OCW
- **URL:** https://ocw.u-tokyo.ac.jp/
- **License:** CC BY-NC-SA
- **Languages:** Japanese, some English
- **Notes:** Prestige institution, high-quality STEM content.

### South Korea

#### KOCW (Korea Open CourseWare)
- **URL:** http://www.kocw.net/
- **License:** Varies
- **Languages:** Korean (primary)
- **Notes:** Government-backed. Limited English content.

### China

#### China Open Resources for Education (CORE)
- **URL:** http://www.core.org.cn/
- **License:** Varies
- **Content:** Translations of MIT OCW and original content
- **Languages:** Chinese (primary)
- **Notes:** Established 2003. Focus on making international OER accessible in Chinese.

---

## Africa

### Pan-African

#### African Virtual University (AVU)
- **URL:** https://oer.avu.org/
- **OER Commons Collection:** https://oercommons.org/curated-collections/837
- **License:** CC BY 2.5
- **Content:**
  - 1,335 OER modules
  - 219 high-quality course modules
- **Subjects:** Mathematics, Physics, Chemistry, Biology, ICT, Teacher Education
- **Languages:** English, French, Portuguese
- **Integration:** OER Commons integration, web download
- **Notes:** **Recommended.** Pan-African intergovernmental organization. Strong teacher education focus. Three-language support.

#### OER Africa (Saide)
- **URL:** https://www.oerafrica.org/
- **License:** CC (various)
- **Content:** Curated African OER, guides, and tools
- **Funding:** Hewlett Foundation
- **Notes:** Capacity building focus. Good source for Africa-contextualized content.

### South Africa

#### University of Cape Town OpenContent
- **URL:** http://opencontent.uct.ac.za/
- **License:** CC BY (typical)
- **Notes:** Leader in African OER movement.

---

## United States (Reference)

US sources already implemented or planned for UnaMentis:

### Implemented

| Source | Status | License |
|--------|--------|---------|
| MIT OpenCourseWare | Complete | CC BY-NC-SA |
| CK-12 FlexBooks | Complete | CC BY-NC |

### Planned/Specified

| Source | Status | License | Notes |
|--------|--------|---------|-------|
| OpenStax | Spec complete | CC BY 4.0 | API available via GitHub |
| Fast.ai | Spec complete | Apache 2.0 | Jupyter notebooks |
| Saylor Academy | Not started | CC BY 4.0 | 317 courses |

### Other Notable US Sources

#### LibreTexts
- **URL:** https://libretexts.org/
- **License:** CC (varies, mostly CC BY or CC BY-NC-SA)
- **Content:** Comprehensive STEM textbooks
- **Integration:** OER Remixer tool, web-based
- **Notes:** Excellent for science and math. Strong remixing capabilities.

#### Open Textbook Library (University of Minnesota)
- **URL:** https://open.umn.edu/opentextbooks
- **License:** CC (various)
- **Content:** 1,760+ peer-reviewed textbooks
- **Notes:** Referatory pointing to textbooks from multiple publishers.

#### MERLOT
- **URL:** https://www.merlot.org/
- **License:** Various
- **Content:** 100,000+ learning resources
- **Integration:** **REST API available**
  - API Docs: http://info.merlot.org/merlothelp/index.htm
  - Supports search, collections, contributions
- **Notes:** Oldest OER repository (1997). API makes it attractive for integration.

---

## Global Aggregators

### OER Commons
- **URL:** https://oercommons.org/
- **License:** Aggregates multiple licenses
- **Content:** Largest OER aggregator
- **Metadata:** Dublin Core, IEEE LOM, RSS
- **Integration:**
  - Feeds in Dublin Core, LOM, RSS
  - Harvesting targets available
  - No public REST API documented
- **Notes:** **Recommended as discovery tool.** Can find content from many sources. Run by ISKME.

### UNESCO OER Dynamic Coalition
- **URL:** https://www.oerdynamiccoalition.org/
- **Content:** Policy resources, member directory
- **Notes:** Not a content repository but valuable for finding national OER initiatives.

### Mason OER Metafinder (MOM)
- **URL:** https://oer.deepwebaccess.com/oer/desktop/en/search.html
- **Content:** Federated search across 22 OER sources
- **Notes:** Good for discovery, searches multiple repositories simultaneously.

---

## Integration Methods

### By Access Method

| Method | Sources | Complexity | Notes |
|--------|---------|------------|-------|
| **REST API** | MERLOT, OpenStax (GitHub) | Medium | Best for automation |
| **RSS/Atom Feeds** | OpenLearn, OER Commons | Low | Good for updates |
| **IMS Common Cartridge** | OpenLearn, BCcampus | Medium | LMS-standard format |
| **Bulk Download** | BCcampus, NPTEL (YouTube) | Low | Manual but comprehensive |
| **Web Scraping** | Most sources | High | Last resort, check ToS |

### Recommended Integration Priority

1. **MERLOT API** - Provides access to 100K+ resources with documented API
2. **BCcampus/Pressbooks** - Permissive licensing, standard formats
3. **OpenLearn IMS CC** - High quality, established format
4. **NPTEL YouTube** - Massive engineering content, YouTube API
5. **OER Commons feeds** - Aggregator access to many sources

### Technical Standards

| Standard | Purpose | Adoption |
|----------|---------|----------|
| **IMS Common Cartridge** | Course packaging | High |
| **IEEE LOM** | Learning object metadata | High |
| **Dublin Core** | General metadata | Universal |
| **SCORM** | LMS interoperability | Medium |
| **LTI** | Tool integration | High |
| **H5P** | Interactive content | Growing |

---

## Priority Recommendations

### Immediate Implementation (High Value, Good Integration)

1. **BCcampus OpenEd** (Canada)
   - Why: CC BY 4.0, Pressbooks format, 300+ textbooks
   - Integration: Pressbooks export, multiple formats
   - Effort: Medium

2. **NPTEL** (India)
   - Why: CC BY-SA, massive STEM content, English
   - Integration: YouTube API, web scraping
   - Effort: Medium

3. **OpenLearn** (UK)
   - Why: CC BY-NC-SA, 900+ courses, established
   - Integration: IMS Common Cartridge, RSS
   - Effort: Medium

4. **MERLOT** (Global)
   - Why: REST API, 100K+ resources
   - Integration: Documented API
   - Effort: Low-Medium

### Medium-Term Implementation

5. **OERu** (New Zealand/Global)
   - Why: Strictly CC BY/BY-SA, credit pathways
   - Integration: Open formats
   - Effort: Medium

6. **African Virtual University**
   - Why: CC BY, multilingual, underserved region
   - Integration: OER Commons, web
   - Effort: Medium

7. **Wikiwijs** (Netherlands)
   - Why: CC BY, government-backed, API available
   - Integration: Open Onderwijs API
   - Effort: Medium-High (Dutch content focus)

### Research/Monitor

8. **LibreTexts** - Excellent remixing but no API
9. **OERSI** (Germany) - Growing English content
10. **Japan OCW** - Limited English but high quality

---

## Compliance Checklist

When implementing any new source:

- [ ] Verify license allows derivatives (no ND)
- [ ] Document license type in curriculum metadata
- [ ] Implement attribution in UMCF format
- [ ] Preserve original source links
- [ ] Track license version (CC 3.0 vs 4.0)
- [ ] Check for NC restrictions if commercial use planned
- [ ] Verify API/scraping is permitted in ToS
- [ ] Test export formats for UMCF compatibility

---

## References

### Official Documentation

- [Creative Commons License Chooser](https://creativecommons.org/choose/)
- [UNESCO OER Recommendation 2019](https://www.unesco.org/en/open-educational-resources)
- [Cape Town Open Education Declaration](https://www.capetowndeclaration.org/)

### Research

- [Open Educational Resources: An Asian Perspective (COL)](https://www.oerknowledgecloud.org/archive/pub_PS_OER_Asia_web.pdf)
- [OER in Continuing Adult Education: German-Speaking Area](https://slejournal.springeropen.com/articles/10.1186/s40561-019-0111-4)

---

## Document History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-29 | 1.0 | Initial comprehensive analysis |

---

*This document should be updated quarterly as the OER landscape evolves rapidly.*
