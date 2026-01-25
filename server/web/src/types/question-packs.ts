// Knowledge Bowl Question Pack Types
// Types for question packs, questions, and pack management

// ============================================================================
// Enums
// ============================================================================

/**
 * Difficulty tiers map to competition levels per KNOWLEDGE_BOWL_EXTENSIONS.md
 */
export type DifficultyTier =
  | 'elementary' // Grades 3-5
  | 'middle_school' // Grades 6-8
  | 'jv' // Grades 9-10 (Junior Varsity)
  | 'varsity' // Grades 11-12
  | 'championship' // State/national level
  | 'college'; // Undergraduate

/**
 * Question types per KNOWLEDGE_BOWL_EXTENSIONS.md
 */
export type QuestionType = 'toss_up' | 'bonus' | 'pyramid' | 'lightning';

/**
 * Question sources per KNOWLEDGE_BOWL_EXTENSIONS.md
 */
export type QuestionSource = 'naqt' | 'nsb' | 'qb_packets' | 'custom' | 'ai_generated';

/**
 * Pack types
 */
export type PackType = 'system' | 'custom' | 'bundle';

/**
 * Entity status
 */
export type EntityStatus = 'active' | 'draft' | 'archived';

// ============================================================================
// Domain Taxonomy
// ============================================================================

/**
 * Knowledge Bowl domains with subcategories
 */
export const KB_DOMAINS = {
  science: ['biology', 'chemistry', 'physics', 'earth_science', 'astronomy', 'computer_science'],
  mathematics: ['arithmetic', 'algebra', 'geometry', 'trigonometry', 'calculus', 'statistics'],
  literature: ['american', 'british', 'world', 'poetry', 'drama', 'mythology'],
  history: ['us_history', 'world_history', 'ancient', 'medieval', 'modern', 'military'],
  social_studies: [
    'geography',
    'government',
    'economics',
    'sociology',
    'psychology',
    'anthropology',
  ],
  fine_arts: ['visual_arts', 'music', 'theater', 'dance', 'architecture', 'film'],
  current_events: ['politics', 'science_news', 'culture', 'sports', 'technology', 'business'],
  language: ['grammar', 'vocabulary', 'etymology', 'foreign_language', 'linguistics'],
  religion_philosophy: ['world_religions', 'philosophy', 'ethics', 'mythology'],
  pop_culture: ['entertainment', 'media', 'sports_culture', 'games', 'internet'],
  technology: ['inventions', 'engineering', 'computing', 'space_exploration'],
  miscellaneous: ['general_trivia', 'cross_domain', 'puzzles', 'wordplay'],
} as const;

export type DomainId = keyof typeof KB_DOMAINS;
export type Subcategory = (typeof KB_DOMAINS)[DomainId][number];

// ============================================================================
// Question Types
// ============================================================================

/**
 * Base question interface with common fields
 */
export interface KBQuestion {
  id: string;
  domain_id: DomainId;
  subcategory: string;
  question_text: string;
  answer_text: string;
  acceptable_answers: string[];
  difficulty: number; // 1-5 numeric scale
  speed_target_seconds: number;
  question_type: QuestionType;
  hints: string[];
  explanation: string;

  // Extended fields per KNOWLEDGE_BOWL_EXTENSIONS.md spec
  difficulty_tier?: DifficultyTier;
  competition_year?: string; // e.g., "2024-2025"
  question_source?: QuestionSource;
  buzzable?: boolean;

  // Pack management
  pack_ids: string[];
  status: EntityStatus;

  // Audio status
  has_audio?: boolean;
  audio_segments?: {
    question?: boolean;
    answer?: boolean;
    hints?: boolean[];
    explanation?: boolean;
  };

  // Audit
  created_at?: string;
  updated_at?: string;
}

/**
 * Bonus question with multi-part structure
 */
export interface BonusQuestion extends KBQuestion {
  question_type: 'bonus';
  lead_in: string;
  parts: Array<{
    prompt: string;
    answer: string;
    points: number;
  }>;
  total_points: number;
  conference_time: number;
}

/**
 * Pyramid question with progressive clues
 */
export interface PyramidQuestion extends KBQuestion {
  question_type: 'pyramid';
  clues: Array<{
    text: string;
    reveal_points: number;
    difficulty: 'expert' | 'hard' | 'medium' | 'easy';
  }>;
}

/**
 * Union type for all question variants
 */
export type Question = KBQuestion | BonusQuestion | PyramidQuestion;

// ============================================================================
// Question Pack Types
// ============================================================================

/**
 * Distribution of numeric difficulty levels (1-5)
 */
export interface DifficultyDistribution {
  1: number;
  2: number;
  3: number;
  4: number;
  5: number;
}

/**
 * Question pack with metadata and content
 */
export interface QuestionPack {
  id: string;
  name: string;
  description: string;
  type: PackType;

  // For bundle packs
  source_pack_ids?: string[];
  is_reference_bundle?: boolean;

  // Competition metadata
  difficulty_tier: DifficultyTier;
  competition_year?: string;
  difficulty_distribution: DifficultyDistribution;
  domain_distribution: Record<DomainId, number>;
  question_types: QuestionType[];

  // Questions
  question_ids: string[];
  question_count: number;

  // Audio status
  audio_coverage_percent: number;
  missing_audio_count: number;

  // Audit
  created_at: string;
  updated_at: string;
  created_by?: string;
  status: EntityStatus;
}

