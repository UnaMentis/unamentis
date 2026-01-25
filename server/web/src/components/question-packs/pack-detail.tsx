'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  ArrowLeft,
  Edit2,
  Download,
  Plus,
  Layers,
  ChevronDown,
  ChevronRight,
  FileText,
  RefreshCw,
  Settings,
  Wand2,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tooltip } from '@/components/ui/tooltip';
import type { QuestionPack, KBQuestion, DifficultyTier, DomainId } from '@/types/question-packs';
import { QuestionBrowser } from './question-browser';

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

// Tier labels
const TIER_LABELS: Record<DifficultyTier, string> = {
  elementary: 'Elementary',
  middle_school: 'Middle School',
  jv: 'JV',
  varsity: 'Varsity',
  championship: 'Championship',
  college: 'College',
};

// API functions
async function getPack(packId: string): Promise<QuestionPack> {
  const response = await fetch(`/api/kb/packs/${packId}`);
  if (!response.ok) {
    throw new Error('Failed to fetch pack');
  }
  const data = await response.json();
  return data.pack;
}

async function getPackQuestions(
  packId: string,
  params?: {
    domain?: string;
    difficulty?: number;
    offset?: number;
    limit?: number;
  }
): Promise<{ questions: KBQuestion[]; total: number }> {
  const queryParams = new URLSearchParams();
  if (params?.domain) queryParams.set('domain', params.domain);
  if (params?.difficulty) queryParams.set('difficulty', String(params.difficulty));
  if (params?.offset) queryParams.set('offset', String(params.offset));
  if (params?.limit) queryParams.set('limit', String(params.limit));

  const query = queryParams.toString();
  const response = await fetch(`/api/kb/packs/${packId}/questions${query ? `?${query}` : ''}`);
  if (!response.ok) {
    throw new Error('Failed to fetch questions');
  }
  return response.json();
}

