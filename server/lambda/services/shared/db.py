"""
Database connection utilities for Lambda functions.

Provides connection pooling and query execution for PostgreSQL.
Connections are reused across Lambda invocations for performance.
"""

import logging
import os
from contextlib import contextmanager
from typing import Any

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Connection pool (reused across Lambda invocations)
_connection_pool: pool.ThreadedConnectionPool | None = None


class DatabaseError(Exception):
    """Custom exception for database errors."""

    def __init__(self, message: str, original_error: Exception | None = None):
        super().__init__(message)
        self.original_error = original_error


def _get_connection_pool() -> pool.ThreadedConnectionPool:
    """Get or create the connection pool."""
    global _connection_pool

    if _connection_pool is None:
        database_url = os.environ.get("DATABASE_URL")
        if not database_url:
            raise DatabaseError("DATABASE_URL environment variable not set")

        try:
            _connection_pool = pool.ThreadedConnectionPool(
                minconn=1,
                maxconn=5,
                dsn=database_url,
            )
            logger.info("Database connection pool created")
        except psycopg2.Error as e:
            raise DatabaseError(f"Failed to create connection pool: {e}", e) from e

    return _connection_pool


@contextmanager
def get_db_connection():
    """
    Context manager for database connections.

    Automatically returns the connection to the pool when done.

    Usage:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM users")
                results = cur.fetchall()
    """
    conn = None
    try:
        pool = _get_connection_pool()
        conn = pool.getconn()
        yield conn
        conn.commit()
    except psycopg2.Error as e:
        if conn:
            conn.rollback()
        raise DatabaseError(f"Database error: {e}", e) from e
    finally:
        if conn:
            pool.putconn(conn)


def execute_query(
    query: str,
    params: tuple | dict | None = None,
    fetch_one: bool = False,
    fetch_all: bool = True,
) -> list[dict[str, Any]] | dict[str, Any] | None:
    """
    Execute a query and return results as dictionaries.

    Args:
        query: SQL query string
        params: Query parameters (tuple or dict)
        fetch_one: If True, return only the first row
        fetch_all: If True, return all rows (default)

    Returns:
        Query results as list of dicts, single dict, or None

    Usage:
        # Fetch all rows
        users = execute_query("SELECT * FROM users WHERE active = %s", (True,))

        # Fetch one row
        user = execute_query(
            "SELECT * FROM users WHERE id = %s",
            (user_id,),
            fetch_one=True
        )

        # Insert/Update (no return)
        execute_query(
            "INSERT INTO users (name, email) VALUES (%s, %s)",
            ("John", "john@example.com"),
            fetch_all=False
        )
    """
    with get_db_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)

            if fetch_one:
                row = cur.fetchone()
                return dict(row) if row else None
            elif fetch_all:
                rows = cur.fetchall()
                return [dict(row) for row in rows]
            else:
                return None


def execute_many(
    query: str,
    params_list: list[tuple | dict],
) -> int:
    """
    Execute a query multiple times with different parameters.

    Args:
        query: SQL query string
        params_list: List of parameter tuples or dicts

    Returns:
        Number of rows affected

    Usage:
        count = execute_many(
            "INSERT INTO users (name, email) VALUES (%s, %s)",
            [("John", "john@example.com"), ("Jane", "jane@example.com")]
        )
    """
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.executemany(query, params_list)
            return cur.rowcount


def check_health() -> dict[str, Any]:
    """
    Check database health.

    Returns:
        Dict with health status and details
    """
    try:
        result = execute_query("SELECT 1 as healthy, NOW() as timestamp", fetch_one=True)
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": str(result["timestamp"]) if result else None,
        }
    except DatabaseError as e:
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e),
        }
