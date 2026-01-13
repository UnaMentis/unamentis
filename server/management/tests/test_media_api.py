"""
Tests for Media API routes.
"""
import base64
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web


class MockDiagramFormat:
    """Mock diagram format enum."""
    MERMAID = "mermaid"
    GRAPHVIZ = "graphviz"
    PLANTUML = "plantuml"
    D2 = "d2"

    def __init__(self, value):
        self.value = value


class MockDiagramRenderMethod:
    """Mock diagram render method enum."""
    def __init__(self, value="mermaid_cli"):
        self.value = value


class MockDiagramResult:
    """Mock diagram render result."""

    def __init__(self, success=True, data=None, error=None):
        self.success = success
        self.data = data or b"<svg></svg>"
        self.error = error
        self.mime_type = "image/svg+xml"
        self.width = 800
        self.height = 600
        self.render_method = MockDiagramRenderMethod()
        self.validation_errors = []


class MockDiagramGenerator:
    """Mock diagram generator."""

    def __init__(self):
        self._mermaid_available = True
        self._graphviz_available = True
        self._plantuml_available = False
        self._d2_available = False

    async def validate(self, spec):
        if "invalid" in spec.source_code:
            return ["Syntax error on line 1"]
        return []

    async def render(self, spec):
        if "fail" in spec.source_code:
            return MockDiagramResult(success=False, error="Render failed")
        return MockDiagramResult(success=True, data=b"<svg>rendered</svg>")


class MockFormulaRenderMethod:
    """Mock formula render method enum."""
    def __init__(self, value="katex"):
        self.value = value


class MockFormulaResult:
    """Mock formula render result."""

    def __init__(self, success=True, data=None, error=None):
        self.success = success
        self.data = data or b"<svg></svg>"
        self.error = error
        self.mime_type = "image/svg+xml"
        self.width = 200
        self.height = 50
        self.render_method = MockFormulaRenderMethod()
        self.validation_errors = []
        self.validation_warnings = []


class MockFormulaGenerator:
    """Mock formula generator."""

    def __init__(self):
        self._katex_available = True
        self._latex_available = False

    async def validate_latex(self, latex):
        errors = []
        warnings = []
        if "invalid" in latex:
            errors.append("Invalid LaTeX syntax")
        if "deprecated" in latex:
            warnings.append("Using deprecated command")
        return errors, warnings

    async def render(self, spec):
        if "fail" in spec.latex:
            return MockFormulaResult(success=False, error="Render failed")
        return MockFormulaResult(success=True, data=b"<svg>formula</svg>")


class MockMapStyle:
    """Mock map style enum."""
    STANDARD = "standard"
    HISTORICAL = "historical"
    PHYSICAL = "physical"
    SATELLITE = "satellite"
    MINIMAL = "minimal"
    EDUCATIONAL = "educational"

    def __init__(self, value):
        self.value = value


class MockMapRenderMethod:
    """Mock map render method enum."""
    def __init__(self, value="static_tiles"):
        self.value = value


class MockMapResult:
    """Mock map render result."""

    def __init__(self, success=True, data=None, error=None):
        self.success = success
        self.data = data or b"\x89PNG"
        self.error = error
        self.mime_type = "image/png"
        self.width = 800
        self.height = 600
        self.render_method = MockMapRenderMethod()
        self.html_content = None


class MockMapGenerator:
    """Mock map generator."""

    def __init__(self):
        self._cartopy_available = False
        self._folium_available = True

    async def render(self, spec):
        if spec.title == "fail":
            return MockMapResult(success=False, error="Render failed")
        result = MockMapResult(success=True, data=b"\x89PNG\r\n\x1a\n")
        if spec.interactive:
            result.html_content = "<html>Interactive map</html>"
        return result


# Import the module under test
import media_api


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    return web.Application()


@pytest.fixture
def mock_request(mock_app):
    """Create a factory for mock requests."""
    def _make_request(method="POST", json_data=None, query=None, match_info=None):
        request = MagicMock(spec=web.Request)
        request.app = mock_app
        request.method = method
        request.query = query or {}
        request.match_info = match_info or {}

        if json_data is not None:
            async def mock_json():
                return json_data
            request.json = mock_json
        else:
            async def mock_json():
                raise ValueError("No JSON")
            request.json = mock_json

        return request
    return _make_request


# =============================================================================
# Generator Helper Tests
# =============================================================================

