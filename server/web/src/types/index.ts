// UnaMentis Management Console Types

export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'DEBUG' | 'INFO' | 'WARNING' | 'ERROR' | 'CRITICAL';
  label: string;
  message: string;
  file?: string;
  function?: string;
  line?: number;
  metadata?: Record<string, unknown>;
  client_id: string;
  client_name: string;
  received_at: number;
}

export interface MetricsSnapshot {
  id: string;
  client_id: string;
  client_name: string;
  timestamp: string;
  received_at: number;
  session_duration: number;
  turns_total: number;
  interruptions: number;
  // Latencies (in ms)
  stt_latency_median: number;
  stt_latency_p99: number;
  llm_ttft_median: number;
  llm_ttft_p99: number;
  tts_ttfb_median: number;
  tts_ttfb_p99: number;
  e2e_latency_median: number;
  e2e_latency_p99: number;
  // Costs
  stt_cost: number;
  tts_cost: number;
  llm_cost: number;
  total_cost: number;
  // Device stats
  thermal_throttle_events: number;
  network_degradations: number;
}

export interface RemoteClient {
  id: string;
  name: string;
  device_model: string;
  os_version: string;
  app_version: string;
  first_seen: number;
  last_seen: number;
  ip_address: string;
  status: 'online' | 'idle' | 'offline';
  current_session_id?: string;
  total_sessions: number;
  total_logs: number;
  config?: Record<string, unknown>;
}

export interface ServerStatus {
  id: string;
  name: string;
  type: 'ollama' | 'whisper' | 'piper' | 'vibevoice' | 'unamentisGateway' | 'custom';
  url: string;
  port: number;
  status: 'unknown' | 'healthy' | 'degraded' | 'unhealthy';
  last_check: number;
  response_time_ms: number;
  capabilities?: Record<string, unknown>;
  models: string[];
  error_message?: string;
}

export interface ModelInfo {
  id: string;
  name: string;
  type: 'llm' | 'stt' | 'tts';
  server_id: string;
  server_name: string;
  status: 'available' | 'loaded' | 'loading' | 'unavailable';
  size_bytes?: number;
  size_gb?: number;
  parameters?: string;
  parameter_size?: string;
  quantization?: string;
  family?: string;
  context_window?: number;
  context_window_formatted?: string;
  vram_bytes?: number;
  vram_gb?: number;
}

// Model Management Types
export interface ModelLoadRequest {
  keep_alive?: string;
}

export interface ModelLoadResponse {
  status: 'ok' | 'error';
  model: string;
  vram_bytes?: number;
  vram_gb?: number;
  load_time_ms?: number;
  message: string;
  error?: string;
}

export interface ModelUnloadResponse {
  status: 'ok' | 'error';
  model: string;
  freed_vram_bytes?: number;
  freed_vram_gb?: number;
  message: string;
  error?: string;
}

export interface ModelPullProgress {
  status: string;
  digest?: string;
  completed: number;
  total: number;
  model?: string;
  error?: string;
}

export interface ModelDeleteResponse {
  status: 'ok' | 'error';
  model: string;
  message?: string;
  error?: string;
}

// Model Configuration Types
export interface ServiceModelConfig {
  llm: {
    default_model: string | null;
    fallback_model: string | null;
  };
  tts: {
    default_provider: 'vibevoice' | 'piper';
    default_voice: string;
  };
  stt: {
    default_model: string;
  };
}

export interface ModelConfig {
  services: ServiceModelConfig;
}

export interface ModelConfigResponse {
  status: 'ok' | 'error';
  config: ModelConfig;
  error?: string;
}

export interface SaveModelConfigResponse {
  status: 'ok' | 'error';
  config: ModelConfig;
  message?: string;
  error?: string;
}

// Model Parameters Types
export interface ModelParameterDef {
  value: number;
  min: number;
  max: number;
  step?: number;
  description: string;
}

export interface ModelParameters {
  num_ctx: ModelParameterDef;
  temperature: ModelParameterDef;
  top_p: ModelParameterDef;
  top_k: ModelParameterDef;
  repeat_penalty: ModelParameterDef;
  seed: ModelParameterDef;
}

export interface ModelParametersResponse {
  status: 'ok' | 'error';
  model: string;
  parameters: ModelParameters;
  error?: string;
}

export interface SaveModelParametersResponse {
  status: 'ok' | 'error';
  model: string;
  parameters: Record<string, number>;
  message?: string;
  error?: string;
}

