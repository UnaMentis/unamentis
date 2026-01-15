"""Tests for TTS Content Extractors."""

import json
import os
import pytest
import tempfile
from pathlib import Path

from tts_pregen.content_extractors import (
    KnowledgeBowlExtractor,
    CurriculumExtractor,
    CustomTextExtractor,
    get_extractor,
)


class TestKnowledgeBowlExtractor:
    """Tests for Knowledge Bowl content extraction."""

    @pytest.fixture
    def kb_data(self):
        """Sample Knowledge Bowl data."""
        return {
            "domains": [
                {
                    "id": "science",
                    "name": "Science",
                    "questions": [
                        {
                            "id": "sci-001",
                            "question_text": "What is the speed of light?",
                            "answer_text": "300 million meters per second",
                            "hints": ["It's very fast", "Named c in physics"],
                            "explanation": "Light travels at approximately 3x10^8 m/s",
                            "difficulty": 2,
                        },
                        {
                            "id": "sci-002",
                            "question_text": "What is water's chemical formula?",
                            "answer_text": "H2O",
                            "hints": ["Two hydrogen atoms"],
                            "explanation": "Water is made of hydrogen and oxygen",
                            "difficulty": 1,
                        },
                    ],
                },
                {
                    "id": "math",
                    "name": "Mathematics",
                    "questions": [
                        {
                            "id": "math-001",
                            "question_text": "What is 2 + 2?",
                            "answer_text": "4",
                            "hints": [],
                            "explanation": "Basic addition",
                            "difficulty": 1,
                        },
                    ],
                },
            ]
        }

    @pytest.fixture
    def kb_file(self, kb_data):
        """Create temporary Knowledge Bowl file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(kb_data, f)
            return f.name

    def test_extract_all_content(self, kb_file):
        """Test extracting all content types."""
        extractor = KnowledgeBowlExtractor(
            data_path=kb_file,
            include_questions=True,
            include_answers=True,
            include_hints=True,
            include_explanations=True,
        )

        items = extractor.extract()

        # 3 questions + 3 answers + 3 hints + 3 explanations = 12 items
        assert len(items) == 12

        # Check question is extracted
        question_items = [i for i in items if "question" in i["source_ref"]]
        assert len(question_items) == 3
        assert any("speed of light" in i["text"] for i in question_items)

        # Check answer is extracted
        answer_items = [i for i in items if "answer" in i["source_ref"]]
        assert len(answer_items) == 3

        # Check hints are extracted
        hint_items = [i for i in items if "hint" in i["source_ref"]]
        assert len(hint_items) == 3

        # Check explanations are extracted
        explanation_items = [i for i in items if "explanation" in i["source_ref"]]
        assert len(explanation_items) == 3

    def test_extract_questions_only(self, kb_file):
        """Test extracting only questions."""
        extractor = KnowledgeBowlExtractor(
            data_path=kb_file,
            include_questions=True,
            include_answers=False,
            include_hints=False,
            include_explanations=False,
        )

        items = extractor.extract()

        assert len(items) == 3
        assert all("question" in i["source_ref"] for i in items)

    def test_filter_by_domain(self, kb_file):
        """Test filtering by domain."""
        extractor = KnowledgeBowlExtractor(
            data_path=kb_file,
            include_questions=True,
            include_answers=False,
            include_hints=False,
            include_explanations=False,
            domains=["science"],
        )

        items = extractor.extract()

        assert len(items) == 2
        assert all("sci-" in i["source_ref"] for i in items)

    def test_filter_by_difficulty(self, kb_file):
        """Test filtering by difficulty."""
        extractor = KnowledgeBowlExtractor(
            data_path=kb_file,
            include_questions=True,
            include_answers=False,
            include_hints=False,
            include_explanations=False,
            difficulties=[1],
        )

        items = extractor.extract()

        # Only difficulty 1 questions: sci-002 and math-001
        assert len(items) == 2

    def test_get_stats(self, kb_file):
        """Test getting statistics."""
        extractor = KnowledgeBowlExtractor(data_path=kb_file)

        stats = extractor.get_stats()

        assert stats["total_domains"] == 2
        assert stats["total_questions"] == 3
        assert stats["domain_counts"]["science"] == 2
        assert stats["domain_counts"]["math"] == 1

    def test_file_not_found(self):
        """Test handling missing file."""
        extractor = KnowledgeBowlExtractor(data_path="/nonexistent/path.json")

        items = extractor.extract()

        assert items == []

    def test_invalid_json(self):
        """Test handling invalid JSON."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write("not valid json")
            path = f.name

        try:
            extractor = KnowledgeBowlExtractor(data_path=path)
            items = extractor.extract()
            assert items == []
        finally:
            os.unlink(path)


