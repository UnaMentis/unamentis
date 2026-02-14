"""
API routes for plugin management.

These routes power the Plugin Manager in the management dashboard,
enabling users to:
- View all discovered plugins
- Enable/disable plugins
- Configure plugin settings
- Trigger first-run wizard
"""

import logging
from pathlib import Path
from typing import Optional

from aiohttp import web

# Import the importer package
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from importers.core.discovery import get_plugin_discovery, PluginDiscovery
from importers.core.registry import SourceRegistry

logger = logging.getLogger(__name__)

# Global discovery instance
_discovery: Optional[PluginDiscovery] = None


def get_discovery() -> PluginDiscovery:
    """Get the plugin discovery instance."""
    global _discovery
    if _discovery is None:
        _discovery = get_plugin_discovery()
        _discovery.discover_all()
        _discovery.load_state()
    return _discovery


def check_plugin_has_config(discovery: PluginDiscovery, plugin_id: str) -> bool:
    """Check if a plugin has configuration options."""
    try:
        handler_class = discovery.get_plugin_class(plugin_id)
        if handler_class:
            handler = handler_class()
            if hasattr(handler, "get_configuration_schema"):
                schema = handler.get_configuration_schema()
                # Check if schema has actual settings
                if schema and (schema.get("settings") or schema.get("fields")):
                    return True
    except Exception as e:
        logger.debug(f"Could not check config for plugin {plugin_id}: {e}")
    return False


def init_plugin_system():
    """Initialize the plugin system (call on server startup)."""
    logger.info("Initializing plugin system...")
    discovery = get_discovery()
    discovered = len(discovery._discovered)
    enabled = len(discovery.get_enabled_plugins())
    logger.info(f"Plugin system initialized: {discovered} discovered, {enabled} enabled")

    # Check if first-run wizard is needed
    if not discovery.has_state_file():
        logger.info("No plugin state file found - first-run wizard will be triggered")


# =============================================================================
# Plugin Routes
# =============================================================================

