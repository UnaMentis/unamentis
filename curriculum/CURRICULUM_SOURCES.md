# Curriculum Sources Catalog

UnaMentis integrates with open educational resources from around the world. All sources use Creative Commons or equivalent open licenses that allow adaptation for voice-based tutoring.

---

## Quick Reference

| Source | Region | Level | Subjects | License | Status |
|--------|--------|-------|----------|---------|--------|
| [MIT OpenCourseWare](#mit-opencourseware) | US | University | All | CC BY-NC-SA | Complete |
| [CK-12 FlexBooks](#ck-12-flexbooks) | US | K-12 | STEM, ELA | CC BY-NC | Complete |
| [OpenStax](#openstax) | US | University | Core subjects | CC BY | Planned |
| [Fast.ai](#fastai) | US | University+ | AI/ML | Apache 2.0 | Spec Ready |
| [Stanford SEE](#stanford-engineering-everywhere) | US | University | Engineering | CC BY-NC-SA | Spec Ready |
| [Saylor Academy](#saylor-academy) | US | University | All | CC BY | Planned |
| [MERLOT](#merlot) | US/Global | All | All | Various CC | Planned |
| [OpenLearn](#openlearn-open-university) | UK | University | All | CC BY-NC-SA | Planned |
| [BCcampus](#bccampus-opened) | Canada | University | All | CC BY | Planned |
| [NPTEL](#nptel) | India | University | Engineering | CC BY-SA | Planned |
| [OERu](#oeru) | NZ/Global | University | Core | CC BY-SA | Research |
| [African Virtual University](#african-virtual-university) | Africa | University | STEM, Education | CC BY | Research |

---

## United States

### MIT OpenCourseWare

<img src="https://ocw.mit.edu/static_assets/images/ocw_logo.svg" alt="MIT OCW" width="200"/>

| | |
|---|---|
| **Website** | https://ocw.mit.edu |
| **Content** | 2,500+ complete MIT courses |
| **Level** | Undergraduate, Graduate |
| **Subjects** | All disciplines |
| **License** | CC BY-NC-SA 4.0 |
| **Format** | HTML, PDF, Video |
| **Status** | **Importer Complete** |

MIT OpenCourseWare is a free, publicly accessible collection of materials from MIT courses. Includes lecture notes, problem sets, exams, video lectures, and more.

**Highlights:**
- Gold standard for university-level OER
- Complete course materials including solutions
- Strong STEM coverage
- Video lectures with transcripts

**Integration:** ZIP package download, IMS manifest parsing

---

### CK-12 FlexBooks

| | |
|---|---|
| **Website** | https://www.ck12.org |
| **Content** | 5,000+ FlexBooks and concepts |
| **Level** | K-12 (8th grade focus) |
| **Subjects** | Math, Science, ELA, Social Studies |
| **License** | CC BY-NC |
| **Format** | EPUB, PDF, HTML |
| **Status** | **Importer Complete** |

CK-12 is a nonprofit providing free, customizable K-12 textbooks and learning resources aligned to Common Core and state standards.

**Highlights:**
- Standards-aligned (CCSS, NGSS)
- Interactive practice problems
- Modular chapter/lesson structure
- Adaptive practice available

**Integration:** EPUB parsing, HTML extraction

---

### OpenStax

| | |
|---|---|
| **Website** | https://openstax.org |
| **Content** | 60+ peer-reviewed textbooks |
| **Level** | High school, University |
| **Subjects** | Core academic subjects |
| **License** | **CC BY 4.0** (most permissive) |
| **Format** | PDF, Web, CNXML |
| **Status** | Planned |

OpenStax provides free, peer-reviewed, openly-licensed textbooks. Published by Rice University with support from major foundations.

**Highlights:**
- Most permissive licensing (CC BY allows commercial use)
- Peer-reviewed, professionally edited
- Ancillary materials (test banks, slides)
- API available via GitHub

**Integration:** GitHub API, CNXML/OPENSTAX format

---

### Fast.ai

| | |
|---|---|
| **Website** | https://www.fast.ai |
| **Repository** | https://github.com/fastai/fastbook |
| **Content** | 4 complete courses |
| **Level** | University, Professional |
| **Subjects** | Deep Learning, AI/ML, NLP |
| **License** | **Apache 2.0** (very permissive) |
| **Format** | Jupyter Notebooks |
| **Status** | Spec Complete |

Fast.ai provides practical deep learning courses created by Jeremy Howard and Rachel Thomas. Known for top-down, hands-on teaching approach.

**Highlights:**
- Industry-leading AI/ML education
- Practical, code-first approach
- Apache license allows any use
- Active community

**Integration:** Jupyter notebook parsing, GitHub

---

### Stanford Engineering Everywhere

| | |
|---|---|
| **Website** | https://see.stanford.edu |
| **Content** | 10 complete Stanford courses |
| **Level** | University |
| **Subjects** | CS, AI/ML, Math, EE |
| **License** | CC BY-NC-SA 4.0 |
| **Format** | PDF, Video, Transcripts |
| **Status** | Spec Complete |

Stanford SEE provides complete Stanford engineering courses with video lectures, handouts, assignments, and exams.

**Highlights:**
- World-class instructors (Andrew Ng, Stephen Boyd)
- Complete course materials with solutions
- Video transcripts available
- Foundational CS and ML courses

**Integration:** ZIP download, transcript extraction

---

### Saylor Academy

| | |
|---|---|
| **Website** | https://www.saylor.org |
| **Content** | 317 college-level courses |
| **Level** | University |
| **Subjects** | All disciplines |
| **License** | **CC BY 4.0** |
| **Format** | Web, PDF |
| **Status** | Planned |

Saylor Academy offers free, self-paced courses with certificates of completion. Content curated from openly-licensed sources.

**Highlights:**
- Free certificates
- Credit-eligible at partner institutions
- CC BY allows any use
- Comprehensive course coverage

**Integration:** Web scraping, structured download

---

### MERLOT

| | |
|---|---|
| **Website** | https://www.merlot.org |
| **Content** | 100,000+ learning resources |
| **Level** | All levels |
| **Subjects** | All disciplines |
| **License** | Various (mostly CC) |
| **Format** | Various |
| **Status** | Planned |

MERLOT (Multimedia Educational Resource for Learning and Online Teaching) is a curated collection of free learning materials, peer-reviewed by educators.

**Highlights:**
- **REST API available** for integration
- Peer-reviewed quality ratings
- Largest OER aggregator
- Established since 1997

**Integration:** REST API

---

### LibreTexts

| | |
|---|---|
| **Website** | https://libretexts.org |
| **Content** | Comprehensive textbook library |
| **Level** | University |
| **Subjects** | STEM focus |
| **License** | Various CC |
| **Format** | Web (wiki-style) |
| **Status** | Research |

LibreTexts is a collaborative platform for creating and remixing open textbooks, with strong tools for customization.

**Highlights:**
- OER Remixer for customization
- Strong STEM coverage
- Interactive elements (H5P)
- Active community development

---

### Open Textbook Library

| | |
|---|---|
| **Website** | https://open.umn.edu/opentextbooks |
| **Content** | 1,760+ textbooks |
| **Level** | University |
| **Subjects** | All disciplines |
| **License** | Various CC |
| **Format** | Various |
| **Status** | Research |

University of Minnesota's catalog of open textbooks with faculty reviews and adoption tracking.

---

## United Kingdom

### OpenLearn (Open University)

| | |
|---|---|
| **Website** | https://www.open.edu/openlearn |
| **Content** | 900+ courses, 10,000+ study hours |
| **Level** | University |
| **Subjects** | All disciplines |
| **License** | CC BY-NC-SA 4.0 |
| **Format** | HTML, PDF, ePub, IMS CC |
| **Status** | Planned |

The Open University's free learning platform, the UK's largest provider of open educational resources.

**Highlights:**
- UK's premier OER source
- Derived from paid OU courses
- Badges and certificates available
- IMS Common Cartridge export

**Integration:** IMS Common Cartridge, RSS feeds

---

### University of Oxford OpenSpires

| | |
|---|---|
| **Website** | https://podcasts.ox.ac.uk |
| **Content** | Thousands of lectures |
| **Level** | University, Public |
| **Subjects** | Humanities, Sciences |
| **License** | CC BY-NC-SA 2.0 UK |
| **Format** | Audio, Video (podcast) |
| **Status** | Research |

Oxford's open podcast collection featuring lectures, seminars, and public talks.

---

## Canada

### BCcampus OpenEd

| | |
|---|---|
| **Website** | https://open.bccampus.ca |
| **Textbooks** | https://opentextbc.ca |
| **Content** | 300+ open textbooks |
| **Level** | University |
| **Subjects** | All disciplines |
| **License** | **CC BY 4.0** |
| **Format** | Pressbooks (Web, PDF, ePub) |
| **Status** | Planned |

British Columbia's open textbook initiative, funded by the BC government.

**Highlights:**
- Most permissive licensing (CC BY)
- 90% of BC institutions have adopted
- Multiple export formats
- Government-funded quality

**Integration:** Pressbooks export, multiple formats

---

### eCampusOntario

| | |
|---|---|
| **Website** | https://openlibrary.ecampusontario.ca |
| **Content** | 250+ resources |
| **Level** | University |
| **Subjects** | All disciplines |
| **License** | CC BY 4.0 |
| **Format** | Pressbooks |
| **Status** | Research |

Ontario's open educational resource library, partnered with BCcampus.

---

## India

### NPTEL

| | |
|---|---|
| **Website** | https://nptel.ac.in |
| **Portal** | https://swayam.gov.in |
| **Content** | 2,700+ courses |
| **Level** | University |
| **Subjects** | Engineering, Sciences, Management |
| **License** | **CC BY-SA** |
| **Format** | Video, PDF, Web |
| **Status** | Planned |

National Programme on Technology Enhanced Learning, a collaboration of IITs and IISc.

**Highlights:**
- World's largest engineering OER
- IIT-quality instruction
- CC BY-SA allows commercial use
- 819 million+ YouTube views

**Integration:** YouTube API, web scraping

---

## Australia & New Zealand

### OERu

| | |
|---|---|
| **Website** | https://oeru.org |
| **Content** | Full degree pathways |
| **Level** | University |
| **Subjects** | Core academic |
| **License** | CC BY or CC BY-SA |
| **Format** | Open formats |
| **Status** | Research |

International network providing free pathways to formal university credentials.

**Highlights:**
- Credit-bearing courses
- Strictly OER-compliant
- Multiple accredited partners
- Open file formats only

---

### CAUL OER Collective

| | |
|---|---|
| **Website** | https://caul.libguides.com/oer-collective-publishing-workflow |
| **Content** | Growing collection |
| **Level** | University |
| **Subjects** | Various |
| **License** | CC BY |
| **Format** | Pressbooks |
| **Status** | Research |

Council of Australian University Librarians' open textbook initiative.

---

## Europe

### Wikiwijs (Netherlands)

| | |
|---|---|
| **Website** | https://www.wikiwijs.nl |
| **Content** | 26,000+ lessons |
| **Level** | All levels |
| **Subjects** | All |
| **License** | CC BY or CC BY-SA |
| **Format** | Web |
| **Status** | Research |

Dutch government-funded OER platform for all educational levels.

**Note:** Primarily Dutch language, limited English content.

---

### OERSI (Germany)

| | |
|---|---|
| **Website** | https://oersi.org |
| **Content** | Search index |
| **Level** | University |
| **Subjects** | Various |
| **License** | Various CC |
| **Format** | Various |
| **Status** | Research |

German national OER search index for higher education.

**Note:** Primarily German language.

---

## Africa

### African Virtual University

| | |
|---|---|
| **Website** | https://oer.avu.org |
| **Content** | 1,335 modules |
| **Level** | University |
| **Subjects** | STEM, Teacher Education |
| **License** | CC BY 2.5 |
| **Format** | Web, PDF |
| **Status** | Research |

Pan-African intergovernmental organization providing OER in English, French, and Portuguese.

**Highlights:**
- Three-language support
- Africa-contextualized content
- Strong teacher education
- Permissive licensing

---

## Asia

### Japan OCW Consortium

| | |
|---|---|
| **Website** | https://www.jocw.jp |
| **Content** | Multiple university courses |
| **Level** | University |
| **Subjects** | Various |
| **License** | CC BY-NC-SA |
| **Format** | Various |
| **Status** | Research |

**Note:** Primarily Japanese language, some English content.

---

### China Open Resources for Education

| | |
|---|---|
| **Website** | http://www.core.org.cn |
| **Content** | Translations + original |
| **Level** | University |
| **Subjects** | Various |
| **License** | Various |
| **Format** | Various |
| **Status** | Not Planned |

**Note:** Chinese language focus.

---

## Global Aggregators

### OER Commons

| | |
|---|---|
| **Website** | https://oercommons.org |
| **Content** | Largest OER aggregator |
| **Metadata** | Dublin Core, IEEE LOM |

Comprehensive search across multiple OER providers.

---

### UNESCO OER Dynamic Coalition

| | |
|---|---|
| **Website** | https://oerdynamiccoalition.org |

International coordination for OER policy and development.

---

## License Quick Guide

| License | Commercial | Derivatives | Share-Alike | Use Case |
|---------|------------|-------------|-------------|----------|
| **CC0** | Yes | Yes | No | Public domain |
| **CC BY** | Yes | Yes | No | Maximum freedom |
| **CC BY-SA** | Yes | Yes | Required | Copyleft |
| **CC BY-NC** | No | Yes | No | Non-profit only |
| **CC BY-NC-SA** | No | Yes | Required | Non-profit, copyleft |
| **Apache 2.0** | Yes | Yes | No | Software-style |

**UnaMentis Compatibility:**
- All licenses above are compatible (we can create derivatives)
- CC BY-ND and CC BY-NC-ND are NOT compatible (no derivatives allowed)

---

## Attribution

UnaMentis provides full attribution for all curriculum content:
- Original creator/institution credited
- License clearly displayed
- Link to source material
- Indication of any modifications

---

*For detailed integration specifications, see the [importers/](importers/) directory.*
