"""
FOV Context Manager - Server-side implementation

Manages the hierarchical cognitive buffers and builds foveated context
for LLM calls during voice tutoring sessions.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from .models import (
    AdaptiveBudgetConfig,
    ConversationTurn,
    CurriculumPosition,
    EpisodicBuffer,
    FOVContext,
    GlossaryTerm,
    ImmediateBuffer,
    LearnerSignals,
    MessageRole,
    MisconceptionTrigger,
    ModelTier,
    PacePreference,
    SemanticBuffer,
    TopicSummary,
    TranscriptSegment,
    WorkingBuffer,
)

logger = logging.getLogger(__name__)


# Default system prompt for voice tutoring
DEFAULT_SYSTEM_PROMPT = """You are an expert AI tutor conducting a voice-based educational session.

INTERACTION GUIDELINES:
- You are in a voice conversation, so be conversational and natural
- Keep responses concise but comprehensive
- Use Socratic questioning to guide learning
- Encourage critical thinking and exploration
- Adapt explanations to the student's demonstrated understanding
- Use concrete examples and analogies
- Check for understanding regularly
- Be prepared for interruptions and clarification questions

If the student interrupts or asks a question, respond helpfully based on the context provided. You have access to the curriculum content, learning objectives, and session history.

Always maintain a supportive, encouraging tone while being intellectually rigorous."""


@dataclass
class FOVContextManager:
    """
    Manages foveated context for voice tutoring sessions.

    Implements a hierarchical buffer system inspired by foveated rendering:
    - Immediate Buffer: Current interaction (highest priority)
    - Working Buffer: Current topic materials
    - Episodic Buffer: Session memory
    - Semantic Buffer: Curriculum overview
    """

    # Configuration
    budget_config: AdaptiveBudgetConfig
    base_system_prompt: str = DEFAULT_SYSTEM_PROMPT

    # Buffers
    immediate_buffer: ImmediateBuffer = field(default_factory=ImmediateBuffer)
    working_buffer: WorkingBuffer = field(default_factory=WorkingBuffer)
    episodic_buffer: EpisodicBuffer = field(default_factory=EpisodicBuffer)
    semantic_buffer: SemanticBuffer = field(default_factory=SemanticBuffer)

    @classmethod
    def for_model(
        cls,
        model_name: str,
        system_prompt: Optional[str] = None
    ) -> "FOVContextManager":
        """Create a context manager configured for a specific model."""
        config = AdaptiveBudgetConfig.for_model(model_name)
        return cls(
            budget_config=config,
            base_system_prompt=system_prompt or DEFAULT_SYSTEM_PROMPT
        )

    @classmethod
    def for_context_window(
        cls,
        context_window: int,
        system_prompt: Optional[str] = None
    ) -> "FOVContextManager":
        """Create a context manager for a given context window size."""
        config = AdaptiveBudgetConfig.from_context_window(context_window)
        return cls(
            budget_config=config,
            base_system_prompt=system_prompt or DEFAULT_SYSTEM_PROMPT
        )

    # --- Context Building ---

    def build_context(
        self,
        conversation_history: Optional[list[ConversationTurn]] = None,
        barge_in_utterance: Optional[str] = None
    ) -> FOVContext:
        """
        Build complete foveated context for an LLM call.

        Args:
            conversation_history: Recent conversation turns
            barge_in_utterance: User's barge-in utterance if interrupting

        Returns:
            FOVContext with all buffer layers rendered
        """
        budgets = self.budget_config.budgets

        # Update immediate buffer with current state
        if conversation_history:
            max_turns = self.budget_config.max_conversation_turns
            self.immediate_buffer.recent_turns = list(conversation_history[-max_turns:])

        if barge_in_utterance:
            self.immediate_buffer.barge_in_utterance = barge_in_utterance

        # Render each buffer within its budget
        immediate_context = self.immediate_buffer.render(budgets.immediate)
        working_context = self.working_buffer.render(budgets.working)
        episodic_context = self.episodic_buffer.render(budgets.episodic)
        semantic_context = self.semantic_buffer.render(budgets.semantic)

        context = FOVContext(
            system_prompt=self.base_system_prompt,
            immediate_context=immediate_context,
            working_context=working_context,
            episodic_context=episodic_context,
            semantic_context=semantic_context
        )

        logger.debug(
            "Built FOV context",
            extra={
                "tier": self.budget_config.tier.value,
                "total_tokens": context.total_token_estimate,
                "has_barge_in": barge_in_utterance is not None
            }
        )

        return context

    def build_messages_for_llm(
        self,
        conversation_history: Optional[list[ConversationTurn]] = None,
        barge_in_utterance: Optional[str] = None
    ) -> list[dict]:
        """
        Build complete message list for LLM call.

        Returns list of messages with system prompt containing foveated context,
        followed by conversation history.
        """
        context = self.build_context(conversation_history, barge_in_utterance)

        messages = context.to_messages()

        # Add conversation history as separate messages
        if conversation_history:
            max_turns = self.budget_config.max_conversation_turns
            for turn in conversation_history[-max_turns:]:
                messages.append({
                    "role": turn.role.value,
                    "content": turn.content
                })

        return messages

    # --- Immediate Buffer Management ---

    def set_current_segment(self, segment: TranscriptSegment) -> None:
        """Set the current transcript segment being played."""
        self.immediate_buffer.current_segment = segment

    def record_barge_in(
        self,
        utterance: str,
        interrupted_position: Optional[float] = None
    ) -> None:
        """Record a barge-in/interruption event."""
        self.immediate_buffer.barge_in_utterance = utterance
        self.immediate_buffer.interrupted_at_position = interrupted_position

    def clear_barge_in(self) -> None:
        """Clear barge-in state after handling."""
        self.immediate_buffer.barge_in_utterance = None
        self.immediate_buffer.interrupted_at_position = None

    def add_conversation_turn(self, turn: ConversationTurn) -> None:
        """Add a turn to the conversation history."""
        self.immediate_buffer.recent_turns.append(turn)

        # Trim to max turns
        max_turns = self.budget_config.max_conversation_turns
        if len(self.immediate_buffer.recent_turns) > max_turns:
            self.immediate_buffer.recent_turns = (
                self.immediate_buffer.recent_turns[-max_turns:]
            )

    # --- Working Buffer Management ---

    def update_working_buffer(
        self,
        topic_id: Optional[str] = None,
        topic_title: Optional[str] = None,
        topic_content: Optional[str] = None,
        learning_objectives: Optional[list[str]] = None,
        glossary_terms: Optional[list[GlossaryTerm]] = None,
        misconception_triggers: Optional[list[MisconceptionTrigger]] = None
    ) -> None:
        """Update the working buffer with current topic information."""
        if topic_id is not None:
            self.working_buffer.topic_id = topic_id
        if topic_title is not None:
            self.working_buffer.topic_title = topic_title
        if topic_content is not None:
            self.working_buffer.topic_content = topic_content
        if learning_objectives is not None:
            self.working_buffer.learning_objectives = learning_objectives
        if glossary_terms is not None:
            self.working_buffer.glossary_terms = glossary_terms
        if misconception_triggers is not None:
            self.working_buffer.misconception_triggers = misconception_triggers

        logger.debug(
            "Updated working buffer",
            extra={"topic_id": topic_id, "topic_title": topic_title}
        )

    def set_current_topic(
        self,
        topic_id: str,
        topic_title: str,
        topic_content: str,
        learning_objectives: list[str],
        glossary_terms: Optional[list[GlossaryTerm]] = None,
        misconception_triggers: Optional[list[MisconceptionTrigger]] = None
    ) -> None:
        """Set the complete current topic context."""
        self.working_buffer = WorkingBuffer(
            topic_id=topic_id,
            topic_title=topic_title,
            topic_content=topic_content,
            learning_objectives=learning_objectives,
            glossary_terms=glossary_terms or [],
            misconception_triggers=misconception_triggers or []
        )

    # --- Episodic Buffer Management ---

    def record_topic_completion(self, summary: TopicSummary) -> None:
        """Record a completed topic."""
        self.episodic_buffer.topic_summaries.append(summary)

        # Keep only recent summaries
        max_summaries = 10
        if len(self.episodic_buffer.topic_summaries) > max_summaries:
            self.episodic_buffer.topic_summaries = (
                self.episodic_buffer.topic_summaries[-max_summaries:]
            )

        logger.debug(
            "Recorded topic completion",
            extra={
                "topic_id": summary.topic_id,
                "mastery": summary.mastery_level
            }
        )

    def record_user_question(self, question: str) -> None:
        """Record a user question for context."""
        self.episodic_buffer.user_questions.append(question)

        # Keep only recent questions
        max_questions = 10
        if len(self.episodic_buffer.user_questions) > max_questions:
            self.episodic_buffer.user_questions = (
                self.episodic_buffer.user_questions[-max_questions:]
            )

    def record_clarification_request(self) -> None:
        """Record that the user requested clarification."""
        self.episodic_buffer.learner_signals.clarification_requests += 1

    def record_repetition_request(self) -> None:
        """Record that the user requested repetition."""
        self.episodic_buffer.learner_signals.repetition_requests += 1

    def record_confusion_signal(self) -> None:
        """Record a confusion indicator."""
        self.episodic_buffer.learner_signals.confusion_indicators += 1

    def set_pace_preference(self, preference: PacePreference) -> None:
        """Set the detected pace preference."""
        self.episodic_buffer.learner_signals.pace_preference = preference

    def update_session_duration(self) -> None:
        """Update the session duration."""
        duration = datetime.now() - self.episodic_buffer.session_start
        self.episodic_buffer.session_duration_minutes = duration.total_seconds() / 60

    # --- Semantic Buffer Management ---

    def update_semantic_buffer(
        self,
        curriculum_outline: Optional[str] = None,
        position: Optional[CurriculumPosition] = None,
        prerequisite_topics: Optional[list[str]] = None,
        upcoming_topics: Optional[list[str]] = None
    ) -> None:
        """Update the semantic buffer with curriculum context."""
        if curriculum_outline is not None:
            self.semantic_buffer.curriculum_outline = curriculum_outline
        if position is not None:
            self.semantic_buffer.position = position
        if prerequisite_topics is not None:
            self.semantic_buffer.prerequisite_topics = prerequisite_topics
        if upcoming_topics is not None:
            self.semantic_buffer.upcoming_topics = upcoming_topics

    def set_curriculum_position(
        self,
        curriculum_id: str,
        curriculum_title: str,
        current_topic_index: int,
        total_topics: int,
        unit_title: Optional[str] = None,
        module_title: Optional[str] = None
    ) -> None:
        """Set the current position in the curriculum."""
        self.semantic_buffer.position = CurriculumPosition(
            curriculum_id=curriculum_id,
            curriculum_title=curriculum_title,
            current_topic_index=current_topic_index,
            total_topics=total_topics,
            unit_title=unit_title,
            module_title=module_title
        )

    # --- State Management ---

    def reset(self) -> None:
        """Reset all buffers for a new session."""
        self.immediate_buffer = ImmediateBuffer()
        self.working_buffer = WorkingBuffer()
        self.episodic_buffer = EpisodicBuffer()
        self.semantic_buffer = SemanticBuffer()
        logger.info("FOV context manager reset")

    def get_state_snapshot(self) -> dict:
        """Get a snapshot of the current state for debugging/analytics."""
        return {
            "tier": self.budget_config.tier.value,
            "budgets": {
                "immediate": self.budget_config.budgets.immediate,
                "working": self.budget_config.budgets.working,
                "episodic": self.budget_config.budgets.episodic,
                "semantic": self.budget_config.budgets.semantic,
                "total": self.budget_config.budgets.total
            },
            "immediate": {
                "turn_count": len(self.immediate_buffer.recent_turns),
                "has_barge_in": self.immediate_buffer.barge_in_utterance is not None,
                "has_segment": self.immediate_buffer.current_segment is not None
            },
            "working": {
                "topic_id": self.working_buffer.topic_id,
                "topic_title": self.working_buffer.topic_title,
                "objective_count": len(self.working_buffer.learning_objectives),
                "glossary_count": len(self.working_buffer.glossary_terms),
                "misconception_count": len(self.working_buffer.misconception_triggers)
            },
            "episodic": {
                "topic_count": len(self.episodic_buffer.topic_summaries),
                "question_count": len(self.episodic_buffer.user_questions),
                "clarification_requests": (
                    self.episodic_buffer.learner_signals.clarification_requests
                ),
                "session_minutes": self.episodic_buffer.session_duration_minutes
            },
            "semantic": {
                "has_outline": bool(self.semantic_buffer.curriculum_outline),
                "has_position": self.semantic_buffer.position is not None,
                "prerequisite_count": len(self.semantic_buffer.prerequisite_topics),
                "upcoming_count": len(self.semantic_buffer.upcoming_topics)
            }
        }
