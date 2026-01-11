'use client';

import { useState, useEffect, useCallback } from 'react';
import { useQueryState, parseAsString, parseAsBoolean } from 'nuqs';
import { BookOpen, Search, Archive, Trash2, RefreshCw, Eye, Plus, SearchCheck, Loader2 } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { CurriculumDetailPanel } from './curriculum-detail-panel';
import type { CurriculumSummary, CurriculaResponse, CurriculumAnalysis, ReprocessConfig } from '@/types';
import { CurriculumStudio } from '@/components/curriculum/CurriculumEditor';
import { Curriculum } from '@/types/curriculum';
import { useMainScrollRestoration } from '@/hooks/useScrollRestoration';
import { CurriculumAnalysisModal } from './curriculum-analysis-modal';

// API functions for curricula
async function getCurricula(params?: {
  search?: string;
  archived?: boolean;
}): Promise<CurriculaResponse> {
  const queryParams = new URLSearchParams();
  if (params?.search) queryParams.set('search', params.search);
  if (params?.archived) queryParams.set('archived', 'true');

  const query = queryParams.toString();
  const response = await fetch(`/api/curricula${query ? `?${query}` : ''}`);

  if (!response.ok) {
    throw new Error('Failed to fetch curricula');
  }

  return response.json();
}

async function reloadCurricula(): Promise<void> {
  const response = await fetch('/api/curricula/reload', { method: 'POST' });
  if (!response.ok) {
    throw new Error('Failed to reload curricula');
  }
}

async function archiveCurriculum(id: string): Promise<void> {
  const response = await fetch(`/api/curricula/${id}/archive`, { method: 'POST' });
  if (!response.ok) {
    throw new Error('Failed to archive curriculum');
  }
}

async function deleteCurriculum(id: string): Promise<void> {
  const response = await fetch(`/api/curricula/${id}?confirm=true`, { method: 'DELETE' });
  if (!response.ok) {
    throw new Error('Failed to delete curriculum');
  }
}

async function analyzeCurriculum(id: string): Promise<CurriculumAnalysis> {
  const response = await fetch(`/api/reprocess/analyze/${id}`, { method: 'POST' });
  if (!response.ok) {
    throw new Error('Failed to analyze curriculum');
  }
  const data = await response.json();
  return data.analysis;
}

async function startReprocess(config: ReprocessConfig): Promise<void> {
  const response = await fetch('/api/reprocess/jobs', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });
  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    throw new Error(data.error || 'Failed to start reprocessing');
  }
}

