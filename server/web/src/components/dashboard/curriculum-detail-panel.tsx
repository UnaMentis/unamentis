'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  BookOpen,
  ArrowLeft,
  Clock,
  Target,
  FileText,
  Image as ImageIcon,
  ChevronDown,
  ChevronRight,
  Play,
  Edit2,
  Save,
  X,
  Layout,
} from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { CurriculumDetail, CurriculumTopic } from '@/types';
import { CurriculumStudio } from '@/components/curriculum/CurriculumEditor';
import { Curriculum, Segment, Transcript } from '@/types/curriculum';
import type { TranscriptSegment, TopicTranscript } from '@/types';

interface CurriculumDetailPanelProps {
  curriculumId: string;
  onBack: () => void;
}

// Map segment type from API format to editor format
function mapSegmentType(
  apiType: TranscriptSegment['type']
): Segment['type'] {
  // Map API types to editor types (they're mostly the same)
  const typeMap: Record<TranscriptSegment['type'], Segment['type']> = {
    introduction: 'introduction',
    lecture: 'lecture',
    explanation: 'explanation',
    summary: 'summary',
    checkpoint: 'checkpoint',
    example: 'example',
  };
  return typeMap[apiType] || 'lecture';
}

// Map transcript segments from API format to editor format
function mapTranscript(apiTranscript: TopicTranscript): Transcript {
  return {
    segments: apiTranscript.segments.map((seg): Segment => ({
      id: seg.id,
      type: mapSegmentType(seg.type),
      content: seg.content,
      speakingNotes: seg.speakingNotes
        ? {
            pace: seg.speakingNotes.pace,
            emotionalTone: seg.speakingNotes.emotionalTone,
            emphasis: seg.speakingNotes.emphasis,
          }
        : undefined,
    })),
  };
}

// Adapter to convert API response to UMCF format for the editor
function adaptToUMCF(detail: CurriculumDetail): Curriculum {
  const isExternal = detail.document?.sourceProvenance?.originType === 'external';

  return {
    umcf: '1.0.0',
    id: { value: detail.id || 'unknown' },
    title: detail.title,
    description: detail.description,
    version: { number: detail.version || '1.0.0' },
    locked: isExternal, // Lock if external
    content:
      detail.topics?.map((t, i) => ({
        id: { value: t.id.value || `topic-${i}` },
        title: t.title,
        type: 'topic' as const,
        description: t.description,
        transcript: t.transcript ? mapTranscript(t.transcript) : undefined,
      })) || [],
  };
}

async function getCurriculumDetail(id: string): Promise<CurriculumDetail> {
  const response = await fetch(`/api/curricula/${id}/full`);
  if (!response.ok) {
    throw new Error('Failed to fetch curriculum details');
  }
  const data = await response.json();
  return data.curriculum;
}

async function updateCurriculum(id: string, data: Partial<CurriculumDetail>): Promise<void> {
  const response = await fetch(`/api/curricula/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  if (!response.ok) {
    throw new Error('Failed to update curriculum');
  }
}

async function saveCurriculumUMCF(id: string, umcfData: Curriculum): Promise<void> {
  const response = await fetch(`/api/curricula/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(umcfData),
  });
  if (!response.ok) {
    const errorData = await response.json().catch(() => ({ error: 'Unknown error' }));
    throw new Error(errorData.error || 'Failed to save curriculum');
  }
}