class TestCurriculumExtractor:
    """Tests for curriculum content extraction."""

    @pytest.fixture
    def curriculum_data(self):
        """Sample curriculum data."""
        return {
            "segments": [
                {
                    "id": "seg-001",
                    "type": "instruction",
                    "content": {
                        "instruction": "Welcome to the lesson",
                        "questions": [
                            {"text": "What did you learn?"},
                            {"text": "Any questions?"},
                        ],
                    },
                },
                {
                    "id": "seg-002",
                    "type": "quiz",
                    "content": {
                        "instruction": "Answer these questions",
                        "prompts": ["Think carefully", "Take your time"],
                    },
                },
            ]
        }

    @pytest.fixture
    def curriculum_file(self, curriculum_data):
        """Create temporary curriculum file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(curriculum_data, f)
            return f.name

    def test_extract_from_file(self, curriculum_file):
        """Test extracting from curriculum file."""
        extractor = CurriculumExtractor(curriculum_path=curriculum_file)

        items = extractor.extract()

        # 2 instructions + 2 questions + 2 prompts = 6 items
        assert len(items) == 6

        # Check instructions
        instruction_items = [i for i in items if "instruction" in i["source_ref"]]
        assert len(instruction_items) == 2

        # Check questions
        question_items = [i for i in items if "question" in i["source_ref"]]
        assert len(question_items) == 2

    def test_filter_by_segment_type(self, curriculum_file):
        """Test filtering by segment type."""
        extractor = CurriculumExtractor(
            curriculum_path=curriculum_file,
            segment_types=["quiz"],
        )

        items = extractor.extract()

        # Only quiz segment: 1 instruction + 2 prompts = 3 items
        assert len(items) == 3
        assert all("seg-002" in i["source_ref"] for i in items)

    def test_extract_from_directory(self, curriculum_data):
        """Test extracting from directory of files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create multiple curriculum files
            for i in range(2):
                path = Path(tmpdir) / f"curriculum_{i}.json"
                with open(path, 'w') as f:
                    json.dump(curriculum_data, f)

            extractor = CurriculumExtractor(curriculum_path=tmpdir)
            items = extractor.extract()

            # 6 items per file x 2 files = 12 items
            assert len(items) == 12


class TestCustomTextExtractor:
    """Tests for custom text extraction."""

    def test_extract_texts(self):
        """Test extracting custom texts."""
        texts = ["Hello world", "How are you?", "Goodbye"]

        extractor = CustomTextExtractor(texts=texts)
        items = extractor.extract()

        assert len(items) == 3
        assert items[0]["text"] == "Hello world"
        assert items[0]["source_ref"] == "custom:0"

    def test_filter_empty_texts(self):
        """Test that empty texts are filtered."""
        texts = ["Valid text", "", "  ", "Another valid"]

        extractor = CustomTextExtractor(texts=texts)
        items = extractor.extract()

        assert len(items) == 2

    def test_empty_list(self):
        """Test with empty list."""
        extractor = CustomTextExtractor(texts=[])
        items = extractor.extract()

        assert items == []


class TestGetExtractor:
    """Tests for extractor factory function."""

    def test_get_knowledge_bowl_extractor(self):
        """Test getting Knowledge Bowl extractor."""
        extractor = get_extractor(
            source_type="knowledge-bowl",
            source_config={"include_questions": True, "include_answers": False},
        )

        assert isinstance(extractor, KnowledgeBowlExtractor)
        assert extractor.include_questions is True
        assert extractor.include_answers is False

    def test_get_curriculum_extractor(self):
        """Test getting curriculum extractor."""
        extractor = get_extractor(
            source_type="curriculum",
            source_config={"curriculum_path": "/tmp/test"},
        )

        assert isinstance(extractor, CurriculumExtractor)

    def test_get_curriculum_extractor_requires_path(self):
        """Test that curriculum extractor requires path."""
        with pytest.raises(ValueError, match="curriculum_path is required"):
            get_extractor(source_type="curriculum")

    def test_get_custom_extractor(self):
        """Test getting custom extractor."""
        extractor = get_extractor(
            source_type="custom",
            source_config={"texts": ["Test"]},
        )

        assert isinstance(extractor, CustomTextExtractor)

    def test_unknown_source_type(self):
        """Test error for unknown source type."""
        with pytest.raises(ValueError, match="Unknown source type"):
            get_extractor(source_type="invalid")