export interface DashboardStats {
  uptime_seconds: number;
  total_logs: number;
  total_metrics: number;
  errors_count: number;
  warnings_count: number;
  logs_last_hour: number;
  sessions_last_hour: number;
  online_clients: number;
  total_clients: number;
  healthy_servers: number;
  total_servers: number;
  avg_e2e_latency: number;
  avg_llm_ttft: number;
  websocket_connections: number;
}

// API Response types
export interface LogsResponse {
  logs: LogEntry[];
  total: number;
  limit: number;
  offset: number;
}

export interface MetricsResponse {
  metrics: MetricsSnapshot[];
  aggregates: {
    avg_e2e_latency: number;
    avg_llm_ttft: number;
    avg_stt_latency: number;
    avg_tts_ttfb: number;
    total_cost: number;
    total_sessions: number;
    total_turns: number;
  };
}

export interface ClientsResponse {
  clients: RemoteClient[];
  total: number;
  online: number;
  idle: number;
  offline: number;
}

export interface ServersResponse {
  servers: ServerStatus[];
  total: number;
  healthy: number;
  degraded: number;
  unhealthy: number;
}

export interface ModelsResponse {
  models: ModelInfo[];
  total: number;
  by_type: {
    llm: number;
    stt: number;
    tts: number;
  };
}

// System Health & Resource Monitoring Types
export interface PowerMetrics {
  current_battery_draw_w: number;
  avg_battery_draw_w: number;
  battery_percent: number;
  battery_charging: boolean;
  estimated_service_power_w: number;
}

export interface ThermalMetrics {
  pressure: 'nominal' | 'fair' | 'serious' | 'critical';
  pressure_level: number;
  cpu_temp_c: number;
  gpu_temp_c: number;
  fan_speed_rpm: number;
}

export interface CpuMetrics {
  total_percent: number;
  by_service: Record<string, number>;
}

export interface ServiceResourceMetrics {
  service_id: string;
  service_name: string;
  status: string;
  cpu_percent: number;
  memory_mb: number;
  gpu_memory_mb: number;
  last_request_time: number | null;
  request_count_5m: number;
  model_loaded: boolean;
  estimated_power_w: number;
}

export interface SystemMetricsSummary {
  timestamp: number;
  power: PowerMetrics;
  thermal: ThermalMetrics;
  cpu: CpuMetrics;
  services: Record<string, ServiceResourceMetrics>;
  history_minutes: number;
}

export interface IdleStatus {
  enabled: boolean;
  current_state: 'active' | 'warm' | 'cool' | 'cold' | 'dormant';
  current_mode: string;
  seconds_idle: number;
  last_activity_type: string;
  last_activity_time: number;
  thresholds: {
    warm: number;
    cool: number;
    cold: number;
    dormant: number;
  };
  keep_awake_remaining: number;
  next_state_in: {
    state: string;
    seconds_remaining: number;
  } | null;
}

export interface PowerMode {
  name: string;
  description: string;
  thresholds: {
    warm: number;
    cool: number;
    cold: number;
    dormant: number;
  };
  enabled: boolean;
  is_builtin?: boolean;
  is_custom?: boolean;
}

export interface PowerModeWithId extends PowerMode {
  id: string;
}

export interface PowerModesResponse {
  modes: Record<string, PowerMode>;
  current: string;
}

export interface CreateProfileRequest {
  id: string;
  name: string;
  description?: string;
  thresholds: {
    warm: number;
    cool: number;
    cold: number;
    dormant: number;
  };
  enabled?: boolean;
}

export interface UpdateProfileRequest {
  name?: string;
  description?: string;
  thresholds?: Partial<{
    warm: number;
    cool: number;
    cold: number;
    dormant: number;
  }>;
  enabled?: boolean;
}

export interface ProfileResponse {
  status: string;
  profile: PowerModeWithId;
}

export interface IdleTransition {
  timestamp: number;
  from_state: string;
  to_state: string;
  idle_seconds: number;
  trigger: string;
}

export interface HourlyMetrics {
  hour: string;
  avg_battery_draw_w: number;
  max_battery_draw_w: number;
  min_battery_percent: number;
  max_battery_percent: number;
  avg_thermal_level: number;
  max_thermal_level: number;
  avg_cpu_temp_c: number;
  max_cpu_temp_c: number;
  avg_cpu_percent: number;
  max_cpu_percent: number;
  service_cpu_avg: Record<string, number>;
  service_cpu_max: Record<string, number>;
  total_requests: number;
  total_inferences: number;
  idle_state_seconds: Record<string, number>;
  sample_count: number;
}

