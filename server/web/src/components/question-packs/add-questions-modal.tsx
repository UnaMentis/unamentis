'use client';

import { useState } from 'react';
import {
  X,
  Plus,
  Upload,
  Copy,
  ChevronRight,
  ChevronLeft,
  Loader2,
  AlertCircle,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import type {
  QuestionPack,
  KBQuestion,
  CreateQuestionData,
  DomainId,
  QuestionType,
  QuestionSource,
  DifficultyTier,
} from '@/types/question-packs';

// Domain labels
const DOMAIN_LABELS: Record<DomainId, string> = {
  science: 'Science',
  mathematics: 'Mathematics',
  literature: 'Literature',
  history: 'History',
  social_studies: 'Social Studies',
  fine_arts: 'Fine Arts',
  current_events: 'Current Events',
  language: 'Language',
  religion_philosophy: 'Religion & Philosophy',
  pop_culture: 'Pop Culture',
  technology: 'Technology',
  miscellaneous: 'Miscellaneous',
};

// Question type labels
const TYPE_LABELS: Record<QuestionType, string> = {
  toss_up: 'Toss-Up',
  bonus: 'Bonus',
  pyramid: 'Pyramid',
  lightning: 'Lightning',
};

// Source labels
const SOURCE_LABELS: Record<QuestionSource, string> = {
  naqt: 'NAQT',
  nsb: 'NSB',
  qb_packets: 'QB Packets',
  custom: 'Custom',
  ai_generated: 'AI Generated',
};

// Difficulty tier labels
const TIER_LABELS: Record<DifficultyTier, string> = {
  elementary: 'Elementary',
  middle_school: 'Middle School',
  jv: 'JV',
  varsity: 'Varsity',
  championship: 'Championship',
  college: 'College',
};

// API functions
async function createQuestion(input: CreateQuestionData): Promise<KBQuestion> {
  const response = await fetch('/api/kb/questions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.error || 'Failed to create question');
  }
  const data = await response.json();
  return data.question;
}

// Note: addQuestionsToPackApi will be used in the "Copy from Pack" flow
// eslint-disable-next-line @typescript-eslint/no-unused-vars
async function addQuestionsToPackApi(packId: string, questionIds: string[]): Promise<void> {
  const response = await fetch(`/api/kb/packs/${packId}/questions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ question_ids: questionIds }),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.error || 'Failed to add questions to pack');
  }
}

async function getAvailablePacks(): Promise<QuestionPack[]> {
  const response = await fetch('/api/kb/packs?status=active');
  if (!response.ok) {
    throw new Error('Failed to fetch packs');
  }
  const data = await response.json();
  return data.packs;
}

interface AddQuestionsModalProps {
  packId: string;
  packName: string;
  onClose: () => void;
  onSuccess: () => void;
}

type AddMode = 'select' | 'single' | 'import' | 'copy';

export function AddQuestionsModal({
  packId,
  packName,
  onClose,
  onSuccess,
}: AddQuestionsModalProps) {
  const [mode, setMode] = useState<AddMode>('select');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Single question form state
  const [questionText, setQuestionText] = useState('');
  const [answerText, setAnswerText] = useState('');
  const [acceptableAnswers, setAcceptableAnswers] = useState('');
  const [domainId, setDomainId] = useState<DomainId>('miscellaneous');
  const [subcategory, setSubcategory] = useState('');
  const [difficulty, setDifficulty] = useState(3);
  const [speedTarget, setSpeedTarget] = useState(10);
  const [questionType, setQuestionType] = useState<QuestionType>('toss_up');
  const [questionSource, setQuestionSource] = useState<QuestionSource>('custom');
  const [difficultyTier, setDifficultyTier] = useState<DifficultyTier>('varsity');
  const [buzzable, setBuzzable] = useState(false);
  const [hints, setHints] = useState<string[]>([]);
  const [explanation, setExplanation] = useState('');
  const [addAnother, setAddAnother] = useState(false);

  // Copy from pack state
  const [availablePacks, setAvailablePacks] = useState<QuestionPack[]>([]);
  const [selectedSourcePack, setSelectedSourcePack] = useState<string | null>(null);
  const [packsLoading, setPacksLoading] = useState(false);

  const resetForm = () => {
    setQuestionText('');
    setAnswerText('');
    setAcceptableAnswers('');
    setDomainId('miscellaneous');
    setSubcategory('');
    setDifficulty(3);
    setSpeedTarget(10);
    setQuestionType('toss_up');
    setQuestionSource('custom');
    setDifficultyTier('varsity');
    setBuzzable(false);
    setHints([]);
    setExplanation('');
    setError(null);
  };

  const handleAddHint = () => {
    setHints([...hints, '']);
  };

  const handleRemoveHint = (index: number) => {
    setHints(hints.filter((_, i) => i !== index));
  };

  const handleUpdateHint = (index: number, value: string) => {
    const newHints = [...hints];
    newHints[index] = value;
    setHints(newHints);
  };

  const handleCreateQuestion = async () => {
    if (!questionText.trim() || !answerText.trim()) {
      setError('Question text and answer are required');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // Create the question
      const input: CreateQuestionData = {
        domain_id: domainId,
        subcategory: subcategory || '',
        question_text: questionText.trim(),
        answer_text: answerText.trim(),
        acceptable_answers: acceptableAnswers
          .split(',')
          .map((a) => a.trim())
          .filter(Boolean),
        difficulty,
        speed_target_seconds: speedTarget,
        question_type: questionType,
        question_source: questionSource,
        difficulty_tier: difficultyTier,
        buzzable,
        hints: hints.filter(Boolean),
        explanation: explanation || undefined,
        pack_ids: [packId],
      };

      await createQuestion(input);

      if (addAnother) {
        resetForm();
      } else {
        onSuccess();
        onClose();
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create question');
    } finally {
      setLoading(false);
    }
  };

  const loadAvailablePacks = async () => {
    setPacksLoading(true);
    try {
      const packs = await getAvailablePacks();
      // Filter out the current pack
      setAvailablePacks(packs.filter((p) => p.id !== packId));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load packs');
    } finally {
      setPacksLoading(false);
    }
  };

  // Mode selection view
  if (mode === 'select') {
    return (
      <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
        <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-lg">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
            <h2 className="text-lg font-semibold text-white">Add Questions to {packName}</h2>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Options */}
          <div className="p-6 space-y-4">
            <p className="text-slate-400 text-sm mb-6">How would you like to add questions?</p>

            <button
              onClick={() => setMode('single')}
              className="w-full flex items-center gap-4 p-4 bg-slate-800 border border-slate-700 rounded-lg hover:border-purple-500 transition-colors text-left"
            >
              <div className="w-12 h-12 bg-purple-500/20 rounded-lg flex items-center justify-center">
                <Plus className="w-6 h-6 text-purple-400" />
              </div>
              <div className="flex-1">
                <div className="font-medium text-slate-200">Add Single Question</div>
                <div className="text-sm text-slate-400">
                  Create a new question with full metadata
                </div>
              </div>
              <ChevronRight className="w-5 h-5 text-slate-500" />
            </button>

            <button
              onClick={() => setMode('import')}
              className="w-full flex items-center gap-4 p-4 bg-slate-800 border border-slate-700 rounded-lg hover:border-purple-500 transition-colors text-left"
            >
              <div className="w-12 h-12 bg-blue-500/20 rounded-lg flex items-center justify-center">
                <Upload className="w-6 h-6 text-blue-400" />
              </div>
              <div className="flex-1">
                <div className="font-medium text-slate-200">Import from CSV/JSON</div>
                <div className="text-sm text-slate-400">Bulk import questions from a file</div>
              </div>
              <ChevronRight className="w-5 h-5 text-slate-500" />
            </button>

            <button
              onClick={() => {
                setMode('copy');
                loadAvailablePacks();
              }}
              className="w-full flex items-center gap-4 p-4 bg-slate-800 border border-slate-700 rounded-lg hover:border-purple-500 transition-colors text-left"
            >
              <div className="w-12 h-12 bg-emerald-500/20 rounded-lg flex items-center justify-center">
                <Copy className="w-6 h-6 text-emerald-400" />
              </div>
              <div className="flex-1">
                <div className="font-medium text-slate-200">Copy from Existing Pack</div>
                <div className="text-sm text-slate-400">Select questions from another pack</div>
              </div>
              <ChevronRight className="w-5 h-5 text-slate-500" />
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Single question form
  if (mode === 'single') {
    return (
      <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4 overflow-y-auto">
        <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-2xl my-8">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
            <div className="flex items-center gap-3">
              <button
                onClick={() => setMode('select')}
                className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
              >
                <ChevronLeft className="w-5 h-5" />
              </button>
              <h2 className="text-lg font-semibold text-white">Add Single Question</h2>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Form */}
          <div className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
            {/* Error */}
            {error && (
              <div className="flex items-center gap-2 p-3 bg-red-500/10 border border-red-500/30 rounded-md text-red-400 text-sm">
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
                {error}
              </div>
            )}

            {/* Question Text */}
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">
                Question Text <span className="text-red-400">*</span>
              </label>
              <textarea
                value={questionText}
                onChange={(e) => setQuestionText(e.target.value)}
                rows={3}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50 resize-none"
                placeholder="Enter the question..."
              />
            </div>

            {/* Answer */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Answer <span className="text-red-400">*</span>
                </label>
                <input
                  type="text"
                  value={answerText}
                  onChange={(e) => setAnswerText(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                  placeholder="Correct answer"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Acceptable Alternatives
                </label>
                <input
                  type="text"
                  value={acceptableAnswers}
                  onChange={(e) => setAcceptableAnswers(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                  placeholder="Answer1, Answer2, ..."
                />
              </div>
            </div>

            {/* Domain and Subcategory */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Domain</label>
                <select
                  value={domainId}
                  onChange={(e) => setDomainId(e.target.value as DomainId)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                >
                  {Object.entries(DOMAIN_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Subcategory</label>
                <input
                  type="text"
                  value={subcategory}
                  onChange={(e) => setSubcategory(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                  placeholder="e.g., Physics, Chemistry"
                />
              </div>
            </div>

            {/* Difficulty and Speed */}
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Difficulty (1-5)
                </label>
                <select
                  value={difficulty}
                  onChange={(e) => setDifficulty(Number(e.target.value))}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                >
                  {[1, 2, 3, 4, 5].map((level) => (
                    <option key={level} value={level}>
                      {level}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Speed Target (sec)
                </label>
                <input
                  type="number"
                  value={speedTarget}
                  onChange={(e) => setSpeedTarget(Number(e.target.value))}
                  min={1}
                  max={60}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Competition Level
                </label>
                <select
                  value={difficultyTier}
                  onChange={(e) => setDifficultyTier(e.target.value as DifficultyTier)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                >
                  {Object.entries(TIER_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Type and Source */}
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">
                  Question Type
                </label>
                <select
                  value={questionType}
                  onChange={(e) => setQuestionType(e.target.value as QuestionType)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                >
                  {Object.entries(TYPE_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Source</label>
                <select
                  value={questionSource}
                  onChange={(e) => setQuestionSource(e.target.value as QuestionSource)}
                  className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
                >
                  {Object.entries(SOURCE_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>
              <div className="flex items-end pb-2">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={buzzable}
                    onChange={(e) => setBuzzable(e.target.checked)}
                    className="w-4 h-4 rounded border-slate-600 bg-slate-800 text-purple-500 focus:ring-purple-500/50"
                  />
                  <span className="text-sm text-slate-300">Buzzable</span>
                </label>
              </div>
            </div>

            {/* Hints */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-sm font-medium text-slate-300">Hints (optional)</label>
                <button
                  type="button"
                  onClick={handleAddHint}
                  className="text-xs text-purple-400 hover:text-purple-300"
                >
                  + Add Hint
                </button>
              </div>
              {hints.length === 0 ? (
                <p className="text-sm text-slate-500">No hints added</p>
              ) : (
                <div className="space-y-2">
                  {hints.map((hint, index) => (
                    <div key={index} className="flex gap-2">
                      <input
                        type="text"
                        value={hint}
                        onChange={(e) => handleUpdateHint(index, e.target.value)}
                        className="flex-1 px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50 text-sm"
                        placeholder={`Hint ${index + 1}`}
                      />
                      <button
                        type="button"
                        onClick={() => handleRemoveHint(index)}
                        className="px-2 text-slate-400 hover:text-red-400"
                      >
                        <X className="w-4 h-4" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Explanation */}
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">
                Explanation (optional)
              </label>
              <textarea
                value={explanation}
                onChange={(e) => setExplanation(e.target.value)}
                rows={2}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50 resize-none text-sm"
                placeholder="Detailed explanation for learning purposes..."
              />
            </div>

            {/* Assign to packs info */}
            <div className="p-3 bg-slate-800/50 rounded-md">
              <p className="text-sm text-slate-400">
                This question will be added to: <span className="text-slate-200">{packName}</span>
              </p>
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between px-6 py-4 border-t border-slate-700">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={addAnother}
                onChange={(e) => setAddAnother(e.target.checked)}
                className="w-4 h-4 rounded border-slate-600 bg-slate-800 text-purple-500 focus:ring-purple-500/50"
              />
              <span className="text-sm text-slate-300">Add another after saving</span>
            </label>
            <div className="flex gap-2">
              <button
                onClick={onClose}
                className="px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleCreateQuestion}
                disabled={loading || !questionText.trim() || !answerText.trim()}
                className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {loading && <Loader2 className="w-4 h-4 animate-spin" />}
                {addAnother ? 'Add & Continue' : 'Add Question'}
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Import from file view (placeholder)
  if (mode === 'import') {
    return (
      <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
        <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-lg">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
            <div className="flex items-center gap-3">
              <button
                onClick={() => setMode('select')}
                className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
              >
                <ChevronLeft className="w-5 h-5" />
              </button>
              <h2 className="text-lg font-semibold text-white">Import from File</h2>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content */}
          <div className="p-6">
            <div className="border-2 border-dashed border-slate-700 rounded-lg p-8 text-center">
              <Upload className="w-12 h-12 text-slate-500 mx-auto mb-4" />
              <p className="text-slate-300 mb-2">Drag and drop a CSV or JSON file here</p>
              <p className="text-sm text-slate-500 mb-4">or click to browse</p>
              <button className="px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors">
                Browse Files
              </button>
            </div>
            <p className="text-xs text-slate-500 mt-4 text-center">
              Supported formats: CSV, JSON. Max file size: 10MB
            </p>
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-2 px-6 py-4 border-t border-slate-700">
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Copy from pack view
  if (mode === 'copy') {
    return (
      <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
        <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-lg">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
            <div className="flex items-center gap-3">
              <button
                onClick={() => setMode('select')}
                className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
              >
                <ChevronLeft className="w-5 h-5" />
              </button>
              <h2 className="text-lg font-semibold text-white">Copy from Existing Pack</h2>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content */}
          <div className="p-6">
            {packsLoading ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-6 h-6 text-purple-500 animate-spin" />
              </div>
            ) : availablePacks.length === 0 ? (
              <div className="text-center py-8 text-slate-400">
                No other packs available to copy from
              </div>
            ) : (
              <div className="space-y-2 max-h-[300px] overflow-y-auto">
                {availablePacks.map((pack) => (
                  <button
                    key={pack.id}
                    onClick={() => setSelectedSourcePack(pack.id)}
                    className={`w-full flex items-center justify-between p-3 rounded-lg border transition-colors text-left ${
                      selectedSourcePack === pack.id
                        ? 'bg-purple-500/20 border-purple-500'
                        : 'bg-slate-800 border-slate-700 hover:border-slate-600'
                    }`}
                  >
                    <div>
                      <div className="font-medium text-slate-200">{pack.name}</div>
                      <div className="text-sm text-slate-400">{pack.question_count} questions</div>
                    </div>
                    <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                      {pack.type}
                    </Badge>
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-2 px-6 py-4 border-t border-slate-700">
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
            >
              Cancel
            </button>
            <button
              disabled={!selectedSourcePack}
              className="px-4 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Select Questions
            </button>
          </div>
        </div>
      </div>
    );
  }

  return null;
}
