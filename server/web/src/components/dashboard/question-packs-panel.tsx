'use client';

import { useState, useEffect, useCallback } from 'react';
import { useQueryState, parseAsString } from 'nuqs';
import {
  Package,
  Search,
  Archive,
  Trash2,
  RefreshCw,
  Eye,
  Plus,
  Copy,
  Layers,
  Lock,
  Volume2,
  Filter,
} from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tooltip } from '@/components/ui/tooltip';
import { HelpButton } from '@/components/ui/help-button';
import { useMainScrollRestoration } from '@/hooks/useScrollRestoration';
import type { QuestionPack, PackType, DifficultyTier, EntityStatus } from '@/types/question-packs';

// API response type
interface PacksResponse {
  success: boolean;
  packs: QuestionPack[];
  total: number;
  error?: string;
}

// Filter types
type FilterStatus = EntityStatus | 'all';
type FilterType = PackType | 'all';

// Difficulty tier display names
const TIER_LABELS: Record<DifficultyTier, string> = {
  elementary: 'Elementary',
  middle_school: 'Middle School',
  jv: 'JV',
  varsity: 'Varsity',
  championship: 'Championship',
  college: 'College',
};

// Pack type styling
const PACK_TYPE_STYLES: Record<PackType, { bg: string; text: string; border: string }> = {
  system: {
    bg: 'bg-blue-500/20',
    text: 'text-blue-400',
    border: 'border-blue-500/30',
  },
  custom: {
    bg: 'bg-purple-500/20',
    text: 'text-purple-400',
    border: 'border-purple-500/30',
  },
  bundle: {
    bg: 'bg-orange-500/20',
    text: 'text-orange-400',
    border: 'border-orange-500/30',
  },
};

