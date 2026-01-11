'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  Brain,
  RefreshCw,
  Play,
  Trash2,
  MessageSquare,
  AlertCircle,
  CheckCircle,
  Layers,
  Activity,
  ChevronDown,
  ChevronRight,
  Send,
  Circle,
} from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatCard } from '@/components/ui/stat-card';
import type {
  FOVHealthStatus,
  FOVSessionDebug,
  FOVSessionSummary,
  FOVConfidenceAnalysis,
} from '@/types';
import {
  getFOVHealth,
  getFOVSessions,
  getFOVSessionDebug,
  createFOVSession,
  startFOVSession,
  addFOVTurn,
  handleFOVBargeIn,
  setFOVTopic,
  analyzeFOVResponse,
  deleteFOVSession,
} from '@/lib/api-client';
import { cn } from '@/lib/utils';

// Token usage bar component
function TokenUsageBar({
  label,
  budget,
  used,
  percentage,
  color,
}: {
  label: string;
  budget: number;
  used: number;
  percentage: number;
  color: string;
}) {
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs">
        <span className="text-slate-400">{label}</span>
        <span className="text-slate-300">
          {used.toLocaleString()} / {budget.toLocaleString()} ({percentage}%)
        </span>
      </div>
      <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
        <div
          className={cn('h-full rounded-full transition-all', color)}
          style={{ width: `${Math.min(percentage, 100)}%` }}
        />
      </div>
    </div>
  );
}

// Buffer state card component
function BufferCard({
  title,
  icon: Icon,
  children,
  color,
}: {
  title: string;
  icon: React.ElementType;
  children: React.ReactNode;
  color: string;
}) {
  return (
    <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700/50">
      <div className="flex items-center gap-2 mb-2">
        <div className={cn('p-1 rounded', color)}>
          <Icon className="w-3.5 h-3.5" />
        </div>
        <span className="text-sm font-medium text-slate-200">{title}</span>
      </div>
      <div className="text-xs text-slate-400 space-y-1">{children}</div>
    </div>
  );
}

// Confidence indicator component
function ConfidenceIndicator({ score, label }: { score: number; label: string }) {
  const getColor = (s: number) => {
    if (s >= 0.8) return 'text-emerald-400';
    if (s >= 0.6) return 'text-yellow-400';
    if (s >= 0.4) return 'text-orange-400';
    return 'text-red-400';
  };

  return (
    <div className="flex items-center justify-between">
      <span className="text-slate-400">{label}</span>
      <span className={cn('font-mono', getColor(score))}>{(score * 100).toFixed(0)}%</span>
    </div>
  );
}

