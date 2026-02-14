"""
API routes for generative media (diagrams, formulas, maps).

These routes enable the curriculum studio to:
- Preview diagrams rendered from Mermaid/Graphviz/etc.
- Validate and preview LaTeX formulas
- Generate map images from specifications
- Check available rendering capabilities
"""

import asyncio
import base64
import logging
from pathlib import Path
from typing import Optional

from aiohttp import web

# Import the generators
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from importers.enrichment.diagram_generator import (
    DiagramGenerator, DiagramSpec, DiagramFormat, DiagramRenderMethod
)
from importers.enrichment.formula_generator import (
    FormulaGenerator, FormulaSpec, FormulaRenderMethod
)
from importers.enrichment.map_generator import (
    MapGenerator, MapSpec, MapStyle, MapMarker, MapRoute, MapRegion, MapRenderMethod
)

logger = logging.getLogger(__name__)

# Global generator instances
_diagram_generator: Optional[DiagramGenerator] = None
_formula_generator: Optional[FormulaGenerator] = None
_map_generator: Optional[MapGenerator] = None


def get_diagram_generator() -> DiagramGenerator:
    """Get or create the diagram generator."""
    global _diagram_generator
    if _diagram_generator is None:
        cache_dir = Path(__file__).parent.parent / "importers" / "cache" / "diagrams"
        _diagram_generator = DiagramGenerator(cache_dir=cache_dir)
    return _diagram_generator


def get_formula_generator() -> FormulaGenerator:
    """Get or create the formula generator."""
    global _formula_generator
    if _formula_generator is None:
        cache_dir = Path(__file__).parent.parent / "importers" / "cache" / "formulas"
        _formula_generator = FormulaGenerator(cache_dir=cache_dir)
    return _formula_generator


def get_map_generator() -> MapGenerator:
    """Get or create the map generator."""
    global _map_generator
    if _map_generator is None:
        cache_dir = Path(__file__).parent.parent / "importers" / "cache" / "maps"
        _map_generator = MapGenerator(cache_dir=cache_dir)
    return _map_generator


# =============================================================================
# Capabilities Endpoint
# =============================================================================

async def handle_get_capabilities(request: web.Request) -> web.Response:
    """
    GET /api/media/capabilities

    Get information about available rendering capabilities.
    """
    try:
        diagram_gen = get_diagram_generator()
        formula_gen = get_formula_generator()
        map_gen = get_map_generator()

        capabilities = {
            "diagrams": {
                "formats": [f.value for f in DiagramFormat],
                "renderers": {
                    "mermaid": diagram_gen._mermaid_available,
                    "graphviz": diagram_gen._graphviz_available,
                    "plantuml": diagram_gen._plantuml_available,
                    "d2": diagram_gen._d2_available,
                },
            },
            "formulas": {
                "renderers": {
                    "katex": formula_gen._katex_available,
                    "latex": formula_gen._latex_available,
                },
                "clientSideSupported": True,  # SwiftMath on iOS
            },
            "maps": {
                "styles": [s.value for s in MapStyle],
                "renderers": {
                    "cartopy": map_gen._cartopy_available,
                    "folium": map_gen._folium_available,
                    "staticTiles": True,  # Always available
                },
                "features": ["markers", "routes", "regions"],
            },
        }

        return web.json_response({
            "success": True,
            "capabilities": capabilities,
        })
    except Exception as e:
        logger.exception("Error getting media capabilities")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Diagram Endpoints
# =============================================================================

