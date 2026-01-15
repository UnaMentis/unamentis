'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  Plus,
  Play,
  Trash2,
  RefreshCw,
  ChevronDown,
  ChevronRight,
  Loader2,
  FileAudio,
  Trophy,
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ComparisonPlayer } from './comparison-player';
import type { TTSComparisonSession, TTSComparisonVariant, TTSComparisonRating } from '@/types';
import { cn } from '@/lib/utils';

interface SessionSummary {
  session_id: string;
  session_name: string;
  status: string;
  total_samples: number;
  total_configurations: number;
  total_variants: number;
  configuration_rankings: Array<{
    config_index: number;
    config_name: string;
    average_rating: number | null;
    rating_count: number;
    ready_count: number;
    failed_count: number;
  }>;
}

interface ComparisonPanelProps {
  onSessionCreated?: (session: TTSComparisonSession) => void;
}

const statusColors: Record<string, string> = {
  draft: 'bg-gray-500/20 text-gray-400 border-gray-500/30',
  generating: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30',
  ready: 'bg-green-500/20 text-green-400 border-green-500/30',
  archived: 'bg-slate-500/20 text-slate-400 border-slate-500/30',
};

export function ComparisonPanel({ onSessionCreated }: ComparisonPanelProps) {
  const [sessions, setSessions] = useState<TTSComparisonSession[]>([]);
  const [expandedSessionId, setExpandedSessionId] = useState<string | null>(null);
  const [sessionDetails, setSessionDetails] = useState<{
    session: TTSComparisonSession;
    variants: TTSComparisonVariant[];
    ratings: Record<string, TTSComparisonRating>;
  } | null>(null);
  const [sessionSummary, setSessionSummary] = useState<SessionSummary | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const [createForm, setCreateForm] = useState({
    name: '',
    description: '',
    samples: '',
    configurations: '',
  });

  // Fetch sessions
  const fetchSessions = useCallback(async () => {
    setIsLoading(true);
    try {
      const response = await fetch('/api/tts/pregen/sessions');
      const data = await response.json();
      if (data.success) {
        setSessions(data.sessions);
      }
    } catch (error) {
      console.error('Failed to fetch sessions:', error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  // Fetch session details when expanded
  const fetchSessionDetails = useCallback(async (sessionId: string) => {
    try {
      const [detailsRes, summaryRes] = await Promise.all([
        fetch(`/api/tts/pregen/sessions/${sessionId}`),
        fetch(`/api/tts/pregen/sessions/${sessionId}/summary`),
      ]);

      const detailsData = await detailsRes.json();
      const summaryData = await summaryRes.json();

      if (detailsData.success) {
        setSessionDetails({
          session: detailsData.session,
          variants: detailsData.variants,
          ratings: detailsData.ratings || {},
        });
      }

      if (summaryData.success) {
        setSessionSummary(summaryData.summary);
      }
    } catch (error) {
      console.error('Failed to fetch session details:', error);
    }
  }, []);

  const handleExpandSession = async (sessionId: string) => {
    if (expandedSessionId === sessionId) {
      setExpandedSessionId(null);
      setSessionDetails(null);
      setSessionSummary(null);
    } else {
      setExpandedSessionId(sessionId);
      await fetchSessionDetails(sessionId);
    }
  };

  // Create session
  const handleCreateSession = async () => {
    setIsCreating(true);
    try {
      // Parse samples (one per line)
      const samples = createForm.samples
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .map((text) => ({ text }));

      // Parse configurations (JSON)
      let configurations;
      try {
        configurations = JSON.parse(createForm.configurations);
      } catch {
        alert('Invalid configurations JSON');
        return;
      }

      const response = await fetch('/api/tts/pregen/sessions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: createForm.name,
          description: createForm.description,
          samples,
          configurations,
        }),
      });

      const data = await response.json();
      if (data.success) {
        setShowCreateDialog(false);
        setCreateForm({ name: '', description: '', samples: '', configurations: '' });
        await fetchSessions();
        onSessionCreated?.(data.session);
      } else {
        alert(data.error || 'Failed to create session');
      }
    } catch (error) {
      console.error('Failed to create session:', error);
      alert('Failed to create session');
    } finally {
      setIsCreating(false);
    }
  };

  // Generate variants
  const handleGenerateVariants = async (sessionId: string, regenerate = false) => {
    try {
      const response = await fetch(`/api/tts/pregen/sessions/${sessionId}/generate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ regenerate }),
      });

      const data = await response.json();
      if (data.success) {
        await fetchSessions();
        if (expandedSessionId === sessionId) {
          await fetchSessionDetails(sessionId);
        }
      } else {
        alert(data.error || 'Failed to generate variants');
      }
    } catch (error) {
      console.error('Failed to generate variants:', error);
      alert('Failed to generate variants');
    }
  };

  // Delete session
  const handleDeleteSession = async (sessionId: string) => {
    if (!confirm('Are you sure you want to delete this session?')) return;

    try {
      const response = await fetch(`/api/tts/pregen/sessions/${sessionId}`, {
        method: 'DELETE',
      });

      if (response.ok) {
        if (expandedSessionId === sessionId) {
          setExpandedSessionId(null);
          setSessionDetails(null);
        }
        await fetchSessions();
      }
    } catch (error) {
      console.error('Failed to delete session:', error);
    }
  };

  // Rate variant
  const handleRateVariant = async (variantId: string, rating: number, notes?: string) => {
    try {
      await fetch(`/api/tts/pregen/variants/${variantId}/rate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rating, notes }),
      });

      // Refresh session details
      if (expandedSessionId) {
        await fetchSessionDetails(expandedSessionId);
      }
    } catch (error) {
      console.error('Failed to rate variant:', error);
    }
  };

  // Save variant as profile
  const handleSaveAsProfile = async (variantId: string) => {
    const name = prompt('Enter profile name:');
    if (!name) return;

    try {
      const response = await fetch(`/api/tts/profiles/from-variant/${variantId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name,
          tags: ['comparison-winner'],
        }),
      });

      const data = await response.json();
      if (data.success) {
        alert(`Profile "${name}" created successfully!`);
      } else {
        alert(data.error || 'Failed to create profile');
      }
    } catch (error) {
      console.error('Failed to save as profile:', error);
      alert('Failed to create profile');
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">TTS Comparison Sessions</h2>
          <p className="text-sm text-muted-foreground">
            Compare different TTS configurations side-by-side
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={fetchSessions} disabled={isLoading}>
            <RefreshCw className={cn('w-4 h-4 mr-2', isLoading && 'animate-spin')} />
            Refresh
          </Button>
          <Button size="sm" onClick={() => setShowCreateDialog(true)}>
            <Plus className="w-4 h-4 mr-2" />
            New Session
          </Button>
        </div>
      </div>

      {/* Sessions list */}
      <div className="space-y-2">
        {sessions.length === 0 && !isLoading && (
          <Card className="p-8 text-center">
            <FileAudio className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
            <p className="text-muted-foreground">No comparison sessions yet</p>
            <Button variant="outline" className="mt-4" onClick={() => setShowCreateDialog(true)}>
              Create your first session
            </Button>
          </Card>
        )}

        {sessions.map((session) => (
          <Card key={session.id}>
            <CardHeader
              className="cursor-pointer hover:bg-muted/50 transition-colors"
              onClick={() => handleExpandSession(session.id)}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  {expandedSessionId === session.id ? (
                    <ChevronDown className="w-4 h-4" />
                  ) : (
                    <ChevronRight className="w-4 h-4" />
                  )}
                  <div>
                    <CardTitle className="text-base">{session.name}</CardTitle>
                    {session.description && (
                      <p className="text-sm text-muted-foreground">{session.description}</p>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Badge className={statusColors[session.status] || statusColors.draft}>
                    {session.status}
                  </Badge>
                  <span className="text-xs text-muted-foreground">
                    {session.config.samples?.length || 0} samples,{' '}
                    {session.config.configurations?.length || 0} configs
                  </span>
                  <div className="flex items-center gap-1">
                    {session.status === 'draft' && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleGenerateVariants(session.id);
                        }}
                      >
                        <Play className="w-4 h-4" />
                      </Button>
                    )}
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDeleteSession(session.id);
                      }}
                    >
                      <Trash2 className="w-4 h-4 text-destructive" />
                    </Button>
                  </div>
                </div>
              </div>
            </CardHeader>

            {expandedSessionId === session.id && sessionDetails && (
              <CardContent className="border-t pt-4 space-y-4">
                {/* Summary */}
                {sessionSummary && sessionSummary.configuration_rankings.length > 0 && (
                  <div className="p-4 bg-muted/30 rounded-lg">
                    <div className="flex items-center gap-2 mb-3">
                      <Trophy className="w-4 h-4 text-yellow-500" />
                      <span className="font-medium">Rankings</span>
                    </div>
                    <div className="space-y-2">
                      {sessionSummary.configuration_rankings.map((rank, idx) => (
                        <div
                          key={rank.config_index}
                          className="flex items-center justify-between text-sm"
                        >
                          <div className="flex items-center gap-2">
                            <span className="w-6 text-center font-medium">
                              {idx === 0
                                ? '🥇'
                                : idx === 1
                                  ? '🥈'
                                  : idx === 2
                                    ? '🥉'
                                    : `#${idx + 1}`}
                            </span>
                            <span>{rank.config_name}</span>
                          </div>
                          <div className="flex items-center gap-3 text-muted-foreground">
                            {rank.average_rating !== null && (
                              <span>
                                ⭐ {rank.average_rating.toFixed(1)} ({rank.rating_count} ratings)
                              </span>
                            )}
                            <span>
                              {rank.ready_count} ready
                              {rank.failed_count > 0 && `, ${rank.failed_count} failed`}
                            </span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Comparison players by sample */}
                {sessionDetails.session.config.samples?.map((sample, sampleIdx) => (
                  <div key={sampleIdx} className="space-y-2">
                    <h4 className="font-medium text-sm">Sample {sampleIdx + 1}</h4>
                    <ComparisonPlayer
                      variants={sessionDetails.variants.filter((v) => v.sample_index === sampleIdx)}
                      ratings={sessionDetails.ratings}
                      configNames={sessionDetails.session.config.configurations?.map((c) => c.name)}
                      sampleText={sample.text}
                      onRate={handleRateVariant}
                      onSaveAsProfile={handleSaveAsProfile}
                    />
                  </div>
                ))}

                {/* Actions */}
                <div className="flex justify-end gap-2 pt-2">
                  {session.status === 'ready' && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleGenerateVariants(session.id, true)}
                    >
                      <RefreshCw className="w-4 h-4 mr-2" />
                      Regenerate All
                    </Button>
                  )}
                </div>
              </CardContent>
            )}
          </Card>
        ))}
      </div>

      {/* Create Session Modal */}
      {showCreateDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          {/* Backdrop */}
          <div
            className="absolute inset-0 bg-black/50"
            onClick={() => setShowCreateDialog(false)}
          />
          {/* Modal Content */}
          <div className="relative z-10 w-full max-w-2xl mx-4 bg-slate-900 border border-slate-700 rounded-lg shadow-xl">
            <div className="p-6">
              <h2 className="text-lg font-semibold mb-4">Create Comparison Session</h2>

              <div className="space-y-4">
                <div className="space-y-2">
                  <label className="text-sm font-medium">Session Name</label>
                  <input
                    type="text"
                    value={createForm.name}
                    onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                      setCreateForm((f) => ({ ...f, name: e.target.value }))
                    }
                    placeholder="e.g., Voice comparison for tutoring"
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-100 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium">Description (optional)</label>
                  <input
                    type="text"
                    value={createForm.description}
                    onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                      setCreateForm((f) => ({ ...f, description: e.target.value }))
                    }
                    placeholder="What are you testing?"
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-100 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium">Sample Texts (one per line)</label>
                  <textarea
                    value={createForm.samples}
                    onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) =>
                      setCreateForm((f) => ({ ...f, samples: e.target.value }))
                    }
                    placeholder={`Welcome to the learning session.\nHow do you feel about math today?\nLet's practice together.`}
                    rows={4}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-100 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none"
                  />
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium">Configurations (JSON array)</label>
                  <textarea
                    value={createForm.configurations}
                    onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) =>
                      setCreateForm((f) => ({ ...f, configurations: e.target.value }))
                    }
                    placeholder={`[
  {"name": "Chatterbox Nova", "provider": "chatterbox", "voice_id": "nova", "settings": {"speed": 1.0}},
  {"name": "Piper Default", "provider": "piper", "voice_id": "default", "settings": {}}
]`}
                    rows={6}
                    className="w-full px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-100 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none font-mono text-sm"
                  />
                </div>
              </div>

              <div className="flex justify-end gap-2 mt-6">
                <Button variant="outline" onClick={() => setShowCreateDialog(false)}>
                  Cancel
                </Button>
                <Button
                  onClick={handleCreateSession}
                  disabled={isCreating || !createForm.name || !createForm.samples}
                >
                  {isCreating && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                  Create Session
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
