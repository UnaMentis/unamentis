"""
Token Service

Handles JWT access tokens and refresh token management following RFC 9700 best practices.

Token Strategy:
- Access tokens: Short-lived JWTs (15 minutes), used for API authentication
- Refresh tokens: Long-lived opaque tokens (30 days), stored hashed in database
- Token families: Track token lineage for replay detection
- Rotation: Each refresh issues new access + refresh token pair
"""

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, Tuple

import jwt


@dataclass
class TokenConfig:
    """Configuration for token generation."""
    # JWT settings
    secret_key: str
    algorithm: str = "HS256"  # Use ES256 in production with proper key management
    issuer: str = "unamentis"
    audience: str = "unamentis-api"

    # Access token settings
    access_token_lifetime_minutes: int = 15

    # Refresh token settings
    refresh_token_lifetime_days: int = 30

    # Maximum active token families per user-device pair
    max_token_families: int = 3


@dataclass
class AccessTokenPayload:
    """Decoded access token payload."""
    user_id: str
    email: str
    role: str
    organization_id: Optional[str]
    device_id: str
    permissions: list
    token_id: str
    issued_at: datetime
    expires_at: datetime


@dataclass
class RefreshTokenData:
    """Refresh token with metadata."""
    token: str
    token_hash: str
    token_id: str
    family_id: str
    generation: int
    user_id: str
    device_id: str
    expires_at: datetime