export function CurriculumDetailPanel({ curriculumId, onBack }: CurriculumDetailPanelProps) {
  const [curriculum, setCurriculum] = useState<CurriculumDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedTopics, setExpandedTopics] = useState<Set<string>>(new Set());
  const [editingField, setEditingField] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');
  const [saving, setSaving] = useState(false);
  const [isStudioOpen, setIsStudioOpen] = useState(false);

  const fetchCurriculum = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getCurriculumDetail(curriculumId);
      setCurriculum(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load curriculum');
    } finally {
      setLoading(false);
    }
  }, [curriculumId]);

  useEffect(() => {
    fetchCurriculum();
  }, [fetchCurriculum]);

  const toggleTopic = (topicId: string) => {
    setExpandedTopics((prev) => {
      const next = new Set(prev);
      if (next.has(topicId)) {
        next.delete(topicId);
      } else {
        next.add(topicId);
      }
      return next;
    });
  };

  const startEditing = (field: string, value: string) => {
    setEditingField(field);
    setEditValue(value);
  };

  const cancelEditing = () => {
    setEditingField(null);
    setEditValue('');
  };

  const saveEdit = async () => {
    if (!curriculum || !editingField) return;

    setSaving(true);
    try {
      const updates: Partial<CurriculumDetail> = {};
      if (editingField === 'title') {
        updates.title = editValue;
      } else if (editingField === 'description') {
        updates.description = editValue;
      }

      await updateCurriculum(curriculumId, updates);
      setCurriculum({ ...curriculum, ...updates });
      setEditingField(null);
      setEditValue('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin w-8 h-8 border-2 border-orange-500 border-t-transparent rounded-full" />
      </div>
    );
  }

  if (error || !curriculum) {
    return (
      <div className="space-y-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-slate-400 hover:text-slate-200 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to Curricula
        </button>
        <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400">
          {error || 'Curriculum not found'}
        </div>
      </div>
    );
  }

  // Render Studio Mode
  if (isStudioOpen) {
    return (
      <CurriculumStudio
        initialData={adaptToUMCF(curriculum)}
        onSave={async (data) => {
          await saveCurriculumUMCF(curriculumId, data);
          // Refresh the curriculum data to get updated version
          await fetchCurriculum();
        }}
        onBack={() => setIsStudioOpen(false)}
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-slate-400 hover:text-slate-200 transition-colors w-fit"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to Curricula
        </button>

        <div className="flex items-start justify-between gap-4">
          <div className="flex-1">
            {editingField === 'title' ? (
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={editValue}
                  onChange={(e) => setEditValue(e.target.value)}
                  className="flex-1 px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-100 text-2xl font-bold focus:outline-none focus:ring-2 focus:ring-orange-500/50"
                  autoFocus
                />
                <button
                  onClick={saveEdit}
                  disabled={saving}
                  className="p-2 text-emerald-400 hover:text-emerald-300 transition-colors"
                >
                  <Save className="w-5 h-5" />
                </button>
                <button
                  onClick={cancelEditing}
                  className="p-2 text-slate-400 hover:text-slate-200 transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-4">
                <h2 className="text-2xl font-bold text-white flex items-center gap-3 group">
                  <BookOpen className="w-6 h-6 text-orange-400" />
                  {curriculum.title}
                  <button
                    onClick={() => startEditing('title', curriculum.title)}
                    className="p-1 text-slate-500 hover:text-slate-300 opacity-0 group-hover:opacity-100 transition-all"
                  >
                    <Edit2 className="w-4 h-4" />
                  </button>
                </h2>
              </div>
            )}

            {editingField === 'description' ? (
              <div className="flex items-start gap-2 mt-2">
                <textarea
                  value={editValue}
                  onChange={(e) => setEditValue(e.target.value)}
                  className="flex-1 px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-300 focus:outline-none focus:ring-2 focus:ring-orange-500/50 min-h-[80px]"
                  autoFocus
                />
                <div className="flex flex-col gap-1">
                  <button
                    onClick={saveEdit}
                    disabled={saving}
                    className="p-2 text-emerald-400 hover:text-emerald-300 transition-colors"
                  >
                    <Save className="w-5 h-5" />
                  </button>
                  <button
                    onClick={cancelEditing}
                    className="p-2 text-slate-400 hover:text-slate-200 transition-colors"
                  >
                    <X className="w-5 h-5" />
                  </button>
                </div>
              </div>
            ) : (
              <p className="text-slate-400 mt-2 group flex items-start gap-2">
                {curriculum.description || 'No description'}
                <button
                  onClick={() => startEditing('description', curriculum.description || '')}
                  className="p-1 text-slate-500 hover:text-slate-300 opacity-0 group-hover:opacity-100 transition-all flex-shrink-0"
                >
                  <Edit2 className="w-3 h-3" />
                </button>
              </p>
            )}
          </div>

          <div className="flex flex-col items-end gap-3">
            <div className="flex items-center gap-2">
              <button
                onClick={() => setIsStudioOpen(true)}
                className="flex items-center gap-2 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-all shadow-lg shadow-indigo-500/20 font-medium text-sm"
              >
                <Layout className="w-4 h-4" />
                {curriculum.document?.sourceProvenance?.originType === 'external'
                  ? 'View in Studio'
                  : 'Open Studio'}
              </button>
            </div>
            <div className="flex items-center gap-2">
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
              {curriculum.version && (
                <Badge className="bg-slate-700/50 text-slate-300 border-slate-600">
                  v{curriculum.version}
                </Badge>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Metadata Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="bg-slate-900/50 border-slate-800">
          <CardContent className="p-4">
            <div className="flex items-center gap-2 text-slate-400 mb-1">
              <FileText className="w-4 h-4" />
              <span className="text-xs uppercase tracking-wide">Topics</span>
            </div>
            <p className="text-2xl font-bold text-slate-100">{curriculum.topicCount}</p>
          </CardContent>
        </Card>

        {curriculum.totalDuration && (
          <Card className="bg-slate-900/50 border-slate-800">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 text-slate-400 mb-1">
                <Clock className="w-4 h-4" />
                <span className="text-xs uppercase tracking-wide">Duration</span>
              </div>
              <p className="text-2xl font-bold text-slate-100">{curriculum.totalDuration}</p>
            </CardContent>
          </Card>
        )}

        {curriculum.difficulty && (
          <Card className="bg-slate-900/50 border-slate-800">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 text-slate-400 mb-1">
                <Target className="w-4 h-4" />
                <span className="text-xs uppercase tracking-wide">Difficulty</span>
              </div>
              <p className="text-2xl font-bold text-slate-100 capitalize">
                {curriculum.difficulty}
              </p>
            </CardContent>
          </Card>
        )}

        {curriculum.hasVisualAssets && (
          <Card className="bg-slate-900/50 border-slate-800">
            <CardContent className="p-4">
              <div className="flex items-center gap-2 text-slate-400 mb-1">
                <ImageIcon className="w-4 h-4" />
                <span className="text-xs uppercase tracking-wide">Assets</span>
              </div>
              <p className="text-2xl font-bold text-slate-100">{curriculum.visualAssetCount}</p>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Topics List */}
      <Card className="bg-slate-900/50 border-slate-800">
        <CardHeader>
          <CardTitle className="text-lg font-medium text-slate-100 flex items-center gap-2">
            <FileText className="w-5 h-5 text-blue-400" />
            Topics ({curriculum.topics?.length || 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {curriculum.topics && curriculum.topics.length > 0 ? (
            curriculum.topics.map((topic, index) => (
              <TopicItem
                key={topic.id.value}
                topic={topic}
                index={index}
                expanded={expandedTopics.has(topic.id.value)}
                onToggle={() => toggleTopic(topic.id.value)}
              />
            ))
          ) : (
            <p className="text-slate-500 text-center py-8">No topics in this curriculum</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

interface TopicItemProps {
  topic: CurriculumTopic;
  index: number;
  expanded: boolean;
  onToggle: () => void;
}

function TopicItem({ topic, index, expanded, onToggle }: TopicItemProps) {
  const hasTranscript = topic.transcript && Object.keys(topic.transcript).length > 0;
  const hasExamples = topic.examples && topic.examples.length > 0;
  const hasAssessments = topic.assessments && topic.assessments.length > 0;
  const hasMedia =
    topic.media &&
    ((topic.media.embedded && topic.media.embedded.length > 0) ||
      (topic.media.reference && topic.media.reference.length > 0));

  return (
    <div className="border border-slate-800 rounded-lg overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 p-4 hover:bg-slate-800/50 transition-colors text-left"
      >
        <span className="flex items-center justify-center w-6 h-6 rounded-full bg-slate-800 text-slate-400 text-xs font-medium">
          {index + 1}
        </span>

        <div className="flex-1 min-w-0">
          <h4 className="font-medium text-slate-100 truncate">{topic.title}</h4>
          {topic.description && (
            <p className="text-sm text-slate-500 truncate mt-0.5">{topic.description}</p>
          )}
        </div>

        <div className="flex items-center gap-2">
          {hasTranscript && (
            <Badge className="bg-emerald-500/20 text-emerald-400 border-emerald-500/30 text-xs">
              Transcript
            </Badge>
          )}
          {hasMedia && (
            <Badge className="bg-violet-500/20 text-violet-400 border-violet-500/30 text-xs">
              Media
            </Badge>
          )}
          {expanded ? (
            <ChevronDown className="w-4 h-4 text-slate-500" />
          ) : (
            <ChevronRight className="w-4 h-4 text-slate-500" />
          )}
        </div>
      </button>

      {expanded && (
        <div className="px-4 pb-4 pt-2 border-t border-slate-800 bg-slate-900/30">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
            {topic.timeEstimates && (
              <div>
                <span className="text-xs text-slate-500 uppercase tracking-wide">
                  Time Estimates
                </span>
                <div className="mt-1 space-y-1">
                  {topic.timeEstimates.overview && (
                    <p className="text-sm text-slate-400">
                      Overview: {topic.timeEstimates.overview}
                    </p>
                  )}
                  {topic.timeEstimates.introductory && (
                    <p className="text-sm text-slate-400">
                      Intro: {topic.timeEstimates.introductory}
                    </p>
                  )}
                  {topic.timeEstimates.intermediate && (
                    <p className="text-sm text-slate-400">
                      Intermediate: {topic.timeEstimates.intermediate}
                    </p>
                  )}
                  {topic.timeEstimates.advanced && (
                    <p className="text-sm text-slate-400">
                      Advanced: {topic.timeEstimates.advanced}
                    </p>
                  )}
                </div>
              </div>
            )}

            {hasExamples && (
              <div>
                <span className="text-xs text-slate-500 uppercase tracking-wide">Examples</span>
                <p className="text-sm text-slate-300 mt-1">{topic.examples!.length} examples</p>
              </div>
            )}

            {hasAssessments && (
              <div>
                <span className="text-xs text-slate-500 uppercase tracking-wide">Assessments</span>
                <p className="text-sm text-slate-300 mt-1">
                  {topic.assessments!.length} assessments
                </p>
              </div>
            )}

            {topic.misconceptions && topic.misconceptions.length > 0 && (
              <div>
                <span className="text-xs text-slate-500 uppercase tracking-wide">
                  Misconceptions
                </span>
                <p className="text-sm text-slate-300 mt-1">
                  {topic.misconceptions.length} common errors
                </p>
              </div>
            )}
          </div>

          {hasTranscript && (
            <div className="mt-4">
              <button className="flex items-center gap-2 px-3 py-2 bg-emerald-500/20 text-emerald-400 rounded-md hover:bg-emerald-500/30 transition-colors text-sm">
                <Play className="w-4 h-4" />
                View Transcript
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