// Help sections for Question Packs
export const questionPacksHelpSections = [
  {
    title: 'What are Question Packs?',
    content: (
      <div className="space-y-2">
        <p>
          Question Packs are organized collections of Knowledge Bowl questions designed for
          competition preparation and practice. They help you group related questions by topic,
          difficulty level, or competition format.
        </p>
        <p className="text-slate-400">
          Packs make it easy to run focused practice sessions and track audio generation progress.
        </p>
      </div>
    ),
  },
  {
    title: 'Pack Types',
    content: (
      <div className="space-y-3">
        <p>There are three types of packs:</p>
        <ul className="space-y-2 text-slate-400">
          <li>
            <span className="text-purple-400 font-medium">Custom Packs:</span> Created by you for
            your specific needs. Fully editable.
          </li>
          <li>
            <span className="text-orange-400 font-medium">Bundle Packs:</span> Combine multiple
            packs into one larger collection with deduplication.
          </li>
          <li>
            <span className="text-blue-400 font-medium">System Packs:</span> Pre-built packs from
            imported content. Read-only, can be duplicated.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Difficulty Tiers',
    content: (
      <div className="space-y-3">
        <p>Packs are organized by competition level to match your students:</p>
        <ul className="space-y-1 text-slate-400">
          <li>
            <span className="text-slate-300">Elementary:</span> Grades 3-5
          </li>
          <li>
            <span className="text-slate-300">Middle School:</span> Grades 6-8
          </li>
          <li>
            <span className="text-slate-300">JV (Junior Varsity):</span> Grades 9-10
          </li>
          <li>
            <span className="text-slate-300">Varsity:</span> Grades 11-12
          </li>
          <li>
            <span className="text-slate-300">Championship:</span> State/national competitions
          </li>
          <li>
            <span className="text-slate-300">College:</span> Undergraduate level
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Creating Packs',
    content: (
      <div className="space-y-3">
        <p>You can create new packs in three ways:</p>
        <ol className="list-decimal list-inside space-y-2 text-slate-400">
          <li>
            <span className="text-slate-300">Create Pack:</span> Start with an empty pack and add
            questions manually or import from CSV
          </li>
          <li>
            <span className="text-slate-300">Bundle Packs:</span> Select existing packs to combine
            into a new bundle
          </li>
          <li>
            <span className="text-slate-300">Duplicate:</span> Copy an existing pack to customize
            for a specific purpose
          </li>
        </ol>
      </div>
    ),
  },
  {
    title: 'Audio Coverage',
    content: (
      <div className="space-y-2">
        <p>
          The audio percentage shows how many questions have pre-generated audio files. Higher
          coverage means faster, more consistent practice sessions.
        </p>
        <ul className="space-y-1 text-slate-400 mt-2">
          <li>
            <span className="text-emerald-400">90%+:</span> Excellent coverage
          </li>
          <li>
            <span className="text-amber-400">50-89%:</span> Partial coverage, some on-demand
            generation
          </li>
          <li>
            <span className="text-red-400">&lt;50%:</span> Low coverage, consider batch generation
          </li>
        </ul>
        <p className="text-slate-400 mt-2">
          Use the Voice Lab to generate missing audio files in bulk.
        </p>
      </div>
    ),
  },
  {
    title: 'Managing Questions',
    content: (
      <div className="space-y-2">
        <p>
          Click on a pack to view its questions organized by topic or difficulty. From the pack
          detail view you can:
        </p>
        <ul className="list-disc list-inside space-y-1 text-slate-400 mt-2">
          <li>Browse questions by domain or difficulty level</li>
          <li>Add new questions individually or import from CSV</li>
          <li>Edit question text, answers, and metadata</li>
          <li>Bulk select and modify multiple questions</li>
          <li>Remove questions from the pack</li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Tips & Best Practices',
    content: (
      <ul className="list-disc list-inside space-y-2 text-slate-400">
        <li>Use clear, descriptive names that indicate pack purpose and competition level</li>
        <li>Create separate packs for different subject areas or competition rounds</li>
        <li>Use bundles to combine packs for comprehensive review sessions</li>
        <li>Generate audio before practice sessions to ensure smooth playback</li>
        <li>Archive old competition packs instead of deleting to preserve history</li>
      </ul>
    ),
  },
];

// API functions
async function getPacks(params?: {
  search?: string;
  status?: FilterStatus;
  type?: FilterType;
}): Promise<PacksResponse> {
  const queryParams = new URLSearchParams();
  if (params?.search) queryParams.set('search', params.search);
  if (params?.status && params.status !== 'all') queryParams.set('status', params.status);
  if (params?.type && params.type !== 'all') queryParams.set('type', params.type);

  const query = queryParams.toString();
  const response = await fetch(`/api/kb/packs${query ? `?${query}` : ''}`);

  if (!response.ok) {
    throw new Error('Failed to fetch packs');
  }

  return response.json();
}

async function duplicatePack(packId: string): Promise<{ success: boolean; pack?: QuestionPack }> {
  const response = await fetch(`/api/kb/packs/${packId}/duplicate`, { method: 'POST' });
  if (!response.ok) {
    throw new Error('Failed to duplicate pack');
  }
  return response.json();
}

async function archivePack(packId: string): Promise<void> {
  const response = await fetch(`/api/kb/packs/${packId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'archived' }),
  });
  if (!response.ok) {
    throw new Error('Failed to archive pack');
  }
}

async function deletePack(packId: string): Promise<void> {
  const response = await fetch(`/api/kb/packs/${packId}`, { method: 'DELETE' });
  if (!response.ok) {
    throw new Error('Failed to delete pack');
  }
}

interface QuestionPacksPanelProps {
  onSelectPack?: (packId: string) => void;
  onCreatePack?: () => void;
  onCreateBundle?: () => void;
}

export function QuestionPacksPanel({
  onSelectPack,
  onCreatePack,
  onCreateBundle,
}: QuestionPacksPanelProps) {
  const [packs, setPacks] = useState<QuestionPack[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // URL-synced state
  const [searchQuery, setSearchQuery] = useQueryState('search', parseAsString.withDefault(''));
  const [filterStatus, setFilterStatus] = useQueryState(
    'status',
    parseAsString.withDefault('active')
  );
  const [filterType, setFilterType] = useQueryState('type', parseAsString.withDefault('all'));

  // Scroll restoration
  useMainScrollRestoration('question-packs-panel');

  const fetchPacks = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getPacks({
        search: searchQuery || undefined,
        status: (filterStatus as FilterStatus) || undefined,
        type: (filterType as FilterType) || undefined,
      });
      setPacks(data.packs);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load packs');
    } finally {
      setLoading(false);
    }
  }, [searchQuery, filterStatus, filterType]);

  useEffect(() => {
    fetchPacks();
  }, [fetchPacks]);

  const handleDuplicate = async (packId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await duplicatePack(packId);
      await fetchPacks();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to duplicate');
    }
  };

  const handleArchive = async (packId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await archivePack(packId);
      await fetchPacks();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to archive');
    }
  };

  const handleDelete = async (packId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm('Are you sure you want to delete this pack? This cannot be undone.')) {
      return;
    }
    try {
      await deletePack(packId);
      await fetchPacks();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete');
    }
  };

  const handleSelectPack = (packId: string) => {
    if (onSelectPack) {
      onSelectPack(packId);
    }
  };

  // Get audio status color
  const getAudioStatusColor = (percent: number) => {
    if (percent >= 90) return 'text-emerald-400';
    if (percent >= 50) return 'text-amber-400';
    return 'text-red-400';
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">
            <Package className="w-6 h-6 text-purple-400" />
            Question Packs
            <HelpButton
              title="Question Packs Help"
              description="Learn how to organize and manage Knowledge Bowl questions"
              sections={questionPacksHelpSections}
            />
          </h2>
          <p className="text-slate-400 mt-1">Manage Knowledge Bowl question packs and bundles</p>
        </div>

        <div className="flex items-center gap-2">
          <Tooltip content="Create a new empty pack to add questions to">
            <button
              onClick={onCreatePack}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors shadow-lg shadow-purple-500/20"
            >
              <Plus className="w-4 h-4" />
              Create Pack
            </button>
          </Tooltip>
          <Tooltip content="Combine multiple existing packs into one bundle">
            <button
              onClick={onCreateBundle}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors border border-slate-700"
            >
              <Layers className="w-4 h-4" />
              Bundle Packs
            </button>
          </Tooltip>
          <Tooltip content="Refresh pack list">
            <button
              onClick={() => fetchPacks()}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
          </Tooltip>
        </div>
      </div>

      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
          <input
            type="text"
            placeholder="Search packs..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50 focus:border-purple-500"
          />
        </div>

        <div className="flex items-center gap-2">
          <Tooltip content="Filter packs by their status (active, draft, or archived)">
            <div className="flex items-center gap-1">
              <Filter className="w-4 h-4 text-slate-400" />
              <select
                value={filterStatus}
                onChange={(e) => setFilterStatus(e.target.value)}
                className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 text-sm focus:outline-none focus:ring-2 focus:ring-purple-500/50"
              >
                <option value="active">Active</option>
                <option value="draft">Draft</option>
                <option value="archived">Archived</option>
                <option value="all">All Status</option>
              </select>
            </div>
          </Tooltip>

          <Tooltip content="Filter by pack type: Custom (your packs), Bundle (combined), System (imported)">
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
              className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-300 text-sm focus:outline-none focus:ring-2 focus:ring-purple-500/50"
            >
              <option value="all">All Types</option>
              <option value="custom">Custom</option>
              <option value="bundle">Bundle</option>
              <option value="system">System</option>
            </select>
          </Tooltip>
        </div>
      </div>

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400">
          {error}
        </div>
      )}

      {/* Packs Grid */}
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin w-8 h-8 border-2 border-purple-500 border-t-transparent rounded-full" />
        </div>
      ) : packs.length === 0 ? (
        <Card className="bg-slate-900/50 border-slate-800">
          <CardContent className="flex flex-col items-center justify-center py-12 text-center">
            <Package className="w-12 h-12 text-slate-600 mb-4" />
            <h3 className="text-lg font-medium text-slate-300 mb-2">No packs found</h3>
            <p className="text-slate-500 max-w-md">
              {searchQuery
                ? 'Try adjusting your search or filters'
                : 'Create a new pack to organize your Knowledge Bowl questions'}
            </p>
            {!searchQuery && (
              <button
                onClick={onCreatePack}
                className="mt-4 flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors"
              >
                <Plus className="w-4 h-4" />
                Create Your First Pack
              </button>
            )}
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {packs.map((pack) => {
            const typeStyle = PACK_TYPE_STYLES[pack.type];
            const isSystem = pack.type === 'system';
            const domainCount = Object.keys(pack.domain_distribution || {}).length;

            return (
              <Card
                key={pack.id}
                className="bg-slate-900/50 border-slate-800 hover:border-slate-700 transition-colors cursor-pointer"
                onClick={() => handleSelectPack(pack.id)}
              >
                <CardHeader className="pb-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2">
                      {isSystem && <Lock className="w-4 h-4 text-blue-400" />}
                      {pack.type === 'bundle' && <Layers className="w-4 h-4 text-orange-400" />}
                      <CardTitle className="text-lg font-medium text-slate-100 line-clamp-1">
                        {pack.name}
                      </CardTitle>
                    </div>
                    <Badge className={`${typeStyle.bg} ${typeStyle.text} ${typeStyle.border}`}>
                      {pack.type}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-slate-400 line-clamp-2 mb-4 min-h-[2.5rem]">
                    {pack.description || 'No description'}
                  </p>

                  {/* Stats Row 1 */}
                  <div className="flex flex-wrap gap-2 mb-2">
                    <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                      {pack.question_count} Qs
                    </Badge>
                    <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                      {domainCount} Domains
                    </Badge>
                    <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                      {TIER_LABELS[pack.difficulty_tier]}
                    </Badge>
                  </div>

                  {/* Stats Row 2 */}
                  <div className="flex flex-wrap gap-2 mb-4">
                    <Tooltip
                      content={`${pack.audio_coverage_percent}% of questions have pre-generated audio. ${pack.missing_audio_count > 0 ? `${pack.missing_audio_count} questions need audio.` : 'All questions have audio!'}`}
                      side="bottom"
                    >
                      <Badge
                        className={`bg-slate-700/50 border-slate-600 flex items-center gap-1 ${getAudioStatusColor(pack.audio_coverage_percent)}`}
                      >
                        <Volume2 className="w-3 h-3" />
                        {pack.audio_coverage_percent}%
                      </Badge>
                    </Tooltip>
                    {pack.competition_year && (
                      <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                        {pack.competition_year}
                      </Badge>
                    )}
                    {pack.status !== 'active' && (
                      <Badge
                        className={
                          pack.status === 'draft'
                            ? 'bg-amber-500/20 text-amber-400 border-amber-500/30'
                            : 'bg-slate-500/20 text-slate-400 border-slate-500/30'
                        }
                      >
                        {pack.status}
                      </Badge>
                    )}
                  </div>

                  {/* Actions */}
                  <div className="flex items-center justify-between pt-2 border-t border-slate-800">
                    <div className="flex items-center gap-2">
                      <Tooltip content="View questions and details" side="bottom">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleSelectPack(pack.id);
                          }}
                          className="flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200 transition-colors"
                        >
                          <Eye className="w-4 h-4" />
                          View
                        </button>
                      </Tooltip>
                      {!isSystem && (
                        <Tooltip content="Create an editable copy of this pack" side="bottom">
                          <button
                            onClick={(e) => handleDuplicate(pack.id, e)}
                            className="flex items-center gap-1.5 text-sm text-slate-400 hover:text-purple-400 transition-colors"
                          >
                            <Copy className="w-4 h-4" />
                            Duplicate
                          </button>
                        </Tooltip>
                      )}
                    </div>

                    {!isSystem && (
                      <div className="flex items-center gap-2">
                        <Tooltip content="Archive this pack (can be restored later)" side="bottom">
                          <button
                            onClick={(e) => handleArchive(pack.id, e)}
                            className="p-1.5 text-slate-400 hover:text-amber-400 transition-colors"
                          >
                            <Archive className="w-4 h-4" />
                          </button>
                        </Tooltip>
                        <Tooltip content="Permanently delete this pack" side="bottom">
                          <button
                            onClick={(e) => handleDelete(pack.id, e)}
                            className="p-1.5 text-slate-400 hover:text-red-400 transition-colors"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </Tooltip>
                      </div>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