export interface DailyMetrics {
  date: string;
  avg_battery_draw_w: number;
  max_battery_draw_w: number;
  min_battery_percent: number;
  battery_drain_percent: number;
  avg_thermal_level: number;
  max_thermal_level: number;
  thermal_events_count: number;
  avg_cpu_temp_c: number;
  max_cpu_temp_c: number;
  avg_cpu_percent: number;
  max_cpu_percent: number;
  service_cpu_avg: Record<string, number>;
  total_requests: number;
  total_inferences: number;
  active_hours: number;
  idle_state_hours: Record<string, number>;
  hours_aggregated: number;
}

export interface MetricsHistorySummary {
  today: DailyMetrics | null;
  yesterday: DailyMetrics | null;
  this_week: {
    days_recorded: number;
    avg_cpu_percent: number;
    total_requests: number;
    max_thermal_level: number;
  } | null;
  total_days_tracked: number;
  total_hours_tracked: number;
  oldest_record: string | null;
}

// =============================================================================
// Curriculum & Visual Asset Types
// =============================================================================
// NOTE: These types support the Curriculum Studio in the UnaMentis Server interface.
// Curriculum data is fetched from the Management API (port 8766) and displayed here.
// The UnaMentis Server provides a unified interface for both DevOps and content management.

/** Types of visual assets supported in UMCF */
export type VisualAssetType =
  | 'image'
  | 'diagram'
  | 'equation'
  | 'chart'
  | 'slideImage'
  | 'slideDeck'
  | 'generated';

/** How visual assets are displayed during playback */
export type VisualDisplayMode =
  | 'persistent' // Stays on screen for entire segment range
  | 'highlight' // Appears prominently, then fades to thumbnail
  | 'popup' // Dismissible overlay
  | 'inline'; // Embedded in transcript text flow

/** Image dimensions */
export interface Dimensions {
  width: number;
  height: number;
}

/** Segment timing for embedded media */
export interface SegmentTiming {
  startSegment: number;
  endSegment: number;
  displayMode: VisualDisplayMode;
}

/** Visual asset definition in UMCF format */
export interface VisualAsset {
  id: string;
  type: VisualAssetType;
  url?: string;
  localPath?: string;
  title?: string;
  alt: string; // Required for accessibility
  caption?: string;
  mimeType?: string;
  dimensions?: Dimensions;
  segmentTiming?: SegmentTiming;
  latex?: string; // For equation type
  audioDescription?: string; // Extended accessibility description
  keywords?: string[]; // For reference assets (search matching)
  description?: string; // For reference assets
}

/** Media collection for a topic */
export interface MediaCollection {
  embedded?: VisualAsset[];
  reference?: VisualAsset[];
}

/** Transcript segment */
export interface TranscriptSegment {
  id: string;
  type: 'introduction' | 'lecture' | 'explanation' | 'summary' | 'checkpoint' | 'example';
  content: string;
  speakingNotes?: {
    emotionalTone?: string;
    pace?: string;
    emphasis?: string[];
  };
  checkpoint?: {
    type: string;
    prompt: string;
    expectedResponsePatterns?: string[];
    fallbackBehavior?: string;
  };
  stoppingPoint?: {
    type: string;
    promptForContinue?: boolean;
    suggestedPrompt?: string;
  };
}

/** Topic transcript */
export interface TopicTranscript {
  segments: TranscriptSegment[];
  voiceProfile?: {
    tone: string;
    pace: string;
  };
}

/** Topic example */
export interface TopicExample {
  id: string;
  type: 'analogy' | 'historical' | 'practical' | 'visual';
  title: string;
  spokenContent: string;
}

/** Assessment choice */
export interface AssessmentChoice {
  id: string;
  text: string;
  correct: boolean;
  feedback?: string;
}

/** Topic assessment */
export interface TopicAssessment {
  id: { catalog?: string; value: string };
  type: 'choice' | 'shortAnswer' | 'oral';
  prompt: string;
  spokenPrompt?: string;
  choices?: AssessmentChoice[];
  difficulty?: number;
  objectivesAssessed?: string[];
}

/** Misconception correction */
export interface Misconception {
  id: string;
  misconception: string;
  triggerPhrases: string[];
  correction: string;
  spokenCorrection: string;
  severity: 'minor' | 'moderate' | 'major';
}

/** Learning objective */
export interface LearningObjective {
  id: { value: string };
  statement: string;
  bloomsLevel: 'remember' | 'understand' | 'apply' | 'analyze' | 'evaluate' | 'create';
}

/** Topic time estimates */
export interface TimeEstimates {
  overview?: string;
  introductory?: string;
  intermediate?: string;
  advanced?: string;
}

