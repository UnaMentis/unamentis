"""
Tests for Token Service

Comprehensive tests for JWT access tokens and refresh token management.
"""

import pytest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
import jwt

from auth.token_service import (
    TokenService,
    TokenConfig,
    AccessTokenPayload,
    RefreshTokenData,
    create_token_service,
)


@pytest.fixture
def token_config():
    """Create a test token configuration."""
    return TokenConfig(
        secret_key="test-secret-key-for-jwt-signing-2024",
        algorithm="HS256",
        issuer="unamentis-test",
        audience="unamentis-api-test",
        access_token_lifetime_minutes=15,
        refresh_token_lifetime_days=30,
    )


@pytest.fixture
def token_service(token_config):
    """Create a test token service."""
    return TokenService(token_config)


class TestTokenConfig:
    """Tests for TokenConfig dataclass."""

    def test_token_config_defaults(self):
        """Test TokenConfig has correct defaults."""
        config = TokenConfig(secret_key="test-key")
        assert config.algorithm == "HS256"
        assert config.issuer == "unamentis"
        assert config.audience == "unamentis-api"
        assert config.access_token_lifetime_minutes == 15
        assert config.refresh_token_lifetime_days == 30
        assert config.max_token_families == 3

    def test_token_config_custom_values(self):
        """Test TokenConfig with custom values."""
        config = TokenConfig(
            secret_key="custom-key",
            algorithm="ES256",
            issuer="custom-issuer",
            access_token_lifetime_minutes=30,
        )
        assert config.algorithm == "ES256"
        assert config.issuer == "custom-issuer"
        assert config.access_token_lifetime_minutes == 30


class TestAccessTokenGeneration:
    """Tests for access token generation."""

    def test_generate_access_token_returns_tuple(self, token_service):
        """Test that generate_access_token returns a tuple."""
        result = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        assert isinstance(result, tuple)
        assert len(result) == 2

    def test_generate_access_token_returns_jwt(self, token_service):
        """Test that generated token is a valid JWT."""
        token, token_id = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        # JWT has 3 parts separated by dots
        parts = token.split(".")
        assert len(parts) == 3

    def test_generate_access_token_returns_unique_id(self, token_service):
        """Test that each token has unique ID."""
        _, token_id1 = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        _, token_id2 = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        assert token_id1 != token_id2

    def test_generate_access_token_with_organization(self, token_service):
        """Test token generation with organization ID."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="admin",
            device_id="device-456",
            organization_id="org-789",
        )
        payload = token_service.validate_access_token(token)
        assert payload.organization_id == "org-789"

    def test_generate_access_token_with_permissions(self, token_service):
        """Test token generation with permissions list."""
        permissions = ["users:read", "users:write", "admin:access"]
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="admin",
            device_id="device-456",
            permissions=permissions,
        )
        payload = token_service.validate_access_token(token)
        assert payload.permissions == permissions

    def test_generate_access_token_default_permissions_empty(self, token_service):
        """Test that default permissions is empty list."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        payload = token_service.validate_access_token(token)
        assert payload.permissions == []


