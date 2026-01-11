# Audio WebSocket Handler
# Real-time audio coordination between clients and server

import asyncio
import base64
import json
import logging
from datetime import datetime
from typing import Dict, List, Optional

import aiohttp
from aiohttp import web, WSMsgType

from fov_context import SessionManager, UserSession, UserVoiceConfig
from session_cache_integration import SessionCacheIntegration

logger = logging.getLogger(__name__)


class AudioWebSocketHandler:
    """Handles WebSocket connections for real-time audio streaming.

    Protocol:
    - Client connects with session_id query parameter
    - Server sends/receives JSON messages
    - Audio is base64 encoded in messages

    Message Types (Client -> Server):
    - request_audio: Request audio for a segment
    - sync: Heartbeat with playback position
    - barge_in: User interrupted playback
    - voice_config: Update voice settings

    Message Types (Server -> Client):
    - audio: Audio data response
    - error: Error response
    - prefetch_status: Background prefetch progress
    """

    def __init__(
        self,
        session_manager: SessionManager,
        session_cache: SessionCacheIntegration,
    ):
        """Initialize WebSocket handler.

        Args:
            session_manager: Session manager for user sessions
            session_cache: Session-cache integration for audio retrieval
        """
        self.session_manager = session_manager
        self.session_cache = session_cache

        # Active connections: session_id -> WebSocketResponse
        self._connections: Dict[str, web.WebSocketResponse] = {}

        # Segment data by curriculum (set by server.py)
        self._segments_by_topic: Dict[str, Dict[str, List[str]]] = {}

    def set_topic_segments(self, curriculum_id: str, topic_id: str, segments: List[str]) -> None:
        """Register segments for a topic.

        Args:
            curriculum_id: Curriculum identifier
            topic_id: Topic identifier
            segments: List of segment texts
        """
        if curriculum_id not in self._segments_by_topic:
            self._segments_by_topic[curriculum_id] = {}
        self._segments_by_topic[curriculum_id][topic_id] = segments

    def get_topic_segments(self, curriculum_id: str, topic_id: str) -> Optional[List[str]]:
        """Get segments for a topic."""
        if curriculum_id in self._segments_by_topic:
            return self._segments_by_topic[curriculum_id].get(topic_id)
        return None

    async def handle_connection(self, request: web.Request) -> web.WebSocketResponse:
        """Handle a new WebSocket connection.

        Args:
            request: HTTP request with session_id query parameter

        Returns:
            WebSocket response
        """
        session_id = request.query.get("session_id")
        user_id = request.query.get("user_id")

        ws = web.WebSocketResponse()
        await ws.prepare(request)

        # Get or create user session
        session: Optional[UserSession] = None

        if session_id:
            session = self.session_manager.get_user_session(session_id)

        if not session and user_id:
            session = self.session_manager.get_user_session_by_user(user_id)

        if not session:
            if user_id:
                session = self.session_manager.create_user_session(user_id)
            else:
                await ws.send_json({
                    "type": "error",
                    "error": "No session_id or user_id provided",
                })
                await ws.close()
                return ws

        # Register connection
        self._connections[session.session_id] = ws
        logger.info(f"WebSocket connected: session {session.session_id}, user {session.user_id}")

        try:
            await self._handle_messages(ws, session)
        except Exception as e:
            logger.error(f"WebSocket error for session {session.session_id}: {e}")
        finally:
            # Cleanup
            if session.session_id in self._connections:
                del self._connections[session.session_id]
            logger.info(f"WebSocket disconnected: session {session.session_id}")

        return ws

    async def _handle_messages(self, ws: web.WebSocketResponse, session: UserSession) -> None:
        """Handle incoming messages from a WebSocket connection."""
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    msg_type = data.get("type")

                    if msg_type == "request_audio":
                        await self._handle_audio_request(ws, session, data)

                    elif msg_type == "sync":
                        await self._handle_sync(ws, session, data)

                    elif msg_type == "barge_in":
                        await self._handle_barge_in(ws, session, data)

                    elif msg_type == "voice_config":
                        await self._handle_voice_config(ws, session, data)

                    elif msg_type == "set_topic":
                        await self._handle_set_topic(ws, session, data)

                    else:
                        await ws.send_json({
                            "type": "error",
                            "error": f"Unknown message type: {msg_type}",
                        })

                except json.JSONDecodeError:
                    await ws.send_json({
                        "type": "error",
                        "error": "Invalid JSON message",
                    })
                except Exception as e:
                    logger.error(f"Error handling message: {e}")
                    await ws.send_json({
                        "type": "error",
                        "error": str(e),
                    })

            elif msg.type == WSMsgType.ERROR:
                logger.error(f"WebSocket error: {ws.exception()}")
                break

            elif msg.type == WSMsgType.CLOSE:
                break

    async def _handle_audio_request(
        self,
        ws: web.WebSocketResponse,
        session: UserSession,
        data: dict,
    ) -> None:
        """Handle request for audio segment.

        Client message:
        {
            "type": "request_audio",
            "segment_index": 0,
            "curriculum_id": "...",  // optional, uses session default
            "topic_id": "..."        // optional, uses session default
        }
        """
        segment_index = data.get("segment_index", 0)
        curriculum_id = data.get("curriculum_id") or session.playback_state.curriculum_id
        topic_id = data.get("topic_id") or session.playback_state.topic_id

        if not curriculum_id or not topic_id:
            await ws.send_json({
                "type": "error",
                "error": "No curriculum_id or topic_id set",
            })
            return

        # Get segments for topic
        segments = self.get_topic_segments(curriculum_id, topic_id)
        if not segments:
            await ws.send_json({
                "type": "error",
                "error": f"No segments found for {curriculum_id}/{topic_id}",
            })
            return

        if segment_index < 0 or segment_index >= len(segments):
            await ws.send_json({
                "type": "error",
                "error": f"Invalid segment_index: {segment_index}",
            })
            return

        segment_text = segments[segment_index]

        # Get audio (from cache or generate)
        try:
            audio_data, cache_hit, duration = await self.session_cache.get_audio_for_segment(
                session, segment_text
            )

            # Update playback state
            session.update_playback(segment_index, 0, True)

            # Send audio response
            await ws.send_json({
                "type": "audio",
                "segment_index": segment_index,
                "audio_base64": base64.b64encode(audio_data).decode("utf-8"),
                "duration_seconds": duration,
                "cache_hit": cache_hit,
                "total_segments": len(segments),
            })

            # Trigger prefetch for upcoming segments
            asyncio.create_task(
                self.session_cache.prefetch_upcoming(
                    session, segment_index, segments
                )
            )

        except Exception as e:
            logger.error(f"Error getting audio for segment {segment_index}: {e}")
            await ws.send_json({
                "type": "error",
                "error": f"Failed to get audio: {str(e)}",
                "segment_index": segment_index,
            })

    async def _handle_sync(
        self,
        ws: web.WebSocketResponse,
        session: UserSession,
        data: dict,
    ) -> None:
        """Handle playback sync/heartbeat.

        Client message:
        {
            "type": "sync",
            "segment_index": 5,
            "offset_ms": 1500,
            "is_playing": true
        }
        """
        segment_index = data.get("segment_index", session.playback_state.segment_index)
        offset_ms = data.get("offset_ms", 0)
        is_playing = data.get("is_playing", True)

        session.update_playback(segment_index, offset_ms, is_playing)

        # Acknowledge
        await ws.send_json({
            "type": "sync_ack",
            "segment_index": segment_index,
            "server_time": datetime.now().isoformat(),
        })

    async def _handle_barge_in(
        self,
        ws: web.WebSocketResponse,
        session: UserSession,
        data: dict,
    ) -> None:
        """Handle user barge-in (interruption).

        Client message:
        {
            "type": "barge_in",
            "segment_index": 5,
            "offset_ms": 1500,
            "utterance": "wait, what does that mean?"  // optional
        }
        """
        segment_index = data.get("segment_index", session.playback_state.segment_index)
        offset_ms = data.get("offset_ms", 0)
        utterance = data.get("utterance")

        # Update playback state (stopped)
        session.update_playback(segment_index, offset_ms, False)

        logger.info(
            f"Barge-in from session {session.session_id} at segment {segment_index}, "
            f"offset {offset_ms}ms"
        )

        # Acknowledge
        await ws.send_json({
            "type": "barge_in_ack",
            "segment_index": segment_index,
            "offset_ms": offset_ms,
        })

        # If there's an utterance, the client will handle it via the conversation API

    async def _handle_voice_config(
        self,
        ws: web.WebSocketResponse,
        session: UserSession,
        data: dict,
    ) -> None:
        """Handle voice configuration update.

        Client message:
        {
            "type": "voice_config",
            "voice_id": "nova",
            "tts_provider": "vibevoice",
            "speed": 1.0
        }
        """
        session.update_voice_config(
            voice_id=data.get("voice_id"),
            tts_provider=data.get("tts_provider"),
            speed=data.get("speed"),
            exaggeration=data.get("exaggeration"),
            cfg_weight=data.get("cfg_weight"),
            language=data.get("language"),
        )

        await ws.send_json({
            "type": "voice_config_ack",
            "voice_config": session.voice_config.to_dict(),
        })

    async def _handle_set_topic(
        self,
        ws: web.WebSocketResponse,
        session: UserSession,
        data: dict,
    ) -> None:
        """Handle set current topic.

        Client message:
        {
            "type": "set_topic",
            "curriculum_id": "physics-101",
            "topic_id": "quantum-intro"
        }
        """
        curriculum_id = data.get("curriculum_id")
        topic_id = data.get("topic_id")

        if not curriculum_id or not topic_id:
            await ws.send_json({
                "type": "error",
                "error": "Missing curriculum_id or topic_id",
            })
            return

        session.set_current_topic(curriculum_id, topic_id)

        # Get segment count
        segments = self.get_topic_segments(curriculum_id, topic_id)
        segment_count = len(segments) if segments else 0

        await ws.send_json({
            "type": "topic_set",
            "curriculum_id": curriculum_id,
            "topic_id": topic_id,
            "total_segments": segment_count,
        })

    async def broadcast_to_session(self, session_id: str, message: dict) -> bool:
        """Send a message to a specific session's WebSocket.

        Args:
            session_id: Target session
            message: Message to send

        Returns:
            True if sent, False if session not connected
        """
        ws = self._connections.get(session_id)
        if ws and not ws.closed:
            await ws.send_json(message)
            return True
        return False

    def get_connected_sessions(self) -> List[str]:
        """Get list of connected session IDs."""
        return list(self._connections.keys())


async def handle_audio_websocket(request: web.Request) -> web.WebSocketResponse:
    """WebSocket endpoint handler.

    Route: /ws/audio?session_id=xxx or /ws/audio?user_id=xxx
    """
    handler: AudioWebSocketHandler = request.app.get("audio_ws_handler")
    if not handler:
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        await ws.send_json({"type": "error", "error": "Audio handler not initialized"})
        await ws.close()
        return ws

    return await handler.handle_connection(request)


def register_audio_websocket(app: web.Application, handler: AudioWebSocketHandler) -> None:
    """Register audio WebSocket route.

    Args:
        app: aiohttp application
        handler: Audio WebSocket handler instance
    """
    app["audio_ws_handler"] = handler
    app.router.add_get("/ws/audio", handle_audio_websocket)
    logger.info("Audio WebSocket route registered: /ws/audio")
