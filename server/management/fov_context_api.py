"""
FOV Context API - REST endpoints for session and context management

Provides endpoints for:
- Session lifecycle (create, start, end)
- Context updates (topic, position, conversation)
- Context building for LLM calls
- Confidence analysis and expansion recommendations
"""

import logging
from aiohttp import web

from fov_context import (
    FOVSession,
    SessionConfig,
    SessionManager,
    SessionState,
    ConversationTurn,
    MessageRole,
    TranscriptSegment,
    GlossaryTerm,
    MisconceptionTrigger,
)

logger = logging.getLogger(__name__)

# Global session manager
_session_manager: SessionManager = SessionManager()


def get_session_manager() -> SessionManager:
    """Get the global session manager."""
    return _session_manager


def setup_fov_context_routes(app: web.Application) -> None:
    """Register FOV context API routes."""
    app.router.add_post("/api/sessions", handle_create_session)
    app.router.add_get("/api/sessions", handle_list_sessions)
    app.router.add_get("/api/sessions/{session_id}", handle_get_session)
    app.router.add_post("/api/sessions/{session_id}/start", handle_start_session)
    app.router.add_post("/api/sessions/{session_id}/pause", handle_pause_session)
    app.router.add_post("/api/sessions/{session_id}/resume", handle_resume_session)
    app.router.add_post("/api/sessions/{session_id}/end", handle_end_session)
    app.router.add_delete("/api/sessions/{session_id}", handle_delete_session)

    # Context updates
    app.router.add_put("/api/sessions/{session_id}/topic", handle_set_topic)
    app.router.add_put("/api/sessions/{session_id}/position", handle_set_position)
    app.router.add_put("/api/sessions/{session_id}/segment", handle_set_segment)

    # Conversation
    app.router.add_post("/api/sessions/{session_id}/turns", handle_add_turn)
    app.router.add_post("/api/sessions/{session_id}/barge-in", handle_barge_in)

    # Context building
    app.router.add_get("/api/sessions/{session_id}/context", handle_get_context)
    app.router.add_post("/api/sessions/{session_id}/context/build", handle_build_context)
    app.router.add_get("/api/sessions/{session_id}/messages", handle_get_messages)

    # Confidence analysis
    app.router.add_post(
        "/api/sessions/{session_id}/analyze-response",
        handle_analyze_response
    )

    # Learner signals
    app.router.add_post("/api/sessions/{session_id}/signals", handle_record_signal)

    # Events
    app.router.add_get("/api/sessions/{session_id}/events", handle_get_events)

    # Debug and observability
    app.router.add_get("/api/sessions/{session_id}/debug", handle_debug_session)
    app.router.add_get("/api/fov/health", handle_fov_health)

    logger.info("FOV context API routes registered")


# --- Session Lifecycle Handlers ---

async def handle_create_session(request: web.Request) -> web.Response:
    """
    Create a new session.

    POST /api/sessions
    {
        "curriculum_id": "uuid",
        "model_name": "claude-3-5-sonnet-20241022",  // optional
        "model_context_window": 200000,  // optional
        "system_prompt": "...",  // optional
        "auto_expand_context": true  // optional
    }
    """
    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    curriculum_id = data.get("curriculum_id")
    if not curriculum_id:
        return web.json_response(
            {"error": "curriculum_id is required"},
            status=400
        )

    config = SessionConfig(
        model_name=data.get("model_name", "claude-3-5-sonnet-20241022"),
        model_context_window=data.get("model_context_window", 200_000),
        system_prompt=data.get("system_prompt"),
        auto_expand_context=data.get("auto_expand_context", True)
    )

    session = _session_manager.create_session(curriculum_id, config)

    return web.json_response({
        "session_id": session.session_id,
        "curriculum_id": session.curriculum_id,
        "state": session.state.value,
        "created_at": session.created_at.isoformat()
    }, status=201)


async def handle_list_sessions(request: web.Request) -> web.Response:
    """
    List all active sessions.

    GET /api/sessions
    """
    sessions = _session_manager.list_sessions()
    return web.json_response({"sessions": sessions})


async def handle_get_session(request: web.Request) -> web.Response:
    """
    Get session details.

    GET /api/sessions/{session_id}
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    return web.json_response(session.get_state())


async def handle_start_session(request: web.Request) -> web.Response:
    """
    Start a session.

    POST /api/sessions/{session_id}/start
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    session.start()
    return web.json_response({"state": session.state.value})


