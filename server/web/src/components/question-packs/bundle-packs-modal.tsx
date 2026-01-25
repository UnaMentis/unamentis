'use client';

import { useState, useEffect } from 'react';
import {
  X,
  ChevronLeft,
  ChevronRight,
  Loader2,
  AlertCircle,
  AlertTriangle,
  Check,
  Layers,
  Package,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import type { QuestionPack, DifficultyTier } from '@/types/question-packs';

// Local type for dedup preview (simplified from API response)
interface DedupPreview {
  duplicate_count: number;
  unique_count: number;
  total_count: number;
}

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
async function getAvailablePacks(): Promise<QuestionPack[]> {
  const response = await fetch('/api/kb/packs?status=active');
  if (!response.ok) {
    throw new Error('Failed to fetch packs');
  }
  const data = await response.json();
  return data.packs;
}

async function previewDedup(packIds: string[]): Promise<DedupPreview> {
  const response = await fetch('/api/kb/packs/preview-dedup', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pack_ids: packIds }),
  });
  if (!response.ok) {
    throw new Error('Failed to preview deduplication');
  }
  return response.json();
}

async function createBundle(input: {
  name: string;
  description: string;
  source_pack_ids: string[];
  is_reference_bundle: boolean;
  dedup_strategy: 'keep_all' | 'keep_first';
  difficulty_tier: DifficultyTier;
}): Promise<QuestionPack> {
  const response = await fetch('/api/kb/packs/bundle', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.error || 'Failed to create bundle');
  }
  const data = await response.json();
  return data.pack;
}

interface BundlePacksModalProps {
  onClose: () => void;
  onSuccess: (packId: string) => void;
  preselectedPackId?: string;
}

type Step = 'select' | 'dedup' | 'settings';

