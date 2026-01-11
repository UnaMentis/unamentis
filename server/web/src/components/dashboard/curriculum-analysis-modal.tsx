'use client';

import { useState } from 'react';
import {
  X,
  Loader2,
  Play,
  AlertTriangle,
  AlertCircle,
  Info,
  ImageOff,
  FileText,
  Target,
  HelpCircle,
  Layers,
  Clock,
  Database,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
} from 'lucide-react';
import type { CurriculumAnalysis, AnalysisIssue, ReprocessConfig, IssueType, IssueSeverity } from '@/types';
import { cn } from '@/lib/utils';

interface CurriculumAnalysisModalProps {
  curriculumId: string;
  curriculumName: string;
  analysis: CurriculumAnalysis;
  onClose: () => void;
  onStartReprocess: (config: ReprocessConfig) => Promise<void>;
}

// Issue type display information
const ISSUE_TYPE_INFO: Record<IssueType, { label: string; icon: typeof AlertCircle; description: string }> = {
  broken_image: {
    label: 'Broken Image',
    icon: ImageOff,
    description: 'Image URL returns 404 or is unreachable',
  },
  placeholder_image: {
    label: 'Placeholder Image',
    icon: ImageOff,
    description: 'Image is marked as a placeholder',
  },
  oversized_segment: {
    label: 'Oversized Segment',
    icon: FileText,
    description: 'Content segment exceeds 2000 characters',
  },
  undersized_segment: {
    label: 'Undersized Segment',
    icon: FileText,
    description: 'Content segment is under 100 characters',
  },
  missing_objectives: {
    label: 'Missing Objectives',
    icon: Target,
    description: 'Learning objectives not defined',
  },
  missing_checkpoints: {
    label: 'Missing Checkpoints',
    icon: HelpCircle,
    description: 'No comprehension check questions',
  },
  missing_alternatives: {
    label: 'Missing Alternatives',
    icon: Layers,
    description: 'No alternative explanations provided',
  },
  missing_time_estimate: {
    label: 'Missing Time Estimate',
    icon: Clock,
    description: 'Duration not specified for content',
  },
  missing_metadata: {
    label: 'Missing Metadata',
    icon: Database,
    description: 'Required metadata fields are empty',
  },
};

// Severity display information
const SEVERITY_INFO: Record<IssueSeverity, { label: string; color: string; bgColor: string; borderColor: string }> = {
  critical: {
    label: 'Critical',
    color: 'text-red-400',
    bgColor: 'bg-red-500/10',
    borderColor: 'border-red-500/30',
  },
  warning: {
    label: 'Warning',
    color: 'text-amber-400',
    bgColor: 'bg-amber-500/10',
    borderColor: 'border-amber-500/30',
  },
  info: {
    label: 'Info',
    color: 'text-blue-400',
    bgColor: 'bg-blue-500/10',
    borderColor: 'border-blue-500/30',
  },
};

function getSeverityIcon(severity: IssueSeverity) {
  switch (severity) {
    case 'critical':
      return AlertCircle;
    case 'warning':
      return AlertTriangle;
    case 'info':
      return Info;
  }
}