class TestAccessTokenValidation:
    """Tests for access token validation."""

    def test_validate_access_token_success(self, token_service):
        """Test successful token validation."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        payload = token_service.validate_access_token(token)
        assert isinstance(payload, AccessTokenPayload)
        assert payload.user_id == "user-123"
        assert payload.email == "test@example.com"
        assert payload.role == "user"
        assert payload.device_id == "device-456"

    def test_validate_access_token_contains_timestamps(self, token_service):
        """Test that payload contains valid timestamps."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        payload = token_service.validate_access_token(token)
        assert isinstance(payload.issued_at, datetime)
        assert isinstance(payload.expires_at, datetime)
        assert payload.expires_at > payload.issued_at

    def test_validate_access_token_expired(self, token_service, token_config):
        """Test that expired token raises ExpiredSignatureError."""
        # Create a token service with very short lifetime
        short_config = TokenConfig(
            secret_key=token_config.secret_key,
            access_token_lifetime_minutes=-1,  # Already expired
        )
        short_service = TokenService(short_config)

        with patch('auth.token_service.datetime') as mock_datetime:
            # Mock datetime to create token in the past
            past_time = datetime.now(timezone.utc) - timedelta(hours=1)
            mock_datetime.now.return_value = past_time
            mock_datetime.side_effect = lambda *args, **kwargs: datetime(*args, **kwargs)

        # Actually just create with current service and decode with wrong secret
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )

        # Manually create an expired token
        now = datetime.now(timezone.utc)
        expired_payload = {
            "iss": token_config.issuer,
            "sub": "user-123",
            "aud": token_config.audience,
            "exp": now - timedelta(hours=1),  # Expired
            "iat": now - timedelta(hours=2),
            "jti": "test-id",
            "email": "test@example.com",
            "role": "user",
            "device_id": "device-456",
            "permissions": [],
        }
        expired_token = jwt.encode(
            expired_payload,
            token_config.secret_key,
            algorithm=token_config.algorithm,
        )

        with pytest.raises(jwt.ExpiredSignatureError):
            token_service.validate_access_token(expired_token)

    def test_validate_access_token_invalid(self, token_service):
        """Test that invalid token raises InvalidTokenError."""
        with pytest.raises(jwt.InvalidTokenError):
            token_service.validate_access_token("not-a-valid-jwt-token")

    def test_validate_access_token_wrong_secret(self, token_service, token_config):
        """Test that token with wrong secret fails validation."""
        # Create token with different secret
        other_config = TokenConfig(
            secret_key="different-secret-key",
            issuer=token_config.issuer,
            audience=token_config.audience,
        )
        other_service = TokenService(other_config)
        token, _ = other_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )

        with pytest.raises(jwt.InvalidTokenError):
            token_service.validate_access_token(token)

    def test_validate_access_token_wrong_audience(self, token_service, token_config):
        """Test that token with wrong audience fails validation."""
        other_config = TokenConfig(
            secret_key=token_config.secret_key,
            issuer=token_config.issuer,
            audience="wrong-audience",
        )
        other_service = TokenService(other_config)
        token, _ = other_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )

        with pytest.raises(jwt.InvalidTokenError):
            token_service.validate_access_token(token)


class TestRefreshTokenGeneration:
    """Tests for refresh token generation."""

    def test_generate_refresh_token_returns_data(self, token_service):
        """Test that generate_refresh_token returns RefreshTokenData."""
        result = token_service.generate_refresh_token(
            user_id="user-123",
            device_id="device-456",
        )
        assert isinstance(result, RefreshTokenData)

    def test_generate_refresh_token_has_all_fields(self, token_service):
        """Test that refresh token data has all required fields."""
        result = token_service.generate_refresh_token(
            user_id="user-123",
            device_id="device-456",
        )
        assert result.token is not None
        assert result.token_hash is not None
        assert result.family_id is not None
        assert result.generation == 1
        assert result.user_id == "user-123"
        assert result.device_id == "device-456"
        assert result.expires_at is not None

    def test_generate_refresh_token_unique(self, token_service):
        """Test that each refresh token is unique."""
        token1 = token_service.generate_refresh_token("user-123", "device-456")
        token2 = token_service.generate_refresh_token("user-123", "device-456")
        assert token1.token != token2.token
        assert token1.token_hash != token2.token_hash

    def test_generate_refresh_token_with_family(self, token_service):
        """Test refresh token generation with existing family."""
        result = token_service.generate_refresh_token(
            user_id="user-123",
            device_id="device-456",
            family_id="existing-family-id",
            generation=5,
        )
        assert result.family_id == "existing-family-id"
        assert result.generation == 5

    def test_generate_refresh_token_creates_new_family(self, token_service):
        """Test that new family is created when not provided."""
        result1 = token_service.generate_refresh_token("user-123", "device-456")
        result2 = token_service.generate_refresh_token("user-123", "device-456")
        assert result1.family_id != result2.family_id

    def test_generate_refresh_token_expiry(self, token_service, token_config):
        """Test that refresh token has correct expiry."""
        result = token_service.generate_refresh_token("user-123", "device-456")
        expected_expiry = datetime.now(timezone.utc) + timedelta(
            days=token_config.refresh_token_lifetime_days
        )
        # Allow 1 minute tolerance
        assert abs((result.expires_at - expected_expiry).total_seconds()) < 60


class TestRefreshTokenRotation:
    """Tests for refresh token rotation."""

    def test_rotate_refresh_token_returns_new_data(self, token_service):
        """Test that rotation returns new RefreshTokenData."""
        old_token = token_service.generate_refresh_token("user-123", "device-456")
        new_token = token_service.rotate_refresh_token(old_token)
        assert isinstance(new_token, RefreshTokenData)

    def test_rotate_refresh_token_keeps_family(self, token_service):
        """Test that rotation keeps the same family."""
        old_token = token_service.generate_refresh_token("user-123", "device-456")
        new_token = token_service.rotate_refresh_token(old_token)
        assert new_token.family_id == old_token.family_id

    def test_rotate_refresh_token_increments_generation(self, token_service):
        """Test that rotation increments generation."""
        old_token = token_service.generate_refresh_token("user-123", "device-456")
        new_token = token_service.rotate_refresh_token(old_token)
        assert new_token.generation == old_token.generation + 1

    def test_rotate_refresh_token_keeps_user_device(self, token_service):
        """Test that rotation keeps user and device IDs."""
        old_token = token_service.generate_refresh_token("user-123", "device-456")
        new_token = token_service.rotate_refresh_token(old_token)
        assert new_token.user_id == old_token.user_id
        assert new_token.device_id == old_token.device_id

    def test_rotate_refresh_token_changes_token(self, token_service):
        """Test that rotation changes the actual token value."""
        old_token = token_service.generate_refresh_token("user-123", "device-456")
        new_token = token_service.rotate_refresh_token(old_token)
        assert new_token.token != old_token.token
        assert new_token.token_hash != old_token.token_hash


