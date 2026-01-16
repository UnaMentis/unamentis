"""
Tests for path security functions in server.py.

These tests verify the path validation and sanitization functions
that prevent path traversal attacks.
"""

import pytest
from pathlib import Path
import tempfile
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from server import (
    validate_path_in_directory,
    sanitize_path_segment,
    sanitize_file_extension,
    safe_error_response,
    codeql_assert_path_within,
    sanitize_and_validate_path,
)


class TestValidatePathInDirectory:
    """Tests for validate_path_in_directory function."""

    def test_valid_path_in_directory(self, tmp_path):
        """Test that a valid path within the directory is accepted."""
        test_file = tmp_path / "test.txt"
        test_file.touch()

        result = validate_path_in_directory(Path("test.txt"), tmp_path)
        assert result == test_file.resolve()

    def test_valid_nested_path(self, tmp_path):
        """Test that a nested path within the directory is accepted."""
        nested_dir = tmp_path / "subdir"
        nested_dir.mkdir()
        test_file = nested_dir / "test.txt"
        test_file.touch()

        result = validate_path_in_directory(Path("subdir/test.txt"), tmp_path)
        assert result == test_file.resolve()

    def test_path_traversal_attack_rejected(self, tmp_path):
        """Test that path traversal attacks with .. are rejected."""
        with pytest.raises(ValueError, match="Invalid path"):
            validate_path_in_directory(Path("../etc/passwd"), tmp_path)

    def test_path_traversal_with_nested_dirs(self, tmp_path):
        """Test path traversal from nested directory is rejected."""
        nested_dir = tmp_path / "subdir"
        nested_dir.mkdir()

        with pytest.raises(ValueError, match="Invalid path"):
            validate_path_in_directory(Path("subdir/../../etc/passwd"), tmp_path)

    def test_absolute_path_outside_directory(self, tmp_path):
        """Test that absolute paths outside the directory are rejected."""
        with pytest.raises(ValueError, match="Invalid path"):
            validate_path_in_directory(Path("/etc/passwd"), tmp_path)

    def test_symlink_escape_rejected(self, tmp_path):
        """Test that symlinks escaping the directory are rejected."""
        # Create a symlink pointing outside the directory
        outside_file = Path(tempfile.gettempdir()) / "outside_file.txt"
        outside_file.touch()

        symlink_path = tmp_path / "evil_link"
        try:
            symlink_path.symlink_to(outside_file)

            with pytest.raises(ValueError, match="Invalid path"):
                validate_path_in_directory(Path("evil_link"), tmp_path)
        finally:
            # Cleanup
            if symlink_path.exists():
                symlink_path.unlink()
            if outside_file.exists():
                outside_file.unlink()

    def test_valid_path_returns_resolved_path(self, tmp_path):
        """Test that the returned path is properly resolved."""
        test_file = tmp_path / "test.txt"
        test_file.touch()

        result = validate_path_in_directory(Path("test.txt"), tmp_path)

        # Result should be an absolute path
        assert result.is_absolute()
        # Result should be resolved (no .. components)
        assert ".." not in str(result)

    def test_empty_path_component(self, tmp_path):
        """Test handling of empty path components."""
        test_file = tmp_path / "test.txt"
        test_file.touch()

        # Path with redundant slashes normalizes correctly
        result = validate_path_in_directory(Path("./test.txt"), tmp_path)
        assert result == test_file.resolve()


class TestSanitizePathSegment:
    """Tests for sanitize_path_segment function."""

    def test_valid_alphanumeric(self):
        """Test that alphanumeric segments are accepted."""
        assert sanitize_path_segment("test123") == "test123"
        assert sanitize_path_segment("Test123") == "Test123"

    def test_valid_with_hyphens_underscores(self):
        """Test that hyphens and underscores are allowed."""
        assert sanitize_path_segment("test-file") == "test-file"
        assert sanitize_path_segment("test_file") == "test_file"
        assert sanitize_path_segment("test-file_123") == "test-file_123"

    def test_valid_with_dots(self):
        """Test that dots are allowed (for file extensions)."""
        assert sanitize_path_segment("test.txt") == "test.txt"
        assert sanitize_path_segment("file.tar.gz") == "file.tar.gz"

    def test_empty_segment_rejected(self):
        """Test that empty segments are rejected."""
        with pytest.raises(ValueError, match="cannot be empty"):
            sanitize_path_segment("")

    def test_path_traversal_rejected(self):
        """Test that path traversal sequences are rejected."""
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("..")

        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("../etc")

    def test_forward_slash_rejected(self):
        """Test that forward slashes are rejected."""
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("path/segment")

    def test_backslash_rejected(self):
        """Test that backslashes are rejected."""
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("path\\segment")

    def test_special_characters_rejected(self):
        """Test that special characters are rejected."""
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("test@file")

        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("test#file")

        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("test$file")

    def test_spaces_rejected(self):
        """Test that spaces are rejected."""
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("test file")

    def test_unicode_alphanumeric_accepted(self):
        """Test that unicode alphanumeric characters are accepted.

        Python's isalnum() accepts unicode alphanumeric characters like accented letters.
        This is generally safe for file paths.
        """
        # Unicode alphanumeric is accepted by isalnum()
        assert sanitize_path_segment("test\u00e9file") == "test\u00e9file"  # e with accent

    def test_unicode_symbols_rejected(self):
        """Test that unicode symbols are rejected."""
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("test\u2022file")  # bullet point