export function CurriculumAnalysisModal({
  curriculumId,
  curriculumName,
  analysis,
  onClose,
  onStartReprocess,
}: CurriculumAnalysisModalProps) {
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedTypes, setExpandedTypes] = useState<Set<string>>(new Set());

  // Reprocess config options
  const [config, setConfig] = useState<Omit<ReprocessConfig, 'curriculumId'>>({
    fixImages: true,
    rechunkSegments: true,
    generateObjectives: true,
    addCheckpoints: true,
    addAlternatives: true,
    fixMetadata: true,
    llmModel: 'qwen2.5:32b',
    dryRun: false,
  });

  // Group issues by type
  const issuesByType = analysis.issues.reduce(
    (acc, issue) => {
      if (!acc[issue.issueType]) {
        acc[issue.issueType] = [];
      }
      acc[issue.issueType].push(issue);
      return acc;
    },
    {} as Record<string, AnalysisIssue[]>
  );

  // Count by severity
  const severityCounts = {
    critical: analysis.issues.filter((i) => i.severity === 'critical').length,
    warning: analysis.issues.filter((i) => i.severity === 'warning').length,
    info: analysis.issues.filter((i) => i.severity === 'info').length,
  };

  const toggleType = (type: string) => {
    setExpandedTypes((prev) => {
      const next = new Set(prev);
      if (next.has(type)) {
        next.delete(type);
      } else {
        next.add(type);
      }
      return next;
    });
  };

  const handleStartReprocess = async () => {
    setStarting(true);
    setError(null);
    try {
      await onStartReprocess({
        curriculumId,
        ...config,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start reprocessing');
    } finally {
      setStarting(false);
    }
  };

  const toggleConfigOption = (key: keyof typeof config) => {
    if (key === 'llmModel' || key === 'dryRun') return;
    setConfig((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-xl border border-slate-700 p-6 w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-semibold text-slate-100">Curriculum Analysis</h2>
            <p className="text-sm text-slate-400">{curriculumName}</p>
          </div>
          <button
            onClick={onClose}
            disabled={starting}
            className="text-slate-400 hover:text-slate-200 disabled:opacity-50"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Summary Bar */}
        <div className="flex items-center gap-4 mb-4 p-3 bg-slate-900/50 rounded-lg">
          <div className="flex items-center gap-2">
            <span className="text-sm text-slate-400">Total Issues:</span>
            <span className="font-semibold text-slate-100">{analysis.totalIssues}</span>
          </div>
          <div className="h-4 w-px bg-slate-700" />
          {severityCounts.critical > 0 && (
            <div className={cn('flex items-center gap-1', SEVERITY_INFO.critical.color)}>
              <AlertCircle className="w-4 h-4" />
              <span className="text-sm font-medium">{severityCounts.critical}</span>
            </div>
          )}
          {severityCounts.warning > 0 && (
            <div className={cn('flex items-center gap-1', SEVERITY_INFO.warning.color)}>
              <AlertTriangle className="w-4 h-4" />
              <span className="text-sm font-medium">{severityCounts.warning}</span>
            </div>
          )}
          {severityCounts.info > 0 && (
            <div className={cn('flex items-center gap-1', SEVERITY_INFO.info.color)}>
              <Info className="w-4 h-4" />
              <span className="text-sm font-medium">{severityCounts.info}</span>
            </div>
          )}
          <div className="flex-1" />
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-green-400" />
            <span className="text-sm text-slate-400">Auto-fixable:</span>
            <span className="font-semibold text-green-400">{analysis.autoFixableCount}</span>
          </div>
        </div>

        {/* Error Display */}
        {error && (
          <div className="mb-4 bg-red-500/10 border border-red-500/30 rounded-lg px-4 py-3 text-red-400 text-sm">
            {error}
          </div>
        )}

        {/* Issues List */}
        <div className="flex-1 overflow-y-auto mb-4 space-y-2">
          {Object.entries(issuesByType).map(([type, issues]) => {
            const typeInfo = ISSUE_TYPE_INFO[type as IssueType] || {
              label: type,
              icon: AlertCircle,
              description: '',
            };
            const TypeIcon = typeInfo.icon;
            const isExpanded = expandedTypes.has(type);
            const severity = issues[0]?.severity || 'info';
            const severityInfo = SEVERITY_INFO[severity];

            return (
              <div
                key={type}
                className={cn('rounded-lg border', severityInfo.bgColor, severityInfo.borderColor)}
              >
                <button
                  onClick={() => toggleType(type)}
                  className="w-full flex items-center gap-3 p-3 text-left"
                >
                  {isExpanded ? (
                    <ChevronDown className="w-4 h-4 text-slate-400" />
                  ) : (
                    <ChevronRight className="w-4 h-4 text-slate-400" />
                  )}
                  <TypeIcon className={cn('w-5 h-5', severityInfo.color)} />
                  <div className="flex-1">
                    <span className="font-medium text-slate-100">{typeInfo.label}</span>
                    <span className="ml-2 text-sm text-slate-400">({issues.length} issues)</span>
                  </div>
                  <span
                    className={cn(
                      'px-2 py-0.5 text-xs font-medium rounded-full',
                      severityInfo.bgColor,
                      severityInfo.color
                    )}
                  >
                    {severityInfo.label}
                  </span>
                </button>

                {isExpanded && (
                  <div className="px-3 pb-3 space-y-2">
                    <p className="text-sm text-slate-400 ml-8">{typeInfo.description}</p>
                    <div className="ml-8 space-y-2">
                      {issues.slice(0, 10).map((issue) => (
                        <div
                          key={issue.id}
                          className="p-2 bg-slate-900/50 rounded text-sm"
                        >
                          <div className="flex items-start justify-between gap-2">
                            <div>
                              <p className="text-slate-200">{issue.description}</p>
                              <p className="text-xs text-slate-500 mt-1">
                                Location: {issue.location}
                                {issue.nodeId && ` (Node: ${issue.nodeId})`}
                              </p>
                            </div>
                            {issue.autoFixable && (
                              <span className="shrink-0 px-2 py-0.5 text-xs bg-green-500/20 text-green-400 rounded">
                                Auto-fix
                              </span>
                            )}
                          </div>
                          {issue.suggestedFix && (
                            <p className="text-xs text-indigo-400 mt-1">
                              Suggested fix: {issue.suggestedFix}
                            </p>
                          )}
                        </div>
                      ))}
                      {issues.length > 10 && (
                        <p className="text-sm text-slate-500 italic">
                          ... and {issues.length - 10} more
                        </p>
                      )}
                    </div>
                  </div>
                )}
              </div>
            );
          })}

          {analysis.totalIssues === 0 && (
            <div className="text-center py-8">
              <CheckCircle2 className="w-12 h-12 text-green-400 mx-auto mb-3" />
              <p className="text-lg font-medium text-slate-100">No Issues Found</p>
              <p className="text-sm text-slate-400">This curriculum passes all quality checks.</p>
            </div>
          )}
        </div>

        {/* Reprocess Options */}
        {analysis.totalIssues > 0 && (
          <div className="border-t border-slate-700 pt-4">
            <h3 className="text-sm font-medium text-slate-300 mb-3">Reprocessing Options</h3>
            <div className="grid grid-cols-2 gap-2 mb-4">
              <label className="flex items-center gap-2 p-2 rounded hover:bg-slate-700/50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={config.fixImages}
                  onChange={() => toggleConfigOption('fixImages')}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Fix Images</span>
              </label>
              <label className="flex items-center gap-2 p-2 rounded hover:bg-slate-700/50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={config.rechunkSegments}
                  onChange={() => toggleConfigOption('rechunkSegments')}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Rechunk Segments</span>
              </label>
              <label className="flex items-center gap-2 p-2 rounded hover:bg-slate-700/50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={config.generateObjectives}
                  onChange={() => toggleConfigOption('generateObjectives')}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Generate Objectives</span>
              </label>
              <label className="flex items-center gap-2 p-2 rounded hover:bg-slate-700/50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={config.addCheckpoints}
                  onChange={() => toggleConfigOption('addCheckpoints')}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Add Checkpoints</span>
              </label>
              <label className="flex items-center gap-2 p-2 rounded hover:bg-slate-700/50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={config.addAlternatives}
                  onChange={() => toggleConfigOption('addAlternatives')}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Add Alternatives</span>
              </label>
              <label className="flex items-center gap-2 p-2 rounded hover:bg-slate-700/50 cursor-pointer">
                <input
                  type="checkbox"
                  checked={config.fixMetadata}
                  onChange={() => toggleConfigOption('fixMetadata')}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Fix Metadata</span>
              </label>
            </div>

            <div className="flex items-center gap-4 mb-4">
              <label className="flex items-center gap-2">
                <span className="text-sm text-slate-400">LLM Model:</span>
                <select
                  value={config.llmModel}
                  onChange={(e) => setConfig((prev) => ({ ...prev, llmModel: e.target.value }))}
                  className="bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
                >
                  <option value="qwen2.5:32b">Qwen 2.5 32B (Recommended)</option>
                  <option value="mistral:7b">Mistral 7B (Fast)</option>
                  <option value="llama3.2:latest">Llama 3.2</option>
                </select>
              </label>
              <label className="flex items-center gap-2 ml-auto">
                <input
                  type="checkbox"
                  checked={config.dryRun}
                  onChange={() => setConfig((prev) => ({ ...prev, dryRun: !prev.dryRun }))}
                  className="rounded border-slate-600 bg-slate-900 text-indigo-500 focus:ring-indigo-500"
                />
                <span className="text-sm text-slate-300">Dry Run (Preview Only)</span>
              </label>
            </div>
          </div>
        )}

        {/* Actions */}
        <div className="flex gap-3 pt-4 border-t border-slate-700">
          <button
            onClick={onClose}
            disabled={starting}
            className="flex-1 px-4 py-2 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:bg-slate-700/50 transition-all disabled:opacity-50"
          >
            Close
          </button>
          {analysis.totalIssues > 0 && (
            <button
              onClick={handleStartReprocess}
              disabled={starting}
              className={cn(
                'flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-all',
                starting
                  ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                  : 'bg-indigo-500 hover:bg-indigo-400 text-white'
              )}
            >
              {starting ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Starting...
                </>
              ) : (
                <>
                  <Play className="w-4 h-4" />
                  {config.dryRun ? 'Preview Changes' : 'Start Reprocessing'}
                </>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