// Session list item component
function SessionListItem({
  session,
  isSelected,
  onSelect,
  onDelete,
}: {
  session: FOVSessionSummary;
  isSelected: boolean;
  onSelect: () => void;
  onDelete: () => void;
}) {
  const stateColors: Record<string, string> = {
    created: 'bg-blue-400',
    active: 'bg-emerald-400',
    paused: 'bg-amber-400',
    ended: 'bg-slate-500',
  };

  return (
    <div
      className={cn(
        'flex items-center justify-between p-3 rounded-lg cursor-pointer transition-colors',
        isSelected
          ? 'bg-blue-500/20 border border-blue-500/50'
          : 'bg-slate-800/30 hover:bg-slate-800/50'
      )}
      onClick={onSelect}
    >
      <div className="flex items-center gap-3">
        <div
          className={cn('w-2 h-2 rounded-full', stateColors[session.state] || stateColors.ended)}
        />
        <div>
          <div className="text-sm font-medium text-slate-100 truncate max-w-[150px]">
            {session.session_id.slice(0, 8)}...
          </div>
          <div className="text-xs text-slate-400">{session.turn_count} turns</div>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <Badge variant={session.state === 'active' ? 'success' : 'default'}>{session.state}</Badge>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
          className="p-1 text-slate-500 hover:text-red-400 transition-colors"
        >
          <Trash2 className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}

export function FOVContextPanel() {
  const [health, setHealth] = useState<FOVHealthStatus | null>(null);
  const [sessions, setSessions] = useState<FOVSessionSummary[]>([]);
  const [selectedSession, setSelectedSession] = useState<FOVSessionDebug | null>(null);
  const [loading, setLoading] = useState(true);
  const [expandedBuffers, setExpandedBuffers] = useState(true);
  const [testInput, setTestInput] = useState('');
  const [testResponse, setTestResponse] = useState('');
  const [analysisResult, setAnalysisResult] = useState<FOVConfidenceAnalysis | null>(null);

  const fetchData = useCallback(async () => {
    try {
      const [healthData, sessionsData] = await Promise.all([getFOVHealth(), getFOVSessions()]);
      setHealth(healthData);
      setSessions(sessionsData.sessions || []);
    } catch (error) {
      console.error('Failed to fetch FOV data:', error);
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchSessionDebug = useCallback(async (sessionId: string) => {
    try {
      const debug = await getFOVSessionDebug(sessionId);
      setSelectedSession(debug);
    } catch (error) {
      console.error('Failed to fetch session debug:', error);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, [fetchData]);

  useEffect(() => {
    if (selectedSession) {
      const interval = setInterval(() => {
        fetchSessionDebug(selectedSession.session_id);
      }, 2000);
      return () => clearInterval(interval);
    }
  }, [selectedSession, fetchSessionDebug]);

  const handleCreateSession = async () => {
    try {
      const result = await createFOVSession({
        curriculum_id: `test-curriculum-${Date.now()}`,
        model_context_window: 200000,
      });
      if (result.session_id) {
        await fetchData();
        await fetchSessionDebug(result.session_id);
      }
    } catch (error) {
      console.error('Failed to create session:', error);
    }
  };

  const handleStartSession = async () => {
    if (!selectedSession) return;
    try {
      await startFOVSession(selectedSession.session_id);
      await fetchSessionDebug(selectedSession.session_id);
      await fetchData();
    } catch (error) {
      console.error('Failed to start session:', error);
    }
  };

  const handleDeleteSession = async (sessionId: string) => {
    try {
      await deleteFOVSession(sessionId);
      if (selectedSession?.session_id === sessionId) {
        setSelectedSession(null);
      }
      await fetchData();
    } catch (error) {
      console.error('Failed to delete session:', error);
    }
  };

  const handleSendMessage = async () => {
    if (!selectedSession || !testInput.trim()) return;
    try {
      // Add user turn
      await addFOVTurn(selectedSession.session_id, 'user', testInput);
      setTestInput('');
      await fetchSessionDebug(selectedSession.session_id);
    } catch (error) {
      console.error('Failed to send message:', error);
    }
  };

  const handleBargeIn = async () => {
    if (!selectedSession || !testInput.trim()) return;
    try {
      const result = await handleFOVBargeIn(selectedSession.session_id, testInput);
      setTestInput('');
      setTestResponse(JSON.stringify(result.context, null, 2));
      await fetchSessionDebug(selectedSession.session_id);
    } catch (error) {
      console.error('Failed to handle barge-in:', error);
    }
  };

  const handleAnalyzeResponse = async () => {
    if (!selectedSession || !testResponse.trim()) return;
    try {
      const result = await analyzeFOVResponse(selectedSession.session_id, testResponse);
      setAnalysisResult(result);
    } catch (error) {
      console.error('Failed to analyze response:', error);
    }
  };

  const handleSetTopic = async () => {
    if (!selectedSession) return;
    try {
      await setFOVTopic(selectedSession.session_id, {
        topic_id: `topic-${Date.now()}`,
        topic_title: 'Test Topic: Introduction to Physics',
        topic_content: 'Physics is the natural science of matter and energy.',
        learning_objectives: ['Understand basic physics concepts'],
        glossary_terms: [{ term: 'Energy', definition: 'The capacity to do work' }],
      });
      await fetchSessionDebug(selectedSession.session_id);
    } catch (error) {
      console.error('Failed to set topic:', error);
    }
  };

  return (
    <div className="space-y-6">
      {/* Health Stats */}
      <div className="grid grid-cols-4 gap-4">
        <StatCard
          icon={health?.status === 'healthy' ? CheckCircle : AlertCircle}
          value={health?.status || 'Unknown'}
          label="System Status"
          iconColor={health?.status === 'healthy' ? 'text-emerald-400' : 'text-red-400'}
          iconBgColor={health?.status === 'healthy' ? 'bg-emerald-400/20' : 'bg-red-400/20'}
        />
        <StatCard
          icon={Brain}
          value={health?.sessions?.total || 0}
          label="Total Sessions"
          iconColor="text-blue-400"
          iconBgColor="bg-blue-400/20"
        />
        <StatCard
          icon={Activity}
          value={health?.sessions?.active || 0}
          label="Active Sessions"
          iconColor="text-emerald-400"
          iconBgColor="bg-emerald-400/20"
        />
        <StatCard
          icon={Circle}
          value={health?.sessions?.paused || 0}
          label="Paused Sessions"
          iconColor="text-amber-400"
          iconBgColor="bg-amber-400/20"
        />
      </div>

      <div className="grid grid-cols-3 gap-6">
        {/* Sessions List */}
        <Card>
          <CardHeader>
            <CardTitle>
              <Layers className="w-5 h-5" />
              FOV Sessions
            </CardTitle>
            <div className="flex gap-2">
              <button
                onClick={handleCreateSession}
                className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-all"
              >
                <Play className="w-3 h-3" />
                New
              </button>
              <button
                onClick={fetchData}
                className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
              >
                <RefreshCw className="w-3 h-3" />
              </button>
            </div>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="text-center text-slate-500 py-8">Loading sessions...</div>
            ) : sessions.length === 0 ? (
              <div className="text-center text-slate-500 py-8">
                <Brain className="w-12 h-12 mx-auto mb-2 opacity-50" />
                <p>No FOV sessions</p>
                <p className="text-xs mt-1">Create a session to test the FOV system</p>
              </div>
            ) : (
              <div className="space-y-2 max-h-[400px] overflow-y-auto">
                {sessions.map((session) => (
                  <SessionListItem
                    key={session.session_id}
                    session={session}
                    isSelected={selectedSession?.session_id === session.session_id}
                    onSelect={() => fetchSessionDebug(session.session_id)}
                    onDelete={() => handleDeleteSession(session.session_id)}
                  />
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Session Detail */}
        <Card className="col-span-2">
          <CardHeader>
            <CardTitle>
              <Activity className="w-5 h-5" />
              Session Detail
            </CardTitle>
            {selectedSession && (
              <div className="flex gap-2">
                {selectedSession.state === 'created' && (
                  <button
                    onClick={handleStartSession}
                    className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30 transition-all"
                  >
                    <Play className="w-3 h-3" />
                    Start
                  </button>
                )}
                <button
                  onClick={handleSetTopic}
                  className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 transition-all"
                >
                  Set Topic
                </button>
              </div>
            )}
          </CardHeader>
          <CardContent>
            {!selectedSession ? (
              <div className="text-center text-slate-500 py-12">
                <Layers className="w-16 h-16 mx-auto mb-4 opacity-30" />
                <p className="text-lg font-medium">Select a session</p>
                <p className="text-sm mt-1">Click a session to view details</p>
              </div>
            ) : (
              <div className="space-y-4">
                {/* Session Info */}
                <div className="flex items-center justify-between p-3 rounded-lg bg-slate-800/30">
                  <div>
                    <div className="text-sm font-medium text-slate-100">
                      Session: {selectedSession.session_id.slice(0, 12)}...
                    </div>
                    <div className="text-xs text-slate-400">
                      Tier: {selectedSession.model_tier} | Turns: {selectedSession.turn_count} |
                      Barge-ins: {selectedSession.barge_in_count}
                    </div>
                  </div>
                  <Badge variant={selectedSession.state === 'active' ? 'success' : 'default'}>
                    {selectedSession.state}
                  </Badge>
                </div>

                {/* Token Usage */}
                <div className="space-y-3">
                  <div
                    className="flex items-center gap-2 cursor-pointer"
                    onClick={() => setExpandedBuffers(!expandedBuffers)}
                  >
                    {expandedBuffers ? (
                      <ChevronDown className="w-4 h-4 text-slate-400" />
                    ) : (
                      <ChevronRight className="w-4 h-4 text-slate-400" />
                    )}
                    <span className="text-sm font-medium text-slate-200">
                      Token Usage ({selectedSession.total_context_tokens.toLocaleString()} total)
                    </span>
                  </div>
                  {expandedBuffers && selectedSession.token_usage && (
                    <div className="space-y-2 pl-6">
                      <TokenUsageBar
                        label="Immediate"
                        budget={selectedSession.token_usage.immediate?.budget || 0}
                        used={selectedSession.token_usage.immediate?.estimated_used || 0}
                        percentage={selectedSession.token_usage.immediate?.percentage || 0}
                        color="bg-blue-500"
                      />
                      <TokenUsageBar
                        label="Working"
                        budget={selectedSession.token_usage.working?.budget || 0}
                        used={selectedSession.token_usage.working?.estimated_used || 0}
                        percentage={selectedSession.token_usage.working?.percentage || 0}
                        color="bg-purple-500"
                      />
                      <TokenUsageBar
                        label="Episodic"
                        budget={selectedSession.token_usage.episodic?.budget || 0}
                        used={selectedSession.token_usage.episodic?.estimated_used || 0}
                        percentage={selectedSession.token_usage.episodic?.percentage || 0}
                        color="bg-amber-500"
                      />
                      <TokenUsageBar
                        label="Semantic"
                        budget={selectedSession.token_usage.semantic?.budget || 0}
                        used={selectedSession.token_usage.semantic?.estimated_used || 0}
                        percentage={selectedSession.token_usage.semantic?.percentage || 0}
                        color="bg-emerald-500"
                      />
                    </div>
                  )}
                </div>

                {/* Buffer States */}
                <div className="grid grid-cols-2 gap-3">
                  <BufferCard
                    title="Immediate Buffer"
                    icon={MessageSquare}
                    color="bg-blue-500/20 text-blue-400"
                  >
                    <p>
                      Turns: {selectedSession.buffers.immediate.turn_count} /{' '}
                      {selectedSession.buffers.immediate.max_turns}
                    </p>
                    <p>Segment: {selectedSession.buffers.immediate.current_segment || 'None'}</p>
                    <p>Barge-in: {selectedSession.buffers.immediate.barge_in || 'None'}</p>
                  </BufferCard>
                  <BufferCard
                    title="Working Buffer"
                    icon={Brain}
                    color="bg-purple-500/20 text-purple-400"
                  >
                    <p>Topic: {selectedSession.buffers.working.topic_title || 'None'}</p>
                    <p>Glossary: {selectedSession.buffers.working.glossary_count} terms</p>
                    <p>Misconceptions: {selectedSession.buffers.working.misconception_count}</p>
                  </BufferCard>
                  <BufferCard
                    title="Episodic Buffer"
                    icon={Activity}
                    color="bg-amber-500/20 text-amber-400"
                  >
                    <p>Summaries: {selectedSession.buffers.episodic.topic_summary_count}</p>
                    <p>Questions: {selectedSession.buffers.episodic.questions_count}</p>
                    <p>
                      Signals: {selectedSession.buffers.episodic.learner_signals.clarifications}C /{' '}
                      {selectedSession.buffers.episodic.learner_signals.repetitions}R /{' '}
                      {selectedSession.buffers.episodic.learner_signals.confusions}X
                    </p>
                  </BufferCard>
                  <BufferCard
                    title="Semantic Buffer"
                    icon={Layers}
                    color="bg-emerald-500/20 text-emerald-400"
                  >
                    <p>Curriculum: {selectedSession.buffers.semantic.curriculum_id || 'None'}</p>
                    <p>
                      Position: {selectedSession.buffers.semantic.current_topic_index} /{' '}
                      {selectedSession.buffers.semantic.total_topics}
                    </p>
                    <p>Outline: {selectedSession.buffers.semantic.has_outline ? 'Yes' : 'No'}</p>
                  </BufferCard>
                </div>

                {/* Test Interface */}
                {selectedSession.state === 'active' && (
                  <div className="space-y-3 pt-2 border-t border-slate-700/50">
                    <div className="text-sm font-medium text-slate-200">Test Interface</div>
                    <div className="flex gap-2">
                      <input
                        type="text"
                        value={testInput}
                        onChange={(e) => setTestInput(e.target.value)}
                        placeholder="Enter message or barge-in utterance..."
                        className="flex-1 px-3 py-2 text-sm rounded-lg bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50"
                        onKeyDown={(e) => e.key === 'Enter' && handleSendMessage()}
                      />
                      <button
                        onClick={handleSendMessage}
                        className="px-3 py-2 rounded-lg bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 transition-all"
                        title="Send as user message"
                      >
                        <Send className="w-4 h-4" />
                      </button>
                      <button
                        onClick={handleBargeIn}
                        className="px-3 py-2 rounded-lg bg-red-500/20 text-red-400 hover:bg-red-500/30 transition-all"
                        title="Send as barge-in"
                      >
                        <AlertCircle className="w-4 h-4" />
                      </button>
                    </div>
                    <div className="flex gap-2">
                      <textarea
                        value={testResponse}
                        onChange={(e) => setTestResponse(e.target.value)}
                        placeholder="Paste LLM response to analyze confidence..."
                        className="flex-1 px-3 py-2 text-sm rounded-lg bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50 h-20 resize-none font-mono text-xs"
                      />
                      <button
                        onClick={handleAnalyzeResponse}
                        className="px-3 py-2 h-fit rounded-lg bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 transition-all"
                        title="Analyze response confidence"
                      >
                        <Activity className="w-4 h-4" />
                      </button>
                    </div>

                    {/* Analysis Result */}
                    {analysisResult && (
                      <div className="p-3 rounded-lg bg-slate-800/50 border border-slate-700/50 space-y-2">
                        <div className="text-xs font-medium text-slate-300">
                          Confidence Analysis
                        </div>
                        <div className="grid grid-cols-3 gap-2 text-xs">
                          <ConfidenceIndicator
                            score={analysisResult.confidence_score}
                            label="Confidence"
                          />
                          <ConfidenceIndicator
                            score={1 - analysisResult.uncertainty_score}
                            label="Certainty"
                          />
                          <ConfidenceIndicator
                            score={1 - analysisResult.hedging_score}
                            label="Directness"
                          />
                        </div>
                        {analysisResult.expansion?.should_expand && (
                          <div className="text-xs p-2 rounded bg-amber-500/10 border border-amber-500/30 text-amber-300">
                            Expansion recommended: {analysisResult.expansion.reason}
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

// Compact version for dashboard overview
export function FOVContextPanelCompact() {
  const [health, setHealth] = useState<FOVHealthStatus | null>(null);

  useEffect(() => {
    const fetchHealth = async () => {
      try {
        const data = await getFOVHealth();
        setHealth(data);
      } catch (error) {
        console.error('Failed to fetch FOV health:', error);
      }
    };

    fetchHealth();
    const interval = setInterval(fetchHealth, 10000);
    return () => clearInterval(interval);
  }, []);

  const statusColor = health?.status === 'healthy' ? 'bg-emerald-400' : 'bg-red-400';

  return (
    <Card>
      <CardHeader>
        <CardTitle>
          <Brain className="w-5 h-5" />
          FOV Context
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className={cn('w-2 h-2 rounded-full', statusColor)} />
            <span className="text-sm text-slate-300">{health?.status || 'Unknown'}</span>
          </div>
          <div className="text-sm text-slate-400">
            {health?.sessions?.active || 0} active / {health?.sessions?.total || 0} total
          </div>
        </div>
        {health?.features && (
          <div className="mt-3 flex flex-wrap gap-1">
            {health.features.confidence_monitoring && <Badge variant="default">Confidence</Badge>}
            {health.features.context_expansion && <Badge variant="default">Expansion</Badge>}
            {health.features.adaptive_budgets && <Badge variant="default">Adaptive</Badge>}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
