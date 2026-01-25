'use client';

import { useState } from 'react';
import {
  X,
  Search,
  Filter,
  Volume2,
  VolumeX,
  Lightbulb,
  Edit2,
  Trash2,
  ChevronLeft,
  ChevronRight,
  Check,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import type { KBQuestion, QuestionType } from '@/types/question-packs';

// Type labels
const TYPE_LABELS: Record<QuestionType, string> = {
  toss_up: 'Toss-Up',
  bonus: 'Bonus',
  pyramid: 'Pyramid',
  lightning: 'Lightning',
};

// Difficulty colors
const DIFFICULTY_COLORS: Record<number, string> = {
  1: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30',
  2: 'bg-lime-500/20 text-lime-400 border-lime-500/30',
  3: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
  4: 'bg-orange-500/20 text-orange-400 border-orange-500/30',
  5: 'bg-red-500/20 text-red-400 border-red-500/30',
};

interface QuestionBrowserProps {
  questions: KBQuestion[];
  total: number;
  loading: boolean;
  filterLabel: string;
  packQuestionCount: number;
  isSystemPack?: boolean;
  onClose: () => void;
  onRemove?: (questionId: string) => void;
  onEdit?: (question: KBQuestion) => void;
  onLoadMore?: () => void;
  onPageChange?: (page: number) => void;
  currentPage?: number;
  pageSize?: number;
}

export function QuestionBrowser({
  questions,
  total,
  loading,
  filterLabel,
  packQuestionCount,
  isSystemPack = false,
  onClose,
  onRemove,
  onEdit,
  // onLoadMore - reserved for future infinite scroll implementation
  onPageChange,
  currentPage = 1,
  pageSize = 20,
}: QuestionBrowserProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedQuestions, setSelectedQuestions] = useState<Set<string>>(new Set());
  const [showFilters, setShowFilters] = useState(false);

  // Filter state
  const [filterDifficulty, setFilterDifficulty] = useState<number | null>(null);
  const [filterType, setFilterType] = useState<QuestionType | null>(null);
  const [filterAudio, setFilterAudio] = useState<'all' | 'has' | 'missing'>('all');

  // Apply local filters
  const filteredQuestions = questions.filter((q) => {
    // Search filter
    if (searchQuery) {
      const search = searchQuery.toLowerCase();
      const matchesSearch =
        q.question_text.toLowerCase().includes(search) ||
        q.answer_text.toLowerCase().includes(search) ||
        q.acceptable_answers?.some((a) => a.toLowerCase().includes(search));
      if (!matchesSearch) return false;
    }

    // Difficulty filter
    if (filterDifficulty !== null && q.difficulty !== filterDifficulty) {
      return false;
    }

    // Type filter
    if (filterType !== null && q.question_type !== filterType) {
      return false;
    }

    // Audio filter
    if (filterAudio === 'has' && !q.has_audio) return false;
    if (filterAudio === 'missing' && q.has_audio) return false;

    return true;
  });

  const totalPages = Math.ceil(total / pageSize);

  const toggleSelectQuestion = (questionId: string) => {
    setSelectedQuestions((prev) => {
      const next = new Set(prev);
      if (next.has(questionId)) {
        next.delete(questionId);
      } else {
        next.add(questionId);
      }
      return next;
    });
  };

  const toggleSelectAll = () => {
    if (selectedQuestions.size === filteredQuestions.length) {
      setSelectedQuestions(new Set());
    } else {
      setSelectedQuestions(new Set(filteredQuestions.map((q) => q.id)));
    }
  };

  const clearFilters = () => {
    setFilterDifficulty(null);
    setFilterType(null);
    setFilterAudio('all');
    setSearchQuery('');
  };

  const hasActiveFilters =
    filterDifficulty !== null || filterType !== null || filterAudio !== 'all' || searchQuery !== '';

  return (
    <div className="bg-slate-900/80 border border-slate-700 rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-slate-700 bg-slate-800/50">
        <div className="flex items-center gap-3">
          <h3 className="font-medium text-slate-200">{filterLabel} Questions</h3>
          <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
            {filteredQuestions.length} of {packQuestionCount}
          </Badge>
        </div>
        <button
          onClick={onClose}
          className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Search and Filters */}
      <div className="px-4 py-3 border-b border-slate-700 space-y-3">
        <div className="flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
            <input
              type="text"
              placeholder="Search questions..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50 text-sm"
            />
          </div>
          <button
            onClick={() => setShowFilters(!showFilters)}
            className={`flex items-center gap-2 px-3 py-2 text-sm rounded-md transition-colors ${
              hasActiveFilters
                ? 'bg-purple-500/20 text-purple-300 border border-purple-500/30'
                : 'bg-slate-800 text-slate-300 border border-slate-700 hover:bg-slate-700'
            }`}
          >
            <Filter className="w-4 h-4" />
            Filters
            {hasActiveFilters && <span className="w-2 h-2 rounded-full bg-purple-400" />}
          </button>
        </div>

        {/* Filter Panel */}
        {showFilters && (
          <div className="flex flex-wrap gap-4 pt-2">
            {/* Difficulty Filter */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400">Difficulty:</span>
              <div className="flex gap-1">
                {[1, 2, 3, 4, 5].map((level) => (
                  <button
                    key={level}
                    onClick={() => setFilterDifficulty(filterDifficulty === level ? null : level)}
                    className={`w-7 h-7 rounded text-xs font-medium transition-colors ${
                      filterDifficulty === level
                        ? 'bg-purple-500 text-white'
                        : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
                    }`}
                  >
                    {level}
                  </button>
                ))}
              </div>
            </div>

            {/* Type Filter */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400">Type:</span>
              <select
                value={filterType || ''}
                onChange={(e) =>
                  setFilterType(e.target.value ? (e.target.value as QuestionType) : null)
                }
                className="px-2 py-1 bg-slate-700 border border-slate-600 rounded text-sm text-slate-300 focus:outline-none"
              >
                <option value="">All</option>
                {Object.entries(TYPE_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </div>

            {/* Audio Filter */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400">Audio:</span>
              <select
                value={filterAudio}
                onChange={(e) => setFilterAudio(e.target.value as 'all' | 'has' | 'missing')}
                className="px-2 py-1 bg-slate-700 border border-slate-600 rounded text-sm text-slate-300 focus:outline-none"
              >
                <option value="all">All</option>
                <option value="has">Has Audio</option>
                <option value="missing">Missing Audio</option>
              </select>
            </div>

            {hasActiveFilters && (
              <button
                onClick={clearFilters}
                className="text-xs text-purple-400 hover:text-purple-300"
              >
                Clear filters
              </button>
            )}
          </div>
        )}
      </div>

      {/* Bulk Actions (when items selected) */}
      {selectedQuestions.size > 0 && !isSystemPack && (
        <div className="flex items-center justify-between px-4 py-2 bg-purple-500/10 border-b border-purple-500/30">
          <span className="text-sm text-purple-300">{selectedQuestions.size} selected</span>
          <div className="flex items-center gap-2">
            <button className="px-3 py-1.5 text-xs font-medium text-slate-300 bg-slate-700 hover:bg-slate-600 rounded transition-colors">
              Change Difficulty
            </button>
            <button className="px-3 py-1.5 text-xs font-medium text-slate-300 bg-slate-700 hover:bg-slate-600 rounded transition-colors">
              Move to Pack
            </button>
            <button className="px-3 py-1.5 text-xs font-medium text-red-300 bg-red-500/20 hover:bg-red-500/30 rounded transition-colors">
              Remove
            </button>
            <button
              onClick={() => setSelectedQuestions(new Set())}
              className="text-xs text-slate-400 hover:text-slate-200"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Question List */}
      <div className="max-h-[500px] overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin w-6 h-6 border-2 border-purple-500 border-t-transparent rounded-full" />
          </div>
        ) : filteredQuestions.length === 0 ? (
          <div className="py-12 text-center text-slate-400">
            {searchQuery || hasActiveFilters
              ? 'No questions match your filters'
              : 'No questions in this category'}
          </div>
        ) : (
          <div className="divide-y divide-slate-800">
            {/* Select All Row */}
            {!isSystemPack && filteredQuestions.length > 0 && (
              <div className="flex items-center gap-3 px-4 py-2 bg-slate-800/30">
                <button
                  onClick={toggleSelectAll}
                  className={`w-5 h-5 rounded border flex items-center justify-center transition-colors ${
                    selectedQuestions.size === filteredQuestions.length
                      ? 'bg-purple-500 border-purple-500'
                      : 'border-slate-600 hover:border-slate-500'
                  }`}
                >
                  {selectedQuestions.size === filteredQuestions.length && (
                    <Check className="w-3 h-3 text-white" />
                  )}
                </button>
                <span className="text-xs text-slate-400">Select all</span>
              </div>
            )}

            {/* Questions */}
            {filteredQuestions.map((question) => (
              <div key={question.id} className="px-4 py-3 hover:bg-slate-800/30 transition-colors">
                <div className="flex items-start gap-3">
                  {/* Checkbox */}
                  {!isSystemPack && (
                    <button
                      onClick={() => toggleSelectQuestion(question.id)}
                      className={`mt-1 w-5 h-5 rounded border flex-shrink-0 flex items-center justify-center transition-colors ${
                        selectedQuestions.has(question.id)
                          ? 'bg-purple-500 border-purple-500'
                          : 'border-slate-600 hover:border-slate-500'
                      }`}
                    >
                      {selectedQuestions.has(question.id) && (
                        <Check className="w-3 h-3 text-white" />
                      )}
                    </button>
                  )}

                  {/* Question Content */}
                  <div className="flex-1 min-w-0">
                    <p className="text-slate-200 text-sm leading-relaxed">
                      <span className="text-slate-500 font-medium">Q: </span>
                      {question.question_text}
                    </p>
                    <p className="text-slate-400 text-sm mt-1">
                      <span className="text-slate-500 font-medium">A: </span>
                      {question.answer_text}
                    </p>

                    {/* Badges */}
                    <div className="flex flex-wrap items-center gap-2 mt-2">
                      <Badge
                        className={DIFFICULTY_COLORS[question.difficulty] || DIFFICULTY_COLORS[3]}
                      >
                        Diff: {question.difficulty}
                      </Badge>
                      <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                        {TYPE_LABELS[question.question_type]}
                      </Badge>
                      {question.has_audio ? (
                        <Badge className="bg-emerald-500/20 text-emerald-400 border-emerald-500/30 flex items-center gap-1">
                          <Volume2 className="w-3 h-3" />
                          Audio
                        </Badge>
                      ) : (
                        <Badge className="bg-slate-700/50 text-slate-400 border-slate-600 flex items-center gap-1">
                          <VolumeX className="w-3 h-3" />
                          No Audio
                        </Badge>
                      )}
                      {question.hints && question.hints.length > 0 && (
                        <Badge className="bg-amber-500/20 text-amber-400 border-amber-500/30 flex items-center gap-1">
                          <Lightbulb className="w-3 h-3" />
                          {question.hints.length} hints
                        </Badge>
                      )}
                      {question.question_source && (
                        <Badge className="bg-slate-700/50 text-slate-400 border-slate-600 uppercase text-xs">
                          {question.question_source}
                        </Badge>
                      )}
                    </div>
                  </div>

                  {/* Actions */}
                  {!isSystemPack && (
                    <div className="flex items-center gap-1 flex-shrink-0">
                      {onEdit && (
                        <button
                          onClick={() => onEdit(question)}
                          className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
                          title="Edit"
                        >
                          <Edit2 className="w-4 h-4" />
                        </button>
                      )}
                      {onRemove && (
                        <button
                          onClick={() => onRemove(question.id)}
                          className="p-1.5 text-slate-400 hover:text-red-400 transition-colors"
                          title="Remove from pack"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      )}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between px-4 py-3 border-t border-slate-700 bg-slate-800/30">
          <span className="text-sm text-slate-400">
            Showing {(currentPage - 1) * pageSize + 1}-{Math.min(currentPage * pageSize, total)} of{' '}
            {total}
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={() => onPageChange?.(currentPage - 1)}
              disabled={currentPage <= 1}
              className="p-1.5 text-slate-400 hover:text-slate-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>
            <span className="text-sm text-slate-300">
              Page {currentPage} of {totalPages}
            </span>
            <button
              onClick={() => onPageChange?.(currentPage + 1)}
              disabled={currentPage >= totalPages}
              className="p-1.5 text-slate-400 hover:text-slate-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <ChevronRight className="w-5 h-5" />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