async def handle_pause_session(request: web.Request) -> web.Response:
    """
    Pause a session.

    POST /api/sessions/{session_id}/pause
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    session.pause()
    return web.json_response({"state": session.state.value})


async def handle_resume_session(request: web.Request) -> web.Response:
    """
    Resume a paused session.

    POST /api/sessions/{session_id}/resume
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    session.resume()
    return web.json_response({"state": session.state.value})


async def handle_end_session(request: web.Request) -> web.Response:
    """
    End a session.

    POST /api/sessions/{session_id}/end
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    # Get final state before ending
    final_state = session.get_state()
    session.end()

    return web.json_response(final_state)


async def handle_delete_session(request: web.Request) -> web.Response:
    """
    Delete a session.

    DELETE /api/sessions/{session_id}
    """
    session_id = request.match_info["session_id"]

    if _session_manager.end_session(session_id):
        return web.json_response({"deleted": True})
    else:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )


# --- Context Update Handlers ---

async def handle_set_topic(request: web.Request) -> web.Response:
    """
    Set the current topic.

    PUT /api/sessions/{session_id}/topic
    {
        "topic_id": "uuid",
        "topic_title": "Introduction to Physics",
        "topic_content": "...",
        "learning_objectives": ["..."],
        "glossary_terms": [{"term": "...", "definition": "..."}],
        "misconceptions": [{"trigger_phrase": "...", "misconception": "...", "remediation": "..."}]
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    topic_id = data.get("topic_id")
    topic_title = data.get("topic_title")
    topic_content = data.get("topic_content", "")
    learning_objectives = data.get("learning_objectives", [])
    glossary_terms = data.get("glossary_terms", [])
    misconceptions = data.get("misconceptions", [])

    if not topic_id or not topic_title:
        return web.json_response(
            {"error": "topic_id and topic_title are required"},
            status=400
        )

    session.set_current_topic(
        topic_id=topic_id,
        topic_title=topic_title,
        topic_content=topic_content,
        learning_objectives=learning_objectives,
        glossary_terms=glossary_terms,
        misconceptions=misconceptions
    )

    return web.json_response({
        "topic_id": topic_id,
        "topic_title": topic_title
    })


async def handle_set_position(request: web.Request) -> web.Response:
    """
    Set the curriculum position.

    PUT /api/sessions/{session_id}/position
    {
        "curriculum_title": "Physics 101",
        "current_topic_index": 3,
        "total_topics": 20,
        "unit_title": "Mechanics",
        "curriculum_outline": "1. Introduction\n2. Motion\n..."
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    session.set_curriculum_position(
        curriculum_title=data.get("curriculum_title", ""),
        current_topic_index=data.get("current_topic_index", 0),
        total_topics=data.get("total_topics", 1),
        unit_title=data.get("unit_title"),
        curriculum_outline=data.get("curriculum_outline")
    )

    return web.json_response({"updated": True})


async def handle_set_segment(request: web.Request) -> web.Response:
    """
    Set the current transcript segment.

    PUT /api/sessions/{session_id}/segment
    {
        "segment_id": "uuid",
        "text": "...",
        "start_time": 0.0,
        "end_time": 10.5,
        "topic_id": "uuid"
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    segment = TranscriptSegment(
        segment_id=data.get("segment_id", ""),
        text=data.get("text", ""),
        start_time=data.get("start_time", 0.0),
        end_time=data.get("end_time", 0.0),
        topic_id=data.get("topic_id")
    )

    session.set_current_segment(segment)

    return web.json_response({"updated": True})


# --- Conversation Handlers ---

async def handle_add_turn(request: web.Request) -> web.Response:
    """
    Add a conversation turn.

    POST /api/sessions/{session_id}/turns
    {
        "role": "user" | "assistant",
        "content": "..."
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    role = data.get("role", "user")
    content = data.get("content", "")

    if role == "user":
        turn = session.add_user_turn(content)
    else:
        turn = session.add_assistant_turn(content)

    return web.json_response({
        "turn_id": turn.id,
        "role": turn.role.value,
        "timestamp": turn.timestamp.isoformat()
    })


async def handle_barge_in(request: web.Request) -> web.Response:
    """
    Handle a barge-in/interruption event.

    POST /api/sessions/{session_id}/barge-in
    {
        "utterance": "Wait, can you explain that again?",
        "interrupted_position": 15.5  // optional, seconds into segment
    }

    Returns the built context for the LLM call.
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    utterance = data.get("utterance", "")
    interrupted_position = data.get("interrupted_position")

    # Record the barge-in as a user turn
    session.add_user_turn(utterance, is_barge_in=True)

    # Build context for LLM
    context = session.build_llm_context(barge_in_utterance=utterance)
    messages = session.build_llm_messages(barge_in_utterance=utterance)

    return web.json_response({
        "session_id": session_id,
        "barge_in_count": session.barge_in_count,
        "context": {
            "system_prompt": context.system_prompt,
            "immediate": context.immediate_context,
            "working": context.working_context,
            "episodic": context.episodic_context,
            "semantic": context.semantic_context,
            "total_tokens": context.total_token_estimate
        },
        "messages": messages
    })


# --- Context Building Handlers ---

async def handle_get_context(request: web.Request) -> web.Response:
    """
    Get the current FOV context state.

    GET /api/sessions/{session_id}/context
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    return web.json_response(session.context_manager.get_state_snapshot())


async def handle_build_context(request: web.Request) -> web.Response:
    """
    Build the FOV context for an LLM call.

    POST /api/sessions/{session_id}/context/build
    {
        "barge_in_utterance": "..."  // optional
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        data = {}

    barge_in_utterance = data.get("barge_in_utterance")

    context = session.build_llm_context(barge_in_utterance)

    return web.json_response({
        "system_message": context.to_system_message(),
        "immediate": context.immediate_context,
        "working": context.working_context,
        "episodic": context.episodic_context,
        "semantic": context.semantic_context,
        "total_tokens": context.total_token_estimate
    })


async def handle_get_messages(request: web.Request) -> web.Response:
    """
    Get the complete message list for an LLM call.

    GET /api/sessions/{session_id}/messages
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    messages = session.build_llm_messages()

    return web.json_response({"messages": messages})


# --- Confidence Analysis Handlers ---

async def handle_analyze_response(request: web.Request) -> web.Response:
    """
    Analyze an LLM response for confidence.

    POST /api/sessions/{session_id}/analyze-response
    {
        "response": "I'm not sure, but I think..."
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    response = data.get("response", "")

    analysis, recommendation = session.process_response_with_confidence(response)

    result = {
        "confidence_score": analysis.confidence_score,
        "uncertainty_score": analysis.uncertainty_score,
        "hedging_score": analysis.hedging_score,
        "deflection_score": analysis.question_deflection_score,
        "knowledge_gap_score": analysis.knowledge_gap_score,
        "vague_language_score": analysis.vague_language_score,
        "detected_markers": [m.value for m in analysis.detected_markers],
        "trend": analysis.trend.value
    }

    if recommendation:
        result["expansion"] = {
            "should_expand": recommendation.should_expand,
            "priority": recommendation.priority.value,
            "scope": recommendation.suggested_scope.value,
            "reason": recommendation.reason
        }

    return web.json_response(result)


# --- Learner Signal Handlers ---

async def handle_record_signal(request: web.Request) -> web.Response:
    """
    Record a learner signal.

    POST /api/sessions/{session_id}/signals
    {
        "signal_type": "clarification" | "repetition" | "confusion" | "question",
        "content": "..."  // optional, for questions
    }
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    try:
        data = await request.json()
    except Exception:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )

    signal_type = data.get("signal_type", "")
    content = data.get("content")

    if signal_type == "clarification":
        session.record_clarification_request()
    elif signal_type == "repetition":
        session.record_repetition_request()
    elif signal_type == "confusion":
        session.record_confusion_signal()
    elif signal_type == "question" and content:
        session.context_manager.record_user_question(content)
    else:
        return web.json_response(
            {"error": f"Unknown signal type: {signal_type}"},
            status=400
        )

    return web.json_response({"recorded": True})


# --- Event Handlers ---

async def handle_get_events(request: web.Request) -> web.Response:
    """
    Get session events.

    GET /api/sessions/{session_id}/events?type=barge_in
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    event_type = request.query.get("type")
    events = session.get_events(event_type)

    return web.json_response({"events": events})


# --- Debug and Observability Handlers ---

async def handle_debug_session(request: web.Request) -> web.Response:
    """
    Get detailed debug information for a session.

    GET /api/sessions/{session_id}/debug

    Returns comprehensive buffer state, token usage, and diagnostic info.
    """
    session_id = request.match_info["session_id"]
    session = _session_manager.get_session(session_id)

    if not session:
        return web.json_response(
            {"error": "Session not found"},
            status=404
        )

    # Get base state snapshot
    state = session.context_manager.get_state_snapshot()

    # Get buffer configs
    budget_config = session.context_manager.budget_config

    # Calculate token usage percentages
    budgets = state.get("budgets", {})
    token_usage = {}
    for buffer_name, budget in budgets.items():
        if budget > 0:
            # Estimate current usage for each buffer
            if buffer_name == "immediate":
                current = len(session.context_manager.immediate_buffer.recent_turns) * 50
            elif buffer_name == "working":
                working = session.context_manager.working_buffer
                current = len(working.topic_content or "") // 4
            elif buffer_name == "episodic":
                episodic = session.context_manager.episodic_buffer
                current = len(episodic.topic_summaries) * 100
            elif buffer_name == "semantic":
                semantic = session.context_manager.semantic_buffer
                current = len(semantic.curriculum_outline or "") // 4
            else:
                current = 0
            token_usage[buffer_name] = {
                "budget": budget,
                "estimated_used": current,
                "percentage": round((current / budget) * 100, 1) if budget > 0 else 0
            }

    # Build current context to get actual estimates
    context = session.build_llm_context()

    # Get confidence history
    confidence_history = []
    for event in session.get_events("confidence_analysis"):
        confidence_history.append({
            "timestamp": event.get("timestamp"),
            "score": event.get("confidence_score"),
            "uncertainty": event.get("uncertainty_score")
        })

    # Get barge-in history
    barge_in_history = session.get_events("barge_in")

    debug_info = {
        "session_id": session_id,
        "state": session.state.value,
        "curriculum_id": session.curriculum_id,
        "turn_count": session.turn_count,
        "barge_in_count": session.barge_in_count,
        "model_tier": state.get("tier"),
        "buffers": {
            "immediate": {
                "current_segment": state.get("immediate", {}).get("current_segment"),
                "barge_in": state.get("immediate", {}).get("barge_in"),
                "turn_count": len(session.context_manager.immediate_buffer.recent_turns),
                "max_turns": budget_config.max_conversation_turns
            },
            "working": {
                "topic_id": state.get("working", {}).get("topic_id"),
                "topic_title": state.get("working", {}).get("topic_title"),
                "glossary_count": len(session.context_manager.working_buffer.glossary_terms),
                "misconception_count": len(session.context_manager.working_buffer.misconception_triggers)
            },
            "episodic": {
                "topic_summary_count": len(session.context_manager.episodic_buffer.topic_summaries),
                "questions_count": len(session.context_manager.episodic_buffer.user_questions),
                "learner_signals": {
                    "clarifications": session.context_manager.episodic_buffer.learner_signals.clarification_requests,
                    "repetitions": session.context_manager.episodic_buffer.learner_signals.repetition_requests,
                    "confusions": session.context_manager.episodic_buffer.learner_signals.confusion_indicators
                }
            },
            "semantic": {
                "curriculum_id": session.context_manager.semantic_buffer.position.curriculum_id,
                "current_topic_index": session.context_manager.semantic_buffer.position.current_topic_index,
                "total_topics": session.context_manager.semantic_buffer.position.total_topics,
                "has_outline": bool(session.context_manager.semantic_buffer.curriculum_outline)
            }
        },
        "token_usage": token_usage,
        "total_context_tokens": context.total_token_estimate,
        "confidence_history": confidence_history[-10:],  # Last 10 entries
        "barge_in_history": barge_in_history[-10:],  # Last 10 entries
        "budget_config": {
            "tier": budget_config.tier.value,
            "immediate_budget": budget_config.immediate_token_budget,
            "working_budget": budget_config.working_token_budget,
            "episodic_budget": budget_config.episodic_token_budget,
            "semantic_budget": budget_config.semantic_token_budget,
            "total_budget": budget_config.total_context_budget,
            "max_conversation_turns": budget_config.max_conversation_turns
        }
    }

    return web.json_response(debug_info)


async def handle_fov_health(request: web.Request) -> web.Response:
    """
    Get FOV context system health status.

    GET /api/fov/health

    Returns overall health and status of the FOV context system.
    """
    sessions = _session_manager.list_sessions()
    active_sessions = [s for s in sessions if s.get("state") == "active"]
    paused_sessions = [s for s in sessions if s.get("state") == "paused"]

    return web.json_response({
        "status": "healthy",
        "sessions": {
            "total": len(sessions),
            "active": len(active_sessions),
            "paused": len(paused_sessions)
        },
        "version": "1.0.0",
        "features": {
            "confidence_monitoring": True,
            "context_expansion": True,
            "adaptive_budgets": True,
            "model_tiers": ["CLOUD", "MID_RANGE", "ON_DEVICE", "TINY"]
        }
    })