async function updatePack(packId: string, updates: Partial<QuestionPack>): Promise<void> {
  const response = await fetch(`/api/kb/packs/${packId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates),
  });
  if (!response.ok) {
    throw new Error('Failed to update pack');
  }
}

async function removeQuestionFromPack(packId: string, questionId: string): Promise<void> {
  const response = await fetch(`/api/kb/packs/${packId}/questions/${questionId}`, {
    method: 'DELETE',
  });
  if (!response.ok) {
    throw new Error('Failed to remove question');
  }
}

interface PackDetailProps {
  packId: string;
  onBack: () => void;
  onAddQuestions?: () => void;
  onBundlePacks?: () => void;
  onGenerateAudio?: () => void;
}

type ViewMode = 'by-topic' | 'by-difficulty' | 'all';

interface TopicGroup {
  domain: DomainId;
  subcategories: Record<string, number>;
  total: number;
}

export function PackDetail({
  packId,
  onBack,
  onAddQuestions,
  onBundlePacks,
  onGenerateAudio,
}: PackDetailProps) {
  const [pack, setPack] = useState<QuestionPack | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // View state
  const [viewMode, setViewMode] = useState<ViewMode>('by-topic');
  const [expandedTopics, setExpandedTopics] = useState<Set<string>>(new Set());
  const [selectedFilter, setSelectedFilter] = useState<{
    type: 'domain' | 'subcategory' | 'difficulty' | 'all';
    domain?: DomainId;
    subcategory?: string;
    difficulty?: number;
  } | null>(null);

  // Questions state
  const [questions, setQuestions] = useState<KBQuestion[]>([]);
  const [questionsTotal, setQuestionsTotal] = useState(0);
  const [questionsLoading, setQuestionsLoading] = useState(false);

  // Edit state
  const [isEditingName, setIsEditingName] = useState(false);
  const [isEditingDescription, setIsEditingDescription] = useState(false);
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');

  const fetchPack = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getPack(packId);
      setPack(data);
      setEditName(data.name);
      setEditDescription(data.description);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load pack');
    } finally {
      setLoading(false);
    }
  }, [packId]);

  const fetchQuestions = useCallback(
    async (filter?: typeof selectedFilter) => {
      if (!pack) return;

      setQuestionsLoading(true);
      try {
        const params: Parameters<typeof getPackQuestions>[1] = { limit: 50 };

        if (filter) {
          if (filter.type === 'domain' && filter.domain) {
            params.domain = filter.domain;
          } else if (filter.type === 'difficulty' && filter.difficulty) {
            params.difficulty = filter.difficulty;
          }
        }

        const data = await getPackQuestions(packId, params);
        setQuestions(data.questions);
        setQuestionsTotal(data.total);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load questions');
      } finally {
        setQuestionsLoading(false);
      }
    },
    [packId, pack]
  );

  useEffect(() => {
    fetchPack();
  }, [fetchPack]);

  useEffect(() => {
    if (selectedFilter) {
      fetchQuestions(selectedFilter);
    }
  }, [selectedFilter, fetchQuestions]);

  const handleSaveName = async () => {
    if (!pack || editName === pack.name) {
      setIsEditingName(false);
      return;
    }
    try {
      await updatePack(packId, { name: editName });
      setPack({ ...pack, name: editName });
      setIsEditingName(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update name');
    }
  };

  const handleSaveDescription = async () => {
    if (!pack || editDescription === pack.description) {
      setIsEditingDescription(false);
      return;
    }
    try {
      await updatePack(packId, { description: editDescription });
      setPack({ ...pack, description: editDescription });
      setIsEditingDescription(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update description');
    }
  };

  const handleRemoveQuestion = async (questionId: string) => {
    if (!confirm('Remove this question from the pack?')) return;
    try {
      await removeQuestionFromPack(packId, questionId);
      setQuestions((prev) => prev.filter((q) => q.id !== questionId));
      setQuestionsTotal((prev) => prev - 1);
      // Refresh pack to update counts
      fetchPack();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to remove question');
    }
  };

  const toggleTopic = (topicKey: string) => {
    setExpandedTopics((prev) => {
      const next = new Set(prev);
      if (next.has(topicKey)) {
        next.delete(topicKey);
      } else {
        next.add(topicKey);
      }
      return next;
    });
  };

  const handleSelectTopic = (domain: DomainId, subcategory?: string) => {
    if (subcategory) {
      setSelectedFilter({ type: 'subcategory', domain, subcategory });
    } else {
      setSelectedFilter({ type: 'domain', domain });
    }
  };

  const handleSelectDifficulty = (difficulty: number) => {
    setSelectedFilter({ type: 'difficulty', difficulty });
  };

  const handleShowAll = () => {
    setSelectedFilter({ type: 'all' });
    fetchQuestions({ type: 'all' });
  };

  // Build topic groups from domain distribution
  const buildTopicGroups = (): TopicGroup[] => {
    if (!pack?.domain_distribution) return [];

    return Object.entries(pack.domain_distribution)
      .filter(([, count]) => count > 0)
      .map(([domain, count]) => ({
        domain: domain as DomainId,
        subcategories: {}, // Would need API support for subcategory breakdown
        total: count,
      }))
      .sort((a, b) => b.total - a.total);
  };

  const topicGroups = buildTopicGroups();

  // Get audio status color
  const getAudioStatusColor = (percent: number) => {
    if (percent >= 90) return 'text-emerald-400';
    if (percent >= 50) return 'text-amber-400';
    return 'text-red-400';
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin w-8 h-8 border-2 border-purple-500 border-t-transparent rounded-full" />
      </div>
    );
  }

  if (error && !pack) {
    return (
      <div className="space-y-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-slate-400 hover:text-slate-200 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to Packs
        </button>
        <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400">
          {error}
        </div>
      </div>
    );
  }

  if (!pack) return null;

  const isSystem = pack.type === 'system';
  const domainCount = Object.keys(pack.domain_distribution || {}).length;

  return (
    <div className="space-y-6">
      {/* Header with back button */}
      <div className="flex items-center gap-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-slate-400 hover:text-slate-200 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back
        </button>
      </div>

      {/* Pack Header */}
      <div className="space-y-4">
        {/* Name (editable) */}
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1">
            {isEditingName ? (
              <input
                type="text"
                value={editName}
                onChange={(e) => setEditName(e.target.value)}
                onBlur={handleSaveName}
                onKeyDown={(e) => e.key === 'Enter' && handleSaveName()}
                autoFocus
                className="text-2xl font-bold bg-slate-800 border border-purple-500 rounded px-2 py-1 text-white w-full focus:outline-none"
              />
            ) : (
              <h1
                className={`text-2xl font-bold text-white ${!isSystem ? 'cursor-pointer hover:text-purple-300' : ''}`}
                onClick={() => !isSystem && setIsEditingName(true)}
              >
                {pack.name}
                {!isSystem && <Edit2 className="w-4 h-4 inline ml-2 opacity-50" />}
              </h1>
            )}
          </div>

          <div className="flex items-center gap-2">
            <Tooltip content="Refresh pack data">
              <button
                onClick={() => fetchPack()}
                className="p-2 text-slate-400 hover:text-slate-200 transition-colors"
              >
                <RefreshCw className="w-4 h-4" />
              </button>
            </Tooltip>
            <Tooltip content="Export questions to CSV or JSON">
              <button className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors">
                <Download className="w-4 h-4" />
                Export
              </button>
            </Tooltip>
          </div>
        </div>

        {/* Description (editable) */}
        {isEditingDescription ? (
          <textarea
            value={editDescription}
            onChange={(e) => setEditDescription(e.target.value)}
            onBlur={handleSaveDescription}
            autoFocus
            rows={2}
            className="w-full bg-slate-800 border border-purple-500 rounded px-3 py-2 text-slate-300 focus:outline-none resize-none"
          />
        ) : (
          <p
            className={`text-slate-400 ${!isSystem ? 'cursor-pointer hover:text-slate-300' : ''}`}
            onClick={() => !isSystem && setIsEditingDescription(true)}
          >
            {pack.description || 'No description'}
            {!isSystem && <Edit2 className="w-3 h-3 inline ml-1 opacity-50" />}
          </p>
        )}

        {/* Stats Row */}
        <div className="flex flex-wrap gap-4">
          <Tooltip content="Total number of questions in this pack">
            <div className="bg-slate-800 rounded-lg px-4 py-3 text-center min-w-[100px]">
              <div className="text-2xl font-bold text-white">{pack.question_count}</div>
              <div className="text-xs text-slate-400">Questions</div>
            </div>
          </Tooltip>
          <Tooltip content="Number of different subject domains covered">
            <div className="bg-slate-800 rounded-lg px-4 py-3 text-center min-w-[100px]">
              <div className="text-2xl font-bold text-white">{domainCount}</div>
              <div className="text-xs text-slate-400">Domains</div>
            </div>
          </Tooltip>
          <Tooltip content="Competition level this pack is designed for">
            <div className="bg-slate-800 rounded-lg px-4 py-3 text-center min-w-[100px]">
              <div className="text-2xl font-bold text-white">
                {TIER_LABELS[pack.difficulty_tier]}
              </div>
              <div className="text-xs text-slate-400">Level</div>
            </div>
          </Tooltip>
          <Tooltip
            content={`${pack.audio_coverage_percent}% of questions have pre-generated audio. ${pack.missing_audio_count > 0 ? `${pack.missing_audio_count} need audio.` : ''}`}
          >
            <div className="bg-slate-800 rounded-lg px-4 py-3 text-center min-w-[100px]">
              <div
                className={`text-2xl font-bold ${getAudioStatusColor(pack.audio_coverage_percent)}`}
              >
                {pack.audio_coverage_percent}%
              </div>
              <div className="text-xs text-slate-400">Audio</div>
            </div>
          </Tooltip>
          {pack.competition_year && (
            <Tooltip content="Academic year or competition season">
              <div className="bg-slate-800 rounded-lg px-4 py-3 text-center min-w-[100px]">
                <div className="text-2xl font-bold text-white">{pack.competition_year}</div>
                <div className="text-xs text-slate-400">Season</div>
              </div>
            </Tooltip>
          )}
        </div>

        {/* Error display */}
        {error && (
          <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400">
            {error}
          </div>
        )}
      </div>

      {/* View Mode Tabs */}
      <div className="border-b border-slate-800">
        <div className="flex gap-1">
          {[
            { id: 'by-topic', label: 'By Topic' },
            { id: 'by-difficulty', label: 'By Difficulty' },
            { id: 'all', label: 'All Questions' },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => {
                setViewMode(tab.id as ViewMode);
                setSelectedFilter(null);
              }}
              className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                viewMode === tab.id
                  ? 'border-purple-500 text-purple-400'
                  : 'border-transparent text-slate-400 hover:text-slate-200'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Action Bar */}
      {!isSystem && (
        <div className="flex flex-wrap gap-2">
          <Tooltip content="Add new questions manually, import from CSV, or copy from another pack">
            <button
              onClick={onAddQuestions}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors"
            >
              <Plus className="w-4 h-4" />
              Add Questions
            </button>
          </Tooltip>
          <Tooltip content="Combine this pack with others into a new bundle">
            <button
              onClick={onBundlePacks}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
            >
              <Layers className="w-4 h-4" />
              Bundle Packs
            </button>
          </Tooltip>
          <Tooltip content="Edit multiple questions at once (difficulty, domain, etc.)">
            <button className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors">
              <Settings className="w-4 h-4" />
              Bulk Edit
            </button>
          </Tooltip>
          {pack.missing_audio_count > 0 && (
            <Tooltip content="Generate audio files for questions missing audio using Voice Lab">
              <button
                onClick={onGenerateAudio}
                className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-amber-300 bg-amber-500/20 hover:bg-amber-500/30 rounded-md transition-colors border border-amber-500/30"
              >
                <Wand2 className="w-4 h-4" />
                Generate Audio ({pack.missing_audio_count})
              </button>
            </Tooltip>
          )}
        </div>
      )}

      {/* Content based on view mode */}
      {viewMode === 'by-topic' && !selectedFilter && (
        <div className="space-y-2">
          {topicGroups.length === 0 ? (
            <Card className="bg-slate-900/50 border-slate-800">
              <CardContent className="py-8 text-center text-slate-400">
                No questions in this pack yet
              </CardContent>
            </Card>
          ) : (
            topicGroups.map((group) => (
              <div
                key={group.domain}
                className="bg-slate-900/50 border border-slate-800 rounded-lg overflow-hidden"
              >
                <button
                  onClick={() => toggleTopic(group.domain)}
                  className="w-full flex items-center justify-between px-4 py-3 hover:bg-slate-800/50 transition-colors"
                >
                  <div className="flex items-center gap-3">
                    {expandedTopics.has(group.domain) ? (
                      <ChevronDown className="w-4 h-4 text-slate-400" />
                    ) : (
                      <ChevronRight className="w-4 h-4 text-slate-400" />
                    )}
                    <span className="font-medium text-slate-200">
                      {DOMAIN_LABELS[group.domain] || group.domain}
                    </span>
                  </div>
                  <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                    {group.total} questions
                  </Badge>
                </button>

                {expandedTopics.has(group.domain) && (
                  <div className="border-t border-slate-800 px-4 py-2">
                    <button
                      onClick={() => handleSelectTopic(group.domain)}
                      className="flex items-center gap-2 w-full px-3 py-2 text-sm text-slate-300 hover:bg-slate-800 rounded transition-colors"
                    >
                      <FileText className="w-4 h-4" />
                      View all {DOMAIN_LABELS[group.domain]} questions ({group.total})
                    </button>
                  </div>
                )}
              </div>
            ))
          )}
        </div>
      )}

      {viewMode === 'by-difficulty' && !selectedFilter && (
        <div className="grid grid-cols-1 sm:grid-cols-3 md:grid-cols-5 gap-4">
          {[1, 2, 3, 4, 5].map((level) => {
            const count = pack.difficulty_distribution?.[level as 1 | 2 | 3 | 4 | 5] || 0;
            return (
              <button
                key={level}
                onClick={() => count > 0 && handleSelectDifficulty(level)}
                disabled={count === 0}
                className={`bg-slate-900/50 border border-slate-800 rounded-lg p-4 text-center transition-colors ${
                  count > 0
                    ? 'hover:border-purple-500 cursor-pointer'
                    : 'opacity-50 cursor-not-allowed'
                }`}
              >
                <div className="text-2xl font-bold text-white mb-1">Level {level}</div>
                <div className="text-slate-400">{count} questions</div>
              </button>
            );
          })}
        </div>
      )}

      {viewMode === 'all' && !selectedFilter && (
        <button
          onClick={handleShowAll}
          className="w-full bg-slate-900/50 border border-slate-800 rounded-lg p-4 text-center hover:border-purple-500 transition-colors"
        >
          <FileText className="w-8 h-8 text-slate-400 mx-auto mb-2" />
          <div className="text-slate-200">View all {pack.question_count} questions</div>
        </button>
      )}

      {/* Question Browser (when a filter is selected) */}
      {selectedFilter && (
        <QuestionBrowser
          questions={questions}
          total={questionsTotal}
          loading={questionsLoading}
          filterLabel={
            selectedFilter.type === 'domain'
              ? DOMAIN_LABELS[selectedFilter.domain!]
              : selectedFilter.type === 'difficulty'
                ? `Level ${selectedFilter.difficulty}`
                : 'All Questions'
          }
          packQuestionCount={pack.question_count}
          isSystemPack={isSystem}
          onClose={() => setSelectedFilter(null)}
          onRemove={handleRemoveQuestion}
          onLoadMore={() => {
            // Would implement pagination here
          }}
        />
      )}
    </div>
  );
}
