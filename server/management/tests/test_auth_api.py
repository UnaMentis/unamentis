"""
Tests for Authentication API

Comprehensive tests for all authentication endpoints with real behavior testing.
Tests use minimal mocking - only the database layer is mocked to avoid external dependencies.
"""

import uuid
import json
import hashlib
import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web
from aiohttp.test_utils import make_mocked_request

from auth.auth_api import AuthAPI, register_auth_routes
from auth.token_service import TokenService, TokenConfig
from auth.password_service import PasswordService


class MockConnection:
    """Mock database connection that simulates asyncpg behavior."""

    def __init__(self, data_store: dict):
        self.data_store = data_store
        self.executed_queries = []
        # Track dynamically created users/devices for lookup
        self._created_users_by_id = {}
        self._created_devices_by_id = {}
        self._created_devices_by_fingerprint = {}

    async def fetchrow(self, query: str, *args):
        """Simulate fetchrow."""
        self.executed_queries.append((query, args))

        # Handle user lookup by email for existence check (registration)
        if "SELECT id FROM users WHERE email" in query:
            email = args[0]
            return self.data_store.get("users", {}).get(email)

        # Handle full user lookup by email (login) - matches query with password_hash, is_active, etc.
        if "SELECT" in query and "FROM users" in query and "WHERE email" in query:
            # Skip the simple "SELECT id FROM users WHERE email" pattern
            if "SELECT id FROM users WHERE email" not in query:
                email = args[0]
                return self.data_store.get("users", {}).get(email)

        # Handle user lookup by id (multiple select patterns)
        if "SELECT" in query and "FROM users WHERE id" in query:
            user_id = args[0]
            # Check dynamically created users first
            if user_id in self._created_users_by_id:
                return self._created_users_by_id[user_id]
            # Check pre-configured users
            for user in self.data_store.get("users", {}).values():
                if user.get("id") == user_id:
                    return user
            return None

        # Handle refresh token lookup
        if "FROM refresh_tokens" in query and "token_hash" in query:
            token_hash = args[0]
            return self.data_store.get("refresh_tokens", {}).get(token_hash)

        # Handle device lookup by user_id and fingerprint
        if "SELECT id FROM devices" in query and "user_id" in query and "fingerprint" in query:
            user_id = args[0]
            fingerprint = args[1]
            key = f"{user_id}:{fingerprint}"
            if key in self._created_devices_by_fingerprint:
                return self._created_devices_by_fingerprint[key]
            return self.data_store.get("devices", {}).get(fingerprint)

        # Handle device lookup by id and user_id (for device removal)
        if "SELECT" in query and "FROM devices WHERE id" in query and "user_id" in query:
            device_id = args[0]
            user_id = args[1]
            # Check stored devices by device_id
            if device_id in self._created_devices_by_id:
                device = self._created_devices_by_id[device_id]
                if device.get("user_id") == user_id:
                    return device
            # Check data_store devices
            for key, device in self.data_store.get("devices", {}).items():
                if device.get("id") == device_id and device.get("user_id") == user_id:
                    return device
            return None

        # Handle single device lookup by id only
        if "SELECT" in query and "FROM devices WHERE id" in query:
            device_id = args[0]
            if device_id in self._created_devices_by_id:
                return self._created_devices_by_id[device_id]
            return None

        # Handle privacy tier
        if "privacy_tiers" in query:
            return {"id": uuid.uuid4()}

        # Handle UPDATE...RETURNING for profile updates
        if "UPDATE users SET" in query and "RETURNING" in query:
            user_id = args[0]  # First arg is the user id
            # Find the user in data store
            for user in self.data_store.get("users", {}).values():
                if user.get("id") == user_id:
                    # Return updated user (simulate the update by returning current + updates)
                    # Args order: user_id, then update values, then updated_at
                    return {
                        "id": user["id"],
                        "email": user["email"],
                        "display_name": args[1] if len(args) > 1 else user.get("display_name"),
                        "avatar_url": user.get("avatar_url"),
                        "locale": user.get("locale"),
                        "timezone": user.get("timezone"),
                        "role": user.get("role", "user"),
                    }
            return None

        return None

    async def fetch(self, query: str, *args):
        """Simulate fetch (multiple rows)."""
        self.executed_queries.append((query, args))

        if "FROM devices" in query and "WHERE user_id" in query:
            user_id = str(args[0])
            # Include dynamically created devices
            devices = list(self.data_store.get("user_devices", {}).get(user_id, []))
            for key, device in self._created_devices_by_fingerprint.items():
                if key.startswith(f"{args[0]}:"):
                    devices.append(device)
            return devices

        if "FROM sessions" in query:
            return list(self.data_store.get("user_sessions", {}).get(str(args[0]), []))

        return []

    async def execute(self, query: str, *args):
        """Simulate execute."""
        self.executed_queries.append((query, args))

        # Track inserts for verification and create queryable records
        if "INSERT INTO users" in query:
            self.data_store.setdefault("created_users", []).append(args)
            # Store user for later lookup by id (args order: id, email, password_hash, display_name, ...)
            if len(args) >= 4:
                user_id = args[0]
                self._created_users_by_id[user_id] = {
                    "id": user_id,
                    "email": args[1],
                    "password_hash": args[2],
                    "display_name": args[3],
                    "role": "user",
                    "organization_id": None,
                    "is_active": True,
                    "is_locked": False,
                }

        if "INSERT INTO refresh_tokens" in query:
            self.data_store.setdefault("created_tokens", []).append(args)

        if "INSERT INTO devices" in query:
            self.data_store.setdefault("created_devices", []).append(args)
            # Store device for later lookup (args order: id, user_id, fingerprint, name, type, ...)
            if len(args) >= 5:
                device_id = args[0]
                user_id = args[1]
                fingerprint = args[2]
                self._created_devices_by_id[device_id] = {
                    "id": device_id,
                    "user_id": user_id,
                    "fingerprint": fingerprint,
                    "name": args[3] if len(args) > 3 else "Unknown",
                    "type": args[4] if len(args) > 4 else "unknown",
                }
                self._created_devices_by_fingerprint[f"{user_id}:{fingerprint}"] = self._created_devices_by_id[device_id]

        if "INSERT INTO sessions" in query:
            self.data_store.setdefault("created_sessions", []).append(args)

        if "INSERT INTO auth_audit_log" in query:
            self.data_store.setdefault("audit_logs", []).append(args)

        if "UPDATE" in query:
            return "UPDATE 1"

        if "DELETE" in query:
            return "DELETE 1"

        return None


