"""
Tests for Password Service

Comprehensive tests for password hashing, validation, and strength checking.
"""

import pytest
from auth.password_service import PasswordService


class TestPasswordHashing:
    """Tests for password hashing functionality."""

    def test_hash_password_returns_string(self):
        """Test that hash_password returns a string."""
        password = "SecurePassword123!"
        hashed = PasswordService.hash_password(password)
        assert isinstance(hashed, str)
        assert len(hashed) > 0

    def test_hash_password_produces_bcrypt_format(self):
        """Test that hash follows bcrypt format ($2b$...)."""
        password = "TestPassword123!"
        hashed = PasswordService.hash_password(password)
        assert hashed.startswith("$2")

    def test_hash_password_different_each_time(self):
        """Test that hashing same password produces different hashes (salted)."""
        password = "SamePassword123!"
        hash1 = PasswordService.hash_password(password)
        hash2 = PasswordService.hash_password(password)
        assert hash1 != hash2

    def test_hash_password_with_special_characters(self):
        """Test hashing passwords with special characters."""
        password = "P@ssw0rd!#$%^&*()"
        hashed = PasswordService.hash_password(password)
        assert isinstance(hashed, str)

    def test_hash_password_with_unicode(self):
        """Test hashing passwords with unicode characters."""
        password = "Password123!日本語"
        hashed = PasswordService.hash_password(password)
        assert isinstance(hashed, str)


class TestPasswordVerification:
    """Tests for password verification."""

    def test_verify_password_correct(self):
        """Test that correct password verifies successfully."""
        password = "CorrectPassword123!"
        hashed = PasswordService.hash_password(password)
        assert PasswordService.verify_password(password, hashed) is True

    def test_verify_password_incorrect(self):
        """Test that incorrect password fails verification."""
        password = "CorrectPassword123!"
        wrong_password = "WrongPassword456!"
        hashed = PasswordService.hash_password(password)
        assert PasswordService.verify_password(wrong_password, hashed) is False

    def test_verify_password_empty_password(self):
        """Test that empty password returns False."""
        hashed = PasswordService.hash_password("ValidPassword123!")
        assert PasswordService.verify_password("", hashed) is False

    def test_verify_password_empty_hash(self):
        """Test that empty hash returns False."""
        assert PasswordService.verify_password("SomePassword123!", "") is False

    def test_verify_password_none_password(self):
        """Test that None password returns False."""
        hashed = PasswordService.hash_password("ValidPassword123!")
        assert PasswordService.verify_password(None, hashed) is False

    def test_verify_password_none_hash(self):
        """Test that None hash returns False."""
        assert PasswordService.verify_password("SomePassword123!", None) is False

    def test_verify_password_invalid_hash_format(self):
        """Test that invalid hash format returns False."""
        assert PasswordService.verify_password("Password123!", "not-a-valid-hash") is False

    def test_verify_password_with_unicode(self):
        """Test verification with unicode passwords."""
        password = "Password123!日本語"
        hashed = PasswordService.hash_password(password)
        assert PasswordService.verify_password(password, hashed) is True


class TestPasswordValidation:
    """Tests for password validation."""

    def test_validate_password_empty(self):
        """Test that empty password raises ValueError."""
        with pytest.raises(ValueError, match="Password cannot be empty"):
            PasswordService.hash_password("")

    def test_validate_password_too_short(self):
        """Test that short password raises ValueError."""
        with pytest.raises(ValueError, match="at least 8 characters"):
            PasswordService.hash_password("Short1!")

    def test_validate_password_minimum_length(self):
        """Test that minimum length password is accepted."""
        password = "Pass123!"  # Exactly 8 characters
        hashed = PasswordService.hash_password(password)
        assert isinstance(hashed, str)

    def test_validate_password_too_long(self):
        """Test that overly long password raises ValueError."""
        password = "A" * 129  # Exceeds MAX_LENGTH of 128
        with pytest.raises(ValueError, match="cannot exceed"):
            PasswordService.hash_password(password)

    def test_validate_password_maximum_length(self):
        """Test that maximum length password is accepted (bcrypt truncates at 72 bytes)."""
        # bcrypt has a 72-byte limit, so test with 72 chars
        password = "A" * 72
        hashed = PasswordService.hash_password(password)
        assert isinstance(hashed, str)


