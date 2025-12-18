# Fast.ai Notebook Importer Specification

**Version:** 1.0.0
**Status:** Draft
**Date:** 2025-12-17
**Target Audience:** Collegiate / Self-Learner (AI/ML Focus)

---

## Table of Contents

1. [Overview](#overview)
2. [Fast.ai Platform Analysis](#fastai-platform-analysis)
3. [Supported Formats](#supported-formats)
4. [Data Mapping](#data-mapping)
5. [Implementation Specification](#implementation-specification)
6. [Code Handling](#code-handling)
7. [Content Extraction](#content-extraction)
8. [Assessment Generation](#assessment-generation)
9. [Error Handling](#error-handling)
10. [Testing Strategy](#testing-strategy)

---

## Overview

The Fast.ai importer converts Fast.ai course materials (Jupyter notebooks) into VLCF format for use with VoiceLearn's conversational AI tutoring system. Fast.ai is a leading AI/ML education platform known for its practical, top-down teaching approach and high-quality free courses.

### Why Fast.ai?

| Criterion | Assessment |
|-----------|------------|
| **License** | Apache 2.0 (permissive, commercial OK) |
| **Cost** | Free |
| **Quality** | Industry-leading, created by Jeremy Howard & Rachel Thomas |
| **Format** | Jupyter Notebooks (.ipynb) - structured, code-native |
| **AI/ML Coverage** | Deep Learning, NLP, Computer Vision, Tabular Data |
| **Pedagogy** | Top-down (practical first, theory later) - ideal for tutoring |
| **Community** | Large, active, well-documented |

### Import Scope

**In Scope:**
- Jupyter notebooks from fastai/fastbook repository
- Markdown cells (explanatory content)
- Code cells with outputs
- Embedded images (base64 or URL)
- fastai library examples
- Practical exercises and homework

**Out of Scope:**
- Video lectures (URL references only)
- Forum discussions
- Real-time notebook execution
- Student submissions

---

## Fast.ai Platform Analysis

### Course Structure

Fast.ai courses follow a consistent structure:

```
fastbook/
├── 01_intro.ipynb              # Chapter 1: Introduction
├── 02_production.ipynb         # Chapter 2: Production
├── 03_ethics.ipynb             # Chapter 3: Ethics
├── 04_mnist_basics.ipynb       # Chapter 4: MNIST Basics
├── 05_pet_breeds.ipynb         # Chapter 5: Pet Breeds
├── ...
├── clean/                      # Cleaned notebooks (no outputs)
├── images/                     # Referenced images
└── utils/                      # Helper utilities
```

### Notebook Cell Types

| Cell Type | Content | VLCF Mapping |
|-----------|---------|--------------|
| **Markdown** | Explanatory text, headings, lists | `transcript.segments[]` |
| **Code** | Python code, fastai library calls | `examples[].content` |
| **Output** | Execution results, visualizations | `examples[].output` |
| **Raw** | Metadata, configuration | Ignored or `extensions` |

### Course Offerings (Primary Targets)

| Course | Repository | Topics |
|--------|------------|--------|
| **Practical Deep Learning** | fastai/fastbook | CNNs, NLP, TabularData, Embeddings |
| **Deep Learning from Foundations** | fastai/course22 | From-scratch implementations |
| **Computational Linear Algebra** | fastai/numerical-linear-algebra | Matrix math, PCA, SVD |
| **NLP with Transformers** | fastai/course-nlp | RNNs, Attention, BERT, GPT |

### Pedagogical Approach

Fast.ai uses a unique "whole game" approach:
1. **Start with complete, working code**
2. **Gradually dig into details**
3. **Repeat concepts with variations**
4. **Encourage experimentation**

This maps well to VLCF's `tutoringConfig.depth` levels:
- `surface`: Show working code, explain what it does
- `standard`: Explain why each part works
- `deep`: Dig into implementation details

---

## Supported Formats

### Primary: Jupyter Notebook (.ipynb)

Jupyter notebooks are the primary format because:
- Native format for all Fast.ai courses
- Structured JSON with clear cell boundaries
- Code and outputs preserved
- Markdown rendering built-in
- `nbformat` library handles parsing

### Secondary: Markdown (.md)

Some supplementary content in markdown:
- README files
- Supplementary explanations
- Course guides

### Content Sources

| Source | URL | Notes |
|--------|-----|-------|
| **fastbook** | github.com/fastai/fastbook | Main book notebooks |
| **course-v5** | github.com/fastai/course-v5 | Video course materials |
| **nbdev** | github.com/fastai/nbdev | Library documentation |

---

## Data Mapping

### Metadata Mapping

| Jupyter Element | VLCF Field | Notes |
|-----------------|------------|-------|
| `metadata.title` | `title` | Notebook title |
| `metadata.authors` | `lifecycle.contributors[]` | Authors |
| File path | `id.value` | Unique identifier |
| First markdown cell | `description` | Course overview |
| `metadata.kernelspec` | `metadata.extensions.kernelspec` | Python version |

### Content Hierarchy Mapping

| Notebook Element | VLCF Type | Detection Method |
|------------------|-----------|------------------|
| Notebook file | Root curriculum or `module` | File boundary |
| H1 heading (# ) | `module` | Markdown parsing |
| H2 heading (## ) | `topic` | Markdown parsing |
| H3+ heading | `topic` (child) | Markdown parsing |
| Markdown cell | `transcript.segments[]` | Cell type |
| Code cell | `examples[]` | Cell type |

### Code Example Mapping

| Code Element | VLCF Field | Notes |
|--------------|------------|-------|
| Code cell source | `examples[].content` | Python code |
| Cell output | `examples[].output` | Execution result |
| Output images | `examples[].visualization` | Base64 or URL |
| Library imports | `prerequisites[]` | Inferred dependencies |

### Assessment Mapping

Fast.ai doesn't have formal quizzes, but we can infer assessments from:

| Pattern | VLCF Assessment | Example |
|---------|-----------------|---------|
| "**Questionnaire**" section | Multiple `choice` | "What does a CNN do?" |
| `#hide` comment questions | `text-entry` | "Complete this function" |
| "Try it yourself" prompts | `self-assessment` | "Modify the code above" |
| Exercise cells | `text-entry` | Code completion |

---

## Implementation Specification

### Module Structure

```python
vlcf_importer/
└── importers/
    └── fastai/
        ├── __init__.py
        ├── importer.py           # Main FastaiImporter class
        ├── notebook_parser.py    # Jupyter parsing logic
        ├── code_extractor.py     # Code cell processing
        ├── markdown_parser.py    # Markdown to transcript
        ├── assessment_detector.py # Questionnaire extraction
        └── models.py             # Fast.ai-specific data models
```

### FastaiImporter Class

```python
from vlcf_importer.core.base import CurriculumImporter, ValidationResult
from vlcf_importer.core.models import CurriculumData
from typing import Dict, Any, List, Optional
import json

class FastaiImporter(CurriculumImporter):
    """
    Importer for Fast.ai course materials (Jupyter notebooks).

    Converts fastbook and course notebooks to VLCF format,
    preserving code examples, outputs, and questionnaires.
    """

    name = "fastai"
    description = "Import Fast.ai Jupyter notebooks"
    file_extensions = [".ipynb"]

    # Fast.ai specific configuration
    DEFAULT_CONFIG = {
        "include_code_outputs": True,
        "include_images": True,
        "extract_questionnaires": True,
        "code_explanation_depth": "standard",  # surface, standard, deep
        "spoken_text_for_code": True,
        "max_code_lines_per_segment": 20,
        "collapse_long_outputs": True,
        "max_output_lines": 50,
    }

    def __init__(
        self,
        storage: "StorageBackend",
        config: Optional[Dict[str, Any]] = None,
        logger: Optional["Logger"] = None
    ):
        super().__init__(storage, config, logger)
        self.config = {**self.DEFAULT_CONFIG, **(config or {})}

    async def validate(self, content: bytes) -> ValidationResult:
        """
        Validate Jupyter notebook format.

        Checks:
        - Valid JSON structure
        - nbformat version compatibility
        - Required fields present
        - Fast.ai markers (optional)
        """
        errors = []
        warnings = []
        metadata = {}

        try:
            notebook = json.loads(content.decode('utf-8'))
        except json.JSONDecodeError as e:
            return ValidationResult(
                is_valid=False,
                errors=[f"Invalid JSON: {str(e)}"],
                format_version=None,
                metadata={}
            )

        # Check nbformat version
        nbformat = notebook.get("nbformat", 0)
        nbformat_minor = notebook.get("nbformat_minor", 0)
        metadata["nbformat"] = f"{nbformat}.{nbformat_minor}"

        if nbformat < 4:
            errors.append(f"Unsupported nbformat version: {nbformat} (need 4+)")

        # Check required fields
        if "cells" not in notebook:
            errors.append("Missing 'cells' array")
        elif len(notebook["cells"]) == 0:
            warnings.append("Notebook has no cells")

        # Check for Fast.ai markers
        nb_metadata = notebook.get("metadata", {})
        kernelspec = nb_metadata.get("kernelspec", {})
        metadata["kernel"] = kernelspec.get("display_name", "Unknown")

        # Look for fastai imports
        fastai_detected = False
        for cell in notebook.get("cells", []):
            if cell.get("cell_type") == "code":
                source = "".join(cell.get("source", []))
                if "fastai" in source or "fastbook" in source:
                    fastai_detected = True
                    break

        metadata["fastai_detected"] = fastai_detected
        if not fastai_detected:
            warnings.append("No fastai imports detected - may not be a Fast.ai notebook")

        # Count cells
        cells = notebook.get("cells", [])
        metadata["cell_count"] = len(cells)
        metadata["code_cells"] = len([c for c in cells if c.get("cell_type") == "code"])
        metadata["markdown_cells"] = len([c for c in cells if c.get("cell_type") == "markdown"])

        return ValidationResult(
            is_valid=len(errors) == 0,
            errors=errors,
            warnings=warnings,
            format_version=metadata["nbformat"],
            metadata=metadata
        )

    async def extract(self, content: bytes) -> Dict[str, Any]:
        """
        Extract raw notebook structure.

        Returns intermediate representation with:
        - Notebook metadata
        - Cell list with types
        - Code cells with outputs
        - Markdown cells
        - Detected headings
        """
        notebook = json.loads(content.decode('utf-8'))

        result = {
            "format": "jupyter",
            "metadata": notebook.get("metadata", {}),
            "nbformat": notebook.get("nbformat"),
            "cells": [],
            "headings": [],
            "questionnaires": [],
        }

        for i, cell in enumerate(notebook.get("cells", [])):
            cell_data = {
                "index": i,
                "type": cell.get("cell_type"),
                "source": self._get_source(cell),
                "metadata": cell.get("metadata", {}),
            }

            if cell.get("cell_type") == "code":
                cell_data["outputs"] = self._process_outputs(cell.get("outputs", []))
                cell_data["execution_count"] = cell.get("execution_count")

            if cell.get("cell_type") == "markdown":
                # Extract headings
                headings = self._extract_headings(cell_data["source"])
                for h in headings:
                    h["cell_index"] = i
                    result["headings"].append(h)

                # Detect questionnaires
                if self._is_questionnaire(cell_data["source"]):
                    questions = self._extract_questionnaire(cell_data["source"])
                    for q in questions:
                        q["cell_index"] = i
                        result["questionnaires"].append(q)

            result["cells"].append(cell_data)

        return result

    def _get_source(self, cell: Dict) -> str:
        """Get cell source as string (handles list or string format)"""
        source = cell.get("source", [])
        if isinstance(source, list):
            return "".join(source)
        return source

    def _process_outputs(self, outputs: List[Dict]) -> List[Dict]:
        """Process cell outputs, extracting text and images"""
        processed = []

        for output in outputs:
            output_type = output.get("output_type")

            if output_type == "stream":
                processed.append({
                    "type": "text",
                    "content": "".join(output.get("text", []))
                })

            elif output_type == "execute_result":
                data = output.get("data", {})
                if "text/plain" in data:
                    text = data["text/plain"]
                    if isinstance(text, list):
                        text = "".join(text)
                    processed.append({"type": "text", "content": text})
                if "image/png" in data:
                    processed.append({
                        "type": "image",
                        "format": "png",
                        "data": data["image/png"]
                    })

            elif output_type == "display_data":
                data = output.get("data", {})
                if "image/png" in data:
                    processed.append({
                        "type": "image",
                        "format": "png",
                        "data": data["image/png"]
                    })
                elif "text/html" in data:
                    html = data["text/html"]
                    if isinstance(html, list):
                        html = "".join(html)
                    processed.append({"type": "html", "content": html})

            elif output_type == "error":
                # Include errors for debugging education
                processed.append({
                    "type": "error",
                    "ename": output.get("ename"),
                    "evalue": output.get("evalue"),
                    "traceback": output.get("traceback", [])
                })

        return processed

    def _extract_headings(self, markdown: str) -> List[Dict]:
        """Extract heading hierarchy from markdown"""
        import re
        headings = []

        for line in markdown.split('\n'):
            match = re.match(r'^(#{1,6})\s+(.+)$', line)
            if match:
                level = len(match.group(1))
                text = match.group(2).strip()
                headings.append({
                    "level": level,
                    "text": text,
                    "slug": self._slugify(text)
                })

        return headings

    def _is_questionnaire(self, markdown: str) -> bool:
        """Check if markdown cell contains questionnaire"""
        markers = [
            "questionnaire",
            "quiz",
            "check your understanding",
            "review questions",
            "further research",
        ]
        lower = markdown.lower()
        return any(marker in lower for marker in markers)

    def _extract_questionnaire(self, markdown: str) -> List[Dict]:
        """Extract questionnaire questions from markdown"""
        questions = []
        import re

        # Pattern: numbered list items
        pattern = r'^\d+\.\s+(.+?)(?=\n\d+\.|\n\n|\Z)'
        matches = re.findall(pattern, markdown, re.MULTILINE | re.DOTALL)

        for i, match in enumerate(matches):
            question_text = match.strip()
            if question_text:
                questions.append({
                    "id": f"q-{i}",
                    "type": "self-assessment",  # Fast.ai questions are open-ended
                    "text": question_text
                })

        return questions

    async def parse(self, content: bytes) -> CurriculumData:
        """
        Parse Jupyter notebook and transform to VLCF format.

        Pipeline:
        1. Extract raw structure
        2. Build content hierarchy from headings
        3. Transform cells to transcript segments
        4. Extract code as examples
        5. Convert questionnaires to assessments
        6. Generate spoken text for code
        """
        raw = await self.extract(content)

        # Build VLCF structure
        vlcf = {
            "vlcf": "1.0.0",
            "id": self._generate_id(raw),
            "title": self._extract_title(raw),
            "description": self._extract_description(raw),
            "version": {
                "number": "1.0.0"
            },
            "lifecycle": self._build_lifecycle(raw),
            "metadata": self._build_metadata(raw),
            "educational": self._build_educational(raw),
            "rights": self._build_rights(),
            "content": [],
            "glossary": []
        }

        # Build content hierarchy from headings
        vlcf["content"] = await self._build_content_tree(raw)

        return CurriculumData(**vlcf)

    async def _build_content_tree(self, raw: Dict) -> List[Dict]:
        """Build hierarchical content from notebook cells and headings"""
        content = []
        current_module = None
        current_topic = None

        cells = raw["cells"]
        headings = raw["headings"]

        # Create heading index for quick lookup
        heading_cells = {h["cell_index"]: h for h in headings}

        i = 0
        while i < len(cells):
            cell = cells[i]

            # Check if this cell starts a new section
            if cell["index"] in heading_cells:
                heading = heading_cells[cell["index"]]

                if heading["level"] == 1:
                    # H1: New module
                    if current_module:
                        content.append(current_module)
                    current_module = {
                        "id": {"value": heading["slug"]},
                        "title": heading["text"],
                        "type": "module",
                        "orderIndex": len(content),
                        "children": [],
                        "transcript": {"segments": []},
                        "examples": [],
                        "assessments": []
                    }
                    current_topic = None

                elif heading["level"] == 2:
                    # H2: New topic
                    if current_topic and current_module:
                        current_module["children"].append(current_topic)
                    current_topic = {
                        "id": {"value": heading["slug"]},
                        "title": heading["text"],
                        "type": "topic",
                        "orderIndex": len(current_module["children"]) if current_module else 0,
                        "transcript": {"segments": []},
                        "examples": [],
                        "assessments": []
                    }

            # Process cell content
            target = current_topic or current_module
            if target:
                if cell["type"] == "markdown":
                    segments = self._markdown_to_segments(cell["source"])
                    target["transcript"]["segments"].extend(segments)

                elif cell["type"] == "code":
                    example = await self._code_to_example(cell)
                    target["examples"].append(example)

                    # Also add code explanation as transcript segment
                    if self.config.get("spoken_text_for_code"):
                        code_segment = self._code_to_segment(cell)
                        target["transcript"]["segments"].append(code_segment)

            i += 1

        # Add remaining nodes
        if current_topic and current_module:
            current_module["children"].append(current_topic)
        if current_module:
            content.append(current_module)

        # Add questionnaires as assessments
        for q in raw.get("questionnaires", []):
            assessment = self._question_to_assessment(q)
            # Add to appropriate node based on cell index
            self._add_assessment_to_node(content, q["cell_index"], assessment, raw["headings"])

        return content

    def _markdown_to_segments(self, markdown: str) -> List[Dict]:
        """Convert markdown to transcript segments"""
        segments = []
        import re

        # Split by paragraphs (double newline)
        paragraphs = re.split(r'\n\n+', markdown)

        for i, para in enumerate(paragraphs):
            para = para.strip()
            if not para:
                continue

            # Skip headings (processed separately)
            if re.match(r'^#{1,6}\s', para):
                continue

            segment = {
                "id": f"seg-{len(segments)}",
                "text": para,
                "type": self._classify_paragraph_type(para)
            }

            # Generate spoken text
            segment["spokenText"] = self._markdown_to_spoken(para)

            segments.append(segment)

        return segments

    def _markdown_to_spoken(self, markdown: str) -> str:
        """Convert markdown to spoken text"""
        import re

        text = markdown

        # Remove markdown formatting
        text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)  # Bold
        text = re.sub(r'\*(.+?)\*', r'\1', text)       # Italic
        text = re.sub(r'`(.+?)`', r'\1', text)         # Inline code
        text = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', text)  # Links
        text = re.sub(r'!\[.*?\]\(.+?\)', 'an image', text)  # Images

        # Expand technical terms
        expansions = {
            r'\bCNN\b': 'Convolutional Neural Network',
            r'\bRNN\b': 'Recurrent Neural Network',
            r'\bGPU\b': 'Graphics Processing Unit',
            r'\bAPI\b': 'A P I',
            r'\bML\b': 'machine learning',
            r'\bDL\b': 'deep learning',
            r'\bSGD\b': 'Stochastic Gradient Descent',
            r'\bNLP\b': 'Natural Language Processing',
        }
        for pattern, replacement in expansions.items():
            text = re.sub(pattern, replacement, text)

        return text.strip()

    async def _code_to_example(self, cell: Dict) -> Dict:
        """Convert code cell to VLCF example"""
        source = cell["source"]
        outputs = cell.get("outputs", [])

        example = {
            "type": "code",
            "language": "python",
            "title": self._infer_code_title(source),
            "content": source,
        }

        # Add outputs
        if outputs and self.config.get("include_code_outputs"):
            output_text = []
            visualizations = []

            for out in outputs:
                if out["type"] == "text":
                    lines = out["content"].split('\n')
                    if len(lines) > self.config.get("max_output_lines", 50):
                        lines = lines[:50] + ["... (output truncated)"]
                    output_text.append('\n'.join(lines))
                elif out["type"] == "image" and self.config.get("include_images"):
                    visualizations.append({
                        "type": "image",
                        "format": out["format"],
                        "data": f"data:image/{out['format']};base64,{out['data']}"
                    })
                elif out["type"] == "error":
                    output_text.append(f"Error: {out['ename']}: {out['evalue']}")

            if output_text:
                example["output"] = '\n'.join(output_text)
            if visualizations:
                example["visualizations"] = visualizations

        return example

    def _code_to_segment(self, cell: Dict) -> Dict:
        """Create transcript segment explaining code"""
        source = cell["source"]

        # Generate natural language explanation of code
        explanation = self._explain_code(source)

        return {
            "id": f"code-seg-{cell.get('index', 0)}",
            "type": "code_explanation",
            "text": f"```python\n{source}\n```",
            "spokenText": explanation,
            "speakingNotes": {
                "pace": "slow",
                "emphasis": ["function names", "key parameters"]
            }
        }

    def _explain_code(self, source: str) -> str:
        """Generate spoken explanation of code"""
        import re

        explanations = []

        lines = source.strip().split('\n')

        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            # Pattern matching for common constructs
            if re.match(r'^from\s+(\w+)\s+import', line):
                match = re.match(r'^from\s+(\w+)\s+import\s+(.+)', line)
                if match:
                    module, items = match.groups()
                    explanations.append(f"We import {items} from the {module} library.")

            elif re.match(r'^import\s+', line):
                match = re.match(r'^import\s+(\w+)', line)
                if match:
                    explanations.append(f"We import the {match.group(1)} library.")

            elif '=' in line and not line.startswith('if') and not line.startswith('for'):
                # Variable assignment
                parts = line.split('=', 1)
                var_name = parts[0].strip()
                if '(' in parts[1]:
                    # Function call
                    func_match = re.search(r'(\w+)\(', parts[1])
                    if func_match:
                        explanations.append(f"We create {var_name} by calling {func_match.group(1)}.")
                else:
                    explanations.append(f"We set {var_name} to the value on the right.")

            elif re.match(r'^def\s+(\w+)', line):
                match = re.match(r'^def\s+(\w+)\(([^)]*)\)', line)
                if match:
                    func_name, params = match.groups()
                    params_text = f" with parameters {params}" if params else ""
                    explanations.append(f"We define a function called {func_name}{params_text}.")

            elif re.match(r'^class\s+(\w+)', line):
                match = re.match(r'^class\s+(\w+)', line)
                if match:
                    explanations.append(f"We define a class called {match.group(1)}.")

            elif line.endswith('.fit(') or '.fit(' in line:
                explanations.append("We train the model by calling the fit method.")

            elif '.predict(' in line:
                explanations.append("We make predictions using the trained model.")

            elif 'learn' in line.lower() and '=' in line:
                explanations.append("We create a learner object, which combines our model, data, and training configuration.")

        if not explanations:
            return "Let's look at this code."

        return ' '.join(explanations)

    def _infer_code_title(self, source: str) -> str:
        """Infer a title for code example from its content"""
        import re

        # Look for function definitions
        func_match = re.search(r'^def\s+(\w+)', source, re.MULTILINE)
        if func_match:
            return f"Function: {func_match.group(1)}"

        # Look for class definitions
        class_match = re.search(r'^class\s+(\w+)', source, re.MULTILINE)
        if class_match:
            return f"Class: {class_match.group(1)}"

        # Look for model training
        if '.fit(' in source or 'learn.fine_tune' in source:
            return "Model Training"

        # Look for data loading
        if 'DataLoaders' in source or 'DataBlock' in source:
            return "Data Loading"

        # Look for visualization
        if '.show(' in source or 'plot' in source.lower():
            return "Visualization"

        return "Code Example"

    def _question_to_assessment(self, question: Dict) -> Dict:
        """Convert extracted question to VLCF assessment"""
        return {
            "id": {"value": question["id"]},
            "type": "self-assessment",
            "prompt": question["text"],
            "guidance": "Think about this question and try to explain your answer out loud.",
            "tutoringConfig": {
                "followUp": True,
                "scaffolding": "socratic"
            }
        }

    def _build_educational(self, raw: Dict) -> Dict:
        """Build VLCF educational context for Fast.ai content"""
        return {
            "audience": {
                "type": "learner",
                "educationalLevel": "collegiate",
                "description": "Self-learners and practitioners interested in deep learning",
                "prerequisites": [
                    "Basic Python programming",
                    "High school mathematics",
                    "Curiosity about AI/ML"
                ]
            },
            "alignment": [
                {
                    "framework": "Bloom's Taxonomy",
                    "targetName": "Apply",
                    "targetDescription": "Fast.ai emphasizes practical application before theory"
                }
            ],
            "duration": {
                "estimated": self._estimate_duration(raw),
                "unit": "hours"
            },
            "pedagogy": {
                "approach": "top-down",
                "description": "Start with complete working examples, then gradually understand the details"
            }
        }

    def _estimate_duration(self, raw: Dict) -> float:
        """Estimate study duration from notebook content"""
        # Rough heuristics
        markdown_cells = raw["metadata"].get("markdown_cells", 0)
        code_cells = raw["metadata"].get("code_cells", 0)

        # Assume 2 min per markdown cell, 5 min per code cell (including experimentation)
        return round((markdown_cells * 2 + code_cells * 5) / 60, 1)

    def _build_rights(self) -> Dict:
        """Build VLCF rights for Fast.ai content"""
        return {
            "license": {
                "type": "Apache-2.0",
                "name": "Apache License 2.0",
                "url": "https://www.apache.org/licenses/LICENSE-2.0",
                "permissions": ["commercial", "modify", "distribute", "patent"],
                "conditions": ["license", "notice"]
            },
            "attribution": {
                "required": True,
                "format": "Based on Fast.ai course materials by Jeremy Howard and Rachel Thomas."
            },
            "holder": {
                "name": "fast.ai",
                "url": "https://www.fast.ai/"
            }
        }

    def _extract_title(self, raw: Dict) -> str:
        """Extract notebook title"""
        # Check metadata
        if raw["metadata"].get("title"):
            return raw["metadata"]["title"]

        # Check first H1 heading
        for h in raw.get("headings", []):
            if h["level"] == 1:
                return h["text"]

        return "Untitled Notebook"

    def _extract_description(self, raw: Dict) -> str:
        """Extract notebook description from first paragraph"""
        for cell in raw.get("cells", []):
            if cell["type"] == "markdown":
                source = cell["source"].strip()
                # Skip headings
                if not source.startswith('#'):
                    # Return first paragraph
                    paragraphs = source.split('\n\n')
                    if paragraphs:
                        return paragraphs[0][:500]  # Limit length
        return ""

    def _generate_id(self, raw: Dict) -> Dict:
        """Generate VLCF ID from notebook metadata"""
        # Try to get from metadata
        nb_meta = raw.get("metadata", {})

        if nb_meta.get("identifier"):
            return {"catalog": "fastai", "value": nb_meta["identifier"]}

        # Generate from title
        title = self._extract_title(raw)
        slug = self._slugify(title)

        return {"catalog": "fastai", "value": slug}

    def _build_lifecycle(self, raw: Dict) -> Dict:
        """Build lifecycle metadata"""
        return {
            "status": "published",
            "contributors": [
                {
                    "name": "Jeremy Howard",
                    "role": "author",
                    "organization": "fast.ai"
                },
                {
                    "name": "Rachel Thomas",
                    "role": "author",
                    "organization": "fast.ai"
                }
            ]
        }

    def _build_metadata(self, raw: Dict) -> Dict:
        """Build VLCF metadata"""
        return {
            "language": "en-US",
            "keywords": ["deep learning", "machine learning", "AI", "fastai", "PyTorch"],
            "extensions": {
                "jupyter": {
                    "kernelspec": raw["metadata"].get("kernelspec", {}),
                    "nbformat": raw.get("nbformat")
                }
            }
        }

    def _classify_paragraph_type(self, para: str) -> str:
        """Classify paragraph type for transcript"""
        if para.startswith('>'):
            return "callout"
        if para.startswith('- ') or para.startswith('* '):
            return "list"
        if '|' in para and '-|-' in para:
            return "table"
        return "narrative"

    def _add_assessment_to_node(
        self,
        content: List[Dict],
        cell_index: int,
        assessment: Dict,
        headings: List[Dict]
    ):
        """Add assessment to appropriate content node based on cell position"""
        # Find the heading that precedes this cell
        preceding_heading = None
        for h in reversed(headings):
            if h["cell_index"] < cell_index:
                preceding_heading = h
                break

        if not preceding_heading:
            # Add to first module
            if content:
                content[0].setdefault("assessments", []).append(assessment)
            return

        # Find matching node
        for module in content:
            if module["id"]["value"] == preceding_heading["slug"]:
                module.setdefault("assessments", []).append(assessment)
                return

            for topic in module.get("children", []):
                if topic["id"]["value"] == preceding_heading["slug"]:
                    topic.setdefault("assessments", []).append(assessment)
                    return

    def _slugify(self, text: str) -> str:
        """Convert text to URL-safe slug"""
        import re
        slug = text.lower()
        slug = re.sub(r'[^\w\s-]', '', slug)
        slug = re.sub(r'[\s_]+', '-', slug)
        return slug.strip('-')

    def _generate_uuid(self) -> str:
        """Generate a UUID string"""
        from uuid import uuid4
        return str(uuid4())
```

---

## Code Handling

### Code Cell Processing Strategy

Fast.ai notebooks are code-heavy. The importer handles code in two ways:

1. **As Examples**: Preserves exact code for reference
2. **As Spoken Content**: Generates natural language explanation

### Code Explanation Depth

| Depth | Description | Use Case |
|-------|-------------|----------|
| `surface` | "This code trains the model" | Quick overview |
| `standard` | Line-by-line explanation | Normal tutoring |
| `deep` | Implementation details, alternatives | Deep understanding |

### Handling Long Code Cells

```python
# Configuration
max_code_lines_per_segment = 20
collapse_long_outputs = True
max_output_lines = 50
```

Long code cells are split into logical chunks with continuation markers.

---

## Assessment Generation

Since Fast.ai doesn't have formal quizzes, the importer infers assessments:

### Questionnaire Detection

Fast.ai chapters typically end with a "Questionnaire" section:

```markdown
## Questionnaire

1. What is a neural network?
2. How does a CNN differ from an RNN?
3. Why do we use transfer learning?
```

These are extracted as `self-assessment` type questions with tutoring follow-up enabled.

### Code Challenge Extraction

Cells marked with `#hide` or "exercise" are treated as challenges:

```python
# Exercise: Complete this function
def mystery_function(x):
    # Your code here
    pass
```

Becomes a `text-entry` assessment with the incomplete code as prompt.

---

## Error Handling

### Common Issues

| Issue | Handling |
|-------|----------|
| Invalid JSON | Return `ValidationResult` with errors |
| Missing cells | Warning, continue with available content |
| Corrupted outputs | Skip output, log warning |
| Large images | Compress or convert to URL reference |
| Non-UTF8 text | Attempt decode with fallback encodings |

### Graceful Degradation

```python
try:
    example = await self._code_to_example(cell)
except Exception as e:
    self.logger.warning(f"Failed to process code cell {cell['index']}: {e}")
    example = {
        "type": "code",
        "language": "python",
        "title": "Code Example",
        "content": cell.get("source", "# Could not parse"),
        "error": str(e)
    }
```

---

## Testing Strategy

### Unit Tests

```python
# tests/test_importers/test_fastai/test_importer.py

@pytest.fixture
def sample_notebook():
    return {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {"kernelspec": {"display_name": "Python 3"}},
        "cells": [
            {"cell_type": "markdown", "source": "# Introduction\n\nWelcome to the course."},
            {"cell_type": "code", "source": "from fastai.vision.all import *", "outputs": []},
        ]
    }

async def test_validate_valid_notebook(importer, sample_notebook):
    content = json.dumps(sample_notebook).encode()
    result = await importer.validate(content)
    assert result.is_valid
    assert result.metadata["fastai_detected"]

async def test_extract_headings(importer, sample_notebook):
    content = json.dumps(sample_notebook).encode()
    raw = await importer.extract(content)
    assert len(raw["headings"]) == 1
    assert raw["headings"][0]["text"] == "Introduction"

async def test_parse_creates_vlcf(importer, sample_notebook):
    content = json.dumps(sample_notebook).encode()
    curriculum = await importer.parse(content)
    assert curriculum.vlcf == "1.0.0"
    assert len(curriculum.content) >= 1
```

### Integration Tests

```python
async def test_import_fastbook_chapter():
    """Test importing actual Fast.ai book chapter"""
    with open("tests/fixtures/01_intro.ipynb", "rb") as f:
        content = f.read()

    importer = FastaiImporter(storage=MemoryStorage())
    result = await importer.import_async(content)

    assert result.success
    assert result.topic_count > 0
    assert result.assessment_count > 0
```

### Fixtures

Store sample notebooks in `tests/fixtures/`:
- `minimal_notebook.ipynb` - Minimum valid notebook
- `01_intro.ipynb` - Real Fast.ai chapter (first chapter)
- `questionnaire_notebook.ipynb` - Notebook with questionnaire section

---

## Appendix: Fast.ai Specific Patterns

### Common fastai Imports

```python
from fastai.vision.all import *    # Vision tasks
from fastai.text.all import *      # NLP tasks
from fastai.tabular.all import *   # Tabular data
from fastai.collab import *        # Collaborative filtering
```

### Learner Pattern

```python
learn = cnn_learner(dls, resnet34, metrics=error_rate)
learn.fine_tune(4)
```

### Data Pipeline Pattern

```python
dls = DataBlock(
    blocks=(ImageBlock, CategoryBlock),
    get_items=get_image_files,
    splitter=RandomSplitter(),
    get_y=parent_label,
    item_tfms=Resize(224)
).dataloaders(path)
```

These patterns are recognized by the code explanation generator to provide domain-specific explanations.
