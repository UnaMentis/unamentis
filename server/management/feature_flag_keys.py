"""
Feature Flag Keys - Management Server

Centralized feature flag key definitions for the management API.
Flag names follow the {category}_{feature} naming convention and must
match what is configured in Unleash.

Categories:
  ops_*       Operational flags (permanent, kill switches)
  service_*   Service-level flags (control subsystem availability)
  feature_*   Feature flags (gradual rollout of new capabilities)
"""

from __future__ import annotations


class FlagKeys:
    """All feature flag keys used by the management server."""

    # ── Operational (permanent, kill switches) ──────────────────────────

    # Block all new session starts (emergency kill switch)
    MAINTENANCE_MODE = "ops_maintenance_mode"
    # Enable detailed logging for debugging
    VERBOSE_LOGGING = "ops_verbose_logging"
    # Control analytics/telemetry collection
    ANALYTICS_ENABLED = "ops_analytics_enabled"
    # Emergency flag when hosting budget is exhausted
    BUDGET_CAP_REACHED = "ops_budget_cap_reached"
    # Kill switch for the curriculum import pipeline
    IMPORT_ENABLED = "ops_import_enabled"
    # Kill switch for AI-powered curriculum reprocessing
    REPROCESSING_ENABLED = "ops_reprocessing_enabled"
    # Kill switch for TTS generation (cost-sensitive)
    TTS_GENERATION_ENABLED = "ops_tts_generation_enabled"
    # Kill switch for media rendering (diagrams, formulas, maps)
    MEDIA_GENERATION_ENABLED = "ops_media_generation_enabled"

    # ── Service-level (control which subsystems are available) ──────────

    # Full two-way LLM conversation
    LLM_INTERACTION = "service_llm_interaction"
    # TTS-based curriculum delivery
    CURRICULUM_DELIVERY = "service_curriculum_delivery"
    # Use self-hosted server (primary)
    SOURCE_DEDICATED_SERVER = "service_source_dedicated_server"
    # Use cloud APIs (fallback)
    SOURCE_CLOUD_APIS = "service_source_cloud_apis"
    # TTS pre-generation and profile system
    TTS_PREGEN = "service_tts_pregen"
    # TTS experimentation lab (dev tool, off by default in prod)
    TTS_LAB = "service_tts_lab"
    # Latency harness and test orchestrator (dev tool)
    LATENCY_TESTING = "service_latency_testing"
    # Knowledge Bowl pack management
    KB_PACKS = "service_kb_packs"
    # Curriculum deployment management
    DEPLOYMENT = "service_deployment"
    # Ollama model management endpoints
    MODEL_MANAGEMENT = "service_model_management"
    # Curriculum collection/list management
    LISTS = "service_lists"
    # FOV context buffer system
    FOV_CONTEXT = "service_fov_context"

    # ── Feature (gradual rollout) ───────────────────────────────────────

    # Plugin/source management for importers
    PLUGIN_SYSTEM = "feature_plugin_system"
    # Specialized training modules (Knowledge Bowl, etc.)
    SPECIALIZED_MODULES = "feature_specialized_modules"
    # Team collaboration features within modules
    TEAM_MODE = "feature_team_mode"
    # Competition simulation features
    COMPETITION_SIM = "feature_competition_sim"


# Default values when Unleash is unavailable.
# Two patterns:
#   - Blocking kill switches (MAINTENANCE_MODE, BUDGET_CAP_REACHED) default OFF
#     so they only activate when explicitly enabled in Unleash.
#   - Enablement/service flags (VERBOSE_LOGGING, ANALYTICS_ENABLED, IMPORT_ENABLED,
#     REPROCESSING_ENABLED, TTS_GENERATION_ENABLED, MEDIA_GENERATION_ENABLED, etc.)
#     default ON so existing functionality is preserved when Unleash is down.
FLAG_DEFAULTS: dict[str, bool] = {
    # Ops: blocking kill switches default OFF, enablement flags default ON
    FlagKeys.MAINTENANCE_MODE: False,
    FlagKeys.VERBOSE_LOGGING: True,
    FlagKeys.ANALYTICS_ENABLED: True,
    FlagKeys.BUDGET_CAP_REACHED: False,
    FlagKeys.IMPORT_ENABLED: True,
    FlagKeys.REPROCESSING_ENABLED: True,
    FlagKeys.TTS_GENERATION_ENABLED: True,
    FlagKeys.MEDIA_GENERATION_ENABLED: True,
    # Service: default ON so everything works without Unleash
    FlagKeys.LLM_INTERACTION: True,
    FlagKeys.CURRICULUM_DELIVERY: True,
    FlagKeys.SOURCE_DEDICATED_SERVER: True,
    FlagKeys.SOURCE_CLOUD_APIS: True,
    FlagKeys.TTS_PREGEN: True,
    FlagKeys.TTS_LAB: False,  # Dev tool, off by default
    FlagKeys.LATENCY_TESTING: False,  # Dev tool, off by default
    FlagKeys.KB_PACKS: True,
    FlagKeys.DEPLOYMENT: True,
    FlagKeys.MODEL_MANAGEMENT: True,
    FlagKeys.LISTS: True,
    FlagKeys.FOV_CONTEXT: True,
    # Feature: default ON
    FlagKeys.PLUGIN_SYSTEM: True,
    FlagKeys.SPECIALIZED_MODULES: True,
    FlagKeys.TEAM_MODE: True,
    FlagKeys.COMPETITION_SIM: True,
}