async def handle_get_plugins(request: web.Request) -> web.Response:
    """
    GET /api/plugins

    Get list of all discovered plugins with their enabled state.
    """
    try:
        discovery = get_discovery()

        plugins = []
        for plugin in discovery._discovered.values():
            state = discovery._states.get(plugin.plugin_id)
            has_config = check_plugin_has_config(discovery, plugin.plugin_id)
            plugins.append({
                **plugin.to_dict(),
                "enabled": state.enabled if state else False,
                "priority": state.priority if state else 100,
                "settings": state.settings if state else {},
                "has_config": has_config,
            })

        return web.json_response({
            "success": True,
            "plugins": plugins,
            "first_run": not discovery.has_state_file(),
        })
    except Exception as e:
        logger.exception("Error getting plugins")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_plugin(request: web.Request) -> web.Response:
    """
    GET /api/plugins/{plugin_id}

    Get details for a specific plugin.
    """
    plugin_id = request.match_info["plugin_id"]

    try:
        discovery = get_discovery()

        plugin = discovery._discovered.get(plugin_id)
        if not plugin:
            return web.json_response({
                "success": False,
                "error": f"Plugin not found: {plugin_id}",
            }, status=404)

        state = discovery._states.get(plugin_id)
        return web.json_response({
            "success": True,
            "plugin": {
                **plugin.to_dict(),
                "enabled": state.enabled if state else False,
                "priority": state.priority if state else 100,
                "settings": state.settings if state else {},
            },
        })
    except Exception as e:
        logger.exception(f"Error getting plugin {plugin_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_enable_plugin(request: web.Request) -> web.Response:
    """
    POST /api/plugins/{plugin_id}/enable

    Enable a plugin.
    """
    plugin_id = request.match_info["plugin_id"]

    try:
        discovery = get_discovery()

        if plugin_id not in discovery._discovered:
            return web.json_response({
                "success": False,
                "error": f"Plugin not found: {plugin_id}",
            }, status=404)

        success = discovery.enable_plugin(plugin_id)

        # Refresh the SourceRegistry to pick up the newly enabled plugin
        if success:
            SourceRegistry.refresh()

        return web.json_response({
            "success": success,
            "message": f"Plugin {plugin_id} enabled" if success else f"Failed to enable {plugin_id}",
        })
    except Exception as e:
        logger.exception(f"Error enabling plugin {plugin_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_disable_plugin(request: web.Request) -> web.Response:
    """
    POST /api/plugins/{plugin_id}/disable

    Disable a plugin.
    """
    plugin_id = request.match_info["plugin_id"]

    try:
        discovery = get_discovery()

        success = discovery.disable_plugin(plugin_id)

        # Refresh the SourceRegistry to remove the disabled plugin
        if success:
            SourceRegistry.refresh()

        return web.json_response({
            "success": success,
            "message": f"Plugin {plugin_id} disabled" if success else f"Failed to disable {plugin_id}",
        })
    except Exception as e:
        logger.exception(f"Error disabling plugin {plugin_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_configure_plugin(request: web.Request) -> web.Response:
    """
    POST /api/plugins/{plugin_id}/configure

    Update plugin settings.

    Body: { "settings": { ... } }
    """
    plugin_id = request.match_info["plugin_id"]

    try:
        discovery = get_discovery()

        if plugin_id not in discovery._discovered:
            return web.json_response({
                "success": False,
                "error": f"Plugin not found: {plugin_id}",
            }, status=404)

        body = await request.json()
        settings = body.get("settings", {})

        # Update settings in discovery state
        if plugin_id not in discovery._states:
            from importers.core.discovery import PluginState
            discovery._states[plugin_id] = PluginState()

        discovery._states[plugin_id].settings = settings
        discovery.save_state()

        # Also notify the plugin instance if it supports configuration
        try:
            handler = SourceRegistry.get_handler(plugin_id)
            if handler and hasattr(handler, "configure"):
                handler.configure(settings)
        except Exception as e:
            logger.warning(f"Could not notify plugin of configuration change: {e}")

        return web.json_response({
            "success": True,
            "message": f"Plugin {plugin_id} configured",
        })
    except Exception as e:
        logger.exception(f"Error configuring plugin {plugin_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_plugin_config_schema(request: web.Request) -> web.Response:
    """
    GET /api/plugins/{plugin_id}/config-schema

    Get the configuration schema for a plugin.
    Returns the settings fields and their types for the UI to render.
    """
    plugin_id = request.match_info["plugin_id"]

    try:
        discovery = get_discovery()

        if plugin_id not in discovery._discovered:
            return web.json_response({
                "success": False,
                "error": f"Plugin not found: {plugin_id}",
            }, status=404)

        # Try to get schema from the handler
        try:
            handler_class = discovery.get_plugin_class(plugin_id)
            if handler_class:
                handler = handler_class()
                if hasattr(handler, "get_configuration_schema"):
                    schema = handler.get_configuration_schema()
                    return web.json_response({
                        "success": True,
                        "schema": schema,
                        "has_config": True,
                    })
        except Exception as e:
            logger.warning(f"Could not get config schema from plugin: {e}")

        # No configuration schema available
        return web.json_response({
            "success": True,
            "schema": None,
            "has_config": False,
        })
    except Exception as e:
        logger.exception(f"Error getting config schema for {plugin_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_test_plugin(request: web.Request) -> web.Response:
    """
    POST /api/plugins/{plugin_id}/test

    Test plugin configuration (e.g., test API key validity).

    Body: { "settings": { "api_key": "..." } }  (optional, uses saved settings if not provided)
    """
    plugin_id = request.match_info["plugin_id"]

    try:
        discovery = get_discovery()

        if plugin_id not in discovery._discovered:
            return web.json_response({
                "success": False,
                "error": f"Plugin not found: {plugin_id}",
            }, status=404)

        # Get test settings from body (or use saved settings)
        body = {}
        try:
            body = await request.json()
        except Exception:
            pass  # No body is fine

        test_settings = body.get("settings", {})

        # Try to test using the handler
        try:
            handler_class = discovery.get_plugin_class(plugin_id)
            if handler_class:
                handler = handler_class()

                # Check if handler has test method
                if hasattr(handler, "test_api_key"):
                    api_key = test_settings.get("api_key")
                    result = await handler.test_api_key(api_key)
                    return web.json_response({
                        "success": True,
                        "test_result": result,
                    })
                else:
                    return web.json_response({
                        "success": True,
                        "test_result": {
                            "valid": True,
                            "message": "Plugin does not support testing",
                        },
                    })
        except Exception as e:
            logger.warning(f"Plugin test failed: {e}")
            return web.json_response({
                "success": True,
                "test_result": {
                    "valid": False,
                    "message": f"Test failed: {str(e)}",
                },
            })

    except Exception as e:
        logger.exception(f"Error testing plugin {plugin_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_initialize_plugins(request: web.Request) -> web.Response:
    """
    POST /api/plugins/initialize

    Initialize plugin state with specified plugins enabled.
    Used by the first-run wizard.

    Body: { "enabled_plugins": ["mit_ocw", "ck12_flexbook"] }
    """
    try:
        discovery = get_discovery()

        body = await request.json()
        enabled_plugins = body.get("enabled_plugins", [])

        success = discovery.initialize_state(enabled_plugins)

        # Refresh the SourceRegistry
        if success:
            SourceRegistry.refresh()

        return web.json_response({
            "success": success,
            "message": f"Initialized {len(enabled_plugins)} plugins" if success else "Failed to initialize",
            "enabled": enabled_plugins,
        })
    except Exception as e:
        logger.exception("Error initializing plugins")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_first_run_status(request: web.Request) -> web.Response:
    """
    GET /api/plugins/first-run

    Check if first-run wizard is needed.
    """
    try:
        discovery = get_discovery()

        return web.json_response({
            "success": True,
            "first_run_needed": not discovery.has_state_file(),
            "discovered_count": len(discovery._discovered),
        })
    except Exception as e:
        logger.exception("Error checking first-run status")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Source Browser API Routes (for Generic Plugin UI)
# =============================================================================

async def handle_get_enabled_sources(request: web.Request) -> web.Response:
    """
    GET /api/sources

    Get all enabled curriculum sources for the Source Browser.
    """
    try:
        sources = SourceRegistry.get_all_sources()
        return web.json_response({
            "success": True,
            "sources": [s.to_dict() for s in sources],
        })
    except Exception as e:
        logger.exception("Error getting enabled sources")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_source_courses(request: web.Request) -> web.Response:
    """
    GET /api/sources/{source_id}/courses

    Get paginated course catalog for a specific source.

    Query params:
    - page: Page number (default 1)
    - page_size: Items per page (default 20)
    - search: Search query
    - subject: Filter by subject
    - level: Filter by level
    """
    source_id = request.match_info["source_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found or not enabled: {source_id}",
            }, status=404)

        # Parse query params
        page = int(request.query.get("page", 1))
        page_size = int(request.query.get("page_size", 20))
        search = request.query.get("search", None)

        # Build filters
        filters = {}
        if request.query.get("subject"):
            filters["subject"] = request.query["subject"]
        if request.query.get("level"):
            filters["level"] = request.query["level"]
        if request.query.get("features"):
            filters["features"] = request.query["features"].split(",")

        # Get courses
        courses, total, filter_options = await handler.get_course_catalog(
            page=page,
            page_size=page_size,
            filters=filters if filters else None,
            search=search,
        )

        return web.json_response({
            "success": True,
            "courses": [c.to_dict() for c in courses],
            "total": total,
            "page": page,
            "page_size": page_size,
            "total_pages": (total + page_size - 1) // page_size,
            "filters": filter_options,
        })
    except Exception as e:
        logger.exception(f"Error getting courses for {source_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_course_detail(request: web.Request) -> web.Response:
    """
    GET /api/sources/{source_id}/courses/{course_id}

    Get normalized course detail for the generic plugin UI.
    Returns standardized structure with source terminology hints.
    """
    source_id = request.match_info["source_id"]
    course_id = request.match_info["course_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found or not enabled: {source_id}",
            }, status=404)

        # Get normalized course detail
        detail = await handler.get_normalized_course_detail(course_id)

        return web.json_response({
            "success": True,
            "course": detail.to_dict(),
        })
    except ValueError as e:
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=404)
    except Exception as e:
        logger.exception(f"Error getting course detail for {source_id}/{course_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_import_course(request: web.Request) -> web.Response:
    """
    POST /api/sources/{source_id}/courses/{course_id}/import

    Start importing a course from a source.

    Body: {
        "selectedContent": ["ch1-lesson-1", "ch1-lesson-2", ...],  // Optional
        "outputName": "my-course",  // Optional
    }
    """
    source_id = request.match_info["source_id"]
    course_id = request.match_info["course_id"]

    try:
        handler = SourceRegistry.get_handler(source_id)
        if not handler:
            return web.json_response({
                "success": False,
                "error": f"Source not found or not enabled: {source_id}",
            }, status=404)

        body = await request.json()
        selected_content = body.get("selectedContent", [])
        output_name = body.get("outputName", course_id)

        # Get output directory
        output_dir = Path(__file__).parent.parent / "importers" / "output"
        output_dir.mkdir(parents=True, exist_ok=True)

        # Download course
        result_path = await handler.download_course(
            course_id=course_id,
            output_dir=output_dir,
            selected_lectures=selected_content if selected_content else None,
        )

        return web.json_response({
            "success": True,
            "message": f"Course {course_id} imported successfully",
            "output_path": str(result_path),
        })
    except ValueError as e:
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=404)
    except Exception as e:
        logger.exception(f"Error importing course {source_id}/{course_id}")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Route Registration
# =============================================================================

def register_plugin_routes(app: web.Application):
    """Register all plugin-related routes on the application."""
    from feature_flag_guard import guarded_routes
    from feature_flag_keys import FlagKeys

    # Initialize plugin system
    init_plugin_system()

    router = guarded_routes(app, FlagKeys.PLUGIN_SYSTEM)

    # Plugin listing
    router.add_get("/api/plugins", handle_get_plugins)
    router.add_get("/api/plugins/first-run", handle_get_first_run_status)
    router.add_post("/api/plugins/initialize", handle_initialize_plugins)

    # Individual plugin operations
    router.add_get("/api/plugins/{plugin_id}", handle_get_plugin)
    router.add_post("/api/plugins/{plugin_id}/enable", handle_enable_plugin)
    router.add_post("/api/plugins/{plugin_id}/disable", handle_disable_plugin)
    router.add_post("/api/plugins/{plugin_id}/configure", handle_configure_plugin)
    router.add_get("/api/plugins/{plugin_id}/config-schema", handle_get_plugin_config_schema)
    router.add_post("/api/plugins/{plugin_id}/test", handle_test_plugin)

    # Source Browser API (Generic Plugin UI)
    router.add_get("/api/sources", handle_get_enabled_sources)
    router.add_get("/api/sources/{source_id}/courses", handle_get_source_courses)
    router.add_get("/api/sources/{source_id}/courses/{course_id}", handle_get_course_detail)
    router.add_post("/api/sources/{source_id}/courses/{course_id}/import", handle_import_course)

    logger.info("Plugin API routes registered")