class MockConnectionContext:
    """Context manager for mock connection."""

    def __init__(self, conn: MockConnection):
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, *args):
        pass


class MockDBPool:
    """Mock database pool."""

    def __init__(self, data_store: dict = None):
        self.data_store = data_store or {}
        self.conn = MockConnection(self.data_store)

    def acquire(self):
        return MockConnectionContext(self.conn)


def create_mock_request(
    method: str = "POST",
    path: str = "/api/auth/test",
    json_data: dict = None,
    headers: dict = None,
    match_info: dict = None,
    user_id: str = None,
    device_id: str = None,
) -> MagicMock:
    """Create a mock aiohttp request."""
    request = MagicMock(spec=web.Request)
    request.method = method
    request.path = path
    request.headers = headers or {}
    request.match_info = match_info or {}

    # Setup JSON parsing
    async def mock_json():
        if json_data is None:
            raise json.JSONDecodeError("No JSON", "", 0)
        return json_data

    request.json = mock_json

    # Setup request attributes (user_id, device_id from middleware)
    request.get = lambda key, default=None: {
        "user_id": user_id,
        "device_id": device_id,
    }.get(key, default)

    # Setup transport for IP extraction
    mock_transport = MagicMock()
    mock_transport.get_extra_info.return_value = ("127.0.0.1", 12345)
    request.transport = mock_transport

    return request


# =============================================================================
# REGISTRATION TESTS
# =============================================================================