export function BundlePacksModal({ onClose, onSuccess, preselectedPackId }: BundlePacksModalProps) {
  const [step, setStep] = useState<Step>('select');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Packs selection
  const [availablePacks, setAvailablePacks] = useState<QuestionPack[]>([]);
  const [selectedPackIds, setSelectedPackIds] = useState<Set<string>>(
    preselectedPackId ? new Set([preselectedPackId]) : new Set()
  );
  const [packsLoading, setPacksLoading] = useState(true);

  // Dedup preview
  const [dedupPreview, setDedupPreview] = useState<DedupPreview | null>(null);
  const [dedupStrategy, setDedupStrategy] = useState<'keep_all' | 'keep_first'>('keep_first');

  // Bundle settings
  const [bundleName, setBundleName] = useState('');
  const [bundleDescription, setBundleDescription] = useState('');
  const [isReferenceBundle, setIsReferenceBundle] = useState(false);
  const [difficultyTier, setDifficultyTier] = useState<DifficultyTier>('varsity');

  // Load available packs
  useEffect(() => {
    const loadPacks = async () => {
      setPacksLoading(true);
      try {
        const packs = await getAvailablePacks();
        setAvailablePacks(packs);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load packs');
      } finally {
        setPacksLoading(false);
      }
    };
    loadPacks();
  }, []);

  const togglePack = (packId: string) => {
    setSelectedPackIds((prev) => {
      const next = new Set(prev);
      if (next.has(packId)) {
        next.delete(packId);
      } else {
        next.add(packId);
      }
      return next;
    });
  };

  const selectedPacks = availablePacks.filter((p) => selectedPackIds.has(p.id));
  const totalQuestions = selectedPacks.reduce((sum, p) => sum + p.question_count, 0);

  const handleNextFromSelect = async () => {
    if (selectedPackIds.size < 2) {
      setError('Please select at least 2 packs to bundle');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const preview = await previewDedup(Array.from(selectedPackIds));
      setDedupPreview(preview);
      setStep('dedup');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to preview');
    } finally {
      setLoading(false);
    }
  };

  const handleNextFromDedup = () => {
    // Generate default bundle name
    if (!bundleName) {
      const packNames = selectedPacks.map((p) => p.name).slice(0, 2);
      const suffix = selectedPacks.length > 2 ? ` + ${selectedPacks.length - 2} more` : '';
      setBundleName(`${packNames.join(' + ')}${suffix}`);
    }
    setStep('settings');
  };

  const handleCreateBundle = async () => {
    if (!bundleName.trim()) {
      setError('Bundle name is required');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const bundle = await createBundle({
        name: bundleName.trim(),
        description: bundleDescription.trim(),
        source_pack_ids: Array.from(selectedPackIds),
        is_reference_bundle: isReferenceBundle,
        dedup_strategy: dedupStrategy,
        difficulty_tier: difficultyTier,
      });

      onSuccess(bundle.id);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create bundle');
    } finally {
      setLoading(false);
    }
  };

  // Step 1: Select packs
  if (step === 'select') {
    return (
      <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
        <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-2xl">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
            <div className="flex items-center gap-3">
              <Layers className="w-5 h-5 text-orange-400" />
              <h2 className="text-lg font-semibold text-white">Create Bundle</h2>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Step indicator */}
          <div className="px-6 py-3 border-b border-slate-700 bg-slate-800/30">
            <div className="flex items-center gap-2 text-sm">
              <span className="flex items-center gap-1.5 text-purple-400">
                <span className="w-5 h-5 rounded-full bg-purple-500 text-white text-xs flex items-center justify-center">
                  1
                </span>
                Select Packs
              </span>
              <ChevronRight className="w-4 h-4 text-slate-600" />
              <span className="text-slate-500">Duplicates</span>
              <ChevronRight className="w-4 h-4 text-slate-600" />
              <span className="text-slate-500">Settings</span>
            </div>
          </div>

          {/* Content */}
          <div className="p-6">
            {error && (
              <div className="flex items-center gap-2 p-3 mb-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400 text-sm">
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
                {error}
              </div>
            )}

            <p className="text-slate-400 text-sm mb-4">
              Select packs to combine into a bundle (minimum 2):
            </p>

            {packsLoading ? (
              <div className="flex items-center justify-center py-12">
                <Loader2 className="w-6 h-6 text-purple-500 animate-spin" />
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-3 max-h-[350px] overflow-y-auto pr-2">
                {availablePacks.map((pack) => (
                  <button
                    key={pack.id}
                    onClick={() => togglePack(pack.id)}
                    className={`flex items-start gap-3 p-3 rounded-lg border transition-colors text-left ${
                      selectedPackIds.has(pack.id)
                        ? 'bg-purple-500/20 border-purple-500'
                        : 'bg-slate-800 border-slate-700 hover:border-slate-600'
                    }`}
                  >
                    <div
                      className={`mt-0.5 w-5 h-5 rounded border flex-shrink-0 flex items-center justify-center ${
                        selectedPackIds.has(pack.id)
                          ? 'bg-purple-500 border-purple-500'
                          : 'border-slate-600'
                      }`}
                    >
                      {selectedPackIds.has(pack.id) && <Check className="w-3 h-3 text-white" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-slate-200 truncate">{pack.name}</div>
                      <div className="flex items-center gap-2 mt-1">
                        <Badge className="bg-slate-700/50 text-slate-300 border-slate-600 text-xs">
                          {pack.question_count} Qs
                        </Badge>
                        <Badge
                          className={`text-xs ${
                            pack.type === 'bundle'
                              ? 'bg-orange-500/20 text-orange-400 border-orange-500/30'
                              : 'bg-slate-700/50 text-slate-300 border-slate-600'
                          }`}
                        >
                          {pack.type}
                        </Badge>
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}

            {/* Selection summary */}
            {selectedPackIds.size > 0 && (
              <div className="mt-4 p-3 bg-slate-800/50 rounded-lg flex items-center justify-between">
                <span className="text-sm text-slate-300">
                  {selectedPackIds.size} packs selected ({totalQuestions} total questions)
                </span>
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
              onClick={handleNextFromSelect}
              disabled={loading || selectedPackIds.size < 2}
              className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading && <Loader2 className="w-4 h-4 animate-spin" />}
              Next
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Step 2: Deduplication options
  if (step === 'dedup') {
    const duplicateCount = dedupPreview?.duplicate_count || 0;

    return (
      <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
        <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-lg">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
            <div className="flex items-center gap-3">
              <Layers className="w-5 h-5 text-orange-400" />
              <h2 className="text-lg font-semibold text-white">Create Bundle</h2>
            </div>
            <button
              onClick={onClose}
              className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Step indicator */}
          <div className="px-6 py-3 border-b border-slate-700 bg-slate-800/30">
            <div className="flex items-center gap-2 text-sm">
              <span className="flex items-center gap-1.5 text-slate-400">
                <span className="w-5 h-5 rounded-full bg-slate-600 text-white text-xs flex items-center justify-center">
                  <Check className="w-3 h-3" />
                </span>
                Select Packs
              </span>
              <ChevronRight className="w-4 h-4 text-slate-600" />
              <span className="flex items-center gap-1.5 text-purple-400">
                <span className="w-5 h-5 rounded-full bg-purple-500 text-white text-xs flex items-center justify-center">
                  2
                </span>
                Duplicates
              </span>
              <ChevronRight className="w-4 h-4 text-slate-600" />
              <span className="text-slate-500">Settings</span>
            </div>
          </div>

          {/* Content */}
          <div className="p-6">
            {duplicateCount > 0 ? (
              <>
                <div className="flex items-center gap-3 p-4 bg-amber-500/10 border border-amber-500/30 rounded-lg mb-6">
                  <AlertTriangle className="w-5 h-5 text-amber-400 flex-shrink-0" />
                  <div>
                    <p className="text-amber-300 font-medium">
                      {duplicateCount} duplicate questions found
                    </p>
                    <p className="text-sm text-amber-400/80">
                      These questions appear in multiple selected packs
                    </p>
                  </div>
                </div>

                <p className="text-slate-400 text-sm mb-4">How should we handle duplicates?</p>

                <div className="space-y-3">
                  <button
                    onClick={() => setDedupStrategy('keep_first')}
                    className={`w-full flex items-start gap-3 p-4 rounded-lg border transition-colors text-left ${
                      dedupStrategy === 'keep_first'
                        ? 'bg-purple-500/20 border-purple-500'
                        : 'bg-slate-800 border-slate-700 hover:border-slate-600'
                    }`}
                  >
                    <div
                      className={`mt-0.5 w-5 h-5 rounded-full border flex-shrink-0 flex items-center justify-center ${
                        dedupStrategy === 'keep_first'
                          ? 'bg-purple-500 border-purple-500'
                          : 'border-slate-600'
                      }`}
                    >
                      {dedupStrategy === 'keep_first' && <Check className="w-3 h-3 text-white" />}
                    </div>
                    <div>
                      <div className="font-medium text-slate-200">
                        Keep first occurrence only
                        <Badge className="ml-2 bg-emerald-500/20 text-emerald-400 border-emerald-500/30 text-xs">
                          Recommended
                        </Badge>
                      </div>
                      <p className="text-sm text-slate-400 mt-1">
                        Results in {dedupPreview?.unique_count || 0} unique questions
                      </p>
                    </div>
                  </button>

                  <button
                    onClick={() => setDedupStrategy('keep_all')}
                    className={`w-full flex items-start gap-3 p-4 rounded-lg border transition-colors text-left ${
                      dedupStrategy === 'keep_all'
                        ? 'bg-purple-500/20 border-purple-500'
                        : 'bg-slate-800 border-slate-700 hover:border-slate-600'
                    }`}
                  >
                    <div
                      className={`mt-0.5 w-5 h-5 rounded-full border flex-shrink-0 flex items-center justify-center ${
                        dedupStrategy === 'keep_all'
                          ? 'bg-purple-500 border-purple-500'
                          : 'border-slate-600'
                      }`}
                    >
                      {dedupStrategy === 'keep_all' && <Check className="w-3 h-3 text-white" />}
                    </div>
                    <div>
                      <div className="font-medium text-slate-200">
                        Keep all (include duplicates)
                      </div>
                      <p className="text-sm text-slate-400 mt-1">
                        Results in {dedupPreview?.total_count || 0} total questions
                      </p>
                    </div>
                  </button>
                </div>
              </>
            ) : (
              <div className="flex items-center gap-3 p-4 bg-emerald-500/10 border border-emerald-500/30 rounded-lg">
                <Check className="w-5 h-5 text-emerald-400" />
                <div>
                  <p className="text-emerald-300 font-medium">No duplicates found</p>
                  <p className="text-sm text-emerald-400/80">
                    All {dedupPreview?.unique_count || 0} questions are unique
                  </p>
                </div>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-between gap-2 px-6 py-4 border-t border-slate-700">
            <button
              onClick={() => setStep('select')}
              className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
            >
              <ChevronLeft className="w-4 h-4" />
              Back
            </button>
            <button
              onClick={handleNextFromDedup}
              className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors"
            >
              Next
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Step 3: Bundle settings
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
      <div className="bg-slate-900 border border-slate-700 rounded-lg w-full max-w-lg">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
          <div className="flex items-center gap-3">
            <Layers className="w-5 h-5 text-orange-400" />
            <h2 className="text-lg font-semibold text-white">Create Bundle</h2>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 text-slate-400 hover:text-slate-200 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Step indicator */}
        <div className="px-6 py-3 border-b border-slate-700 bg-slate-800/30">
          <div className="flex items-center gap-2 text-sm">
            <span className="flex items-center gap-1.5 text-slate-400">
              <span className="w-5 h-5 rounded-full bg-slate-600 text-white text-xs flex items-center justify-center">
                <Check className="w-3 h-3" />
              </span>
              Select Packs
            </span>
            <ChevronRight className="w-4 h-4 text-slate-600" />
            <span className="flex items-center gap-1.5 text-slate-400">
              <span className="w-5 h-5 rounded-full bg-slate-600 text-white text-xs flex items-center justify-center">
                <Check className="w-3 h-3" />
              </span>
              Duplicates
            </span>
            <ChevronRight className="w-4 h-4 text-slate-600" />
            <span className="flex items-center gap-1.5 text-purple-400">
              <span className="w-5 h-5 rounded-full bg-purple-500 text-white text-xs flex items-center justify-center">
                3
              </span>
              Settings
            </span>
          </div>
        </div>

        {/* Content */}
        <div className="p-6 space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 bg-red-500/10 border border-red-500/30 rounded-md text-red-400 text-sm">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              {error}
            </div>
          )}

          {/* Bundle Name */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">
              Bundle Name <span className="text-red-400">*</span>
            </label>
            <input
              type="text"
              value={bundleName}
              onChange={(e) => setBundleName(e.target.value)}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50"
              placeholder="Enter bundle name..."
            />
          </div>

          {/* Description */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-1">Description</label>
            <textarea
              value={bundleDescription}
              onChange={(e) => setBundleDescription(e.target.value)}
              rows={2}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-md text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500/50 resize-none"
              placeholder="Describe the purpose of this bundle..."
            />
          </div>

          {/* Difficulty Tier */}
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

          {/* Bundle Type */}
          <div>
            <label className="block text-sm font-medium text-slate-300 mb-3">Bundle Type</label>
            <div className="space-y-3">
              <button
                onClick={() => setIsReferenceBundle(false)}
                className={`w-full flex items-start gap-3 p-3 rounded-lg border transition-colors text-left ${
                  !isReferenceBundle
                    ? 'bg-purple-500/20 border-purple-500'
                    : 'bg-slate-800 border-slate-700 hover:border-slate-600'
                }`}
              >
                <div
                  className={`mt-0.5 w-5 h-5 rounded-full border flex-shrink-0 flex items-center justify-center ${
                    !isReferenceBundle ? 'bg-purple-500 border-purple-500' : 'border-slate-600'
                  }`}
                >
                  {!isReferenceBundle && <Check className="w-3 h-3 text-white" />}
                </div>
                <div>
                  <div className="font-medium text-slate-200">Copy Bundle</div>
                  <p className="text-sm text-slate-400">
                    Independent copy of questions, does not sync with source packs
                  </p>
                </div>
              </button>

              <button
                onClick={() => setIsReferenceBundle(true)}
                className={`w-full flex items-start gap-3 p-3 rounded-lg border transition-colors text-left ${
                  isReferenceBundle
                    ? 'bg-purple-500/20 border-purple-500'
                    : 'bg-slate-800 border-slate-700 hover:border-slate-600'
                }`}
              >
                <div
                  className={`mt-0.5 w-5 h-5 rounded-full border flex-shrink-0 flex items-center justify-center ${
                    isReferenceBundle ? 'bg-purple-500 border-purple-500' : 'border-slate-600'
                  }`}
                >
                  {isReferenceBundle && <Check className="w-3 h-3 text-white" />}
                </div>
                <div>
                  <div className="font-medium text-slate-200">Reference Bundle</div>
                  <p className="text-sm text-slate-400">
                    Links to source packs, stays in sync with changes
                  </p>
                </div>
              </button>
            </div>
          </div>

          {/* Summary */}
          <div className="p-3 bg-slate-800/50 rounded-lg">
            <div className="flex items-center gap-2 text-sm text-slate-300">
              <Package className="w-4 h-4" />
              <span>
                Creating bundle with{' '}
                {dedupStrategy === 'keep_first'
                  ? dedupPreview?.unique_count
                  : dedupPreview?.total_count}{' '}
                questions from {selectedPackIds.size} packs
              </span>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="flex justify-between gap-2 px-6 py-4 border-t border-slate-700">
          <button
            onClick={() => setStep('dedup')}
            className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-slate-300 bg-slate-800 hover:bg-slate-700 rounded-md transition-colors"
          >
            <ChevronLeft className="w-4 h-4" />
            Back
          </button>
          <button
            onClick={handleCreateBundle}
            disabled={loading || !bundleName.trim()}
            className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading && <Loader2 className="w-4 h-4 animate-spin" />}
            Create Bundle
          </button>
        </div>
      </div>
    </div>
  );
}