class TestGetDiagramGenerator:
    """Tests for get_diagram_generator helper."""

    @patch('media_api._diagram_generator', None)
    @patch('media_api.DiagramGenerator')
    def test_creates_generator_on_first_call(self, mock_class):
        """Test that generator is created on first call."""
        mock_class.return_value = MockDiagramGenerator()
        result = media_api.get_diagram_generator()
        mock_class.assert_called_once()


class TestGetFormulaGenerator:
    """Tests for get_formula_generator helper."""

    @patch('media_api._formula_generator', None)
    @patch('media_api.FormulaGenerator')
    def test_creates_generator_on_first_call(self, mock_class):
        """Test that generator is created on first call."""
        mock_class.return_value = MockFormulaGenerator()
        result = media_api.get_formula_generator()
        mock_class.assert_called_once()


class TestGetMapGenerator:
    """Tests for get_map_generator helper."""

    @patch('media_api._map_generator', None)
    @patch('media_api.MapGenerator')
    def test_creates_generator_on_first_call(self, mock_class):
        """Test that generator is created on first call."""
        mock_class.return_value = MockMapGenerator()
        result = media_api.get_map_generator()
        mock_class.assert_called_once()


# =============================================================================
# Capabilities Endpoint Tests
# =============================================================================

class TestHandleGetCapabilities:
    """Tests for handle_get_capabilities endpoint."""

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.get_formula_generator')
    @patch('media_api.get_diagram_generator')
    async def test_get_capabilities_success(
        self, mock_diagram, mock_formula, mock_map, mock_request
    ):
        """Test successful capabilities retrieval."""
        mock_diagram.return_value = MockDiagramGenerator()
        mock_formula.return_value = MockFormulaGenerator()
        mock_map.return_value = MockMapGenerator()

        request = mock_request(method="GET")
        response = await media_api.handle_get_capabilities(request)

        assert response.status == 200
        assert response.content_type == "application/json"

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    async def test_get_capabilities_error(self, mock_diagram, mock_request):
        """Test error handling in capabilities retrieval."""
        mock_diagram.side_effect = Exception("Generator error")

        request = mock_request(method="GET")
        response = await media_api.handle_get_capabilities(request)

        assert response.status == 500


# =============================================================================
# Diagram Validation Tests
# =============================================================================