async def handle_validate_diagram(request: web.Request) -> web.Response:
    """
    POST /api/media/diagrams/validate

    Validate diagram source code syntax.

    Request body:
    {
        "format": "mermaid",  // mermaid, graphviz, plantuml, d2
        "code": "graph LR\\n  A --> B"
    }
    """
    try:
        data = await request.json()
        format_str = data.get("format", "mermaid")
        code = data.get("code", "")

        try:
            source_format = DiagramFormat(format_str)
        except ValueError:
            return web.json_response({
                "success": False,
                "error": f"Unknown diagram format: {format_str}",
                "validFormats": [f.value for f in DiagramFormat],
            }, status=400)

        generator = get_diagram_generator()
        spec = DiagramSpec(
            id="validation",
            title="Validation",
            source_format=source_format,
            source_code=code,
        )

        errors = await generator.validate(spec)

        return web.json_response({
            "success": True,
            "valid": len(errors) == 0,
            "errors": errors,
        })
    except Exception as e:
        logger.exception("Error validating diagram")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_render_diagram(request: web.Request) -> web.Response:
    """
    POST /api/media/diagrams/render

    Render a diagram to an image.

    Request body:
    {
        "format": "mermaid",
        "code": "graph LR\\n  A --> B",
        "outputFormat": "svg",  // svg, png
        "theme": "default",
        "width": 800,
        "height": 600
    }
    """
    try:
        data = await request.json()
        format_str = data.get("format", "mermaid")
        code = data.get("code", "")
        output_format = data.get("outputFormat", "svg")
        theme = data.get("theme", "default")
        width = data.get("width")
        height = data.get("height")

        try:
            source_format = DiagramFormat(format_str)
        except ValueError:
            return web.json_response({
                "success": False,
                "error": f"Unknown diagram format: {format_str}",
            }, status=400)

        generator = get_diagram_generator()
        spec = DiagramSpec(
            id="preview",
            title="Preview",
            source_format=source_format,
            source_code=code,
            output_format=output_format,
            theme=theme,
            width=width,
            height=height,
        )

        result = await generator.render(spec)

        if result.success and result.data:
            # Encode as base64 for JSON transport
            data_b64 = base64.b64encode(result.data).decode("utf-8")
            return web.json_response({
                "success": True,
                "data": data_b64,
                "mimeType": result.mime_type,
                "width": result.width,
                "height": result.height,
                "renderMethod": result.render_method.value,
            })
        else:
            return web.json_response({
                "success": False,
                "error": result.error or "Rendering failed",
                "validationErrors": result.validation_errors,
                "renderMethod": result.render_method.value,
            }, status=400)
    except Exception as e:
        logger.exception("Error rendering diagram")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Formula Endpoints
# =============================================================================

async def handle_validate_formula(request: web.Request) -> web.Response:
    """
    POST /api/media/formulas/validate

    Validate LaTeX formula syntax.

    Request body:
    {
        "latex": "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}"
    }
    """
    try:
        data = await request.json()
        latex = data.get("latex", "")

        generator = get_formula_generator()
        errors, warnings = await generator.validate_latex(latex)

        return web.json_response({
            "success": True,
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings,
        })
    except Exception as e:
        logger.exception("Error validating formula")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_render_formula(request: web.Request) -> web.Response:
    """
    POST /api/media/formulas/render

    Render a LaTeX formula to an image.

    Request body:
    {
        "latex": "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}",
        "outputFormat": "svg",  // svg, png
        "displayMode": true,    // true for block, false for inline
        "fontSize": 18,
        "color": "#000000"
    }
    """
    try:
        data = await request.json()
        latex = data.get("latex", "")
        output_format = data.get("outputFormat", "svg")
        display_mode = data.get("displayMode", True)
        font_size = data.get("fontSize", 18)
        color = data.get("color", "#000000")

        generator = get_formula_generator()
        spec = FormulaSpec(
            id="preview",
            latex=latex,
            output_format=output_format,
            display_mode=display_mode,
            font_size=font_size,
            color=color,
        )

        result = await generator.render(spec)

        if result.success and result.data:
            data_b64 = base64.b64encode(result.data).decode("utf-8")
            return web.json_response({
                "success": True,
                "data": data_b64,
                "mimeType": result.mime_type,
                "width": result.width,
                "height": result.height,
                "renderMethod": result.render_method.value,
                "warnings": result.validation_warnings,
            })
        else:
            return web.json_response({
                "success": False,
                "error": result.error or "Rendering failed",
                "validationErrors": result.validation_errors,
                "renderMethod": result.render_method.value,
            }, status=400)
    except Exception as e:
        logger.exception("Error rendering formula")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


# =============================================================================
# Map Endpoints
# =============================================================================

