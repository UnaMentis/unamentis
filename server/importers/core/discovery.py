"""
Plugin discovery module.

This module provides filesystem-based plugin discovery. Plugins are found
in the plugins/ folder but are NOT automatically enabled. The management
interface is used to enable/disable plugins.

Plugin Discovery Flow:
1. Scan plugins/{sources,parsers,enrichers}/ for .py files
2. Load each module and extract plugin metadata
3. Return list of discovered plugins (not enabled)
4. Plugin Manager UI shows discovered plugins
5. User enables plugins they want to use
6. Enabled plugins are registered with PluginManager
"""

import importlib
import importlib.util
import inspect
import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from types import ModuleType
from typing import Any, Dict, List, Optional, Type

logger = logging.getLogger(__name__)


def _extract_module_metadata(module: ModuleType) -> Dict[str, Optional[str]]:
    """
    Extract metadata from a Python module.

    Looks for standard module-level attributes and falls back to parsing
    the module docstring for common patterns.

    Args:
        module: The loaded Python module

    Returns:
        Dictionary with keys: version, author, url, email, license
    """
    metadata: Dict[str, Optional[str]] = {
        "version": None,
        "author": None,
        "url": None,
        "email": None,
        "license": None,
    }

    # Extract from module attributes (standard Python convention)
    if hasattr(module, "__version__"):
        metadata["version"] = str(module.__version__)
    if hasattr(module, "__author__"):
        metadata["author"] = str(module.__author__)
    if hasattr(module, "__url__"):
        metadata["url"] = str(module.__url__)
    if hasattr(module, "__email__"):
        metadata["email"] = str(module.__email__)
    if hasattr(module, "__license__"):
        metadata["license"] = str(module.__license__)

    # Fall back to parsing docstring if attributes not defined
    docstring = module.__doc__
    if docstring:
        # Extract Reference URL (common pattern in our plugins)
        if metadata["url"] is None:
            ref_match = re.search(r"Reference:\s*(https?://[^\s]+)", docstring)
            if ref_match:
                metadata["url"] = ref_match.group(1)

        # Extract Author from docstring (e.g., "Author: John Doe")
        if metadata["author"] is None:
            author_match = re.search(r"Author:\s*(.+?)(?:\n|$)", docstring)
            if author_match:
                metadata["author"] = author_match.group(1).strip()

        # Extract Version from docstring (e.g., "Version: 1.2.0")
        if metadata["version"] is None:
            version_match = re.search(r"Version:\s*([\d.]+)", docstring)
            if version_match:
                metadata["version"] = version_match.group(1)

    return metadata

# Plugin types supported
PLUGIN_TYPES = ["sources", "parsers", "enrichers"]


@dataclass
class DiscoveredPlugin:
    """Metadata for a discovered plugin."""

    plugin_id: str
    name: str
    description: str
    version: str
    plugin_type: str  # "sources", "parsers", "enrichers"
    file_path: str
    module_name: str
    class_name: str
    license_type: Optional[str] = None
    features: List[str] = field(default_factory=list)
    author: Optional[str] = None
    url: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "plugin_id": self.plugin_id,
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "plugin_type": self.plugin_type,
            "file_path": self.file_path,
            "module_name": self.module_name,
            "class_name": self.class_name,
            "license_type": self.license_type,
            "features": self.features,
            "author": self.author,
            "url": self.url,
        }


@dataclass
class PluginState:
    """Persistent state for a plugin."""

    enabled: bool = False
    priority: int = 100
    settings: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "enabled": self.enabled,
            "priority": self.priority,
            "settings": self.settings,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PluginState":
        """Create from dictionary."""
        return cls(
            enabled=data.get("enabled", False),
            priority=data.get("priority", 100),
            settings=data.get("settings", {}),
        )


