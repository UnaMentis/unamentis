'use client';

import { useState } from 'react';
import { X, ChevronRight, ChevronLeft, Zap, FileAudio, Eye, Loader2 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { HelpTooltip } from '@/components/ui/tooltip';
import type { TTSProfile, ExtractResponse } from '@/types/tts-pregen';
import { extractContent, createBatchJob, startBatchJob } from '@/lib/api-client';

interface BatchJobCreateFormProps {
  profiles: TTSProfile[];
  onComplete: () => void;
  onCancel: () => void;
}

type SourceType = 'knowledge-bowl' | 'curriculum' | 'custom';

interface FormData {
  name: string;
  sourceType: SourceType;
  profileId: string;
  includeQuestions: boolean;
  includeAnswers: boolean;
  includeHints: boolean;
  includeExplanations: boolean;
  outputFormat: string;
  normalizeVolume: boolean;
}

export function BatchJobCreateForm({ profiles, onComplete, onCancel }: BatchJobCreateFormProps) {
  const [step, setStep] = useState(1);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    sourceType: 'knowledge-bowl',
    profileId: profiles.find((p) => p.is_default)?.id || profiles[0]?.id || '',
    includeQuestions: true,
    includeAnswers: true,
    includeHints: true,
    includeExplanations: true,
    outputFormat: 'wav',
    normalizeVolume: false,
  });
  const [extractedContent, setExtractedContent] = useState<ExtractResponse | null>(null);
  const [extracting, setExtracting] = useState(false);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedProfile = profiles.find((p) => p.id === formData.profileId);

  const handleExtract = async () => {
    setExtracting(true);
    setError(null);
    try {
      const result = await extractContent({
        source_type: formData.sourceType,
        include_questions: formData.includeQuestions,
        include_answers: formData.includeAnswers,
        include_hints: formData.includeHints,
        include_explanations: formData.includeExplanations,
      });
      if (result.success) {
        setExtractedContent(result);
        setStep(3);
      } else {
        setError(result.error || 'Failed to extract content');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to extract content');
    } finally {
      setExtracting(false);
    }
  };

  const handleCreate = async (autoStart: boolean) => {
    if (!formData.name.trim()) {
      setError('Please enter a job name');
      return;
    }

    setCreating(true);
    setError(null);
    try {
      const result = await createBatchJob({
        name: formData.name,
        source_type: formData.sourceType,
        profile_id: formData.profileId || undefined,
        output_format: formData.outputFormat,
        normalize_volume: formData.normalizeVolume,
        include_questions: formData.includeQuestions,
        include_answers: formData.includeAnswers,
        include_hints: formData.includeHints,
        include_explanations: formData.includeExplanations,
      });

      if (result.success && result.job) {
        if (autoStart) {
          await startBatchJob(result.job.id);
        }
        onComplete();
      } else {
        setError(result.error || 'Failed to create job');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create job');
    } finally {
      setCreating(false);
    }
  };

  const canProceedStep1 =
    formData.includeQuestions ||
    formData.includeAnswers ||
    formData.includeHints ||
    formData.includeExplanations;

  const canProceedStep2 = !!formData.profileId;

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <Card className="bg-slate-900 border-slate-700 w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <CardHeader className="flex flex-row items-center justify-between border-b border-slate-800 pb-4">
          <CardTitle className="flex items-center gap-2 text-white">
            <Zap className="w-5 h-5 text-amber-400" />
            Create Batch Job
          </CardTitle>
          <Button variant="ghost" size="sm" onClick={onCancel}>
            <X className="w-5 h-5" />
          </Button>
        </CardHeader>

        <CardContent className="pt-6">
          {/* Step Indicator */}
          <div className="flex items-center justify-center gap-2 mb-6">
            {[1, 2, 3, 4].map((s) => (
              <div key={s} className="flex items-center">
                <div
                  className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                    s === step
                      ? 'bg-amber-500 text-white'
                      : s < step
                        ? 'bg-emerald-500 text-white'
                        : 'bg-slate-700 text-slate-400'
                  }`}
                >
                  {s}
                </div>
                {s < 4 && (
                  <div className={`w-12 h-0.5 ${s < step ? 'bg-emerald-500' : 'bg-slate-700'}`} />
                )}
              </div>
            ))}
          </div>

          {/* Step Labels */}
          <div className="flex justify-between text-xs text-slate-500 mb-8 px-4">
            <span>Source</span>
            <span>Profile</span>
            <span>Preview</span>
            <span>Create</span>
          </div>

          {/* Error */}
          {error && (
            <div className="p-3 mb-4 bg-red-500/10 border border-red-500/30 rounded-md text-red-400 text-sm">
              {error}
            </div>
          )}

          {/* Step 1: Source Selection */}
          {step === 1 && (
            <div className="space-y-6">
              <div>
                <Label className="text-slate-300 flex items-center">
                  Content Source
                  <HelpTooltip
                    content="Choose where the text content will come from. Knowledge Bowl contains quiz questions, answers, hints, and explanations."
                    side="right"
                  />
                </Label>
                <div className="grid grid-cols-3 gap-3 mt-2">
                  {(['knowledge-bowl', 'curriculum', 'custom'] as const).map((type) => (
                    <button
                      key={type}
                      onClick={() => setFormData((prev) => ({ ...prev, sourceType: type }))}
                      disabled={type !== 'knowledge-bowl'}
                      className={`p-4 rounded-lg border text-left transition-colors ${
                        formData.sourceType === type
                          ? 'border-amber-500 bg-amber-500/10'
                          : type === 'knowledge-bowl'
                            ? 'border-slate-700 hover:border-slate-600'
                            : 'border-slate-800 opacity-50 cursor-not-allowed'
                      }`}
                    >
                      <div className="font-medium text-slate-200">
                        {type === 'knowledge-bowl'
                          ? 'Knowledge Bowl'
                          : type === 'curriculum'
                            ? 'Curriculum'
                            : 'Custom'}
                      </div>
                      <div className="text-xs text-slate-500 mt-1">
                        {type === 'knowledge-bowl'
                          ? 'Questions & answers'
                          : type === 'curriculum'
                            ? 'Coming soon'
                            : 'Coming soon'}
                      </div>
                    </button>
                  ))}
                </div>
              </div>

              {formData.sourceType === 'knowledge-bowl' && (
                <div>
                  <Label className="text-slate-300 flex items-center">
                    Content Types
                    <HelpTooltip
                      content="Select which types of text to generate audio for. Questions are the prompts, Answers are correct responses, Hints help learners, and Explanations provide educational context."
                      side="right"
                    />
                  </Label>
                  <div className="grid grid-cols-2 gap-3 mt-2">
                    {[
                      { key: 'includeQuestions', label: 'Questions' },
                      { key: 'includeAnswers', label: 'Answers' },
                      { key: 'includeHints', label: 'Hints' },
                      { key: 'includeExplanations', label: 'Explanations' },
                    ].map(({ key, label }) => (
                      <label
                        key={key}
                        className="flex items-center gap-2 p-3 rounded-lg border border-slate-700 cursor-pointer hover:border-slate-600"
                      >
                        <input
                          type="checkbox"
                          checked={formData[key as keyof FormData] as boolean}
                          onChange={(e) =>
                            setFormData((prev) => ({
                              ...prev,
                              [key]: e.target.checked,
                            }))
                          }
                          className="w-4 h-4 rounded border-slate-600 text-amber-500 focus:ring-amber-500"
                        />
                        <span className="text-slate-300">{label}</span>
                      </label>
                    ))}
                  </div>
                </div>
              )}

              <div className="flex justify-end">
                <Button
                  onClick={() => setStep(2)}
                  disabled={!canProceedStep1}
                  className="bg-amber-600 hover:bg-amber-700"
                >
                  Next
                  <ChevronRight className="w-4 h-4 ml-1" />
                </Button>
              </div>
            </div>
          )}

          {/* Step 2: Profile Selection */}
          {step === 2 && (
            <div className="space-y-6">
              <div>
                <Label className="text-slate-300 flex items-center">
                  TTS Profile
                  <HelpTooltip
                    content="TTS profiles define voice settings like provider, speed, and expression. The default profile is pre-selected. Create profiles in the Profiles tab."
                    side="right"
                  />
                </Label>
                <p className="text-sm text-slate-500 mt-1">
                  Select the voice profile to use for audio generation
                </p>

                <div className="space-y-2 mt-4 max-h-64 overflow-y-auto">
                  {profiles.length === 0 ? (
                    <p className="text-slate-500 text-center py-4">
                      No profiles available. Create one first.
                    </p>
                  ) : (
                    profiles.map((profile) => (
                      <button
                        key={profile.id}
                        onClick={() =>
                          setFormData((prev) => ({
                            ...prev,
                            profileId: profile.id,
                          }))
                        }
                        className={`w-full p-4 rounded-lg border text-left transition-colors ${
                          formData.profileId === profile.id
                            ? 'border-amber-500 bg-amber-500/10'
                            : 'border-slate-700 hover:border-slate-600'
                        }`}
                      >
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-slate-200">{profile.name}</span>
                          {profile.is_default && (
                            <Badge className="bg-amber-500/20 text-amber-400 border-amber-500/30">
                              Default
                            </Badge>
                          )}
                        </div>
                        <div className="flex items-center gap-2 mt-1 text-xs text-slate-500">
                          <Badge
                            className={`${
                              profile.provider === 'chatterbox'
                                ? 'bg-purple-500/20 text-purple-400'
                                : profile.provider === 'vibevoice'
                                  ? 'bg-blue-500/20 text-blue-400'
                                  : 'bg-green-500/20 text-green-400'
                            }`}
                          >
                            {profile.provider}
                          </Badge>
                          <span>Speed: {profile.settings.speed}x</span>
                          {profile.settings.exaggeration !== undefined && (
                            <span>Expr: {profile.settings.exaggeration}</span>
                          )}
                        </div>
                        {profile.description && (
                          <p className="text-xs text-slate-500 mt-1">{profile.description}</p>
                        )}
                      </button>
                    ))
                  )}
                </div>
              </div>

              <div className="flex justify-between">
                <Button variant="outline" onClick={() => setStep(1)}>
                  <ChevronLeft className="w-4 h-4 mr-1" />
                  Back
                </Button>
                <Button
                  onClick={handleExtract}
                  disabled={!canProceedStep2 || extracting}
                  className="bg-amber-600 hover:bg-amber-700"
                >
                  {extracting ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Extracting...
                    </>
                  ) : (
                    <>
                      <Eye className="w-4 h-4 mr-2" />
                      Preview Content
                    </>
                  )}
                </Button>
              </div>
            </div>
          )}

          {/* Step 3: Preview */}
          {step === 3 && extractedContent && (
            <div className="space-y-6">
              <div>
                <Label className="text-slate-300">Content Preview</Label>
                <div className="mt-4 p-4 bg-slate-800/50 rounded-lg">
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <span className="text-slate-500">Total Items:</span>
                      <span className="text-white font-medium ml-2">
                        {extractedContent.total_count}
                      </span>
                    </div>
                    {extractedContent.stats?.total_questions && (
                      <div>
                        <span className="text-slate-500">Questions:</span>
                        <span className="text-white font-medium ml-2">
                          {extractedContent.stats.total_questions}
                        </span>
                      </div>
                    )}
                  </div>

                  {extractedContent.stats?.type_counts && (
                    <div className="mt-4">
                      <span className="text-slate-500 text-sm">By Type:</span>
                      <div className="flex flex-wrap gap-2 mt-2">
                        {Object.entries(extractedContent.stats.type_counts).map(([type, count]) => (
                          <Badge key={type} className="bg-slate-700 text-slate-300">
                            {type}: {count}
                          </Badge>
                        ))}
                      </div>
                    </div>
                  )}

                  {extractedContent.stats?.domain_counts && (
                    <div className="mt-4">
                      <span className="text-slate-500 text-sm">By Domain:</span>
                      <div className="flex flex-wrap gap-2 mt-2">
                        {Object.entries(extractedContent.stats.domain_counts).map(
                          ([domain, count]) => (
                            <Badge key={domain} className="bg-slate-700 text-slate-300">
                              {domain}: {count}
                            </Badge>
                          )
                        )}
                      </div>
                    </div>
                  )}
                </div>

                {/* Sample Items */}
                <div className="mt-4">
                  <span className="text-slate-500 text-sm">Sample Items:</span>
                  <div className="mt-2 space-y-2 max-h-40 overflow-y-auto">
                    {extractedContent.items.slice(0, 5).map((item, idx) => (
                      <div key={idx} className="p-2 bg-slate-800/30 rounded text-sm">
                        <span className="text-slate-500 text-xs">{item.source_ref}</span>
                        <p className="text-slate-300 truncate">{item.text}</p>
                      </div>
                    ))}
                    {extractedContent.items.length > 5 && (
                      <p className="text-slate-500 text-xs text-center">
                        +{extractedContent.items.length - 5} more items...
                      </p>
                    )}
                  </div>
                </div>
              </div>

              <div className="flex justify-between">
                <Button variant="outline" onClick={() => setStep(2)}>
                  <ChevronLeft className="w-4 h-4 mr-1" />
                  Back
                </Button>
                <Button onClick={() => setStep(4)} className="bg-amber-600 hover:bg-amber-700">
                  Continue
                  <ChevronRight className="w-4 h-4 ml-1" />
                </Button>
              </div>
            </div>
          )}

          {/* Step 4: Create */}
          {step === 4 && (
            <div className="space-y-6">
              <div>
                <Label htmlFor="jobName" className="text-slate-300 flex items-center">
                  Job Name
                  <HelpTooltip
                    content="A descriptive name to identify this batch job. Use something meaningful like 'KB Physics Jan 2026' to track jobs easily."
                    side="right"
                  />
                </Label>
                <Input
                  id="jobName"
                  value={formData.name}
                  onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))}
                  placeholder="e.g., KB Physics Questions Batch"
                  className="mt-2 bg-slate-800 border-slate-700"
                />
              </div>

              <div>
                <Label className="text-slate-300 flex items-center">
                  Output Format
                  <HelpTooltip
                    content="WAV is uncompressed (highest quality, larger files). MP3 is compressed (smaller files, good quality). OGG is open format (good compression)."
                    side="right"
                  />
                </Label>
                <div className="flex gap-3 mt-2">
                  {['wav', 'mp3', 'ogg'].map((format) => (
                    <button
                      key={format}
                      onClick={() => setFormData((prev) => ({ ...prev, outputFormat: format }))}
                      className={`px-4 py-2 rounded-lg border transition-colors ${
                        formData.outputFormat === format
                          ? 'border-amber-500 bg-amber-500/10 text-amber-400'
                          : 'border-slate-700 text-slate-400 hover:border-slate-600'
                      }`}
                    >
                      {format.toUpperCase()}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.normalizeVolume}
                    onChange={(e) =>
                      setFormData((prev) => ({
                        ...prev,
                        normalizeVolume: e.target.checked,
                      }))
                    }
                    className="w-4 h-4 rounded border-slate-600 text-amber-500 focus:ring-amber-500"
                  />
                  <span className="text-slate-300 flex items-center">
                    Normalize volume
                    <HelpTooltip
                      content="Adjusts audio levels to a consistent volume. Recommended when mixing audio from different sources to ensure even playback."
                      side="right"
                    />
                  </span>
                </label>
              </div>

              {/* Summary */}
              <div className="p-4 bg-slate-800/50 rounded-lg">
                <h4 className="text-sm font-medium text-slate-300 mb-3">Summary</h4>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-slate-500">Source:</span>
                    <span className="text-slate-300">
                      {formData.sourceType === 'knowledge-bowl'
                        ? 'Knowledge Bowl'
                        : formData.sourceType}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-slate-500">Profile:</span>
                    <span className="text-slate-300">{selectedProfile?.name || 'None'}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-slate-500">Items:</span>
                    <span className="text-slate-300">{extractedContent?.total_count || 0}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-slate-500">Format:</span>
                    <span className="text-slate-300">{formData.outputFormat.toUpperCase()}</span>
                  </div>
                </div>
              </div>

              <div className="flex justify-between">
                <Button variant="outline" onClick={() => setStep(3)}>
                  <ChevronLeft className="w-4 h-4 mr-1" />
                  Back
                </Button>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    onClick={() => handleCreate(false)}
                    disabled={creating || !formData.name.trim()}
                  >
                    {creating ? (
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    ) : (
                      <FileAudio className="w-4 h-4 mr-2" />
                    )}
                    Create
                  </Button>
                  <Button
                    onClick={() => handleCreate(true)}
                    disabled={creating || !formData.name.trim()}
                    className="bg-emerald-600 hover:bg-emerald-700"
                  >
                    {creating ? (
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    ) : (
                      <Zap className="w-4 h-4 mr-2" />
                    )}
                    Create & Start
                  </Button>
                </div>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