/** Topic prerequisite */
export interface TopicPrerequisite {
  nodeId: string;
  required: boolean;
}

/** Topic within a curriculum */
export interface CurriculumTopic {
  id: { value: string };
  title: string;
  type: 'topic';
  orderIndex: number;
  description?: string;
  prerequisites?: TopicPrerequisite[];
  timeEstimates?: TimeEstimates;
  transcript?: TopicTranscript;
  examples?: TopicExample[];
  assessments?: TopicAssessment[];
  misconceptions?: Misconception[];
  media?: MediaCollection;
}

/** Curriculum tutoring configuration */
export interface TutoringConfig {
  contentDepth: 'overview' | 'introductory' | 'intermediate' | 'advanced' | 'graduate' | 'research';
  adaptiveDepth: boolean;
  interactionMode: 'socratic' | 'lecture' | 'mixed';
  allowTangents: boolean;
  checkpointFrequency: 'low' | 'medium' | 'high';
}

/** Curriculum content node */
export interface CurriculumContent {
  id: { value: string };
  title: string;
  type: 'curriculum';
  description?: string;
  learningObjectives?: LearningObjective[];
  tutoringConfig?: TutoringConfig;
  children?: CurriculumTopic[];
}

/** Curriculum version info */
export interface CurriculumVersion {
  number: string;
  date: string;
  changelog?: string;
}

/** Curriculum lifecycle info */
export interface CurriculumLifecycle {
  status: 'draft' | 'review' | 'final' | 'deprecated';
  contributors?: Array<{
    name: string;
    role: string;
    organization?: string;
  }>;
  created?: string;
}

/** Curriculum metadata */
export interface CurriculumMetadata {
  language: string;
  keywords?: string[];
  structure?: string;
  aggregationLevel?: number;
}

/** Curriculum educational info */
export interface CurriculumEducational {
  interactivityType?: string;
  interactivityLevel?: string;
  learningResourceType?: string[];
  intendedEndUserRole?: string[];
  context?: string[];
  typicalAgeRange?: string;
  difficulty?: string;
  typicalLearningTime?: string;
  educationalAlignment?: Array<{
    alignmentType: string;
    educationalFramework: string;
    targetName: string;
    targetDescription?: string;
  }>;
  audienceProfile?: {
    educationLevel?: string;
    gradeLevel?: string;
    prerequisites?: Array<{
      description: string;
      required: boolean;
    }>;
  };
}

/** Curriculum rights info */
export interface CurriculumRights {
  cost: boolean;
  license: {
    type: string;
    url?: string;
  };
  holder?: string;
}

/** Glossary term */
export interface GlossaryTerm {
  id: string;
  term: string;
  pronunciation?: string;
  definition: string;
  spokenDefinition?: string;
  simpleDefinition?: string;
  etymology?: string;
  relatedTerms?: string[];
}

/** Full UMCF curriculum document */
export interface UMCFDocument {
  umcf: string; // Version string
  id: { catalog?: string; value: string };
  title: string;
  description?: string;
  version?: CurriculumVersion;
  lifecycle?: CurriculumLifecycle;
  metadata?: CurriculumMetadata;
  educational?: CurriculumEducational;
  rights?: CurriculumRights;
  glossary?: { terms: GlossaryTerm[] };
  content?: CurriculumContent[];
  extensions?: Record<string, unknown>;
  sourceProvenance?: {
    originType?: string;
    primarySources?: Array<{
      title: string;
      type: string;
      authors?: string[];
      url?: string;
      publisher?: string;
      publicationDate?: string;
      relationshipToContent?: string;
      notes?: string;
    }>;
    aiGenerationMetadata?: {
      model: string;
      generationDate: string;
      prompt?: string;
      humanReviewed: boolean;
    };
  };
}

/** Curriculum summary for list views */
export interface CurriculumSummary {
  id: string;
  title: string;
  description: string;
  version?: string;
  status?: string;
  topicCount: number;
  totalDuration?: string;
  difficulty?: string;
  gradeLevel?: string;
  keywords?: string[];
  hasVisualAssets: boolean;
  visualAssetCount: number;
}

/** Curriculum detail for editor */
export interface CurriculumDetail extends CurriculumSummary {
  document: UMCFDocument;
  topics: CurriculumTopic[];
}

/** API response for curriculum list */
export interface CurriculaResponse {
  curricula: CurriculumSummary[];
  total: number;
}

/** API response for curriculum detail */
export interface CurriculumDetailResponse {
  curriculum: CurriculumDetail;
}

