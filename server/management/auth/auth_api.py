"""
Authentication API Routes

Provides REST endpoints for user authentication:
- Registration and login
- Token refresh and logout
- Device management
- Session management
- Profile management
- Password reset

Open source version - users operate independently (no organization required).
Enterprise extension points available for multi-tenant features.
"""

import uuid
import hashlib
import logging
from datetime import datetime, timezone
from typing import Optional
from aiohttp import web

from .password_service import PasswordService
from .token_service import TokenService, TokenConfig, RefreshTokenData
from .rate_limiter import RateLimiter

logger = logging.getLogger(__name__)


class AuthAPI:
    """Authentication API handler."""

    def __init__(
        self,
        db_pool,
        token_service: TokenService,
        rate_limiter: Optional[RateLimiter] = None,
    ):
        self.db = db_pool
        self.token_service = token_service
        self.rate_limiter = rate_limiter
        self.password_service = PasswordService()

    # =========================================================================
    # REGISTRATION
    # =========================================================================

    async def register(self, request: web.Request) -> web.Response:
        """
        Register a new user account.

        POST /api/auth/register
        {
            "email": "user@example.com",
            "password": "securepassword",
            "display_name": "User Name",  // optional
            "device": {  // optional, registers device on signup
                "fingerprint": "device-uuid",
                "name": "iPhone 15",
                "type": "ios",
                "model": "iPhone15,2",
                "os_version": "18.0",
                "app_version": "1.0.0"
            }
        }
        """
        try:
            data = await request.json()
        except Exception:
            return web.json_response(
                {"error": "invalid_json", "message": "Invalid JSON body"},
                status=400
            )

        email = data.get("email", "").strip().lower()
        password = data.get("password", "")
        display_name = data.get("display_name", "").strip() or None
        device_data = data.get("device")

        # Validate email
        if not email or "@" not in email:
            return web.json_response(
                {"error": "invalid_email", "message": "Valid email is required"},
                status=400
            )

        # Validate password
        if not password:
            return web.json_response(
                {"error": "invalid_password", "message": "Password is required"},
                status=400
            )

        # Check password strength
        strength = PasswordService.check_password_strength(password)
        if strength["score"] < 2:
            return web.json_response(
                {
                    "error": "weak_password",
                    "message": "Password is too weak",
                    "suggestions": strength["suggestions"]
                },
                status=400
            )

        async with self.db.acquire() as conn:
            # Check if email already exists
            existing = await conn.fetchrow(
                "SELECT id FROM users WHERE email = $1 AND organization_id IS NULL",
                email
            )
            if existing:
                return web.json_response(
                    {"error": "email_exists", "message": "Email already registered"},
                    status=409
                )

            # Get default privacy tier
            default_tier = await conn.fetchrow(
                "SELECT id FROM privacy_tiers WHERE is_system_default = true LIMIT 1"
            )

            # Hash password
            password_hash = PasswordService.hash_password(password)

            # Create user
            user_id = uuid.uuid4()
            now = datetime.now(timezone.utc)

            await conn.execute(
                """
                INSERT INTO users (
                    id, email, password_hash, password_updated_at,
                    display_name, privacy_tier_id, created_at, updated_at
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
                """,
                user_id,
                email,
                password_hash,
                now,
                display_name,
                default_tier["id"] if default_tier else None,
                now,
            )

            # Log registration
            await self._log_auth_event(
                conn,
                user_id=user_id,
                event_type="user_created",
                event_status="success",
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            response_data = {
                "user": {
                    "id": str(user_id),
                    "email": email,
                    "display_name": display_name,
                    "role": "user",
                }
            }

            # If device data provided, register device and create session
            if device_data and device_data.get("fingerprint"):
                device_result = await self._register_device(
                    conn, user_id, device_data, request
                )
                if device_result:
                    device_id, tokens = device_result
                    response_data["device"] = {"id": str(device_id)}
                    response_data["tokens"] = tokens

            return web.json_response(response_data, status=201)

    # =========================================================================
    # LOGIN
    # =========================================================================

    async def login(self, request: web.Request) -> web.Response:
        """
        Authenticate user and return tokens.

        POST /api/auth/login
        {
            "email": "user@example.com",
            "password": "securepassword",
            "device": {
                "fingerprint": "device-uuid",
                "name": "iPhone 15",
                "type": "ios"
            }
        }
        """
        try:
            data = await request.json()
        except Exception:
            return web.json_response(
                {"error": "invalid_json", "message": "Invalid JSON body"},
                status=400
            )

        email = data.get("email", "").strip().lower()
        password = data.get("password", "")
        device_data = data.get("device", {})

        if not email or not password:
            return web.json_response(
                {"error": "missing_credentials", "message": "Email and password required"},
                status=400
            )

        if not device_data.get("fingerprint"):
            return web.json_response(
                {"error": "missing_device", "message": "Device fingerprint required"},
                status=400
            )

        async with self.db.acquire() as conn:
            # Find user
            user = await conn.fetchrow(
                """
                SELECT id, email, password_hash, display_name, role,
                       is_active, is_locked, organization_id
                FROM users
                WHERE email = $1 AND organization_id IS NULL
                """,
                email
            )

            if not user:
                await self._log_auth_event(
                    conn,
                    event_type="login_failed",
                    event_status="failure",
                    event_details={"reason": "user_not_found", "email": email},
                    ip_address=self._get_client_ip(request),
                    user_agent=request.headers.get("User-Agent"),
                )
                return web.json_response(
                    {"error": "invalid_credentials", "message": "Invalid email or password"},
                    status=401
                )

            # Check account status
            if not user["is_active"]:
                return web.json_response(
                    {"error": "account_inactive", "message": "Account is inactive"},
                    status=403
                )

            if user["is_locked"]:
                return web.json_response(
                    {"error": "account_locked", "message": "Account is locked"},
                    status=403
                )

            # Verify password
            if not PasswordService.verify_password(password, user["password_hash"]):
                await self._log_auth_event(
                    conn,
                    user_id=user["id"],
                    event_type="login_failed",
                    event_status="failure",
                    event_details={"reason": "invalid_password"},
                    ip_address=self._get_client_ip(request),
                    user_agent=request.headers.get("User-Agent"),
                )
                return web.json_response(
                    {"error": "invalid_credentials", "message": "Invalid email or password"},
                    status=401
                )

            # Register or update device
            device_result = await self._register_device(
                conn, user["id"], device_data, request
            )

            if not device_result:
                return web.json_response(
                    {"error": "device_error", "message": "Failed to register device"},
                    status=500
                )

            device_id, tokens = device_result

            # Update last login
            await conn.execute(
                "UPDATE users SET last_login_at = $1 WHERE id = $2",
                datetime.now(timezone.utc),
                user["id"]
            )

            # Log successful login
            await self._log_auth_event(
                conn,
                user_id=user["id"],
                device_id=device_id,
                event_type="login",
                event_status="success",
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({
                "user": {
                    "id": str(user["id"]),
                    "email": user["email"],
                    "display_name": user["display_name"],
                    "role": user["role"],
                },
                "device": {"id": str(device_id)},
                "tokens": tokens,
            })

    # =========================================================================
    # TOKEN REFRESH
    # =========================================================================

    async def refresh(self, request: web.Request) -> web.Response:
        """
        Refresh access token using refresh token.

        POST /api/auth/refresh
        {
            "refresh_token": "opaque-refresh-token"
        }
        """
        try:
            data = await request.json()
        except Exception:
            return web.json_response(
                {"error": "invalid_json", "message": "Invalid JSON body"},
                status=400
            )

        refresh_token = data.get("refresh_token", "")
        if not refresh_token:
            return web.json_response(
                {"error": "missing_token", "message": "Refresh token required"},
                status=400
            )

        # Hash token for lookup
        token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()

        async with self.db.acquire() as conn:
            # Find token
            token_record = await conn.fetchrow(
                """
                SELECT rt.id, rt.user_id, rt.device_id, rt.token_family,
                       rt.generation, rt.is_revoked, rt.expires_at,
                       u.email, u.role, u.is_active, u.organization_id
                FROM refresh_tokens rt
                JOIN users u ON rt.user_id = u.id
                WHERE rt.token_hash = $1
                """,
                token_hash
            )

            if not token_record:
                return web.json_response(
                    {"error": "invalid_token", "message": "Invalid refresh token"},
                    status=401
                )

            # Check if revoked (possible token reuse attack)
            if token_record["is_revoked"]:
                # Revoke entire family as security measure
                await conn.execute(
                    "SELECT revoke_token_family($1, 'reuse_detected')",
                    token_record["token_family"]
                )
                logger.warning(
                    f"Token reuse detected for user {token_record['user_id']}, "
                    f"family {token_record['token_family']}"
                )
                return web.json_response(
                    {"error": "token_reused", "message": "Security violation detected"},
                    status=401
                )

            # Check expiry
            if token_record["expires_at"] < datetime.now(timezone.utc):
                return web.json_response(
                    {"error": "token_expired", "message": "Refresh token expired"},
                    status=401
                )

            # Check user status
            if not token_record["is_active"]:
                return web.json_response(
                    {"error": "account_inactive", "message": "Account is inactive"},
                    status=403
                )

            # Revoke old token
            await conn.execute(
                """
                UPDATE refresh_tokens
                SET is_revoked = true, revoked_at = $1, revoked_reason = 'rotated'
                WHERE id = $2
                """,
                datetime.now(timezone.utc),
                token_record["id"]
            )

            # Generate new tokens
            user_id = token_record["user_id"]
            device_id = token_record["device_id"]

            # Create new refresh token (same family, incremented generation)
            new_refresh = self.token_service.generate_refresh_token(
                user_id=str(user_id),
                device_id=str(device_id),
                family_id=str(token_record["token_family"]),
                generation=token_record["generation"] + 1,
            )

            # Store new refresh token
            await conn.execute(
                """
                INSERT INTO refresh_tokens (
                    id, user_id, device_id, token_hash, token_family,
                    generation, parent_token_id, expires_at,
                    ip_address, user_agent
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                """,
                uuid.UUID(new_refresh.token_id),
                user_id,
                device_id,
                new_refresh.token_hash,
                uuid.UUID(new_refresh.family_id),
                new_refresh.generation,
                token_record["id"],
                new_refresh.expires_at,
                self._get_client_ip(request),
                request.headers.get("User-Agent"),
            )

            # Generate new access token
            access_token, _ = self.token_service.generate_access_token(
                user_id=str(user_id),
                email=token_record["email"],
                role=token_record["role"],
                device_id=str(device_id),
                organization_id=str(token_record["organization_id"]) if token_record["organization_id"] else None,
            )

            # Update device last seen
            await conn.execute(
                "UPDATE devices SET last_seen_at = $1 WHERE id = $2",
                datetime.now(timezone.utc),
                device_id
            )

            # Log refresh
            await self._log_auth_event(
                conn,
                user_id=user_id,
                device_id=device_id,
                event_type="token_refresh",
                event_status="success",
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({
                "tokens": {
                    "access_token": access_token,
                    "refresh_token": new_refresh.token,
                    "token_type": "Bearer",
                    "expires_in": self.token_service.config.access_token_lifetime_minutes * 60,
                }
            })

    # =========================================================================
    # LOGOUT
    # =========================================================================

    async def logout(self, request: web.Request) -> web.Response:
        """
        Logout and revoke refresh token.

        POST /api/auth/logout
        {
            "refresh_token": "opaque-refresh-token",  // optional
            "all_devices": false  // optional, logout from all devices
        }
        """
        user_id = request.get("user_id")
        device_id = request.get("device_id")

        try:
            data = await request.json()
        except Exception:
            data = {}

        refresh_token = data.get("refresh_token")
        all_devices = data.get("all_devices", False)

        async with self.db.acquire() as conn:
            if all_devices and user_id:
                # Revoke all tokens for user
                await conn.execute(
                    """
                    UPDATE refresh_tokens
                    SET is_revoked = true, revoked_at = $1, revoked_reason = 'logout_all'
                    WHERE user_id = $2 AND is_revoked = false
                    """,
                    datetime.now(timezone.utc),
                    uuid.UUID(user_id)
                )
                # End all sessions
                await conn.execute(
                    """
                    UPDATE sessions
                    SET is_active = false, ended_at = $1, end_reason = 'logout_all'
                    WHERE user_id = $2 AND is_active = true
                    """,
                    datetime.now(timezone.utc),
                    uuid.UUID(user_id)
                )
            elif refresh_token:
                # Revoke specific token family
                token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
                token_record = await conn.fetchrow(
                    "SELECT token_family FROM refresh_tokens WHERE token_hash = $1",
                    token_hash
                )
                if token_record:
                    await conn.execute(
                        "SELECT revoke_token_family($1, 'logout')",
                        token_record["token_family"]
                    )

            # Log logout
            await self._log_auth_event(
                conn,
                user_id=uuid.UUID(user_id) if user_id else None,
                device_id=uuid.UUID(device_id) if device_id else None,
                event_type="logout",
                event_status="success",
                event_details={"all_devices": all_devices},
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({"message": "Logged out successfully"})

    # =========================================================================
    # PROFILE
    # =========================================================================

    async def get_me(self, request: web.Request) -> web.Response:
        """Get current user profile."""
        user_id = request.get("user_id")
        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        async with self.db.acquire() as conn:
            user = await conn.fetchrow(
                """
                SELECT id, email, email_verified, display_name, avatar_url,
                       locale, timezone, role, mfa_enabled, created_at, last_login_at
                FROM users WHERE id = $1
                """,
                uuid.UUID(user_id)
            )

            if not user:
                return web.json_response(
                    {"error": "not_found", "message": "User not found"},
                    status=404
                )

            return web.json_response({
                "user": {
                    "id": str(user["id"]),
                    "email": user["email"],
                    "email_verified": user["email_verified"],
                    "display_name": user["display_name"],
                    "avatar_url": user["avatar_url"],
                    "locale": user["locale"],
                    "timezone": user["timezone"],
                    "role": user["role"],
                    "mfa_enabled": user["mfa_enabled"],
                    "created_at": user["created_at"].isoformat() if user["created_at"] else None,
                    "last_login_at": user["last_login_at"].isoformat() if user["last_login_at"] else None,
                }
            })

    async def update_me(self, request: web.Request) -> web.Response:
        """Update current user profile."""
        user_id = request.get("user_id")
        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        try:
            data = await request.json()
        except Exception:
            return web.json_response(
                {"error": "invalid_json", "message": "Invalid JSON body"},
                status=400
            )

        # Allowed fields to update
        allowed = {"display_name", "avatar_url", "locale", "timezone"}
        updates = {k: v for k, v in data.items() if k in allowed}

        if not updates:
            return web.json_response(
                {"error": "no_updates", "message": "No valid fields to update"},
                status=400
            )

        async with self.db.acquire() as conn:
            # Build update query
            set_clauses = [f"{k} = ${i+2}" for i, k in enumerate(updates.keys())]
            set_clauses.append(f"updated_at = ${len(updates)+2}")

            query = f"""
                UPDATE users SET {', '.join(set_clauses)}
                WHERE id = $1
                RETURNING id, email, display_name, avatar_url, locale, timezone, role
            """

            values = [uuid.UUID(user_id)] + list(updates.values()) + [datetime.now(timezone.utc)]
            user = await conn.fetchrow(query, *values)

            await self._log_auth_event(
                conn,
                user_id=uuid.UUID(user_id),
                event_type="user_updated",
                event_status="success",
                event_details={"fields": list(updates.keys())},
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({
                "user": {
                    "id": str(user["id"]),
                    "email": user["email"],
                    "display_name": user["display_name"],
                    "avatar_url": user["avatar_url"],
                    "locale": user["locale"],
                    "timezone": user["timezone"],
                    "role": user["role"],
                }
            })

    # =========================================================================
    # PASSWORD MANAGEMENT
    # =========================================================================

    async def change_password(self, request: web.Request) -> web.Response:
        """
        Change password for authenticated user.

        POST /api/auth/password
        {
            "current_password": "oldpassword",
            "new_password": "newpassword"
        }
        """
        user_id = request.get("user_id")
        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        try:
            data = await request.json()
        except Exception:
            return web.json_response(
                {"error": "invalid_json", "message": "Invalid JSON body"},
                status=400
            )

        current_password = data.get("current_password", "")
        new_password = data.get("new_password", "")

        if not current_password or not new_password:
            return web.json_response(
                {"error": "missing_passwords", "message": "Current and new passwords required"},
                status=400
            )

        # Check new password strength
        strength = PasswordService.check_password_strength(new_password)
        if strength["score"] < 2:
            return web.json_response(
                {
                    "error": "weak_password",
                    "message": "New password is too weak",
                    "suggestions": strength["suggestions"]
                },
                status=400
            )

        async with self.db.acquire() as conn:
            user = await conn.fetchrow(
                "SELECT password_hash FROM users WHERE id = $1",
                uuid.UUID(user_id)
            )

            if not PasswordService.verify_password(current_password, user["password_hash"]):
                await self._log_auth_event(
                    conn,
                    user_id=uuid.UUID(user_id),
                    event_type="password_change",
                    event_status="failure",
                    event_details={"reason": "invalid_current_password"},
                    ip_address=self._get_client_ip(request),
                    user_agent=request.headers.get("User-Agent"),
                )
                return web.json_response(
                    {"error": "invalid_password", "message": "Current password is incorrect"},
                    status=401
                )

            # Update password
            new_hash = PasswordService.hash_password(new_password)
            now = datetime.now(timezone.utc)

            await conn.execute(
                """
                UPDATE users
                SET password_hash = $1, password_updated_at = $2, updated_at = $2
                WHERE id = $3
                """,
                new_hash,
                now,
                uuid.UUID(user_id)
            )

            # Revoke all refresh tokens except current device
            device_id = request.get("device_id")
            if device_id:
                await conn.execute(
                    """
                    UPDATE refresh_tokens
                    SET is_revoked = true, revoked_at = $1, revoked_reason = 'password_change'
                    WHERE user_id = $2 AND device_id != $3 AND is_revoked = false
                    """,
                    now,
                    uuid.UUID(user_id),
                    uuid.UUID(device_id)
                )

            await self._log_auth_event(
                conn,
                user_id=uuid.UUID(user_id),
                event_type="password_change",
                event_status="success",
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({"message": "Password changed successfully"})

    # =========================================================================
    # DEVICE MANAGEMENT
    # =========================================================================

    async def list_devices(self, request: web.Request) -> web.Response:
        """List user's registered devices."""
        user_id = request.get("user_id")
        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        async with self.db.acquire() as conn:
            devices = await conn.fetch(
                """
                SELECT id, device_name, device_type, device_model,
                       os_version, app_version, is_trusted, last_seen_at, created_at
                FROM devices
                WHERE user_id = $1 AND is_active = true
                ORDER BY last_seen_at DESC
                """,
                uuid.UUID(user_id)
            )

            return web.json_response({
                "devices": [
                    {
                        "id": str(d["id"]),
                        "name": d["device_name"],
                        "type": d["device_type"],
                        "model": d["device_model"],
                        "os_version": d["os_version"],
                        "app_version": d["app_version"],
                        "is_trusted": d["is_trusted"],
                        "last_seen_at": d["last_seen_at"].isoformat() if d["last_seen_at"] else None,
                        "created_at": d["created_at"].isoformat() if d["created_at"] else None,
                    }
                    for d in devices
                ]
            })

    async def remove_device(self, request: web.Request) -> web.Response:
        """Remove a device and revoke its tokens."""
        user_id = request.get("user_id")
        device_id = request.match_info.get("device_id")

        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        async with self.db.acquire() as conn:
            # Verify device belongs to user
            device = await conn.fetchrow(
                "SELECT id FROM devices WHERE id = $1 AND user_id = $2",
                uuid.UUID(device_id),
                uuid.UUID(user_id)
            )

            if not device:
                return web.json_response(
                    {"error": "not_found", "message": "Device not found"},
                    status=404
                )

            now = datetime.now(timezone.utc)

            # Revoke all tokens for device
            await conn.execute(
                """
                UPDATE refresh_tokens
                SET is_revoked = true, revoked_at = $1, revoked_reason = 'device_removed'
                WHERE device_id = $2 AND is_revoked = false
                """,
                now,
                uuid.UUID(device_id)
            )

            # Deactivate device
            await conn.execute(
                "UPDATE devices SET is_active = false WHERE id = $1",
                uuid.UUID(device_id)
            )

            await self._log_auth_event(
                conn,
                user_id=uuid.UUID(user_id),
                device_id=uuid.UUID(device_id),
                event_type="device_removed",
                event_status="success",
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({"message": "Device removed successfully"})

    # =========================================================================
    # SESSION MANAGEMENT
    # =========================================================================

    async def list_sessions(self, request: web.Request) -> web.Response:
        """List user's active sessions."""
        user_id = request.get("user_id")
        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        async with self.db.acquire() as conn:
            sessions = await conn.fetch(
                """
                SELECT s.id, s.ip_address, s.user_agent, s.location_country,
                       s.location_city, s.created_at, s.last_activity_at,
                       d.device_name, d.device_type
                FROM sessions s
                LEFT JOIN devices d ON s.device_id = d.id
                WHERE s.user_id = $1 AND s.is_active = true
                ORDER BY s.last_activity_at DESC
                """,
                uuid.UUID(user_id)
            )

            return web.json_response({
                "sessions": [
                    {
                        "id": str(s["id"]),
                        "ip_address": str(s["ip_address"]) if s["ip_address"] else None,
                        "user_agent": s["user_agent"],
                        "location": {
                            "country": s["location_country"],
                            "city": s["location_city"],
                        } if s["location_country"] else None,
                        "device": {
                            "name": s["device_name"],
                            "type": s["device_type"],
                        } if s["device_name"] else None,
                        "created_at": s["created_at"].isoformat() if s["created_at"] else None,
                        "last_activity_at": s["last_activity_at"].isoformat() if s["last_activity_at"] else None,
                    }
                    for s in sessions
                ]
            })

    async def terminate_session(self, request: web.Request) -> web.Response:
        """Terminate a specific session."""
        user_id = request.get("user_id")
        session_id = request.match_info.get("session_id")

        if not user_id:
            return web.json_response(
                {"error": "unauthorized", "message": "Authentication required"},
                status=401
            )

        async with self.db.acquire() as conn:
            result = await conn.execute(
                """
                UPDATE sessions
                SET is_active = false, ended_at = $1, end_reason = 'user_terminated'
                WHERE id = $2 AND user_id = $3 AND is_active = true
                """,
                datetime.now(timezone.utc),
                uuid.UUID(session_id),
                uuid.UUID(user_id)
            )

            if result == "UPDATE 0":
                return web.json_response(
                    {"error": "not_found", "message": "Session not found"},
                    status=404
                )

            await self._log_auth_event(
                conn,
                user_id=uuid.UUID(user_id),
                event_type="session_terminated",
                event_status="success",
                event_details={"session_id": session_id},
                ip_address=self._get_client_ip(request),
                user_agent=request.headers.get("User-Agent"),
            )

            return web.json_response({"message": "Session terminated"})

    # =========================================================================
    # HELPERS
    # =========================================================================

    async def _register_device(
        self,
        conn,
        user_id: uuid.UUID,
        device_data: dict,
        request: web.Request,
    ) -> Optional[tuple]:
        """Register or update device and create tokens."""
        fingerprint = device_data.get("fingerprint")
        if not fingerprint:
            return None

        # Check for existing device
        existing = await conn.fetchrow(
            "SELECT id FROM devices WHERE user_id = $1 AND device_fingerprint = $2",
            user_id,
            fingerprint
        )

        now = datetime.now(timezone.utc)
        client_ip = self._get_client_ip(request)

        if existing:
            device_id = existing["id"]
            # Update device info
            await conn.execute(
                """
                UPDATE devices SET
                    device_name = COALESCE($2, device_name),
                    device_model = COALESCE($3, device_model),
                    os_version = COALESCE($4, os_version),
                    app_version = COALESCE($5, app_version),
                    last_seen_at = $6,
                    last_ip_address = $7,
                    is_active = true
                WHERE id = $1
                """,
                device_id,
                device_data.get("name"),
                device_data.get("model"),
                device_data.get("os_version"),
                device_data.get("app_version"),
                now,
                client_ip,
            )
        else:
            device_id = uuid.uuid4()
            await conn.execute(
                """
                INSERT INTO devices (
                    id, user_id, device_fingerprint, device_name, device_type,
                    device_model, os_version, app_version, last_seen_at, last_ip_address
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                """,
                device_id,
                user_id,
                fingerprint,
                device_data.get("name"),
                device_data.get("type"),
                device_data.get("model"),
                device_data.get("os_version"),
                device_data.get("app_version"),
                now,
                client_ip,
            )

            await self._log_auth_event(
                conn,
                user_id=user_id,
                device_id=device_id,
                event_type="device_registered",
                event_status="success",
                ip_address=client_ip,
                user_agent=request.headers.get("User-Agent"),
            )

        # Generate tokens
        refresh_data = self.token_service.generate_refresh_token(
            user_id=str(user_id),
            device_id=str(device_id),
        )

        # Store refresh token
        refresh_token_id = uuid.uuid4()
        await conn.execute(
            """
            INSERT INTO refresh_tokens (
                id, user_id, device_id, token_hash, token_family,
                generation, expires_at, ip_address, user_agent
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            """,
            refresh_token_id,
            user_id,
            device_id,
            refresh_data.token_hash,
            uuid.UUID(refresh_data.family_id),
            refresh_data.generation,
            refresh_data.expires_at,
            client_ip,
            request.headers.get("User-Agent"),
        )

        # Get user info for access token
        user = await conn.fetchrow(
            "SELECT email, role, organization_id FROM users WHERE id = $1",
            user_id
        )

        access_token, _ = self.token_service.generate_access_token(
            user_id=str(user_id),
            email=user["email"],
            role=user["role"],
            device_id=str(device_id),
            organization_id=str(user["organization_id"]) if user["organization_id"] else None,
        )

        # Create session
        session_id = uuid.uuid4()
        await conn.execute(
            """
            INSERT INTO sessions (
                id, user_id, device_id, ip_address, user_agent
            ) VALUES ($1, $2, $3, $4, $5)
            """,
            session_id,
            user_id,
            device_id,
            client_ip,
            request.headers.get("User-Agent"),
        )

        tokens = {
            "access_token": access_token,
            "refresh_token": refresh_data.token,
            "token_type": "Bearer",
            "expires_in": self.token_service.config.access_token_lifetime_minutes * 60,
        }

        return device_id, tokens

    async def _log_auth_event(
        self,
        conn,
        user_id: Optional[uuid.UUID] = None,
        device_id: Optional[uuid.UUID] = None,
        organization_id: Optional[uuid.UUID] = None,
        event_type: str = "",
        event_status: str = "success",
        event_details: Optional[dict] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
        error_code: Optional[str] = None,
        error_message: Optional[str] = None,
    ):
        """Log authentication event to audit log."""
        import json

        await conn.execute(
            """
            INSERT INTO auth_audit_log (
                user_id, device_id, organization_id, event_type, event_status,
                event_details, ip_address, user_agent, error_code, error_message
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            """,
            user_id,
            device_id,
            organization_id,
            event_type,
            event_status,
            json.dumps(event_details) if event_details else None,
            ip_address,
            user_agent,
            error_code,
            error_message,
        )

    def _get_client_ip(self, request: web.Request) -> Optional[str]:
        """Extract client IP from request, considering proxies."""
        # Check X-Forwarded-For first (for reverse proxies)
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            # Take first IP (original client)
            return forwarded.split(",")[0].strip()

        # Fall back to direct connection
        peername = request.transport.get_extra_info("peername")
        if peername:
            return peername[0]

        return None


def register_auth_routes(app: web.Application, auth_api: AuthAPI):
    """Register authentication routes with the application."""
    app.router.add_post("/api/auth/register", auth_api.register)
    app.router.add_post("/api/auth/login", auth_api.login)
    app.router.add_post("/api/auth/refresh", auth_api.refresh)
    app.router.add_post("/api/auth/logout", auth_api.logout)

    app.router.add_get("/api/auth/me", auth_api.get_me)
    app.router.add_patch("/api/auth/me", auth_api.update_me)
    app.router.add_post("/api/auth/password", auth_api.change_password)

    app.router.add_get("/api/auth/devices", auth_api.list_devices)
    app.router.add_delete("/api/auth/devices/{device_id}", auth_api.remove_device)

    app.router.add_get("/api/auth/sessions", auth_api.list_sessions)
    app.router.add_delete("/api/auth/sessions/{session_id}", auth_api.terminate_session)