export function CurriculaPanel() {
  const [curricula, setCurricula] = useState<CurriculumSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // URL-synced state using nuqs for persistence across refreshes
  const [searchQuery, setSearchQuery] = useQueryState('search', parseAsString.withDefault(''));
  const [showArchived, setShowArchived] = useQueryState(
    'archived',
    parseAsBoolean.withDefault(false)
  );
  const [selectedCurriculumId, setSelectedCurriculumId] = useQueryState(
    'curriculum',
    parseAsString
  );

  const [isCreating, setIsCreating] = useState(false);

  // Analysis modal state
  const [analyzingId, setAnalyzingId] = useState<string | null>(null);
  const [analysisResult, setAnalysisResult] = useState<{
    curriculumId: string;
    curriculumName: string;
    analysis: CurriculumAnalysis;
  } | null>(null);

  // Scroll restoration for the curricula panel (saves/restores main scroll position)
  useMainScrollRestoration('curricula-panel');

  const fetchCurricula = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getCurricula({
        search: searchQuery || undefined,
        archived: showArchived || undefined,
      });
      setCurricula(data.curricula);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load curricula');
    } finally {
      setLoading(false);
    }
  }, [searchQuery, showArchived]);

  useEffect(() => {
    fetchCurricula();
  }, [fetchCurricula]);

  // If creating new, show studio
  if (isCreating) {
    const newCurriculum: Curriculum = {
      umcf: '1.0.0',
      id: { value: crypto.randomUUID() },
      title: 'New Curriculum',
      version: { number: '0.1.0' },
      content: [
        {
          id: { value: 'unit-1' },
          title: 'Unit 1',
          type: 'unit',
          children: [],
        },
      ],
    };

    return (
      <CurriculumStudio
        initialData={newCurriculum}
        onSave={async (data) => {
          const curriculumId = data.id?.value || crypto.randomUUID();
          try {
            const response = await fetch(`/api/curricula/${curriculumId}`, {
              method: 'PUT',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(data),
            });
            if (!response.ok) {
              const errorData = await response.json().catch(() => ({}));
              throw new Error(errorData.error || `Failed to save curriculum: ${response.status}`);
            }
            setIsCreating(false);
            fetchCurricula();
          } catch (err) {
            console.error('Failed to save curriculum:', err);
            setError(err instanceof Error ? err.message : 'Failed to save curriculum');
          }
        }}
        onBack={() => setIsCreating(false)}
      />
    );
  }

  // If a curriculum is selected, show the detail panel
  if (selectedCurriculumId) {
    return (
      <CurriculumDetailPanel
        curriculumId={selectedCurriculumId}
        onBack={() => setSelectedCurriculumId(null)}
      />
    );
  }

  const handleReload = async () => {
    try {
      await reloadCurricula();
      await fetchCurricula();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to reload');
    }
  };

  const handleArchive = async (id: string) => {
    try {
      await archiveCurriculum(id);
      await fetchCurricula();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to archive');
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this curriculum? This cannot be undone.')) {
      return;
    }
    try {
      await deleteCurriculum(id);
      await fetchCurricula();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete');
    }
  };

  const handleAnalyze = async (curriculum: CurriculumSummary) => {
    setAnalyzingId(curriculum.id);
    setError(null);
    try {
      const analysis = await analyzeCurriculum(curriculum.id);
      setAnalysisResult({
        curriculumId: curriculum.id,
        curriculumName: curriculum.title,
        analysis,
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to analyze');
    } finally {
      setAnalyzingId(null);
    }
  };

  const handleStartReprocess = async (config: ReprocessConfig) => {
    await startReprocess(config);
    setAnalysisResult(null);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">
            <BookOpen className="w-6 h-6 text-orange-400" />
            Curricula
          </h2>
          <p className="text-slate-400 mt-1">Manage your curriculum library</p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsCreating(true)}
            className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-md transition-colors shadow-lg shadow-indigo-500/20"
          >
            <Plus className="w-4 h-4" />
            Create New
          </button>
          <button
            onClick={handleReload}
            className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
          >
            <RefreshCw className="w-4 h-4" />
            Reload
          </button>
        </div>
      </div>

      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
          <input
            type="text"
            placeholder="Search curricula..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-orange-500/50 focus:border-orange-500"
          />
        </div>

        <button
          onClick={() => setShowArchived(!showArchived)}
          className={`flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-md transition-colors ${
            showArchived
              ? 'bg-orange-500/20 text-orange-300 border border-orange-500/30'
              : 'text-slate-400 bg-slate-800 hover:bg-slate-700 border border-slate-700'
          }`}
        >
          <Archive className="w-4 h-4" />
          {showArchived ? 'Showing Archived' : 'Show Archived'}
        </button>
      </div>

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400">
          {error}
        </div>
      )}

      {/* Curricula Grid */}
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin w-8 h-8 border-2 border-orange-500 border-t-transparent rounded-full" />
        </div>
      ) : curricula.length === 0 ? (
        <Card className="bg-slate-900/50 border-slate-800">
          <CardContent className="flex flex-col items-center justify-center py-12 text-center">
            <BookOpen className="w-12 h-12 text-slate-600 mb-4" />
            <h3 className="text-lg font-medium text-slate-300 mb-2">No curricula found</h3>
            <p className="text-slate-500 max-w-md">
              {searchQuery
                ? 'Try adjusting your search query'
                : 'Import curricula from the Sources tab to get started'}
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {curricula.map((curriculum) => (
            <Card
              key={curriculum.id}
              className="bg-slate-900/50 border-slate-800 hover:border-slate-700 transition-colors cursor-pointer"
              onClick={() => setSelectedCurriculumId(curriculum.id)}
            >
              <CardHeader className="pb-2">
                <div className="flex items-start justify-between gap-2">
                  <CardTitle className="text-lg font-medium text-slate-100 line-clamp-2">
                    {curriculum.title}
                  </CardTitle>
                  {curriculum.status && (
                    <Badge
                      className={
                        curriculum.status === 'final'
                          ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                          : curriculum.status === 'draft'
                            ? 'bg-amber-500/20 text-amber-400 border-amber-500/30'
                            : 'bg-slate-500/20 text-slate-400 border-slate-500/30'
                      }
                    >
                      {curriculum.status}
                    </Badge>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-slate-400 line-clamp-2 mb-4">
                  {curriculum.description || 'No description'}
                </p>

                <div className="flex flex-wrap gap-2 mb-4">
                  <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                    {curriculum.topicCount} topics
                  </Badge>
                  {curriculum.difficulty && (
                    <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                      {curriculum.difficulty}
                    </Badge>
                  )}
                  {curriculum.hasVisualAssets && (
                    <Badge className="bg-violet-500/20 text-violet-400 border-violet-500/30">
                      {curriculum.visualAssetCount} assets
                    </Badge>
                  )}
                </div>

                <div className="flex items-center justify-between pt-2 border-t border-slate-800">
                  <div className="flex items-center gap-2">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setSelectedCurriculumId(curriculum.id);
                      }}
                      className="flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200 transition-colors"
                    >
                      <Eye className="w-4 h-4" />
                      View
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleAnalyze(curriculum);
                      }}
                      disabled={analyzingId === curriculum.id}
                      className="flex items-center gap-1.5 text-sm text-slate-400 hover:text-indigo-400 transition-colors disabled:opacity-50"
                      title="Analyze for issues"
                    >
                      {analyzingId === curriculum.id ? (
                        <Loader2 className="w-4 h-4 animate-spin" />
                      ) : (
                        <SearchCheck className="w-4 h-4" />
                      )}
                      Analyze
                    </button>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleArchive(curriculum.id);
                      }}
                      className="p-1.5 text-slate-400 hover:text-amber-400 transition-colors"
                      title="Archive"
                    >
                      <Archive className="w-4 h-4" />
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDelete(curriculum.id);
                      }}
                      className="p-1.5 text-slate-400 hover:text-red-400 transition-colors"
                      title="Delete"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Analysis Modal */}
      {analysisResult && (
        <CurriculumAnalysisModal
          curriculumId={analysisResult.curriculumId}
          curriculumName={analysisResult.curriculumName}
          analysis={analysisResult.analysis}
          onClose={() => setAnalysisResult(null)}
          onStartReprocess={handleStartReprocess}
        />
      )}
    </div>
  );
}