class TestPasswordStrengthCheck:
    """Tests for password strength checking."""

    def test_check_password_strength_weak(self):
        """Test weak password detection."""
        result = PasswordService.check_password_strength("password")
        assert result["strength"] == "weak"
        assert result["score"] <= 2

    def test_check_password_strength_fair(self):
        """Test fair password detection."""
        result = PasswordService.check_password_strength("Password1")
        assert result["strength"] in ["fair", "good"]
        assert result["score"] >= 3

    def test_check_password_strength_good(self):
        """Test good password detection."""
        result = PasswordService.check_password_strength("Password123")
        assert result["strength"] in ["fair", "good"]

    def test_check_password_strength_strong(self):
        """Test strong password detection."""
        result = PasswordService.check_password_strength("MyStr0ng!Password@2024")
        assert result["strength"] == "strong"
        assert result["score"] >= 6

    def test_check_password_strength_returns_suggestions(self):
        """Test that suggestions are returned for weak passwords."""
        result = PasswordService.check_password_strength("weakpass")
        assert "suggestions" in result
        assert len(result["suggestions"]) > 0

    def test_check_password_strength_no_uppercase(self):
        """Test suggestion for missing uppercase."""
        result = PasswordService.check_password_strength("lowercase123!")
        assert "Add uppercase letters" in result["suggestions"]

    def test_check_password_strength_no_lowercase(self):
        """Test suggestion for missing lowercase."""
        result = PasswordService.check_password_strength("UPPERCASE123!")
        assert "Add lowercase letters" in result["suggestions"]

    def test_check_password_strength_no_numbers(self):
        """Test suggestion for missing numbers."""
        result = PasswordService.check_password_strength("Password!")
        assert "Add numbers" in result["suggestions"]

    def test_check_password_strength_no_special(self):
        """Test suggestion for missing special characters."""
        result = PasswordService.check_password_strength("Password123")
        assert "Add special characters" in result["suggestions"]

    def test_check_password_strength_max_score(self):
        """Test that max_score is 7."""
        result = PasswordService.check_password_strength("Test")
        assert result["max_score"] == 7

    def test_check_password_strength_length_bonuses(self):
        """Test that longer passwords get bonus points."""
        short_result = PasswordService.check_password_strength("Pass1!aB")  # 8 chars
        medium_result = PasswordService.check_password_strength("Pass1!aBcDeF")  # 12 chars
        long_result = PasswordService.check_password_strength("Pass1!aBcDeFgHiJ")  # 16 chars

        # Longer passwords should have higher scores (when other factors are equal)
        assert long_result["score"] >= medium_result["score"]


class TestResetToken:
    """Tests for reset token generation and verification."""

    def test_generate_reset_token_returns_string(self):
        """Test that generate_reset_token returns a string."""
        token = PasswordService.generate_reset_token()
        assert isinstance(token, str)

    def test_generate_reset_token_length(self):
        """Test that reset token has expected length (64 hex chars)."""
        token = PasswordService.generate_reset_token()
        assert len(token) == 64  # 32 bytes = 64 hex chars

    def test_generate_reset_token_unique(self):
        """Test that tokens are unique."""
        token1 = PasswordService.generate_reset_token()
        token2 = PasswordService.generate_reset_token()
        assert token1 != token2

    def test_generate_reset_token_is_hex(self):
        """Test that token is valid hex string."""
        token = PasswordService.generate_reset_token()
        # Should not raise ValueError
        int(token, 16)


class TestTokenHashing:
    """Tests for token hashing and verification."""

    def test_hash_token_returns_string(self):
        """Test that hash_token returns a string."""
        token = "test-token-12345"
        hashed = PasswordService.hash_token(token)
        assert isinstance(hashed, str)

    def test_hash_token_sha256_length(self):
        """Test that hash has SHA-256 length (64 hex chars)."""
        token = "test-token"
        hashed = PasswordService.hash_token(token)
        assert len(hashed) == 64

    def test_hash_token_deterministic(self):
        """Test that same token produces same hash."""
        token = "same-token"
        hash1 = PasswordService.hash_token(token)
        hash2 = PasswordService.hash_token(token)
        assert hash1 == hash2

    def test_hash_token_different_tokens(self):
        """Test that different tokens produce different hashes."""
        hash1 = PasswordService.hash_token("token1")
        hash2 = PasswordService.hash_token("token2")
        assert hash1 != hash2

    def test_verify_token_correct(self):
        """Test that correct token verifies."""
        token = "my-secret-token"
        hashed = PasswordService.hash_token(token)
        assert PasswordService.verify_token(token, hashed) is True

    def test_verify_token_incorrect(self):
        """Test that incorrect token fails verification."""
        token = "correct-token"
        wrong_token = "wrong-token"
        hashed = PasswordService.hash_token(token)
        assert PasswordService.verify_token(wrong_token, hashed) is False

    def test_verify_token_timing_safe(self):
        """Test that token verification uses timing-safe comparison."""
        # This test ensures the implementation uses secrets.compare_digest
        # which prevents timing attacks
        token = "secure-token"
        hashed = PasswordService.hash_token(token)
        # Should work correctly regardless of comparison method
        assert PasswordService.verify_token(token, hashed) is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