class TestRegistration:
    """Tests for user registration endpoint."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI instance with mock database."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        return AuthAPI(db_pool, token_service)

    @pytest.mark.asyncio
    async def test_register_success(self, auth_api):
        """Test successful user registration."""
        request = create_mock_request(json_data={
            "email": "newuser@example.com",
            "password": "SecurePass123!",
            "display_name": "New User",
        })

        response = await auth_api.register(request)

        assert response.status == 201
        data = json.loads(response.body)
        assert "user" in data
        assert data["user"]["email"] == "newuser@example.com"
        assert data["user"]["display_name"] == "New User"
        assert data["user"]["role"] == "user"

    @pytest.mark.asyncio
    async def test_register_with_device(self, auth_api):
        """Test registration with device creates tokens."""
        request = create_mock_request(json_data={
            "email": "deviceuser@example.com",
            "password": "SecurePass123!",
            "device": {
                "fingerprint": "test-device-fingerprint",
                "name": "iPhone 15",
                "type": "ios",
            },
        })

        response = await auth_api.register(request)

        assert response.status == 201
        data = json.loads(response.body)
        assert "tokens" in data
        assert "access_token" in data["tokens"]
        assert "refresh_token" in data["tokens"]
        assert data["tokens"]["token_type"] == "Bearer"

    @pytest.mark.asyncio
    async def test_register_invalid_json(self, auth_api):
        """Test registration with invalid JSON returns 400."""
        request = create_mock_request(json_data=None)

        response = await auth_api.register(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "invalid_json"

    @pytest.mark.asyncio
    async def test_register_missing_email(self, auth_api):
        """Test registration without email returns 400."""
        request = create_mock_request(json_data={
            "password": "SecurePass123!",
        })

        response = await auth_api.register(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "invalid_email"

    @pytest.mark.asyncio
    async def test_register_invalid_email(self, auth_api):
        """Test registration with invalid email format returns 400."""
        request = create_mock_request(json_data={
            "email": "not-an-email",
            "password": "SecurePass123!",
        })

        response = await auth_api.register(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "invalid_email"

    @pytest.mark.asyncio
    async def test_register_missing_password(self, auth_api):
        """Test registration without password returns 400."""
        request = create_mock_request(json_data={
            "email": "user@example.com",
        })

        response = await auth_api.register(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "invalid_password"

    @pytest.mark.asyncio
    async def test_register_weak_password(self, auth_api):
        """Test registration with weak password returns 400."""
        request = create_mock_request(json_data={
            "email": "user@example.com",
            "password": "weak",
        })

        response = await auth_api.register(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "weak_password"
        assert "suggestions" in data

    @pytest.mark.asyncio
    async def test_register_email_exists(self, auth_api):
        """Test registration with existing email returns 409."""
        # Setup existing user
        auth_api.db.data_store["users"] = {
            "existing@example.com": {"id": uuid.uuid4()}
        }

        request = create_mock_request(json_data={
            "email": "existing@example.com",
            "password": "SecurePass123!",
        })

        response = await auth_api.register(request)

        assert response.status == 409
        data = json.loads(response.body)
        assert data["error"] == "email_exists"

    @pytest.mark.asyncio
    async def test_register_normalizes_email(self, auth_api):
        """Test that email is normalized to lowercase."""
        request = create_mock_request(json_data={
            "email": "  User@EXAMPLE.com  ",
            "password": "SecurePass123!",
        })

        response = await auth_api.register(request)

        assert response.status == 201
        data = json.loads(response.body)
        assert data["user"]["email"] == "user@example.com"

    @pytest.mark.asyncio
    async def test_register_logs_audit_event(self, auth_api):
        """Test that registration creates audit log entry."""
        request = create_mock_request(json_data={
            "email": "audit@example.com",
            "password": "SecurePass123!",
        })

        await auth_api.register(request)

        # Check audit log was created
        audit_logs = auth_api.db.data_store.get("audit_logs", [])
        assert len(audit_logs) > 0
        # Find user_created event
        events = [log for log in audit_logs if log[3] == "user_created"]
        assert len(events) > 0


# =============================================================================
# LOGIN TESTS
# =============================================================================


class TestLogin:
    """Tests for user login endpoint."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI with test user in database."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        api = AuthAPI(db_pool, token_service)

        # Create test user with hashed password
        test_password = "TestPassword123!"
        password_hash = PasswordService.hash_password(test_password)
        test_user_id = uuid.uuid4()

        api.db.data_store["users"] = {
            "test@example.com": {
                "id": test_user_id,
                "email": "test@example.com",
                "password_hash": password_hash,
                "display_name": "Test User",
                "role": "user",
                "is_active": True,
                "is_locked": False,
                "organization_id": None,
            }
        }
        api.db.data_store["test_password"] = test_password
        api.db.data_store["test_user_id"] = test_user_id

        return api

    @pytest.mark.asyncio
    async def test_login_success(self, auth_api):
        """Test successful login returns tokens."""
        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": auth_api.db.data_store["test_password"],
            "device": {
                "fingerprint": "login-device",
                "name": "Test Device",
                "type": "ios",
            },
        })

        response = await auth_api.login(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "user" in data
        assert "tokens" in data
        assert data["user"]["email"] == "test@example.com"
        assert "access_token" in data["tokens"]
        assert "refresh_token" in data["tokens"]

    @pytest.mark.asyncio
    async def test_login_invalid_json(self, auth_api):
        """Test login with invalid JSON returns 400."""
        request = create_mock_request(json_data=None)

        response = await auth_api.login(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "invalid_json"

    @pytest.mark.asyncio
    async def test_login_missing_credentials(self, auth_api):
        """Test login without email/password returns 400."""
        request = create_mock_request(json_data={
            "device": {"fingerprint": "test"},
        })

        response = await auth_api.login(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "missing_credentials"

    @pytest.mark.asyncio
    async def test_login_missing_device(self, auth_api):
        """Test login without device fingerprint returns 400."""
        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": "password",
        })

        response = await auth_api.login(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "missing_device"

    @pytest.mark.asyncio
    async def test_login_user_not_found(self, auth_api):
        """Test login with non-existent user returns 401."""
        request = create_mock_request(json_data={
            "email": "nonexistent@example.com",
            "password": "password",
            "device": {"fingerprint": "test"},
        })

        response = await auth_api.login(request)

        assert response.status == 401
        data = json.loads(response.body)
        assert data["error"] == "invalid_credentials"

    @pytest.mark.asyncio
    async def test_login_wrong_password(self, auth_api):
        """Test login with wrong password returns 401."""
        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": "WrongPassword123!",
            "device": {"fingerprint": "test"},
        })

        response = await auth_api.login(request)

        assert response.status == 401
        data = json.loads(response.body)
        assert data["error"] == "invalid_credentials"

    @pytest.mark.asyncio
    async def test_login_inactive_account(self, auth_api):
        """Test login to inactive account returns 403."""
        auth_api.db.data_store["users"]["test@example.com"]["is_active"] = False

        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": auth_api.db.data_store["test_password"],
            "device": {"fingerprint": "test"},
        })

        response = await auth_api.login(request)

        assert response.status == 403
        data = json.loads(response.body)
        assert data["error"] == "account_inactive"

    @pytest.mark.asyncio
    async def test_login_locked_account(self, auth_api):
        """Test login to locked account returns 403."""
        auth_api.db.data_store["users"]["test@example.com"]["is_locked"] = True

        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": auth_api.db.data_store["test_password"],
            "device": {"fingerprint": "test"},
        })

        response = await auth_api.login(request)

        assert response.status == 403
        data = json.loads(response.body)
        assert data["error"] == "account_locked"

    @pytest.mark.asyncio
    async def test_login_logs_success_event(self, auth_api):
        """Test successful login creates audit log."""
        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": auth_api.db.data_store["test_password"],
            "device": {"fingerprint": "test"},
        })

        await auth_api.login(request)

        audit_logs = auth_api.db.data_store.get("audit_logs", [])
        login_events = [log for log in audit_logs if log[3] == "login"]
        assert len(login_events) > 0

    @pytest.mark.asyncio
    async def test_login_logs_failure_event(self, auth_api):
        """Test failed login creates audit log."""
        request = create_mock_request(json_data={
            "email": "test@example.com",
            "password": "WrongPassword",
            "device": {"fingerprint": "test"},
        })

        await auth_api.login(request)

        audit_logs = auth_api.db.data_store.get("audit_logs", [])
        failed_events = [log for log in audit_logs if log[3] == "login_failed"]
        assert len(failed_events) > 0