/** Visual asset upload request */
export interface AssetUploadRequest {
  file: File;
  topicId: string;
  type: VisualAssetType;
  title?: string;
  alt: string;
  caption?: string;
  displayMode: VisualDisplayMode;
  startSegment?: number;
  endSegment?: number;
  isReference?: boolean;
  keywords?: string[];
}

/** Visual asset upload response */
export interface AssetUploadResponse {
  status: 'success' | 'error';
  asset?: VisualAsset;
  url?: string;
  error?: string;
}

/** Curriculum save request */
export interface CurriculumSaveRequest {
  curriculumId: string;
  document: UMCFDocument;
}

/** Curriculum save response */
export interface CurriculumSaveResponse {
  status: 'success' | 'error';
  error?: string;
  savedAt?: string;
}

// =============================================================================
// Curriculum Import System Types (Source Browser)
// =============================================================================

/** License information for a curriculum source */
export interface LicenseInfo {
  type: string;
  name: string;
  url?: string;
  requiresAttribution: boolean;
  allowsCommercialUse: boolean;
  allowsDerivatives: boolean;
  shareAlike: boolean;
}

/** Curriculum source (e.g., MIT OCW, Stanford SEE) */
export interface CurriculumSource {
  id: string;
  name: string;
  description: string;
  provider: string;
  website: string;
  logo?: string;
  license: LicenseInfo;
  contentTypes: string[];
  subjects: string[];
  courseCount: number;
  isActive: boolean;
  lastUpdated?: string;
}

/** Course catalog entry (summary for listing) */
export interface CourseCatalogEntry {
  id: string;
  title: string;
  description: string;
  instructor?: string;
  institution: string;
  subject: string;
  level: string;
  language: string;
  thumbnail?: string;
  url: string;
  license: LicenseInfo;
  contentTypes: string[];
  estimatedDuration?: string;
  lastUpdated?: string;
}

/** Detailed course information */
export interface CourseDetail extends CourseCatalogEntry {
  longDescription?: string;
  syllabus?: string;
  prerequisites?: string[];
  learningOutcomes?: string[];
  topics?: string[];
  contentSummary: {
    lectureCount: number;
    hasTranscripts: boolean;
    hasLectureNotes: boolean;
    hasAssignments: boolean;
    hasExams: boolean;
    hasVideos: boolean;
    hasSolutions: boolean;
  };
  downloads?: {
    type: string;
    format: string;
    size?: number;
    url: string;
  }[];
}

/** Import configuration options */
export interface ImportConfig {
  sourceId: string;
  courseId: string;
  outputName: string;
  includeTranscripts: boolean;
  includeLectureNotes: boolean;
  includeAssignments: boolean;
  includeExams: boolean;
  includeVideos: boolean;
  generateObjectives: boolean;
  createCheckpoints: boolean;
  generateSpokenText: boolean;
  buildKnowledgeGraph: boolean;
  generatePracticeProblems: boolean;
}

/** Import job status */
export type ImportStatus =
  | 'queued'
  | 'downloading'
  | 'validating'
  | 'extracting'
  | 'enriching'
  | 'generating'
  | 'storing'
  | 'completed'
  | 'failed'
  | 'cancelled';

/** Import progress information */
export interface ImportProgress {
  jobId: string;
  status: ImportStatus;
  sourceId: string;
  courseId: string;
  courseName: string;
  currentStage: string;
  stageProgress: number;
  overallProgress: number;
  startedAt: string;
  updatedAt: string;
  completedAt?: string;
  error?: string;
  warnings: string[];
  stats: {
    filesDownloaded: number;
    filesProcessed: number;
    topicsCreated: number;
    objectivesGenerated: number;
    assessmentsGenerated: number;
  };
}

/** API response for sources list */
export interface SourcesResponse {
  success: boolean;
  sources: CurriculumSource[];
  error?: string;
}

/** API response for course catalog */
export interface CourseCatalogResponse {
  success: boolean;
  courses: CourseCatalogEntry[];
  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
  filters?: {
    subjects: string[];
    levels: string[];
    features: string[];
  };
  error?: string;
}

/** API response for course detail */
export interface CourseDetailResponse {
  success: boolean;
  course: CourseDetail;
  canImport: boolean;
  licenseWarnings: string[];
  attribution?: string;
  error?: string;
}

/** API response for starting import */
export interface StartImportResponse {
  success: boolean;
  jobId: string;
  status: ImportStatus;
  error?: string;
  licenseRestriction?: boolean;
}

/** API response for import progress */
export interface ImportProgressResponse {
  success: boolean;
  progress: ImportProgress;
  error?: string;
}