class TestSanitizeFileExtension:
    """Tests for sanitize_file_extension function."""

    def test_valid_extension_lowercase(self):
        """Test that valid lowercase extensions are accepted."""
        allowed = {".png", ".jpg", ".gif"}
        assert sanitize_file_extension("image.png", allowed) == ".png"
        assert sanitize_file_extension("photo.jpg", allowed) == ".jpg"

    def test_valid_extension_uppercase_normalized(self):
        """Test that uppercase extensions are normalized to lowercase."""
        allowed = {".png", ".jpg"}
        assert sanitize_file_extension("image.PNG", allowed) == ".png"
        assert sanitize_file_extension("PHOTO.JPG", allowed) == ".jpg"

    def test_valid_extension_mixed_case(self):
        """Test that mixed case extensions are normalized."""
        allowed = {".png"}
        assert sanitize_file_extension("image.PnG", allowed) == ".png"

    def test_invalid_extension_rejected(self):
        """Test that invalid extensions are rejected."""
        allowed = {".png", ".jpg"}
        with pytest.raises(ValueError, match="not allowed"):
            sanitize_file_extension("script.exe", allowed)

    def test_no_extension_rejected(self):
        """Test that files without extensions are rejected."""
        allowed = {".png", ".jpg"}
        with pytest.raises(ValueError, match="not allowed"):
            sanitize_file_extension("noextension", allowed)

    def test_double_extension(self):
        """Test handling of double extensions (takes last)."""
        allowed = {".gz"}
        assert sanitize_file_extension("file.tar.gz", allowed) == ".gz"

    def test_hidden_file_with_extension(self):
        """Test hidden files with extensions."""
        allowed = {".txt"}
        assert sanitize_file_extension(".hidden.txt", allowed) == ".txt"

    def test_empty_allowed_set(self):
        """Test that empty allowed set rejects all extensions."""
        allowed: set[str] = set()
        with pytest.raises(ValueError, match="not allowed"):
            sanitize_file_extension("file.txt", allowed)


class TestSafeErrorResponse:
    """Tests for safe_error_response function."""

    def test_returns_json_response(self):
        """Test that the function returns a web.Response."""
        error = ValueError("Test error")
        response = safe_error_response(error, "test operation")

        assert response.status == 500
        assert response.content_type == "application/json"

    def test_does_not_expose_error_details(self):
        """Test that the response doesn't expose internal error details."""
        sensitive_error = Exception("Database password is xyz123")
        response = safe_error_response(sensitive_error, "database operation")

        # The response body shouldn't contain the sensitive error message
        body_text = response.text
        assert "xyz123" not in body_text
        assert "password" not in body_text

    def test_includes_context(self):
        """Test that the response includes the operation context."""
        error = ValueError("Some error")
        response = safe_error_response(error, "file upload")

        body_text = response.text
        assert "file upload" in body_text


class TestPathValidationIntegration:
    """Integration tests combining multiple path security functions."""

    def test_validate_sanitized_segment(self, tmp_path):
        """Test using sanitized segment with path validation."""
        # Create a test directory structure
        test_dir = tmp_path / "test-dir"
        test_dir.mkdir()
        test_file = test_dir / "file.txt"
        test_file.touch()

        # Sanitize the segment
        safe_segment = sanitize_path_segment("test-dir")

        # Validate the path
        result = validate_path_in_directory(
            Path(safe_segment) / "file.txt", tmp_path
        )
        assert result == test_file.resolve()

    def test_validate_file_with_extension_check(self, tmp_path):
        """Test combining extension validation with path validation."""
        test_file = tmp_path / "image.png"
        test_file.touch()

        # Check extension first
        ext = sanitize_file_extension("image.png", {".png", ".jpg"})
        assert ext == ".png"

        # Then validate path
        result = validate_path_in_directory(Path("image.png"), tmp_path)
        assert result == test_file.resolve()

    def test_attack_scenario_path_traversal_in_segment(self, tmp_path):
        """Test that path traversal in segment is caught by sanitize_path_segment."""
        with pytest.raises(ValueError):
            sanitize_path_segment("../../../etc/passwd")

    def test_attack_scenario_null_byte_injection(self, tmp_path):
        """Test that null byte injection attempts are handled."""
        # Null bytes are not alphanumeric, so should be rejected
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("file\x00.txt")

    def test_attack_scenario_unicode_normalization(self, tmp_path):
        """Test handling of unicode that could normalize to path separators."""
        # Unicode characters that might normalize to / or \
        with pytest.raises(ValueError, match="invalid characters"):
            sanitize_path_segment("test\u2215file")  # Unicode division slash