class TestRefreshTokenVerification:
    """Tests for refresh token verification."""

    def test_verify_refresh_token_correct(self, token_service):
        """Test that correct token verifies."""
        token_data = token_service.generate_refresh_token("user-123", "device-456")
        assert token_service.verify_refresh_token(token_data.token, token_data.token_hash) is True

    def test_verify_refresh_token_incorrect(self, token_service):
        """Test that incorrect token fails verification."""
        token_data = token_service.generate_refresh_token("user-123", "device-456")
        assert token_service.verify_refresh_token("wrong-token", token_data.token_hash) is False

    def test_verify_refresh_token_wrong_hash(self, token_service):
        """Test that token with wrong hash fails verification."""
        token_data = token_service.generate_refresh_token("user-123", "device-456")
        assert token_service.verify_refresh_token(token_data.token, "wrong-hash") is False


class TestTokenExpiry:
    """Tests for token expiry checking."""

    def test_get_token_expiry_from_jwt(self, token_service):
        """Test extracting expiry from JWT."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        expiry = token_service.get_token_expiry_from_jwt(token)
        assert isinstance(expiry, datetime)

    def test_get_token_expiry_from_jwt_invalid(self, token_service):
        """Test that invalid JWT returns None."""
        expiry = token_service.get_token_expiry_from_jwt("not-a-jwt")
        assert expiry is None

    def test_is_token_expired_valid(self, token_service):
        """Test that valid token is not expired."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        assert token_service.is_token_expired(token) is False

    def test_is_token_expired_invalid(self, token_service):
        """Test that invalid token is considered expired."""
        assert token_service.is_token_expired("not-a-jwt") is True

    def test_should_refresh_not_needed(self, token_service):
        """Test that fresh token doesn't need refresh."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="user",
            device_id="device-456",
        )
        # Token has 15 min lifetime, should not need refresh with 5 min threshold
        assert token_service.should_refresh(token, threshold_minutes=5) is False

    def test_should_refresh_invalid_token(self, token_service):
        """Test that invalid token should refresh."""
        assert token_service.should_refresh("not-a-jwt") is True


class TestTokenHashMethod:
    """Tests for _hash_token static method."""

    def test_hash_token_returns_string(self, token_service):
        """Test that _hash_token returns a string."""
        result = TokenService._hash_token("test-token")
        assert isinstance(result, str)

    def test_hash_token_sha256_length(self, token_service):
        """Test that hash has SHA-256 length (64 hex chars)."""
        result = TokenService._hash_token("test-token")
        assert len(result) == 64

    def test_hash_token_deterministic(self, token_service):
        """Test that same token produces same hash."""
        hash1 = TokenService._hash_token("same-token")
        hash2 = TokenService._hash_token("same-token")
        assert hash1 == hash2

    def test_hash_token_different_tokens(self, token_service):
        """Test that different tokens produce different hashes."""
        hash1 = TokenService._hash_token("token1")
        hash2 = TokenService._hash_token("token2")
        assert hash1 != hash2


class TestCreateTokenService:
    """Tests for create_token_service factory function."""

    def test_create_token_service_returns_service(self):
        """Test that factory returns TokenService."""
        service = create_token_service("test-secret-key")
        assert isinstance(service, TokenService)

    def test_create_token_service_with_defaults(self):
        """Test factory with default values."""
        service = create_token_service("test-secret-key")
        assert service.config.access_token_lifetime_minutes == 15
        assert service.config.refresh_token_lifetime_days == 30

    def test_create_token_service_with_custom_values(self):
        """Test factory with custom values."""
        service = create_token_service(
            "test-secret-key",
            access_token_lifetime_minutes=30,
            refresh_token_lifetime_days=60,
        )
        assert service.config.access_token_lifetime_minutes == 30
        assert service.config.refresh_token_lifetime_days == 60


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