/** API response for import jobs list */
export interface ImportJobsResponse {
  success: boolean;
  jobs: ImportProgress[];
  error?: string;
}

// =============================================================================
// Generative Media Types (Diagrams, Formulas, Maps)
// =============================================================================

/** Diagram source format */
export type DiagramFormat = 'mermaid' | 'graphviz' | 'plantuml' | 'd2' | 'svg-raw';

/** Diagram render method used by server */
export type DiagramRenderMethod =
  | 'mermaid_cli'
  | 'graphviz'
  | 'plantuml'
  | 'd2'
  | 'passthrough'
  | 'placeholder'
  | 'failed';

/** Request to validate diagram syntax */
export interface DiagramValidateRequest {
  format: DiagramFormat;
  code: string;
}

/** Response from diagram validation */
export interface DiagramValidateResponse {
  success: boolean;
  valid: boolean;
  errors: string[];
  error?: string;
}

/** Request to render a diagram */
export interface DiagramRenderRequest {
  format: DiagramFormat;
  code: string;
  outputFormat?: 'svg' | 'png';
  theme?: string;
  width?: number;
  height?: number;
}

/** Response from diagram rendering */
export interface DiagramRenderResponse {
  success: boolean;
  data?: string; // base64 encoded
  mimeType?: string;
  width?: number;
  height?: number;
  renderMethod?: DiagramRenderMethod;
  error?: string;
  validationErrors?: string[];
}

/** Formula render method used by server */
export type FormulaRenderMethod = 'katex' | 'latex' | 'placeholder' | 'failed';

/** Request to validate LaTeX formula */
export interface FormulaValidateRequest {
  latex: string;
}

/** Response from formula validation */
export interface FormulaValidateResponse {
  success: boolean;
  valid: boolean;
  errors: string[];
  warnings: string[];
  error?: string;
}

/** Request to render a formula */
export interface FormulaRenderRequest {
  latex: string;
  outputFormat?: 'svg' | 'png';
  displayMode?: boolean;
  fontSize?: number;
  color?: string;
}

/** Response from formula rendering */
export interface FormulaRenderResponse {
  success: boolean;
  data?: string; // base64 encoded
  mimeType?: string;
  width?: number;
  height?: number;
  renderMethod?: FormulaRenderMethod;
  warnings?: string[];
  error?: string;
  validationErrors?: string[];
}

/** Map style options */
export type MapStyleOption =
  | 'standard'
  | 'historical'
  | 'physical'
  | 'satellite'
  | 'minimal'
  | 'educational';

/** Map render method used by server */
export type MapRenderMethod = 'cartopy' | 'folium' | 'static_tiles' | 'placeholder' | 'failed';

/** Map marker definition */
export interface MapMarkerSpec {
  latitude: number;
  longitude: number;
  label: string;
  icon?: string;
  color?: string;
  popup?: string;
}

/** Map route definition */
export interface MapRouteSpec {
  points: [number, number][]; // [lat, lon] pairs
  label: string;
  color?: string;
  width?: number;
  style?: 'solid' | 'dashed' | 'dotted';
}

/** Map region definition */
export interface MapRegionSpec {
  points: [number, number][]; // polygon vertices [lat, lon]
  label: string;
  fillColor?: string;
  fillOpacity?: number;
  borderColor?: string;
  borderWidth?: number;
}

/** Request to render a map */
export interface MapRenderRequest {
  title?: string;
  center: {
    latitude: number;
    longitude: number;
  };
  zoom?: number;
  style?: MapStyleOption;
  width?: number;
  height?: number;
  outputFormat?: 'png' | 'svg';
  markers?: MapMarkerSpec[];
  routes?: MapRouteSpec[];
  regions?: MapRegionSpec[];
  timePeriod?: string;
  language?: string;
  interactive?: boolean;
}

/** Response from map rendering */
export interface MapRenderResponse {
  success: boolean;
  data?: string; // base64 encoded
  mimeType?: string;
  width?: number;
  height?: number;
  renderMethod?: MapRenderMethod;
  htmlContent?: string; // for interactive maps
  error?: string;
}

/** Map style info */
export interface MapStyleInfo {
  id: MapStyleOption;
  name: string;
  description: string;
}

/** Response from map styles endpoint */
export interface MapStylesResponse {
  success: boolean;
  styles: MapStyleInfo[];
}