# =============================================================================
# TOKEN REFRESH TESTS
# =============================================================================


class TestTokenRefresh:
    """Tests for token refresh endpoint."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI with refresh token in database."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        api = AuthAPI(db_pool, token_service)

        # Create test refresh token
        test_user_id = uuid.uuid4()
        test_device_id = uuid.uuid4()
        test_family_id = uuid.uuid4()
        test_token = "test-refresh-token-12345"
        token_hash = hashlib.sha256(test_token.encode()).hexdigest()

        api.db.data_store["refresh_tokens"] = {
            token_hash: {
                "id": uuid.uuid4(),
                "user_id": test_user_id,
                "device_id": test_device_id,
                "token_family": test_family_id,
                "generation": 1,
                "is_revoked": False,
                "expires_at": datetime.now(timezone.utc) + timedelta(days=30),
                "email": "test@example.com",
                "role": "user",
                "is_active": True,
                "organization_id": None,
            }
        }
        api.db.data_store["test_token"] = test_token
        api.db.data_store["test_user_id"] = test_user_id

        return api

    @pytest.mark.asyncio
    async def test_refresh_success(self, auth_api):
        """Test successful token refresh."""
        request = create_mock_request(json_data={
            "refresh_token": auth_api.db.data_store["test_token"],
        })

        response = await auth_api.refresh(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "tokens" in data
        assert "access_token" in data["tokens"]
        assert "refresh_token" in data["tokens"]

    @pytest.mark.asyncio
    async def test_refresh_invalid_json(self, auth_api):
        """Test refresh with invalid JSON returns 400."""
        request = create_mock_request(json_data=None)

        response = await auth_api.refresh(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_refresh_missing_token(self, auth_api):
        """Test refresh without token returns 400."""
        request = create_mock_request(json_data={})

        response = await auth_api.refresh(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "missing_token"

    @pytest.mark.asyncio
    async def test_refresh_invalid_token(self, auth_api):
        """Test refresh with invalid token returns 401."""
        request = create_mock_request(json_data={
            "refresh_token": "invalid-token",
        })

        response = await auth_api.refresh(request)

        assert response.status == 401
        data = json.loads(response.body)
        assert data["error"] == "invalid_token"

    @pytest.mark.asyncio
    async def test_refresh_revoked_token_triggers_security(self, auth_api):
        """Test refresh with revoked token returns 401 and revokes family."""
        token = auth_api.db.data_store["test_token"]
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        auth_api.db.data_store["refresh_tokens"][token_hash]["is_revoked"] = True

        request = create_mock_request(json_data={
            "refresh_token": token,
        })

        response = await auth_api.refresh(request)

        assert response.status == 401
        data = json.loads(response.body)
        assert data["error"] == "token_reused"

    @pytest.mark.asyncio
    async def test_refresh_expired_token(self, auth_api):
        """Test refresh with expired token returns 401."""
        token = auth_api.db.data_store["test_token"]
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        auth_api.db.data_store["refresh_tokens"][token_hash]["expires_at"] = (
            datetime.now(timezone.utc) - timedelta(days=1)
        )

        request = create_mock_request(json_data={
            "refresh_token": token,
        })

        response = await auth_api.refresh(request)

        assert response.status == 401
        data = json.loads(response.body)
        assert data["error"] == "token_expired"

    @pytest.mark.asyncio
    async def test_refresh_inactive_user(self, auth_api):
        """Test refresh for inactive user returns 403."""
        token = auth_api.db.data_store["test_token"]
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        auth_api.db.data_store["refresh_tokens"][token_hash]["is_active"] = False

        request = create_mock_request(json_data={
            "refresh_token": token,
        })

        response = await auth_api.refresh(request)

        assert response.status == 403
        data = json.loads(response.body)
        assert data["error"] == "account_inactive"


# =============================================================================
# LOGOUT TESTS
# =============================================================================


class TestLogout:
    """Tests for logout endpoint."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI instance."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        return AuthAPI(db_pool, token_service)

    @pytest.mark.asyncio
    async def test_logout_success(self, auth_api):
        """Test successful logout."""
        user_id = str(uuid.uuid4())
        request = create_mock_request(
            json_data={},
            user_id=user_id,
        )

        response = await auth_api.logout(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["message"] == "Logged out successfully"

    @pytest.mark.asyncio
    async def test_logout_all_devices(self, auth_api):
        """Test logout from all devices."""
        user_id = str(uuid.uuid4())
        request = create_mock_request(
            json_data={"all_devices": True},
            user_id=user_id,
        )

        response = await auth_api.logout(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_logout_with_refresh_token(self, auth_api):
        """Test logout with specific refresh token."""
        test_token = "logout-refresh-token"
        token_hash = hashlib.sha256(test_token.encode()).hexdigest()
        auth_api.db.data_store["refresh_tokens"] = {
            token_hash: {"token_family": uuid.uuid4()}
        }

        request = create_mock_request(json_data={
            "refresh_token": test_token,
        })

        response = await auth_api.logout(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_logout_logs_event(self, auth_api):
        """Test logout creates audit log."""
        user_id = str(uuid.uuid4())
        request = create_mock_request(
            json_data={},
            user_id=user_id,
        )

        await auth_api.logout(request)

        audit_logs = auth_api.db.data_store.get("audit_logs", [])
        logout_events = [log for log in audit_logs if log[3] == "logout"]
        assert len(logout_events) > 0


# =============================================================================
# PROFILE TESTS
# =============================================================================


class TestProfile:
    """Tests for profile endpoints."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI with test user."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        api = AuthAPI(db_pool, token_service)

        test_user_id = uuid.uuid4()
        api.db.data_store["users"] = {
            "profile@example.com": {
                "id": test_user_id,
                "email": "profile@example.com",
                "email_verified": True,
                "display_name": "Profile User",
                "avatar_url": "https://example.com/avatar.png",
                "locale": "en-US",
                "timezone": "America/New_York",
                "role": "user",
                "mfa_enabled": False,
                "created_at": datetime.now(timezone.utc),
                "last_login_at": datetime.now(timezone.utc),
            }
        }
        api.db.data_store["test_user_id"] = test_user_id

        return api

    @pytest.mark.asyncio
    async def test_get_me_success(self, auth_api):
        """Test getting current user profile."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(user_id=user_id)

        response = await auth_api.get_me(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "user" in data
        assert data["user"]["email"] == "profile@example.com"

    @pytest.mark.asyncio
    async def test_get_me_unauthorized(self, auth_api):
        """Test get_me without authentication returns 401."""
        request = create_mock_request()

        response = await auth_api.get_me(request)

        assert response.status == 401

    @pytest.mark.asyncio
    async def test_get_me_user_not_found(self, auth_api):
        """Test get_me for non-existent user returns 404."""
        request = create_mock_request(user_id=str(uuid.uuid4()))

        response = await auth_api.get_me(request)

        assert response.status == 404

    @pytest.mark.asyncio
    async def test_update_me_success(self, auth_api):
        """Test updating user profile."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(
            json_data={"display_name": "Updated Name"},
            user_id=user_id,
        )

        response = await auth_api.update_me(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_update_me_unauthorized(self, auth_api):
        """Test update_me without authentication returns 401."""
        request = create_mock_request(json_data={"display_name": "Test"})

        response = await auth_api.update_me(request)

        assert response.status == 401

    @pytest.mark.asyncio
    async def test_update_me_invalid_json(self, auth_api):
        """Test update_me with invalid JSON returns 400."""
        request = create_mock_request(json_data=None, user_id=str(uuid.uuid4()))

        response = await auth_api.update_me(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_update_me_no_valid_fields(self, auth_api):
        """Test update_me with no valid fields returns 400."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(
            json_data={"invalid_field": "value"},
            user_id=user_id,
        )

        response = await auth_api.update_me(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "no_updates"


# =============================================================================
# PASSWORD CHANGE TESTS
# =============================================================================


class TestPasswordChange:
    """Tests for password change endpoint."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI with test user."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        api = AuthAPI(db_pool, token_service)

        test_user_id = uuid.uuid4()
        current_password = "CurrentPass123!"
        password_hash = PasswordService.hash_password(current_password)

        api.db.data_store["users"] = {
            "password@example.com": {
                "id": test_user_id,
                "password_hash": password_hash,
            }
        }
        api.db.data_store["test_user_id"] = test_user_id
        api.db.data_store["current_password"] = current_password

        return api

    @pytest.mark.asyncio
    async def test_change_password_success(self, auth_api):
        """Test successful password change."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(
            json_data={
                "current_password": auth_api.db.data_store["current_password"],
                "new_password": "NewSecurePass123!",
            },
            user_id=user_id,
        )

        response = await auth_api.change_password(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["message"] == "Password changed successfully"

    @pytest.mark.asyncio
    async def test_change_password_unauthorized(self, auth_api):
        """Test password change without auth returns 401."""
        request = create_mock_request(json_data={
            "current_password": "old",
            "new_password": "new",
        })

        response = await auth_api.change_password(request)

        assert response.status == 401

    @pytest.mark.asyncio
    async def test_change_password_invalid_json(self, auth_api):
        """Test password change with invalid JSON returns 400."""
        request = create_mock_request(json_data=None, user_id=str(uuid.uuid4()))

        response = await auth_api.change_password(request)

        assert response.status == 400

    @pytest.mark.asyncio
    async def test_change_password_missing_passwords(self, auth_api):
        """Test password change without passwords returns 400."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(json_data={}, user_id=user_id)

        response = await auth_api.change_password(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "missing_passwords"

    @pytest.mark.asyncio
    async def test_change_password_weak_new_password(self, auth_api):
        """Test password change with weak new password returns 400."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(
            json_data={
                "current_password": auth_api.db.data_store["current_password"],
                "new_password": "weak",
            },
            user_id=user_id,
        )

        response = await auth_api.change_password(request)

        assert response.status == 400
        data = json.loads(response.body)
        assert data["error"] == "weak_password"

    @pytest.mark.asyncio
    async def test_change_password_wrong_current(self, auth_api):
        """Test password change with wrong current password returns 401."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(
            json_data={
                "current_password": "WrongCurrentPass123!",
                "new_password": "NewSecurePass123!",
            },
            user_id=user_id,
        )

        response = await auth_api.change_password(request)

        assert response.status == 401
        data = json.loads(response.body)
        assert data["error"] == "invalid_password"


# =============================================================================
# DEVICE MANAGEMENT TESTS
# =============================================================================


class TestDeviceManagement:
    """Tests for device management endpoints."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI with test devices."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        api = AuthAPI(db_pool, token_service)

        test_user_id = uuid.uuid4()
        test_device_id = uuid.uuid4()

        api.db.data_store["user_devices"] = {
            str(test_user_id): [
                {
                    "id": test_device_id,
                    "device_name": "iPhone 15",
                    "device_type": "ios",
                    "device_model": "iPhone15,2",
                    "os_version": "18.0",
                    "app_version": "1.0.0",
                    "is_trusted": True,
                    "last_seen_at": datetime.now(timezone.utc),
                    "created_at": datetime.now(timezone.utc),
                }
            ]
        }
        api.db.data_store["test_user_id"] = test_user_id
        api.db.data_store["test_device_id"] = test_device_id

        return api

    @pytest.mark.asyncio
    async def test_list_devices_success(self, auth_api):
        """Test listing user devices."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(user_id=user_id)

        response = await auth_api.list_devices(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "devices" in data
        assert len(data["devices"]) == 1
        assert data["devices"][0]["name"] == "iPhone 15"

    @pytest.mark.asyncio
    async def test_list_devices_unauthorized(self, auth_api):
        """Test list_devices without auth returns 401."""
        request = create_mock_request()

        response = await auth_api.list_devices(request)

        assert response.status == 401

    @pytest.mark.asyncio
    async def test_remove_device_success(self, auth_api):
        """Test removing a device."""
        test_user_id = auth_api.db.data_store["test_user_id"]
        test_device_id = auth_api.db.data_store["test_device_id"]
        user_id = str(test_user_id)
        device_id = str(test_device_id)

        # Mock device lookup - store with the UUID device_id as key
        # and include user_id for the ownership check query
        auth_api.db.data_store["devices"] = {
            device_id: {
                "id": test_device_id,
                "user_id": test_user_id,
            }
        }

        request = create_mock_request(
            user_id=user_id,
            match_info={"device_id": device_id},
        )

        response = await auth_api.remove_device(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_remove_device_unauthorized(self, auth_api):
        """Test remove_device without auth returns 401."""
        request = create_mock_request(match_info={"device_id": str(uuid.uuid4())})

        response = await auth_api.remove_device(request)

        assert response.status == 401

    @pytest.mark.asyncio
    async def test_remove_device_not_found(self, auth_api):
        """Test removing non-existent device returns 404."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(
            user_id=user_id,
            match_info={"device_id": str(uuid.uuid4())},
        )

        response = await auth_api.remove_device(request)

        assert response.status == 404


# =============================================================================
# SESSION MANAGEMENT TESTS
# =============================================================================


class TestSessionManagement:
    """Tests for session management endpoints."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI with test sessions."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        api = AuthAPI(db_pool, token_service)

        test_user_id = uuid.uuid4()
        test_session_id = uuid.uuid4()

        api.db.data_store["user_sessions"] = {
            str(test_user_id): [
                {
                    "id": test_session_id,
                    "ip_address": "192.168.1.1",
                    "user_agent": "Mozilla/5.0",
                    "location_country": "US",
                    "location_city": "New York",
                    "created_at": datetime.now(timezone.utc),
                    "last_activity_at": datetime.now(timezone.utc),
                    "device_name": "iPhone 15",
                    "device_type": "ios",
                }
            ]
        }
        api.db.data_store["test_user_id"] = test_user_id
        api.db.data_store["test_session_id"] = test_session_id

        return api

    @pytest.mark.asyncio
    async def test_list_sessions_success(self, auth_api):
        """Test listing user sessions."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        request = create_mock_request(user_id=user_id)

        response = await auth_api.list_sessions(request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "sessions" in data
        assert len(data["sessions"]) == 1

    @pytest.mark.asyncio
    async def test_list_sessions_unauthorized(self, auth_api):
        """Test list_sessions without auth returns 401."""
        request = create_mock_request()

        response = await auth_api.list_sessions(request)

        assert response.status == 401

    @pytest.mark.asyncio
    async def test_terminate_session_success(self, auth_api):
        """Test terminating a session."""
        user_id = str(auth_api.db.data_store["test_user_id"])
        session_id = str(auth_api.db.data_store["test_session_id"])

        request = create_mock_request(
            user_id=user_id,
            match_info={"session_id": session_id},
        )

        response = await auth_api.terminate_session(request)

        assert response.status == 200

    @pytest.mark.asyncio
    async def test_terminate_session_unauthorized(self, auth_api):
        """Test terminate_session without auth returns 401."""
        request = create_mock_request(match_info={"session_id": str(uuid.uuid4())})

        response = await auth_api.terminate_session(request)

        assert response.status == 401


# =============================================================================
# HELPER FUNCTION TESTS
# =============================================================================


class TestHelperFunctions:
    """Tests for helper functions."""

    @pytest.fixture
    def auth_api(self):
        """Create AuthAPI instance."""
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        return AuthAPI(db_pool, token_service)

    def test_get_client_ip_from_forwarded_header(self, auth_api):
        """Test IP extraction from X-Forwarded-For header."""
        request = MagicMock()
        request.headers = {"X-Forwarded-For": "192.168.1.100, 10.0.0.1"}
        request.transport.get_extra_info.return_value = ("127.0.0.1", 12345)

        ip = auth_api._get_client_ip(request)

        assert ip == "192.168.1.100"

    def test_get_client_ip_from_transport(self, auth_api):
        """Test IP extraction from transport."""
        request = MagicMock()
        request.headers = {}
        request.transport.get_extra_info.return_value = ("192.168.1.50", 12345)

        ip = auth_api._get_client_ip(request)

        assert ip == "192.168.1.50"

    def test_get_client_ip_none_when_unavailable(self, auth_api):
        """Test IP extraction returns None when unavailable."""
        request = MagicMock()
        request.headers = {}
        request.transport.get_extra_info.return_value = None

        ip = auth_api._get_client_ip(request)

        assert ip is None


# =============================================================================
# ROUTE REGISTRATION TESTS
# =============================================================================


class TestRouteRegistration:
    """Tests for route registration."""

    def test_register_auth_routes(self):
        """Test that all routes are registered."""
        app = web.Application()
        db_pool = MockDBPool()
        token_service = TokenService(TokenConfig(secret_key="test-secret-key-32chars!"))
        auth_api = AuthAPI(db_pool, token_service)

        register_auth_routes(app, auth_api)

        # Check all routes exist
        routes = [r.resource.canonical for r in app.router.routes() if hasattr(r, 'resource')]
        expected_routes = [
            "/api/auth/register",
            "/api/auth/login",
            "/api/auth/refresh",
            "/api/auth/logout",
            "/api/auth/me",
            "/api/auth/password",
            "/api/auth/devices",
            "/api/auth/devices/{device_id}",
            "/api/auth/sessions",
            "/api/auth/sessions/{session_id}",
        ]

        for expected in expected_routes:
            assert any(expected in str(r) for r in routes), f"Route {expected} not found"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