/**
 * Summary view of a pack (for list display)
 */
export interface QuestionPackSummary {
  id: string;
  name: string;
  description: string;
  type: PackType;
  difficulty_tier: DifficultyTier;
  question_count: number;
  domain_count: number;
  audio_coverage_percent: number;
  status: EntityStatus;
  updated_at: string;
}

// ============================================================================
// Pack Organization Types
// ============================================================================

/**
 * Domain grouping with question counts
 */
export interface DomainGroup {
  domain_id: DomainId;
  domain_name: string;
  question_count: number;
  subcategories: Array<{
    subcategory: string;
    question_count: number;
  }>;
}

/**
 * Difficulty grouping with question counts
 */
export interface DifficultyGroup {
  difficulty: number;
  label: string; // "Easy", "Medium", "Hard", etc.
  question_count: number;
}

/**
 * Source grouping with question counts
 */
export interface SourceGroup {
  source: QuestionSource;
  label: string;
  question_count: number;
}

// ============================================================================
// API Response Types
// ============================================================================

export interface PacksResponse {
  success: boolean;
  packs: QuestionPackSummary[];
  total: number;
  limit: number;
  offset: number;
  error?: string;
}

export interface PackResponse {
  success: boolean;
  pack: QuestionPack;
  domain_groups?: DomainGroup[];
  error?: string;
}

export interface QuestionsResponse {
  success: boolean;
  questions: KBQuestion[];
  total: number;
  limit: number;
  offset: number;
  error?: string;
}

export interface QuestionResponse {
  success: boolean;
  question: Question;
  error?: string;
}

// ============================================================================
// Form/Create Types
// ============================================================================

export interface CreatePackData {
  name: string;
  description?: string;
  type: PackType;
  difficulty_tier: DifficultyTier;
  competition_year?: string;
  status?: EntityStatus;
}

export interface UpdatePackData {
  name?: string;
  description?: string;
  difficulty_tier?: DifficultyTier;
  competition_year?: string;
  status?: EntityStatus;
}

export interface CreateQuestionData {
  domain_id: DomainId;
  subcategory: string;
  question_text: string;
  answer_text: string;
  acceptable_answers?: string[];
  difficulty: number;
  speed_target_seconds?: number;
  question_type?: QuestionType;
  hints?: string[];
  explanation?: string;
  difficulty_tier?: DifficultyTier;
  competition_year?: string;
  question_source?: QuestionSource;
  buzzable?: boolean;
  pack_ids?: string[];
  status?: EntityStatus;
}

export interface UpdateQuestionData {
  domain_id?: DomainId;
  subcategory?: string;
  question_text?: string;
  answer_text?: string;
  acceptable_answers?: string[];
  difficulty?: number;
  speed_target_seconds?: number;
  question_type?: QuestionType;
  hints?: string[];
  explanation?: string;
  difficulty_tier?: DifficultyTier;
  competition_year?: string;
  question_source?: QuestionSource;
  buzzable?: boolean;
  status?: EntityStatus;
}

// ============================================================================
// Bundle Types
// ============================================================================

export interface BundlePacksData {
  name: string;
  description?: string;
  source_pack_ids: string[];
  is_reference_bundle?: boolean;
  deduplication_strategy: 'keep_all' | 'keep_first' | 'manual';
  excluded_question_ids?: string[];
  difficulty_tier: DifficultyTier;
  competition_year?: string;
}

export interface DeduplicationPreview {
  duplicate_groups: Array<{
    question_text: string;
    occurrences: Array<{
      question_id: string;
      pack_id: string;
      pack_name: string;
    }>;
  }>;
  total_duplicates: number;
  unique_questions_after_dedup: number;
}

// ============================================================================
// Import Types
// ============================================================================

export interface ImportQuestionData {
  question_text: string;
  answer_text: string;
  acceptable_answers?: string;
  domain_id?: string;
  subcategory?: string;
  difficulty?: number;
  hints?: string;
  explanation?: string;
  question_type?: string;
  question_source?: string;
}

export interface ImportPreview {
  valid_questions: CreateQuestionData[];
  invalid_rows: Array<{
    row_number: number;
    data: ImportQuestionData;
    errors: string[];
  }>;
  column_mapping: Record<string, string>;
}

export interface ImportResult {
  success: boolean;
  imported_count: number;
  failed_count: number;
  questions: KBQuestion[];
  errors?: Array<{
    row_number: number;
    error: string;
  }>;
}

// ============================================================================
// Bulk Operations
// ============================================================================

export interface BulkUpdateData {
  question_ids: string[];
  updates: UpdateQuestionData;
}

export interface BulkMoveData {
  question_ids: string[];
  target_pack_id: string;
  remove_from_current?: boolean;
}

export interface BulkOperationResult {
  success: boolean;
  affected_count: number;
  errors?: Array<{
    question_id: string;
    error: string;
  }>;
}

// ============================================================================
// Filter Types
// ============================================================================

export interface QuestionFilters {
  domain_id?: DomainId;
  subcategory?: string;
  difficulty?: number[];
  question_type?: QuestionType[];
  question_source?: QuestionSource[];
  has_audio?: boolean;
  status?: EntityStatus[];
  search?: string;
}

export interface PackFilters {
  type?: PackType[];
  difficulty_tier?: DifficultyTier[];
  status?: EntityStatus[];
  search?: string;
}
