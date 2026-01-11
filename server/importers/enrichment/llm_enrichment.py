"""
LLM Enrichment Service - Uses Ollama for curriculum content generation.

This service provides LLM-based enrichment capabilities for:
- Re-chunking oversized segments into conversational turns
- Generating Bloom-aligned learning objectives
- Creating comprehension checkpoints
- Generating alternative explanations
"""

import json
import logging
import re
from typing import Any, Dict, List, Optional

import aiohttp

logger = logging.getLogger(__name__)

# Ollama endpoint (OpenAI-compatible API)
OLLAMA_URL = "http://localhost:11434/v1/chat/completions"

# Model recommendations by task
MODELS = {
    "rechunk": "qwen2.5:32b",       # Complex reasoning for natural breaks
    "objectives": "mistral:7b",     # Structured output, fast
    "checkpoints": "mistral:7b",    # Quick question generation
    "alternatives": "qwen2.5:32b",  # Creative paraphrasing
    "metadata": "mistral:7b",       # Simple extraction
}


# =============================================================================
# System Prompts
# =============================================================================

RECHUNK_SYSTEM_PROMPT = """You are an expert educational content editor. Your task is to break up
a long piece of educational content into smaller, conversational segments suitable for voice-based tutoring.

Guidelines:
- Each segment should be 150-400 words (under 2000 characters)
- Preserve the semantic meaning and flow
- Create natural break points between concepts
- Each segment should feel like a complete thought or explanation
- Maintain the original voice and tone
- Preserve any technical terminology

Output format: Return a JSON array of segment objects, each with:
- "content": The text content of the segment
- "type": One of "introduction", "explanation", "example", "summary"
- "speakingNotes": Optional object with "pace" (slow/normal/fast) and "emphasis" (array of words to emphasize)

Return ONLY valid JSON, no additional text."""

OBJECTIVES_SYSTEM_PROMPT = """You are an expert instructional designer. Generate Bloom's taxonomy-aligned
learning objectives for educational content.

Bloom's Taxonomy Levels (use these exact values):
- remember: Recall facts and basic concepts
- understand: Explain ideas or concepts
- apply: Use information in new situations
- analyze: Draw connections among ideas
- evaluate: Justify a stand or decision
- create: Produce new or original work

Output format: Return a JSON array of 2-4 objective objects, each with:
- "id": Unique identifier (e.g., "obj-1", "obj-2")
- "text": The objective statement starting with an action verb
- "bloomLevel": One of the taxonomy levels above
- "assessable": true if this can be directly assessed

Return ONLY valid JSON, no additional text."""

CHECKPOINT_SYSTEM_PROMPT = """You are an expert tutor creating comprehension checks. Generate a question
that verifies the learner understood the preceding content.

Guidelines:
- Ask one clear, focused question
- Target the key concept just explained
- Provide expected answer patterns (not exact answers)
- Include keywords the learner should mention
- Keep it conversational, not quiz-like

Output format: Return a JSON object with:
- "type": "comprehension_check"
- "question": The question to ask
- "expectedResponsePatterns": Array of regex patterns for valid answers
- "expectedKeywords": Array of key terms that should appear in response
- "hintOnStruggle": A hint to give if learner struggles
- "celebrationMessage": Brief praise for correct answer (1 sentence)

Return ONLY valid JSON, no additional text."""

ALTERNATIVES_SYSTEM_PROMPT = """You are an expert educator who excels at explaining concepts in multiple ways.
Generate alternative explanations for a piece of educational content.

Create three versions:
1. "simpler": Use everyday language, more analogies, shorter sentences
2. "technical": Use precise terminology, include formal definitions
3. "analogy": Build understanding through a relatable comparison

Each alternative should convey the same core concept but in a different style.

Output format: Return a JSON object with:
- "simpler": { "style": "simpler", "content": "..." }
- "technical": { "style": "technical", "content": "..." }
- "analogy": { "style": "analogy", "content": "..." }

Return ONLY valid JSON, no additional text."""