class TestCodeqlAssertPathWithin:
    """Tests for codeql_assert_path_within function.

    This function uses CodeQL-recognized patterns (os.path.realpath + startswith)
    to validate that paths stay within allowed directories.
    """

    def test_valid_path_within_directory(self, tmp_path):
        """Test that valid paths within the base directory are accepted."""
        test_file = tmp_path / "test.txt"
        test_file.touch()

        # Should not raise
        codeql_assert_path_within(test_file, tmp_path)

    def test_valid_nested_path(self, tmp_path):
        """Test that nested paths within the base directory are accepted."""
        nested_dir = tmp_path / "subdir" / "nested"
        nested_dir.mkdir(parents=True)
        test_file = nested_dir / "test.txt"
        test_file.touch()

        # Should not raise
        codeql_assert_path_within(test_file, tmp_path)

    def test_path_traversal_rejected(self, tmp_path):
        """Test that path traversal attempts are rejected."""
        # Create a path that escapes the base directory
        escape_path = tmp_path / ".." / "etc" / "passwd"

        with pytest.raises(ValueError, match="escapes allowed directory"):
            codeql_assert_path_within(escape_path, tmp_path)

    def test_absolute_path_outside_rejected(self, tmp_path):
        """Test that absolute paths outside the base directory are rejected."""
        outside_path = Path("/etc/passwd")

        with pytest.raises(ValueError, match="escapes allowed directory"):
            codeql_assert_path_within(outside_path, tmp_path)

    def test_base_directory_itself_accepted(self, tmp_path):
        """Test that the base directory itself is accepted."""
        # Should not raise
        codeql_assert_path_within(tmp_path, tmp_path)

    def test_sibling_directory_rejected(self, tmp_path):
        """Test that sibling directories are rejected."""
        # Create sibling directory
        sibling = tmp_path.parent / "sibling"
        sibling.mkdir(exist_ok=True)

        try:
            with pytest.raises(ValueError, match="escapes allowed directory"):
                codeql_assert_path_within(sibling, tmp_path)
        finally:
            sibling.rmdir()

    def test_symlink_escape_rejected(self, tmp_path):
        """Test that symlinks escaping the directory are rejected."""
        import os

        # Create a symlink pointing outside
        symlink_path = tmp_path / "escape_link"
        try:
            os.symlink("/etc", str(symlink_path))
            target_file = symlink_path / "passwd"

            with pytest.raises(ValueError, match="escapes allowed directory"):
                codeql_assert_path_within(target_file, tmp_path)
        finally:
            if symlink_path.exists() or symlink_path.is_symlink():
                symlink_path.unlink()


class TestSanitizeAndValidatePath:
    """Tests for sanitize_and_validate_path function (returns sanitized path)."""

    def test_valid_path_returns_sanitized_path(self, tmp_path):
        """Test that valid paths return the sanitized path."""
        test_dir = tmp_path / "subdir"
        test_dir.mkdir()

        result = sanitize_and_validate_path(test_dir, tmp_path)
        assert result == test_dir.resolve()
        assert isinstance(result, Path)

    def test_valid_nested_path_returns_sanitized(self, tmp_path):
        """Test that nested valid paths return the sanitized path."""
        nested = tmp_path / "a" / "b" / "c"
        nested.mkdir(parents=True)

        result = sanitize_and_validate_path(nested, tmp_path)
        assert result == nested.resolve()

    def test_path_traversal_rejected(self, tmp_path):
        """Test that path traversal attempts are rejected."""
        escape_path = tmp_path / ".." / ".." / "etc" / "passwd"

        with pytest.raises(ValueError, match="escapes allowed directory"):
            sanitize_and_validate_path(escape_path, tmp_path)

    def test_absolute_path_outside_rejected(self, tmp_path):
        """Test that absolute paths outside base are rejected."""
        outside_path = Path("/etc/passwd")

        with pytest.raises(ValueError, match="escapes allowed directory"):
            sanitize_and_validate_path(outside_path, tmp_path)

    def test_base_directory_itself_accepted(self, tmp_path):
        """Test that the base directory itself is accepted."""
        result = sanitize_and_validate_path(tmp_path, tmp_path)
        assert result == tmp_path.resolve()

    def test_returns_path_object(self, tmp_path):
        """Test that the function returns a Path object."""
        test_file = tmp_path / "test.txt"
        test_file.touch()

        result = sanitize_and_validate_path(test_file, tmp_path)
        assert isinstance(result, Path)
