# UnaMentis Management API Reference

**Base URL**: `http://localhost:8766`
**Version**: 1.0.0

---

## Table of Contents

1. [Overview](#overview)
2. [Authentication](#authentication)
3. [Curricula](#curricula)
4. [Visual Assets](#visual-assets)
5. [Media Generation](#media-generation)
6. [Import & Sources](#import--sources)
7. [Plugins](#plugins)
8. [System](#system)
9. [Logs & Metrics](#logs--metrics)
10. [Clients](#clients)
11. [WebSocket](#websocket)
12. [Rate Limiting](#rate-limiting)
13. [Error Handling](#error-handling)

---

## Overview

The UnaMentis Management API is a Python/aiohttp backend providing:
- User authentication with JWT tokens
- Curriculum management (UMCF format)
- Visual asset handling
- Media generation (formulas, diagrams, maps)
- Curriculum import from external sources
- System monitoring and logging

### Common Headers

```
Authorization: Bearer {access_token}
Content-Type: application/json
```

### Response Format

Success:
```json
{
  "success": true,
  "data": { ... }
}
```

Error:
```json
{
  "error": "error_code",
  "message": "Human readable message",
  "code": "ERROR_CODE"
}
```

---

## Authentication

### POST /api/auth/register

Create a new user account.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "securepassword",
  "display_name": "User Name",
  "device": {
    "fingerprint": "device-uuid",
    "name": "Chrome on macOS",
    "type": "web",
    "model": "Chrome",
    "os_version": "120.0",
    "app_version": "1.0.0"
  }
}
```

**Response (201):**
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "display_name": "User Name",
    "role": "user"
  },
  "device": {
    "id": "device-uuid"
  },
  "tokens": {
    "access_token": "jwt-token",
    "refresh_token": "opaque-token",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

**Errors:**
- `400 invalid_email` - Invalid email format
- `400 weak_password` - Password too weak
- `409 email_exists` - Email already registered

---

### POST /api/auth/login

Authenticate and receive tokens.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "password",
  "device": {
    "fingerprint": "device-uuid",
    "name": "Chrome on macOS",
    "type": "web",
    "model": "Chrome",
    "os_version": "120.0",
    "app_version": "1.0.0"
  }
}
```

**Response (200):**
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "display_name": "User Name",
    "role": "user"
  },
  "device": {
    "id": "device-uuid"
  },
  "tokens": {
    "access_token": "jwt-token",
    "refresh_token": "opaque-token",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

**Errors:**
- `400 missing_credentials` - Email or password missing
- `400 missing_device` - Device info required
- `401 invalid_credentials` - Wrong email or password
- `401 account_inactive` - Account disabled
- `401 account_locked` - Too many failed attempts

**Rate Limit:** 5 requests per 60 seconds

---

### POST /api/auth/refresh

Refresh access token using refresh token.

**Request:**
```json
{
  "refresh_token": "opaque-refresh-token"
}
```

**Response (200):**
```json
{
  "tokens": {
    "access_token": "new-jwt-token",
    "refresh_token": "new-opaque-token",
    "token_type": "Bearer",
    "expires_in": 900
  }
}
```

**Errors:**
- `400 missing_token` - Refresh token required
- `401 invalid_token` - Token not found or invalid
- `401 token_expired` - Refresh token expired
- `401 token_reused` - Token already used (family revoked)

**Token Strategy:**
- Access tokens: 15 minutes (JWT)
- Refresh tokens: 30 days (opaque, hashed in DB)
- Token rotation: New refresh token on each refresh
- Family tracking: Reuse detection revokes entire family

---

### POST /api/auth/logout

Logout and revoke tokens.

**Request:**
```json
{
  "refresh_token": "opaque-refresh-token",
  "all_devices": false
}
```

**Response (200):**
```json
{
  "message": "Logged out successfully"
}
```

---

### GET /api/auth/me

Get current user profile.

**Headers:** `Authorization: Bearer {access_token}`

**Response (200):**
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "email_verified": true,
    "display_name": "User Name",
    "avatar_url": null,
    "locale": "en-US",
    "timezone": "America/New_York",
    "role": "user",
    "mfa_enabled": false,
    "created_at": "2024-01-01T00:00:00Z",
    "last_login_at": "2024-01-15T12:30:00Z"
  }
}
```

---

### PATCH /api/auth/me

Update user profile.

**Headers:** `Authorization: Bearer {access_token}`

**Request:**
```json
{
  "display_name": "New Name",
  "avatar_url": "https://...",
  "locale": "en-US",
  "timezone": "America/Los_Angeles"
}
```

**Response (200):** Updated user object

---

### POST /api/auth/password

Change password.

**Headers:** `Authorization: Bearer {access_token}`

**Request:**
```json
{
  "current_password": "<current>",
  "new_password": "<new>"
}
```

**Response (200):**
```json
{
  "message": "Password changed successfully"
}
```

**Behavior:** Revokes all refresh tokens from other devices.

---

### GET /api/auth/devices

List registered devices.

**Headers:** `Authorization: Bearer {access_token}`

**Response (200):**
```json
{
  "devices": [
    {
      "id": "device-uuid",
      "name": "Chrome on macOS",
      "type": "web",
      "model": "Chrome",
      "os_version": "120.0",
      "app_version": "1.0.0",
      "is_trusted": false,
      "last_seen_at": "2024-01-15T12:30:00Z",
      "created_at": "2024-01-01T00:00:00Z"
    }
  ]
}
```

---

### DELETE /api/auth/devices/{device_id}

Remove a device.

**Headers:** `Authorization: Bearer {access_token}`

**Response (200):**
```json
{
  "message": "Device removed successfully"
}
```

---

### GET /api/auth/sessions

List active sessions.

**Headers:** `Authorization: Bearer {access_token}`

**Response (200):**
```json
{
  "sessions": [
    {
      "id": "session-uuid",
      "ip_address": "192.168.1.1",
      "user_agent": "Mozilla/5.0...",
      "location": {
        "country": "US",
        "city": "San Francisco"
      },
      "device": {
        "name": "Chrome on macOS",
        "type": "web"
      },
      "created_at": "2024-01-15T00:00:00Z",
      "last_activity_at": "2024-01-15T12:30:00Z"
    }
  ]
}
```

---

### DELETE /api/auth/sessions/{session_id}

Terminate a session.

**Headers:** `Authorization: Bearer {access_token}`

**Response (200):**
```json
{
  "message": "Session terminated"
}
```

---

## Curricula

### GET /api/curricula

List all curricula.

**Response (200):**
```json
{
  "curricula": [
    {
      "id": "curriculum-id",
      "title": "Biology 101",
      "description": "Introduction to biology",
      "author": "Dr. Smith",
      "language": "en",
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-15T12:30:00Z",
      "topics_count": 42,
      "status": "published"
    }
  ]
}
```

---

### GET /api/curricula/{curriculum_id}

Get curriculum detail with topics.

**Response (200):**
```json
{
  "curriculum": {
    "id": "curriculum-id",
    "title": "Biology 101",
    "description": "Introduction to biology",
    "author": "Dr. Smith",
    "language": "en",
    "topics": [
      {
        "id": "topic-1",
        "title": "Cell Structure",
        "description": "Introduction to cells",
        "duration": 1200,
        "assets": [
          {
            "id": "asset-1",
            "type": "diagram",
            "format": "svg",
            "url": "/assets/cell-diagram.svg",
            "description": "Cell diagram"
          }
        ]
      }
    ]
  }
}
```

---

### GET /api/curricula/{curriculum_id}/full

Get full UMCF JSON document.

**Response (200):** Complete UMCF JSON

---

### GET /api/curricula/{curriculum_id}/full-with-assets

Get full curriculum with binary assets.

**Response (200):**
```json
{
  "curriculum": { ... },
  "assets": {
    "asset-id": "base64-encoded-binary",
    ...
  }
}
```

---

### GET /api/curricula/{curriculum_id}/topics/{topic_id}/transcript

Get topic transcript segments.

**Response (200):**
```json
{
  "transcript": {
    "segments": [
      {
        "id": "seg-1",
        "type": "introduction",
        "content": "Welcome to this lesson...",
        "speakingNotes": {
          "pace": "normal",
          "emphasis": ["key word"],
          "pauseAfter": true
        }
      }
    ],
    "totalDuration": "PT45M",
    "pronunciationGuide": {
      "mitochondria": {
        "ipa": "/maɪtəˈkɑːndriə/",
        "respelling": "my-tuh-KON-dree-uh"
      }
    }
  }
}
```

---

### GET /api/curricula/{curriculum_id}/topics/{topic_id}/stream-audio

Stream pre-recorded topic audio.

**Response:** Audio stream (chunked, audio/mpeg or audio/wav)

---

### PUT /api/curricula/{curriculum_id}

Update curriculum.

**Request:** Full curriculum object

**Response (200):** Updated curriculum

---

### DELETE /api/curricula/{curriculum_id}

Delete curriculum.

**Query:** `confirm=true` (required)

**Response (200):**
```json
{
  "message": "Curriculum deleted"
}
```

---

### POST /api/curricula/{curriculum_id}/archive

Archive curriculum.

**Response (200):**
```json
{
  "message": "Curriculum archived",
  "archive_file": "curriculum-id-2024-01-15.tar.gz"
}
```

---

### GET /api/curricula/archived

List archived curricula.

**Response (200):**
```json
{
  "archived": [
    {
      "file_name": "curriculum-id-2024-01-15.tar.gz",
      "curriculum_id": "curriculum-id",
      "curriculum_title": "Biology 101",
      "archived_at": "2024-01-15T12:30:00Z",
      "file_size": 102400,
      "checksum": "sha256-hash"
    }
  ]
}
```

---

### POST /api/curricula/archived/{file_name}/unarchive

Unarchive curriculum.

**Response (200):**
```json
{
  "message": "Curriculum unarchived",
  "curriculum_id": "curriculum-id"
}
```

---

### POST /api/curricula/reload

Reload curricula from disk/database.

**Response (200):**
```json
{
  "message": "Curricula reloaded",
  "curricula_count": 42
}
```

---

### POST /api/curricula/import

Import curriculum from file.

**Request:** Form data with file upload

**Response (200):**
```json
{
  "message": "Curriculum imported",
  "curriculum_id": "new-curriculum-id"
}
```

---

## Visual Assets

### POST /api/curricula/{curriculum_id}/topics/{topic_id}/assets

Upload visual asset.

**Request:** Form data
- `file`: Binary image/diagram
- `type`: diagram|formula|map|image
- `description`: Optional description

**Response (201):**
```json
{
  "asset": {
    "id": "asset-id",
    "type": "diagram",
    "format": "svg",
    "url": "/assets/...",
    "description": "Cell diagram",
    "size": 4096,
    "created_at": "2024-01-15T12:30:00Z"
  }
}
```

---

### PATCH /api/curricula/{curriculum_id}/topics/{topic_id}/assets/{asset_id}

Update asset metadata.

**Request:**
```json
{
  "description": "Updated description",
  "alt_text": "Alternative text"
}
```

**Response (200):** Updated asset object

---

### DELETE /api/curricula/{curriculum_id}/topics/{topic_id}/assets/{asset_id}

Delete visual asset.

**Response (200):**
```json
{
  "message": "Asset deleted"
}
```

---

### POST /api/curricula/{curriculum_id}/preload-assets

Preload all curriculum assets.

**Response (200):**
```json
{
  "message": "Assets preloaded",
  "total_assets": 15,
  "total_size_bytes": 2097152
}
```

---

## Media Generation

### GET /api/media/capabilities

Get available rendering capabilities.

**Response (200):**
```json
{
  "success": true,
  "capabilities": {
    "diagrams": {
      "formats": ["mermaid", "graphviz", "plantuml", "d2"],
      "renderers": {
        "mermaid": true,
        "graphviz": true,
        "plantuml": false,
        "d2": false
      }
    },
    "formulas": {
      "renderers": {
        "katex": true,
        "latex": true
      },
      "clientSideSupported": true
    },
    "maps": {
      "styles": ["standard", "historical", "physical", "satellite", "minimal", "educational"],
      "renderers": {
        "cartopy": true,
        "folium": true,
        "staticTiles": true
      },
      "features": ["markers", "routes", "regions"]
    }
  }
}
```

---

### POST /api/media/diagrams/validate

Validate diagram source.

**Request:**
```json
{
  "format": "mermaid",
  "code": "graph LR\n  A --> B"
}
```

**Response (200):**
```json
{
  "success": true,
  "valid": true,
  "errors": []
}
```

---

### POST /api/media/diagrams/render

Render diagram to image.

**Request:**
```json
{
  "format": "mermaid",
  "code": "graph LR\n  A --> B",
  "outputFormat": "svg",
  "theme": "default",
  "width": 800,
  "height": 600
}
```

**Response (200):**
```json
{
  "success": true,
  "data": "base64-encoded-image",
  "mimeType": "image/svg+xml",
  "width": 800,
  "height": 600,
  "renderMethod": "mermaid"
}
```

---

### POST /api/media/formulas/validate

Validate LaTeX formula.

**Request:**
```json
{
  "latex": "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}"
}
```

**Response (200):**
```json
{
  "success": true,
  "valid": true,
  "errors": [],
  "warnings": []
}
```

---

### POST /api/media/formulas/render

Render formula to image.

**Request:**
```json
{
  "latex": "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}",
  "outputFormat": "svg",
  "displayMode": true,
  "fontSize": 18,
  "color": "#000000"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": "base64-encoded-image",
  "mimeType": "image/svg+xml",
  "width": 300,
  "height": 80,
  "renderMethod": "katex"
}
```

---

### POST /api/media/maps/render

Render geographic map.

**Request:**
```json
{
  "title": "Italian City-States",
  "center": {
    "latitude": 43.0,
    "longitude": 12.0
  },
  "zoom": 6,
  "style": "educational",
  "width": 800,
  "height": 600,
  "outputFormat": "png",
  "markers": [
    {
      "latitude": 41.9,
      "longitude": 12.5,
      "label": "Rome",
      "color": "#E74C3C"
    }
  ],
  "routes": [
    {
      "points": [[41.9, 12.5], [43.7, 11.2]],
      "label": "Trade Route",
      "color": "#3498DB",
      "width": 2.0
    }
  ],
  "regions": [
    {
      "points": [[42.0, 11.0], [42.5, 13.0], [41.5, 13.0]],
      "label": "Papal States",
      "fillColor": "#ff0000",
      "fillOpacity": 0.3
    }
  ]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": "base64-encoded-image",
  "mimeType": "image/png",
  "width": 800,
  "height": 600,
  "renderMethod": "cartopy"
}
```

---

### GET /api/media/maps/styles

List available map styles.

**Response (200):**
```json
{
  "success": true,
  "styles": [
    {
      "id": "standard",
      "name": "Standard",
      "description": "Modern political map"
    },
    {
      "id": "historical",
      "name": "Historical",
      "description": "Aged parchment style"
    },
    {
      "id": "physical",
      "name": "Physical",
      "description": "Terrain and elevation"
    },
    {
      "id": "satellite",
      "name": "Satellite",
      "description": "Aerial imagery"
    },
    {
      "id": "minimal",
      "name": "Minimal",
      "description": "Clean, minimal styling"
    },
    {
      "id": "educational",
      "name": "Educational",
      "description": "Clear labels for learning"
    }
  ]
}
```

---

## Import & Sources

### GET /api/import/sources

List curriculum import sources.

**Response (200):**
```json
{
  "success": true,
  "sources": [
    {
      "id": "mit_ocw",
      "name": "MIT OpenCourseWare",
      "description": "MIT's free courses",
      "url": "https://ocw.mit.edu",
      "icon_url": "https://...",
      "license_type": "cc-by-4.0",
      "supported_features": ["transcripts", "lecture_notes", "assignments"]
    }
  ]
}
```

---

### GET /api/import/sources/{source_id}

Get source details.

**Response (200):**
```json
{
  "success": true,
  "source": {
    "id": "mit_ocw",
    "name": "MIT OpenCourseWare",
    "description": "...",
    "url": "https://...",
    "icon_url": "https://...",
    "license_type": "cc-by-4.0",
    "supported_features": ["transcripts", "lecture_notes"]
  }
}
```

---

### GET /api/import/sources/{source_id}/courses

List courses from source.

**Query Parameters:**
- `page`: Page number (default: 1)
- `pageSize`: Items per page (default: 20)
- `search`: Search query
- `subject`: Filter by subject
- `level`: Filter by level

**Response (200):**
```json
{
  "success": true,
  "courses": [
    {
      "id": "6-001-spring-2005",
      "title": "Structure and Interpretation of Computer Programs",
      "description": "...",
      "instructor": "Prof. Sussman",
      "subject": "computer-science",
      "level": "introductory",
      "language": "en",
      "duration": 1800,
      "featured": true,
      "available_features": ["transcripts", "lecture_notes"]
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 150,
    "totalPages": 8
  }
}
```

---

### GET /api/import/sources/{source_id}/courses/{course_id}

Get course details.

**Response (200):**
```json
{
  "success": true,
  "course": {
    "id": "6-001-spring-2005",
    "title": "Structure and Interpretation of Computer Programs",
    "description": "Full description...",
    "instructor": "Prof. Sussman",
    "instructor_bio": "...",
    "subject": "computer-science",
    "level": "introductory",
    "language": "en",
    "duration": 1800,
    "lectures": [
      {
        "id": "lecture-1",
        "title": "Introduction",
        "duration": 50,
        "has_transcript": true,
        "has_video": true,
        "has_notes": true
      }
    ],
    "resources": {
      "assignments": 12,
      "exams": 2,
      "reading_materials": 34
    }
  },
  "canImport": true,
  "licenseWarnings": [],
  "attribution": "MIT OpenCourseWare (CC-BY-4.0)"
}
```

---

### POST /api/import/jobs

Start import job.

**Request:**
```json
{
  "sourceId": "mit_ocw",
  "courseId": "6-001-spring-2005",
  "outputName": "sicp-6001",
  "selectedLectures": ["lecture-1", "lecture-2"],
  "includeTranscripts": true,
  "includeLectureNotes": true,
  "includeAssignments": true,
  "generateObjectives": true,
  "createCheckpoints": true,
  "generateSpokenText": true
}
```

**Response (200):**
```json
{
  "success": true,
  "jobId": "import-job-uuid",
  "status": "queued"
}
```

---

### GET /api/import/jobs/{job_id}

Get import progress.

**Response (200):**
```json
{
  "success": true,
  "progress": {
    "id": "import-job-uuid",
    "source_id": "mit_ocw",
    "course_id": "6-001-spring-2005",
    "status": "in_progress",
    "percent_complete": 45,
    "current_step": "Processing lecture 3 of 12",
    "items_processed": 3,
    "items_total": 12,
    "errors": [],
    "warnings": ["Lecture 5 video unavailable"],
    "started_at": "2024-01-15T12:00:00Z",
    "estimated_completion_at": "2024-01-15T13:30:00Z"
  }
}
```

---

### GET /api/import/jobs

List import jobs.

**Query:** `status`: Filter by status (queued, in_progress, complete, failed, cancelled)

**Response (200):**
```json
{
  "success": true,
  "jobs": [...]
}
```

---

### DELETE /api/import/jobs/{job_id}

Cancel import job.

**Response (200):**
```json
{
  "success": true,
  "cancelled": true
}
```

---

## Plugins

### GET /api/plugins

List discovered plugins.

**Response (200):**
```json
{
  "success": true,
  "plugins": [
    {
      "plugin_id": "mit_ocw",
      "name": "MIT OpenCourseWare",
      "version": "1.0.0",
      "description": "Curriculum importer for MIT OCW",
      "author": "UnaMentis",
      "enabled": true,
      "priority": 100,
      "settings": {},
      "has_config": false
    }
  ],
  "first_run": false
}
```

---

### POST /api/plugins/{plugin_id}/enable

Enable plugin.

**Response (200):**
```json
{
  "success": true,
  "message": "Plugin enabled"
}
```

---

### POST /api/plugins/{plugin_id}/disable

Disable plugin.

**Response (200):**
```json
{
  "success": true,
  "message": "Plugin disabled"
}
```

---

### POST /api/plugins/{plugin_id}/configure

Configure plugin settings.

**Request:**
```json
{
  "settings": {
    "api_key": "...",
    "timeout": 30
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Plugin configured"
}
```

---

### POST /api/plugins/initialize

Initialize plugins on first run.

**Request:**
```json
{
  "enabled_plugins": ["mit_ocw", "ck12_flexbook"]
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Initialized 2 plugins",
  "enabled": ["mit_ocw", "ck12_flexbook"]
}
```

---

## System

### GET /health

Health check.

**Response (200):**
```json
{
  "status": "healthy",
  "server_time": "2024-01-15T12:30:00Z",
  "uptime_seconds": 3600,
  "version": "1.0.0"
}
```

---

### GET /api/system/metrics

Get system metrics.

**Response (200):**
```json
{
  "success": true,
  "cpu_percent": 45.2,
  "memory_percent": 62.1,
  "disk_percent": 71.5,
  "gpu_percent": 0,
  "temperature": 58.3,
  "timestamp": "2024-01-15T12:30:00Z"
}
```

---

### GET /api/system/snapshot

Get system snapshot with processes.

**Response (200):**
```json
{
  "success": true,
  "snapshot": {
    "timestamp": "2024-01-15T12:30:00Z",
    "metrics": { ... },
    "processes": [
      {
        "pid": 1234,
        "name": "python",
        "cpu_percent": 15.2,
        "memory_mb": 256.5
      }
    ]
  }
}
```

---

### GET /api/stats

Get server statistics.

**Response (200):**
```json
{
  "total_logs_received": 150000,
  "total_metrics_received": 50000,
  "online_clients": 12,
  "registered_servers": 3,
  "uptime_seconds": 7200
}
```

---

### GET /api/system/idle/status

Get idle management status.

**Response (200):**
```json
{
  "success": true,
  "current_state": "active",
  "idle_enabled": true,
  "keep_awake_until": null,
  "idle_timeout_minutes": 30,
  "power_mode": "performance"
}
```

---

### POST /api/system/idle/config

Configure idle management.

**Request:**
```json
{
  "idle_timeout_minutes": 30,
  "power_mode": "balanced",
  "enabled": true
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Idle configuration updated"
}
```

---

### POST /api/system/idle/keep-awake

Prevent idle for duration.

**Request:**
```json
{
  "duration_minutes": 60
}
```

**Response (200):**
```json
{
  "success": true,
  "keep_awake_until": "2024-01-15T13:30:00Z"
}
```

---

## Logs & Metrics

### POST /api/logs

Send log entry.

**Request:**
```json
{
  "id": "log-entry-id",
  "timestamp": "2024-01-15T12:30:00Z",
  "level": "INFO",
  "label": "SessionManager",
  "message": "Session started",
  "file": "session.ts",
  "function": "startSession",
  "line": 123,
  "metadata": {
    "session_id": "session-uuid"
  },
  "client_id": "device-uuid",
  "client_name": "Chrome on macOS"
}
```

**Response (200):**
```json
{
  "success": true
}
```

---

### GET /api/logs

Get logs.

**Query:**
- `limit`: Number of logs (default: 1000)
- `level`: Filter by level (INFO, DEBUG, WARNING, ERROR)
- `label`: Filter by label
- `since`: ISO timestamp

**Response (200):**
```json
{
  "logs": [
    {
      "id": "log-entry-id",
      "timestamp": "2024-01-15T12:30:00Z",
      "level": "INFO",
      "label": "SessionManager",
      "message": "Session started",
      "client_name": "Chrome on macOS"
    }
  ],
  "total": 15000
}
```

---

### DELETE /api/logs

Clear logs.

**Response (200):**
```json
{
  "success": true,
  "cleared_count": 15000
}
```

---

### POST /api/metrics

Send metrics.

**Request:**
```json
{
  "id": "metric-id",
  "client_id": "device-uuid",
  "client_name": "Chrome on macOS",
  "timestamp": "2024-01-15T12:30:00Z",
  "memory_mb": 512,
  "cpu_percent": 45.2,
  "network_latency_ms": 25,
  "custom_metrics": {
    "stt_latency": 150,
    "llm_ttft": 280,
    "tts_ttfb": 120,
    "e2e_latency": 450
  }
}
```

**Response (200):**
```json
{
  "success": true
}
```

---

### GET /api/metrics

Get metrics.

**Query:**
- `client_id`: Filter by client
- `limit`: Number of metrics (default: 1000)

**Response (200):**
```json
{
  "metrics": [...],
  "total": 50000
}
```

---

## Clients

### GET /api/clients

List connected clients.

**Response (200):**
```json
{
  "clients": [
    {
      "client_id": "device-uuid",
      "client_name": "Chrome on macOS",
      "status": "online",
      "last_heartbeat": "2024-01-15T12:30:00Z",
      "created_at": "2024-01-01T00:00:00Z",
      "logs_sent": 1500,
      "metrics_sent": 500
    }
  ],
  "total": 12
}
```

---

### POST /api/clients/heartbeat

Client heartbeat.

**Request:**
```json
{
  "client_id": "device-uuid",
  "client_name": "Chrome on macOS",
  "status": "online",
  "memory_mb": 512,
  "cpu_percent": 45.2
}
```

**Response (200):**
```json
{
  "success": true,
  "server_time": "2024-01-15T12:30:00Z"
}
```

---

## WebSocket

### WS /ws

Real-time updates via WebSocket.

**Connection:**
```
ws://localhost:8766/ws
```

**Connected Message:**
```json
{
  "type": "connected",
  "data": {
    "server_time": "2024-01-15T12:30:00Z",
    "stats": {
      "total_logs": 150000,
      "online_clients": 12
    }
  }
}
```

**Client Ping:**
```json
{
  "type": "ping"
}
```

**Server Pong:**
```json
{
  "type": "pong",
  "timestamp": 1705328400.123
}
```

**Broadcast Messages:**
- `log_received`: New log entry
- `metrics_received`: New metrics
- `client_status_changed`: Client online/offline

---

## Rate Limiting

All endpoints subject to token bucket rate limiting:

| Endpoint | Requests | Window | Burst |
|----------|----------|--------|-------|
| `auth/login` | 5 | 60s | 5 |
| `auth/register` | 3 | 3600s | 3 |
| `auth/refresh` | 60 | 60s | 10 |
| Authenticated API | 1000 | 60s | 100 |
| Unauthenticated | 100 | 60s | 20 |

**Rate Limit Headers:**
```
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 3
X-RateLimit-Reset: 1705328460
X-RateLimit-Window: 60
Retry-After: 12
```

**Rate Limit Error (429):**
```json
{
  "error": "Rate limit exceeded",
  "code": "RATE_LIMIT_EXCEEDED",
  "retry_after": 12
}
```

---

## Error Handling

### HTTP Status Codes

| Status | Meaning |
|--------|---------|
| 200 | Success |
| 201 | Created |
| 204 | No Content |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 409 | Conflict |
| 429 | Rate Limited |
| 500 | Server Error |
| 503 | Unavailable |

### Error Response Format

```json
{
  "error": "error_code",
  "message": "Human readable message",
  "code": "ERROR_CODE",
  "details": {}
}
```

### Common Error Codes

| Code | Meaning |
|------|---------|
| `invalid_json` | Malformed JSON body |
| `missing_field` | Required field missing |
| `invalid_email` | Invalid email format |
| `weak_password` | Password too weak |
| `invalid_credentials` | Wrong email/password |
| `token_expired` | Token has expired |
| `not_found` | Resource not found |
| `rate_limit_exceeded` | Too many requests |

---

*End of API Reference*