class LLMEnrichmentService:
    """
    Service for LLM-based curriculum enrichment using Ollama.
    """

    def __init__(
        self,
        ollama_url: str = OLLAMA_URL,
        default_model: str = "qwen2.5:32b",
        timeout: float = 120.0
    ):
        """
        Initialize the service.

        Args:
            ollama_url: URL to Ollama's OpenAI-compatible API
            default_model: Default model to use
            timeout: Request timeout in seconds
        """
        self.ollama_url = ollama_url
        self.default_model = default_model
        self.timeout = timeout

    async def _call_llm(
        self,
        messages: List[Dict[str, str]],
        model: str = None,
        temperature: float = 0.5,
        max_tokens: int = 4096
    ) -> str:
        """
        Call the Ollama LLM API.

        Args:
            messages: List of message dicts with role and content
            model: Model to use (defaults to self.default_model)
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate

        Returns:
            The assistant's response content
        """
        model = model or self.default_model

        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": False,
        }

        logger.debug(f"Calling LLM {model} with {len(messages)} messages")

        timeout = aiohttp.ClientTimeout(total=self.timeout)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(self.ollama_url, json=payload) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    raise RuntimeError(f"LLM API error {resp.status}: {error_text}")

                data = await resp.json()
                content = data["choices"][0]["message"]["content"]
                logger.debug(f"LLM response: {len(content)} chars")
                return content

    def _parse_json_response(self, response: str) -> Any:
        """
        Parse JSON from LLM response, handling common issues.
        """
        # Try to find JSON in the response
        response = response.strip()

        # Remove markdown code blocks if present
        if response.startswith("```"):
            # Find the end of the code block
            lines = response.split("\n")
            json_lines = []
            in_block = False
            for line in lines:
                if line.startswith("```") and not in_block:
                    in_block = True
                    continue
                elif line.startswith("```") and in_block:
                    break
                elif in_block:
                    json_lines.append(line)
            response = "\n".join(json_lines)

        # Try direct parse
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            pass

        # Try to extract JSON array or object
        array_match = re.search(r'\[[\s\S]*\]', response)
        if array_match:
            try:
                return json.loads(array_match.group())
            except json.JSONDecodeError:
                pass

        object_match = re.search(r'\{[\s\S]*\}', response)
        if object_match:
            try:
                return json.loads(object_match.group())
            except json.JSONDecodeError:
                pass

        raise ValueError(f"Could not parse JSON from response: {response[:200]}...")

    # =========================================================================
    # Re-chunking
    # =========================================================================

    async def rechunk_segment(
        self,
        segment_text: str,
        context: Dict[str, Any],
        model: str = None
    ) -> List[Dict[str, Any]]:
        """
        Split an oversized segment into conversational turns.

        Args:
            segment_text: The text content to split
            context: Context dict with topic_title, segment_type, audience

        Returns:
            List of new segment dicts
        """
        model = model or MODELS["rechunk"]

        user_prompt = f"""Break this educational content into smaller segments:

Topic: {context.get('topic_title', 'Unknown')}
Target audience: {context.get('audience', 'general learners')}
Original segment type: {context.get('segment_type', 'explanation')}

Content to split:
{segment_text}

Return a JSON array of 2-4 segments, each under 2000 characters."""

        response = await self._call_llm(
            messages=[
                {"role": "system", "content": RECHUNK_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            model=model,
            temperature=0.3  # Lower temperature for consistent structure
        )

        segments = self._parse_json_response(response)

        # Validate and normalize segments
        result = []
        for i, seg in enumerate(segments):
            if isinstance(seg, dict) and "content" in seg:
                result.append({
                    "id": f"seg-rechunk-{i+1}",
                    "content": seg["content"],
                    "type": seg.get("type", "explanation"),
                    "speakingNotes": seg.get("speakingNotes", {}),
                })

        logger.info(f"Rechunked segment into {len(result)} parts")
        return result

    # =========================================================================
    # Learning Objectives
    # =========================================================================

    async def generate_objectives(
        self,
        topic_content: str,
        topic_title: str,
        audience: str = "general learners",
        model: str = None
    ) -> List[Dict[str, Any]]:
        """
        Generate Bloom-aligned learning objectives for a topic.

        Args:
            topic_content: The topic's text content
            topic_title: Title of the topic
            audience: Target audience description

        Returns:
            List of learning objective dicts
        """
        model = model or MODELS["objectives"]

        # Limit content to avoid token overflow
        content_preview = topic_content[:3000]
        if len(topic_content) > 3000:
            content_preview += "\n\n[Content truncated for analysis...]"

        user_prompt = f"""Generate 2-4 learning objectives for this educational content:

Topic Title: {topic_title}
Target audience: {audience}

Content:
{content_preview}

Return a JSON array of learning objectives."""

        response = await self._call_llm(
            messages=[
                {"role": "system", "content": OBJECTIVES_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            model=model,
            temperature=0.5
        )

        objectives = self._parse_json_response(response)

        # Validate and normalize
        result = []
        for i, obj in enumerate(objectives):
            if isinstance(obj, dict) and "text" in obj:
                bloom_level = obj.get("bloomLevel", "understand").lower()
                if bloom_level not in {"remember", "understand", "apply", "analyze", "evaluate", "create"}:
                    bloom_level = "understand"

                result.append({
                    "id": obj.get("id", f"obj-{i+1}"),
                    "text": obj["text"],
                    "bloomLevel": bloom_level,
                    "assessable": obj.get("assessable", True),
                })

        logger.info(f"Generated {len(result)} learning objectives for '{topic_title}'")
        return result

    # =========================================================================
    # Checkpoints
    # =========================================================================

    async def generate_checkpoint(
        self,
        segment_content: str,
        preceding_content: str,
        topic_title: str,
        model: str = None
    ) -> Dict[str, Any]:
        """
        Generate a comprehension check for a segment.

        Args:
            segment_content: The segment to create a checkpoint for
            preceding_content: Content that came before (for context)
            topic_title: Title of the current topic

        Returns:
            Checkpoint dict with question, patterns, keywords, hints
        """
        model = model or MODELS["checkpoints"]

        user_prompt = f"""Create a comprehension check for this content:

Topic: {topic_title}

What was just explained:
{segment_content}

Previous context (for reference):
{preceding_content[-1000:] if len(preceding_content) > 1000 else preceding_content}

Generate a conversational comprehension check question."""

        response = await self._call_llm(
            messages=[
                {"role": "system", "content": CHECKPOINT_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            model=model,
            temperature=0.6
        )

        checkpoint = self._parse_json_response(response)

        # Normalize the checkpoint
        result = {
            "type": "comprehension_check",
            "question": checkpoint.get("question", "Can you explain what we just covered?"),
            "expectedResponsePatterns": checkpoint.get("expectedResponsePatterns", []),
            "expectedKeywords": checkpoint.get("expectedKeywords", []),
            "hintOnStruggle": checkpoint.get("hintOnStruggle", "Let me rephrase that..."),
            "celebrationMessage": checkpoint.get("celebrationMessage", "Great understanding!"),
        }

        logger.info(f"Generated checkpoint for '{topic_title}'")
        return result

    # =========================================================================
    # Alternative Explanations
    # =========================================================================

    async def generate_alternatives(
        self,
        explanation: str,
        audience_level: str = "general",
        model: str = None
    ) -> Dict[str, Any]:
        """
        Generate alternative explanations (simpler, technical, analogy).

        Args:
            explanation: The original explanation text
            audience_level: Target audience level

        Returns:
            Dict with simpler, technical, and analogy versions
        """
        model = model or MODELS["alternatives"]

        user_prompt = f"""Generate alternative explanations for this content:

Audience level: {audience_level}

Original explanation:
{explanation}

Create three alternative versions: simpler, technical, and analogy-based."""

        response = await self._call_llm(
            messages=[
                {"role": "system", "content": ALTERNATIVES_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            model=model,
            temperature=0.7  # Higher for creative alternatives
        )

        alternatives = self._parse_json_response(response)

        # Normalize the response
        result = []
        for style in ["simpler", "technical", "analogy"]:
            alt = alternatives.get(style, {})
            if isinstance(alt, dict) and "content" in alt:
                result.append({
                    "style": style,
                    "content": alt["content"],
                })
            elif isinstance(alt, str):
                result.append({
                    "style": style,
                    "content": alt,
                })

        logger.info(f"Generated {len(result)} alternative explanations")
        return result

    # =========================================================================
    # Metadata Inference
    # =========================================================================

    async def infer_metadata(
        self,
        content: str,
        missing_fields: List[str],
        model: str = None
    ) -> Dict[str, str]:
        """
        Infer missing metadata fields from content.

        Args:
            content: The curriculum content
            missing_fields: List of field names to infer

        Returns:
            Dict mapping field names to inferred values
        """
        model = model or MODELS["metadata"]

        fields_str = ", ".join(missing_fields)

        user_prompt = f"""Based on this educational content, infer the following metadata fields: {fields_str}

Content preview:
{content[:2000]}

Return a JSON object with the field names as keys and inferred values."""

        response = await self._call_llm(
            messages=[
                {"role": "system", "content": "You are an educational content analyst. Infer metadata fields from educational content. Return only valid JSON."},
                {"role": "user", "content": user_prompt}
            ],
            model=model,
            temperature=0.3
        )

        result = self._parse_json_response(response)

        logger.info(f"Inferred {len(result)} metadata fields")
        return result

    # =========================================================================
    # Health Check
    # =========================================================================

    async def health_check(self) -> bool:
        """
        Check if the Ollama service is available.

        Returns:
            True if service is healthy
        """
        try:
            # Simple completion to test connectivity
            response = await self._call_llm(
                messages=[{"role": "user", "content": "Say 'ok'"}],
                model="mistral:7b",
                max_tokens=10,
            )
            return "ok" in response.lower()
        except Exception as e:
            logger.warning(f"LLM health check failed: {e}")
            return False