/** Media generation capabilities */
export interface MediaCapabilities {
  diagrams: {
    formats: DiagramFormat[];
    renderers: {
      mermaid: boolean;
      graphviz: boolean;
      plantuml: boolean;
      d2: boolean;
    };
  };
  formulas: {
    renderers: {
      katex: boolean;
      latex: boolean;
    };
    clientSideSupported: boolean;
  };
  maps: {
    styles: MapStyleOption[];
    renderers: {
      cartopy: boolean;
      folium: boolean;
      staticTiles: boolean;
    };
    features: string[];
  };
}

/** Response from capabilities endpoint */
export interface MediaCapabilitiesResponse {
  success: boolean;
  capabilities: MediaCapabilities;
  error?: string;
}

// =============================================================================
// FOV Context Management Types
// =============================================================================

/** FOV model tier for adaptive token budgets */
export type FOVModelTier = 'CLOUD' | 'MID_RANGE' | 'ON_DEVICE' | 'TINY';

/** FOV session state */
export type FOVSessionState = 'created' | 'active' | 'paused' | 'ended';

/** FOV session summary for list views */
export interface FOVSessionSummary {
  session_id: string;
  curriculum_id: string;
  state: FOVSessionState;
  created_at: string;
  turn_count: number;
  barge_in_count: number;
}

/** FOV token usage for a buffer */
export interface FOVTokenUsage {
  budget: number;
  estimated_used: number;
  percentage: number;
}

/** FOV learner signals */
export interface FOVLearnerSignals {
  clarifications: number;
  repetitions: number;
  confusions: number;
}

/** FOV buffer state for debug view */
export interface FOVBufferState {
  immediate: {
    current_segment: string | null;
    barge_in: string | null;
    turn_count: number;
    max_turns: number;
  };
  working: {
    topic_id: string | null;
    topic_title: string | null;
    glossary_count: number;
    misconception_count: number;
  };
  episodic: {
    topic_summary_count: number;
    questions_count: number;
    learner_signals: FOVLearnerSignals;
  };
  semantic: {
    curriculum_id: string | null;
    current_topic_index: number;
    total_topics: number;
    has_outline: boolean;
  };
}

/** FOV budget configuration */
export interface FOVBudgetConfig {
  tier: FOVModelTier;
  immediate_budget: number;
  working_budget: number;
  episodic_budget: number;
  semantic_budget: number;
  total_budget: number;
  max_conversation_turns: number;
}

/** FOV confidence history entry */
export interface FOVConfidenceEntry {
  timestamp: string;
  score: number;
  uncertainty: number;
}

/** FOV barge-in history entry */
export interface FOVBargeInEntry {
  timestamp: string;
  utterance: string;
  topic_id?: string;
}

/** FOV session debug information */
export interface FOVSessionDebug {
  session_id: string;
  state: FOVSessionState;
  curriculum_id: string;
  turn_count: number;
  barge_in_count: number;
  model_tier: FOVModelTier;
  buffers: FOVBufferState;
  token_usage: {
    immediate: FOVTokenUsage;
    working: FOVTokenUsage;
    episodic: FOVTokenUsage;
    semantic: FOVTokenUsage;
  };
  total_context_tokens: number;
  confidence_history: FOVConfidenceEntry[];
  barge_in_history: FOVBargeInEntry[];
  budget_config: FOVBudgetConfig;
}

/** FOV health status */
export interface FOVHealthStatus {
  status: 'healthy' | 'unavailable' | 'error';
  sessions: {
    total: number;
    active: number;
    paused: number;
  };
  version?: string;
  features?: {
    confidence_monitoring: boolean;
    context_expansion: boolean;
    adaptive_budgets: boolean;
    model_tiers: FOVModelTier[];
  };
  error?: string;
}

/** FOV sessions list response */
export interface FOVSessionsResponse {
  sessions: FOVSessionSummary[];
  error?: string;
}

/** FOV context build response */
export interface FOVContextBuildResponse {
  system_message: string;
  immediate: string;
  working: string;
  episodic: string;
  semantic: string;
  total_tokens: number;
}

/** FOV confidence analysis result */
export interface FOVConfidenceAnalysis {
  confidence_score: number;
  uncertainty_score: number;
  hedging_score: number;
  deflection_score: number;
  knowledge_gap_score: number;
  vague_language_score: number;
  detected_markers: string[];
  trend: 'improving' | 'stable' | 'declining';
  expansion?: {
    should_expand: boolean;
    priority: 'low' | 'medium' | 'high' | 'critical';
    scope: 'narrow' | 'broad' | 'comprehensive';
    reason: string;
  };
}

// =============================================================================
// Curriculum Reprocessing Types
// =============================================================================