class TokenService:
    """
    Service for JWT access tokens and refresh token management.

    Implements RFC 9700 compliant refresh token rotation:
    - Each refresh token can only be used once
    - Token families track the chain of rotations
    - If an old token is reused, the entire family is revoked (replay detection)
    """

    def __init__(self, config: TokenConfig):
        self.config = config

    def generate_access_token(
        self,
        user_id: str,
        email: str,
        role: str,
        device_id: str,
        organization_id: Optional[str] = None,
        permissions: Optional[list] = None
    ) -> Tuple[str, str]:
        """
        Generate a new JWT access token.

        Args:
            user_id: The user's UUID
            email: The user's email
            role: The user's role (user, admin, etc.)
            device_id: The device UUID
            organization_id: Optional organization UUID
            permissions: Optional list of permission strings

        Returns:
            Tuple of (token_string, token_id)
        """
        now = datetime.now(timezone.utc)
        expires = now + timedelta(minutes=self.config.access_token_lifetime_minutes)
        token_id = str(uuid.uuid4())

        payload = {
            # Standard JWT claims
            "iss": self.config.issuer,
            "sub": user_id,
            "aud": self.config.audience,
            "exp": expires,
            "iat": now,
            "jti": token_id,

            # Custom claims
            "email": email,
            "role": role,
            "device_id": device_id,
            "permissions": permissions or [],
        }

        if organization_id:
            payload["org_id"] = organization_id

        token = jwt.encode(
            payload,
            self.config.secret_key,
            algorithm=self.config.algorithm
        )

        return token, token_id

    def validate_access_token(self, token: str) -> AccessTokenPayload:
        """
        Validate and decode a JWT access token.

        Args:
            token: The JWT token string

        Returns:
            AccessTokenPayload with decoded claims

        Raises:
            jwt.ExpiredSignatureError: If token is expired
            jwt.InvalidTokenError: If token is invalid
        """
        payload = jwt.decode(
            token,
            self.config.secret_key,
            algorithms=[self.config.algorithm],
            audience=self.config.audience,
            issuer=self.config.issuer
        )

        return AccessTokenPayload(
            user_id=payload["sub"],
            email=payload.get("email", ""),
            role=payload.get("role", "user"),
            organization_id=payload.get("org_id"),
            device_id=payload.get("device_id", ""),
            permissions=payload.get("permissions", []),
            token_id=payload["jti"],
            issued_at=datetime.fromtimestamp(payload["iat"], tz=timezone.utc),
            expires_at=datetime.fromtimestamp(payload["exp"], tz=timezone.utc)
        )

    def generate_refresh_token(
        self,
        user_id: str,
        device_id: str,
        family_id: Optional[str] = None,
        generation: int = 1
    ) -> RefreshTokenData:
        """
        Generate a new refresh token.

        Args:
            user_id: The user's UUID
            device_id: The device UUID
            family_id: Optional existing family ID (for rotation)
            generation: The generation number in the family

        Returns:
            RefreshTokenData with token and metadata
        """
        # Generate random token
        token = secrets.token_urlsafe(64)

        # Hash for storage
        token_hash = self._hash_token(token)

        # Create or use existing family
        family = family_id or str(uuid.uuid4())

        expires = datetime.now(timezone.utc) + timedelta(
            days=self.config.refresh_token_lifetime_days
        )

        # Generate a unique token ID for database storage
        token_id = str(uuid.uuid4())

        return RefreshTokenData(
            token=token,
            token_hash=token_hash,
            token_id=token_id,
            family_id=family,
            generation=generation,
            user_id=user_id,
            device_id=device_id,
            expires_at=expires
        )

    def rotate_refresh_token(
        self,
        old_token_data: RefreshTokenData
    ) -> RefreshTokenData:
        """
        Rotate a refresh token (issue new token in same family).

        Args:
            old_token_data: The existing token being rotated

        Returns:
            New RefreshTokenData in the same family with incremented generation
        """
        return self.generate_refresh_token(
            user_id=old_token_data.user_id,
            device_id=old_token_data.device_id,
            family_id=old_token_data.family_id,
            generation=old_token_data.generation + 1
        )

    def verify_refresh_token(self, token: str, stored_hash: str) -> bool:
        """
        Verify a refresh token against its stored hash.

        Args:
            token: The plaintext refresh token
            stored_hash: The hash stored in the database

        Returns:
            True if the token matches, False otherwise
        """
        return secrets.compare_digest(
            self._hash_token(token),
            stored_hash
        )

    @staticmethod
    def _hash_token(token: str) -> str:
        """
        Hash a token using SHA-256.

        Args:
            token: The token to hash

        Returns:
            The hex digest of the hash
        """
        return hashlib.sha256(token.encode('utf-8')).hexdigest()

    def get_token_expiry_from_jwt(self, token: str) -> Optional[datetime]:
        """
        Extract expiry time from a JWT without full validation.
        Useful for checking if a token needs refresh.

        Args:
            token: The JWT token string

        Returns:
            The expiry datetime, or None if extraction fails
        """
        try:
            # Decode without verification to get expiry
            payload = jwt.decode(
                token,
                options={"verify_signature": False}
            )
            exp = payload.get("exp")
            if exp:
                return datetime.fromtimestamp(exp, tz=timezone.utc)
        except Exception:
            pass
        return None

    def is_token_expired(self, token: str) -> bool:
        """
        Check if a JWT token is expired.

        Args:
            token: The JWT token string

        Returns:
            True if expired, False otherwise
        """
        expiry = self.get_token_expiry_from_jwt(token)
        if expiry is None:
            return True
        return datetime.now(timezone.utc) >= expiry

    def should_refresh(self, token: str, threshold_minutes: int = 5) -> bool:
        """
        Check if a token should be refreshed (within threshold of expiry).

        Args:
            token: The JWT token string
            threshold_minutes: Refresh if expiring within this many minutes

        Returns:
            True if token should be refreshed, False otherwise
        """
        expiry = self.get_token_expiry_from_jwt(token)
        if expiry is None:
            return True

        threshold = datetime.now(timezone.utc) + timedelta(minutes=threshold_minutes)
        return expiry <= threshold


def create_token_service(
    secret_key: str,
    access_token_lifetime_minutes: int = 15,
    refresh_token_lifetime_days: int = 30
) -> TokenService:
    """
    Factory function to create a TokenService with configuration.

    Args:
        secret_key: The secret key for JWT signing
        access_token_lifetime_minutes: Access token lifetime (default 15)
        refresh_token_lifetime_days: Refresh token lifetime (default 30)

    Returns:
        Configured TokenService instance
    """
    config = TokenConfig(
        secret_key=secret_key,
        access_token_lifetime_minutes=access_token_lifetime_minutes,
        refresh_token_lifetime_days=refresh_token_lifetime_days
    )
    return TokenService(config)