class TestHandleValidateDiagram:
    """Tests for handle_validate_diagram endpoint."""

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    @patch('media_api.DiagramFormat', MockDiagramFormat)
    @patch('media_api.DiagramSpec')
    async def test_validate_diagram_success(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test successful diagram validation."""
        mock_generator.return_value = MockDiagramGenerator()

        request = mock_request(json_data={
            "format": "mermaid",
            "code": "graph LR\n  A --> B"
        })
        response = await media_api.handle_validate_diagram(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.DiagramFormat')
    async def test_validate_diagram_invalid_format(self, mock_format, mock_request):
        """Test validation with invalid format."""
        mock_format.side_effect = ValueError("Unknown format")

        request = mock_request(json_data={
            "format": "unknown_format",
            "code": "test"
        })
        response = await media_api.handle_validate_diagram(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    async def test_validate_diagram_error(self, mock_generator, mock_request):
        """Test error handling in validation."""
        mock_generator.side_effect = Exception("Validation error")

        request = mock_request(json_data={
            "format": "mermaid",
            "code": "test"
        })
        response = await media_api.handle_validate_diagram(request)

        assert response.status == 500


# =============================================================================
# Diagram Render Tests
# =============================================================================

class TestHandleRenderDiagram:
    """Tests for handle_render_diagram endpoint."""

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    @patch('media_api.DiagramFormat', MockDiagramFormat)
    @patch('media_api.DiagramSpec')
    async def test_render_diagram_success(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test successful diagram rendering."""
        gen = MockDiagramGenerator()
        mock_generator.return_value = gen

        request = mock_request(json_data={
            "format": "mermaid",
            "code": "graph LR\n  A --> B",
            "outputFormat": "svg"
        })
        response = await media_api.handle_render_diagram(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.DiagramFormat')
    async def test_render_diagram_invalid_format(self, mock_format, mock_request):
        """Test rendering with invalid format."""
        mock_format.side_effect = ValueError("Unknown format")

        request = mock_request(json_data={
            "format": "unknown",
            "code": "test"
        })
        response = await media_api.handle_render_diagram(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    @patch('media_api.DiagramFormat', MockDiagramFormat)
    @patch('media_api.DiagramSpec')
    async def test_render_diagram_failure(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test handling of render failure."""
        gen = MockDiagramGenerator()
        gen.render = AsyncMock(return_value=MockDiagramResult(
            success=False, error="Render failed"
        ))
        mock_generator.return_value = gen

        request = mock_request(json_data={
            "format": "mermaid",
            "code": "fail"
        })
        response = await media_api.handle_render_diagram(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    async def test_render_diagram_error(self, mock_generator, mock_request):
        """Test error handling in rendering."""
        mock_generator.side_effect = Exception("Render error")

        request = mock_request(json_data={
            "format": "mermaid",
            "code": "test"
        })
        response = await media_api.handle_render_diagram(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('media_api.get_diagram_generator')
    @patch('media_api.DiagramFormat', MockDiagramFormat)
    @patch('media_api.DiagramSpec')
    async def test_render_diagram_with_options(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test rendering with all options."""
        gen = MockDiagramGenerator()
        mock_generator.return_value = gen

        request = mock_request(json_data={
            "format": "mermaid",
            "code": "graph LR\n  A --> B",
            "outputFormat": "png",
            "theme": "dark",
            "width": 1200,
            "height": 800
        })
        response = await media_api.handle_render_diagram(request)

        assert response.status == 200


# =============================================================================
# Formula Validation Tests
# =============================================================================

class TestHandleValidateFormula:
    """Tests for handle_validate_formula endpoint."""

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    async def test_validate_formula_success(self, mock_generator, mock_request):
        """Test successful formula validation."""
        mock_generator.return_value = MockFormulaGenerator()

        request = mock_request(json_data={
            "latex": "x^2 + y^2 = z^2"
        })
        response = await media_api.handle_validate_formula(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    async def test_validate_formula_with_errors(self, mock_generator, mock_request):
        """Test validation with errors."""
        mock_generator.return_value = MockFormulaGenerator()

        request = mock_request(json_data={
            "latex": "invalid latex"
        })
        response = await media_api.handle_validate_formula(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    async def test_validate_formula_error(self, mock_generator, mock_request):
        """Test error handling in validation."""
        mock_generator.side_effect = Exception("Validation error")

        request = mock_request(json_data={
            "latex": "test"
        })
        response = await media_api.handle_validate_formula(request)

        assert response.status == 500


# =============================================================================
# Formula Render Tests
# =============================================================================

class TestHandleRenderFormula:
    """Tests for handle_render_formula endpoint."""

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    @patch('media_api.FormulaSpec')
    async def test_render_formula_success(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test successful formula rendering."""
        mock_generator.return_value = MockFormulaGenerator()

        request = mock_request(json_data={
            "latex": "x^2 + y^2 = z^2"
        })
        response = await media_api.handle_render_formula(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    @patch('media_api.FormulaSpec')
    async def test_render_formula_failure(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test handling of render failure."""
        gen = MockFormulaGenerator()
        gen.render = AsyncMock(return_value=MockFormulaResult(
            success=False, error="Render failed"
        ))
        mock_generator.return_value = gen

        request = mock_request(json_data={
            "latex": "fail"
        })
        response = await media_api.handle_render_formula(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    async def test_render_formula_error(self, mock_generator, mock_request):
        """Test error handling in rendering."""
        mock_generator.side_effect = Exception("Render error")

        request = mock_request(json_data={
            "latex": "test"
        })
        response = await media_api.handle_render_formula(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('media_api.get_formula_generator')
    @patch('media_api.FormulaSpec')
    async def test_render_formula_with_options(
        self, mock_spec, mock_generator, mock_request
    ):
        """Test rendering with all options."""
        mock_generator.return_value = MockFormulaGenerator()

        request = mock_request(json_data={
            "latex": "E = mc^2",
            "outputFormat": "png",
            "displayMode": True,
            "fontSize": 24,
            "color": "#FF0000"
        })
        response = await media_api.handle_render_formula(request)

        assert response.status == 200


# =============================================================================
# Map Render Tests
# =============================================================================

class TestHandleRenderMap:
    """Tests for handle_render_map endpoint."""

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle', MockMapStyle)
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_success(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_generator, mock_request
    ):
        """Test successful map rendering."""
        mock_generator.return_value = MockMapGenerator()

        request = mock_request(json_data={
            "title": "Test Map",
            "center": {"latitude": 40.0, "longitude": -74.0},
            "zoom": 10
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle', MockMapStyle)
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_with_markers(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_generator, mock_request
    ):
        """Test rendering map with markers."""
        mock_generator.return_value = MockMapGenerator()

        request = mock_request(json_data={
            "title": "Map with Markers",
            "center": {"latitude": 40.0, "longitude": -74.0},
            "markers": [
                {"latitude": 40.7, "longitude": -74.0, "label": "NYC"},
                {"latitude": 34.0, "longitude": -118.2, "label": "LA", "color": "#FF0000"}
            ]
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle', MockMapStyle)
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_with_routes(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_generator, mock_request
    ):
        """Test rendering map with routes."""
        mock_generator.return_value = MockMapGenerator()

        request = mock_request(json_data={
            "title": "Map with Routes",
            "center": {"latitude": 40.0, "longitude": -74.0},
            "routes": [
                {"points": [[40.7, -74.0], [34.0, -118.2]], "label": "Cross-country"}
            ]
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle', MockMapStyle)
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_with_regions(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_generator, mock_request
    ):
        """Test rendering map with regions."""
        mock_generator.return_value = MockMapGenerator()

        request = mock_request(json_data={
            "title": "Map with Regions",
            "center": {"latitude": 40.0, "longitude": -74.0},
            "regions": [
                {
                    "points": [[40.0, -74.0], [41.0, -74.0], [41.0, -73.0], [40.0, -73.0]],
                    "label": "Northeast",
                    "fillColor": "#00FF00"
                }
            ]
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle', MockMapStyle)
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_failure(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_generator, mock_request
    ):
        """Test handling of render failure."""
        gen = MockMapGenerator()
        gen.render = AsyncMock(return_value=MockMapResult(
            success=False, error="Render failed"
        ))
        mock_generator.return_value = gen

        request = mock_request(json_data={
            "title": "fail",
            "center": {"latitude": 0, "longitude": 0}
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 400

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    async def test_render_map_error(self, mock_generator, mock_request):
        """Test error handling in rendering."""
        mock_generator.side_effect = Exception("Render error")

        request = mock_request(json_data={
            "title": "Test",
            "center": {"latitude": 0, "longitude": 0}
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 500

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle')
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_unknown_style_defaults(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_style, mock_generator, mock_request
    ):
        """Test that unknown style defaults to educational."""
        mock_generator.return_value = MockMapGenerator()
        mock_style.side_effect = ValueError("Unknown style")
        mock_style.EDUCATIONAL = MockMapStyle("educational")

        request = mock_request(json_data={
            "title": "Test Map",
            "center": {"latitude": 0, "longitude": 0},
            "style": "unknown_style"
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 200

    @pytest.mark.asyncio
    @patch('media_api.get_map_generator')
    @patch('media_api.MapStyle', MockMapStyle)
    @patch('media_api.MapSpec')
    @patch('media_api.MapMarker')
    @patch('media_api.MapRoute')
    @patch('media_api.MapRegion')
    async def test_render_map_interactive(
        self, mock_region, mock_route, mock_marker,
        mock_spec, mock_generator, mock_request
    ):
        """Test rendering interactive map."""
        gen = MockMapGenerator()
        result = MockMapResult(success=True)
        result.html_content = "<html>Interactive</html>"
        gen.render = AsyncMock(return_value=result)
        mock_generator.return_value = gen

        request = mock_request(json_data={
            "title": "Interactive Map",
            "center": {"latitude": 0, "longitude": 0},
            "interactive": True
        })
        response = await media_api.handle_render_map(request)

        assert response.status == 200


# =============================================================================
# Map Styles Endpoint Tests
# =============================================================================

class TestHandleGetMapStyles:
    """Tests for handle_get_map_styles endpoint."""

    @pytest.mark.asyncio
    async def test_get_map_styles_success(self, mock_request):
        """Test successful styles retrieval."""
        request = mock_request(method="GET")
        response = await media_api.handle_get_map_styles(request)

        assert response.status == 200
        assert response.content_type == "application/json"


# =============================================================================
# Route Registration Tests
# =============================================================================

class TestRegisterRoutes:
    """Tests for route registration."""

    def test_register_media_routes(self):
        """Test that media routes are registered correctly."""
        app = web.Application()

        media_api.register_media_routes(app)

        route_paths = [r.resource.canonical for r in app.router.routes()]

        assert "/api/media/capabilities" in route_paths
        assert "/api/media/diagrams/validate" in route_paths
        assert "/api/media/diagrams/render" in route_paths
        assert "/api/media/formulas/validate" in route_paths
        assert "/api/media/formulas/render" in route_paths
        assert "/api/media/maps/render" in route_paths
        assert "/api/media/maps/styles" in route_paths