/** Severity levels for analysis issues */
export type IssueSeverity = 'critical' | 'warning' | 'info';

/** Types of issues that can be detected */
export type IssueType =
  | 'broken_image'
  | 'placeholder_image'
  | 'oversized_segment'
  | 'undersized_segment'
  | 'missing_objectives'
  | 'missing_checkpoints'
  | 'missing_alternatives'
  | 'missing_time_estimate'
  | 'missing_metadata'
  | 'invalid_bloom_level';

/** A detected issue in the curriculum */
export interface AnalysisIssue {
  id: string;
  issueType: IssueType;
  severity: IssueSeverity;
  location: string;
  nodeId?: string;
  description: string;
  suggestedFix: string;
  autoFixable: boolean;
  details: Record<string, unknown>;
}

/** Summary statistics for an analysis */
export interface AnalysisStats {
  totalIssues: number;
  criticalCount: number;
  warningCount: number;
  infoCount: number;
  autoFixableCount: number;
  issuesByType: Record<string, number>;
}

/** Full analysis result for a curriculum */
export interface CurriculumAnalysis {
  curriculumId: string;
  curriculumTitle: string;
  analyzedAt: string;
  analysisDurationMs: number;
  issues: AnalysisIssue[];
  stats: AnalysisStats;
}

/** Reprocessing job status */
export type ReprocessStatus =
  | 'queued'
  | 'loading'
  | 'analyzing'
  | 'fixing_images'
  | 'rechunking'
  | 'generating_objectives'
  | 'adding_checkpoints'
  | 'adding_alternatives'
  | 'fixing_metadata'
  | 'validating'
  | 'storing'
  | 'complete'
  | 'failed'
  | 'cancelled';

/** Configuration for a reprocessing job */
export interface ReprocessConfig {
  curriculumId: string;
  fixImages: boolean;
  rechunkSegments: boolean;
  generateObjectives: boolean;
  addCheckpoints: boolean;
  addAlternatives: boolean;
  fixMetadata: boolean;
  llmModel: string;
  llmTemperature: number;
  imageSearchEnabled: boolean;
  generatePlaceholders: boolean;
  dryRun: boolean;
  issueTypes?: IssueType[];
  nodeIds?: string[];
}

/** Progress information for a single stage */
export interface ReprocessStage {
  id: string;
  name: string;
  status: 'pending' | 'in_progress' | 'complete' | 'skipped' | 'failed';
  progress: number;
  startedAt?: string;
  completedAt?: string;
  itemsTotal: number;
  itemsProcessed: number;
  error?: string;
}

/** Final result of a reprocessing job */
export interface ReprocessResult {
  success: boolean;
  fixesApplied: string[];
  issuesFixed: number;
  issuesRemaining: number;
  durationMs: number;
  outputPath?: string;
  error?: string;
}

/** Full progress information for a reprocessing job */
export interface ReprocessProgress {
  id: string;
  config: ReprocessConfig;
  status: ReprocessStatus;
  overallProgress: number;
  currentStage: string;
  currentActivity: string;
  stages: ReprocessStage[];
  analysis?: CurriculumAnalysis;
  fixesApplied: string[];
  startedAt?: string;
  result?: ReprocessResult;
  error?: string;
}

/** Job summary for list views */
export interface ReprocessJobSummary {
  id: string;
  curriculumId: string;
  status: ReprocessStatus;
  overallProgress: number;
  currentStage: string;
  startedAt?: string;
  fixesApplied: number;
}

/** Proposed change for preview */
export interface ProposedChange {
  location: string;
  changeType: string;
  before: Record<string, unknown>;
  after: Record<string, unknown>;
  description: string;
}

/** Preview of what reprocessing would do */
export interface ReprocessPreview {
  curriculumId: string;
  proposedChanges: ProposedChange[];
  summary: Record<string, number>;
}

/** API response for analysis */
export interface AnalysisResponse {
  success: boolean;
  analysis?: CurriculumAnalysis;
  message?: string;
  error?: string;
}

/** API response for starting a job */
export interface StartReprocessResponse {
  success: boolean;
  jobId?: string;
  status?: ReprocessStatus;
  error?: string;
}

/** API response for job progress */
export interface ReprocessProgressResponse {
  success: boolean;
  progress?: ReprocessProgress;
  error?: string;
}

/** API response for jobs list */
export interface ReprocessJobsResponse {
  success: boolean;
  jobs: ReprocessJobSummary[];
  error?: string;
}

/** API response for preview */
export interface ReprocessPreviewResponse {
  success: boolean;
  preview?: ReprocessPreview;
  error?: string;
}