async def handle_render_map(request: web.Request) -> web.Response:
    """
    POST /api/media/maps/render

    Render a map image from specification.

    Request body:
    {
        "title": "Italian City-States",
        "center": { "latitude": 43.0, "longitude": 12.0 },
        "zoom": 6,
        "style": "educational",  // standard, historical, physical, etc.
        "width": 800,
        "height": 600,
        "outputFormat": "png",  // png, svg
        "markers": [
            { "latitude": 41.9, "longitude": 12.5, "label": "Rome" }
        ],
        "routes": [
            { "points": [[41.9, 12.5], [43.7, 11.2]], "label": "Trade Route" }
        ],
        "regions": [
            { "points": [[...]], "label": "Papal States", "fillColor": "#ff0000" }
        ]
    }
    """
    try:
        data = await request.json()

        # Parse center coordinates
        center = data.get("center", {})
        center_lat = center.get("latitude", 0.0)
        center_lon = center.get("longitude", 0.0)

        # Parse style
        style_str = data.get("style", "educational")
        try:
            style = MapStyle(style_str)
        except ValueError:
            style = MapStyle.EDUCATIONAL

        # Parse markers
        markers = []
        for m in data.get("markers", []):
            markers.append(MapMarker(
                latitude=m.get("latitude", 0),
                longitude=m.get("longitude", 0),
                label=m.get("label", ""),
                icon=m.get("icon"),
                color=m.get("color", "#E74C3C"),
                popup=m.get("popup"),
            ))

        # Parse routes
        routes = []
        for r in data.get("routes", []):
            points = [(p[0], p[1]) for p in r.get("points", [])]
            routes.append(MapRoute(
                points=points,
                label=r.get("label", ""),
                color=r.get("color", "#3498DB"),
                width=r.get("width", 2.0),
                style=r.get("style", "solid"),
            ))

        # Parse regions
        regions = []
        for reg in data.get("regions", []):
            points = [(p[0], p[1]) for p in reg.get("points", [])]
            regions.append(MapRegion(
                points=points,
                label=reg.get("label", ""),
                fill_color=reg.get("fillColor", "#3498DB"),
                fill_opacity=reg.get("fillOpacity", 0.3),
                border_color=reg.get("borderColor", "#2980B9"),
                border_width=reg.get("borderWidth", 1.0),
            ))

        generator = get_map_generator()
        spec = MapSpec(
            id="preview",
            title=data.get("title", "Map"),
            center_latitude=center_lat,
            center_longitude=center_lon,
            zoom=data.get("zoom", 5),
            width=data.get("width", 800),
            height=data.get("height", 600),
            style=style,
            markers=markers,
            routes=routes,
            regions=regions,
            time_period=data.get("timePeriod"),
            language=data.get("language", "en"),
            output_format=data.get("outputFormat", "png"),
            interactive=data.get("interactive", False),
        )

        result = await generator.render(spec)

        if result.success and result.data:
            data_b64 = base64.b64encode(result.data).decode("utf-8")
            response = {
                "success": True,
                "data": data_b64,
                "mimeType": result.mime_type,
                "width": result.width,
                "height": result.height,
                "renderMethod": result.render_method.value,
            }
            if result.html_content:
                response["htmlContent"] = result.html_content
            return web.json_response(response)
        else:
            return web.json_response({
                "success": False,
                "error": result.error or "Rendering failed",
                "renderMethod": result.render_method.value,
            }, status=400)
    except Exception as e:
        logger.exception("Error rendering map")
        return web.json_response({
            "success": False,
            "error": str(e),
        }, status=500)


async def handle_get_map_styles(request: web.Request) -> web.Response:
    """
    GET /api/media/maps/styles

    Get available map styles with descriptions.
    """
    styles = [
        {"id": "standard", "name": "Standard", "description": "Modern political map"},
        {"id": "historical", "name": "Historical", "description": "Aged parchment style"},
        {"id": "physical", "name": "Physical", "description": "Terrain and elevation focus"},
        {"id": "satellite", "name": "Satellite", "description": "Aerial imagery"},
        {"id": "minimal", "name": "Minimal", "description": "Clean, minimal styling"},
        {"id": "educational", "name": "Educational", "description": "Clear labels for learning"},
    ]
    return web.json_response({
        "success": True,
        "styles": styles,
    })


# =============================================================================
# Route Registration
# =============================================================================

def register_media_routes(app: web.Application):
    """Register all media generation routes on the application."""
    from feature_flag_guard import guarded_routes
    from feature_flag_keys import FlagKeys

    logger.info("Registering media generation API routes...")

    router = guarded_routes(app, FlagKeys.MEDIA_GENERATION_ENABLED)

    # Capabilities
    router.add_get("/api/media/capabilities", handle_get_capabilities)

    # Diagrams
    router.add_post("/api/media/diagrams/validate", handle_validate_diagram)
    router.add_post("/api/media/diagrams/render", handle_render_diagram)

    # Formulas
    router.add_post("/api/media/formulas/validate", handle_validate_formula)
    router.add_post("/api/media/formulas/render", handle_render_formula)

    # Maps
    router.add_post("/api/media/maps/render", handle_render_map)
    router.add_get("/api/media/maps/styles", handle_get_map_styles)

    logger.info("Media API routes registered")