class PluginDiscovery:
    """
    Discovers plugins from the plugins/ folder.

    Plugins are discovered but NOT automatically enabled. The user must
    enable plugins through the Plugin Manager interface.
    """

    def __init__(self, plugins_dir: Optional[Path] = None, state_file: Optional[Path] = None):
        """
        Initialize plugin discovery.

        Args:
            plugins_dir: Path to plugins folder (default: importers/plugins/)
            state_file: Path to plugin state file (default: management/data/plugins.json)
        """
        if plugins_dir is None:
            plugins_dir = Path(__file__).parent.parent / "plugins"
        if state_file is None:
            state_file = Path(__file__).parent.parent.parent / "management" / "data" / "plugins.json"

        self.plugins_dir = plugins_dir
        self.state_file = state_file
        self._discovered: Dict[str, DiscoveredPlugin] = {}
        self._states: Dict[str, PluginState] = {}
        self._loaded_classes: Dict[str, Type] = {}

    def discover_all(self) -> List[DiscoveredPlugin]:
        """
        Discover all plugins in the plugins/ folder.

        This scans for plugins but does NOT enable them.

        Returns:
            List of discovered plugins with metadata
        """
        self._discovered.clear()

        for plugin_type in PLUGIN_TYPES:
            type_dir = self.plugins_dir / plugin_type
            if not type_dir.exists():
                logger.debug(f"Plugin directory not found: {type_dir}")
                continue

            for py_file in type_dir.glob("*.py"):
                if py_file.name.startswith("_"):
                    continue

                try:
                    plugin = self._discover_plugin(py_file, plugin_type)
                    if plugin:
                        self._discovered[plugin.plugin_id] = plugin
                        logger.info(f"Discovered plugin: {plugin.plugin_id} ({plugin.name})")
                except Exception as e:
                    logger.warning(f"Failed to discover plugin from {py_file}: {e}")

        logger.info(f"Plugin discovery complete: {len(self._discovered)} plugins found")
        return list(self._discovered.values())

    def _discover_plugin(self, file_path: Path, plugin_type: str) -> Optional[DiscoveredPlugin]:
        """
        Discover a single plugin from a Python file.

        Args:
            file_path: Path to the plugin Python file
            plugin_type: Type of plugin (sources, parsers, enrichers)

        Returns:
            DiscoveredPlugin if valid, None otherwise
        """
        module_name = f"importers.plugins.{plugin_type}.{file_path.stem}"

        # Load the module
        spec = importlib.util.spec_from_file_location(module_name, file_path)
        if spec is None or spec.loader is None:
            logger.debug(f"Could not load spec for {file_path}")
            return None

        module = importlib.util.module_from_spec(spec)

        try:
            spec.loader.exec_module(module)
        except Exception as e:
            logger.warning(f"Error loading module {file_path}: {e}")
            return None

        # Find the handler/plugin class
        handler_class = None
        class_name = None

        for name, obj in inspect.getmembers(module, inspect.isclass):
            # Look for classes that inherit from CurriculumSourceHandler or BaseImporterPlugin
            if name.endswith("Handler") or name.endswith("Plugin"):
                # Check if it's defined in this module (not imported)
                if obj.__module__ == module_name:
                    handler_class = obj
                    class_name = name
                    break

        if handler_class is None:
            logger.debug(f"No handler/plugin class found in {file_path}")
            return None

        # Extract metadata from the handler and module
        try:
            instance = handler_class()
            self._loaded_classes[instance.source_id] = handler_class

            # Get source info for metadata
            source_info = instance.source_info
            default_license = instance.default_license

            # Extract module-level metadata (version, author, url, etc.)
            module_metadata = _extract_module_metadata(module)

            # Determine version: module attribute > docstring > default
            version = module_metadata["version"] or "1.0.0"

            # Determine author: module attribute > docstring > None
            author = module_metadata["author"]

            # Determine URL: source_info.base_url > module attribute > docstring
            url = None
            if hasattr(source_info, "base_url") and source_info.base_url:
                url = source_info.base_url
            elif module_metadata["url"]:
                url = module_metadata["url"]

            return DiscoveredPlugin(
                plugin_id=instance.source_id,
                name=source_info.name,
                description=source_info.description,
                version=version,
                plugin_type=plugin_type,
                file_path=str(file_path),
                module_name=module_name,
                class_name=class_name,
                license_type=default_license.type if default_license else None,
                features=source_info.features if hasattr(source_info, "features") else [],
                author=author,
                url=url,
            )
        except Exception as e:
            logger.warning(f"Error extracting metadata from {file_path}: {e}")
            return None

    def load_state(self) -> Dict[str, PluginState]:
        """
        Load plugin state from persistent storage.

        Returns:
            Dictionary of plugin_id -> PluginState
        """
        self._states.clear()

        if not self.state_file.exists():
            logger.info("No plugin state file found, all plugins disabled by default")
            return {}

        try:
            with open(self.state_file, "r") as f:
                data = json.load(f)

            for plugin_id, state_data in data.items():
                self._states[plugin_id] = PluginState.from_dict(state_data)

            logger.info(f"Loaded state for {len(self._states)} plugins")
            return self._states.copy()
        except Exception as e:
            logger.error(f"Error loading plugin state: {e}")
            return {}

    def save_state(self) -> bool:
        """
        Save plugin state to persistent storage.

        Returns:
            True if successful
        """
        try:
            # Ensure directory exists
            self.state_file.parent.mkdir(parents=True, exist_ok=True)

            data = {plugin_id: state.to_dict() for plugin_id, state in self._states.items()}

            with open(self.state_file, "w") as f:
                json.dump(data, f, indent=2)

            logger.info(f"Saved state for {len(self._states)} plugins")
            return True
        except Exception as e:
            logger.error(f"Error saving plugin state: {e}")
            return False

    def is_enabled(self, plugin_id: str) -> bool:
        """Check if a plugin is enabled."""
        state = self._states.get(plugin_id)
        return state.enabled if state else False

    def enable_plugin(self, plugin_id: str) -> bool:
        """
        Enable a plugin.

        Args:
            plugin_id: The plugin ID to enable

        Returns:
            True if successful
        """
        if plugin_id not in self._discovered:
            logger.warning(f"Cannot enable unknown plugin: {plugin_id}")
            return False

        if plugin_id not in self._states:
            self._states[plugin_id] = PluginState()

        self._states[plugin_id].enabled = True
        self.save_state()
        logger.info(f"Enabled plugin: {plugin_id}")
        return True

    def disable_plugin(self, plugin_id: str) -> bool:
        """
        Disable a plugin.

        Args:
            plugin_id: The plugin ID to disable

        Returns:
            True if successful
        """
        if plugin_id not in self._states:
            self._states[plugin_id] = PluginState()

        self._states[plugin_id].enabled = False
        self.save_state()
        logger.info(f"Disabled plugin: {plugin_id}")
        return True

    def get_enabled_plugins(self) -> List[DiscoveredPlugin]:
        """Get list of enabled plugins."""
        return [plugin for plugin in self._discovered.values() if self.is_enabled(plugin.plugin_id)]

    def get_disabled_plugins(self) -> List[DiscoveredPlugin]:
        """Get list of disabled plugins."""
        return [plugin for plugin in self._discovered.values() if not self.is_enabled(plugin.plugin_id)]

    def get_plugin_class(self, plugin_id: str) -> Optional[Type]:
        """
        Get the handler class for a plugin.

        Args:
            plugin_id: The plugin ID

        Returns:
            The handler class or None if not found
        """
        return self._loaded_classes.get(plugin_id)

    def has_state_file(self) -> bool:
        """Check if plugin state file exists (for first-run detection)."""
        return self.state_file.exists()

    def initialize_state(self, enabled_plugins: List[str]) -> bool:
        """
        Initialize plugin state with specified plugins enabled.

        Used by first-run wizard to set initial state.

        Args:
            enabled_plugins: List of plugin IDs to enable

        Returns:
            True if successful
        """
        self._states.clear()

        for plugin_id in self._discovered:
            self._states[plugin_id] = PluginState(enabled=plugin_id in enabled_plugins)

        return self.save_state()


# Global discovery instance
_discovery: Optional[PluginDiscovery] = None


def get_plugin_discovery() -> PluginDiscovery:
    """Get the global plugin discovery instance."""
    global _discovery
    if _discovery is None:
        _discovery = PluginDiscovery()
    return _discovery


def reset_plugin_discovery() -> None:
    """Reset the global plugin discovery instance (for testing)."""
    global _discovery
    _discovery = None
