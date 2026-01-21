'use client';

import { useState, useRef } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Volume2,
  Smartphone,
  Server,
  Download,
  Zap,
  TrendingUp,
  ExternalLink,
  Play,
  Pause,
  Square,
  Loader2,
} from 'lucide-react';
import { cn } from '@/lib/utils';

/**
 * Voice Model Selection Panel (Voice Lab)
 *
 * Displays TTS (Text-to-Speech) model recommendations for UnaMentis.
 * This panel is focused exclusively on voice/TTS models.
 * For LLM management, see Operations > Models.
 *
 * Updated: January 2026
 */

/**
 * Reference text for TTS evaluation samples.
 * This text is designed to test various TTS capabilities:
 * - Challenging pronunciations (proper nouns, technical terms)
 * - Natural phrasing and rhythm
 * - Question intonation
 * - Emotional expression
 * - Comma pauses and sentence flow
 */
const TTS_REFERENCE_TEXT = `The quick mathematician, Dr. Sarah Chen, carefully examined the peculiar equation. "Could this really be correct?" she wondered aloud, her eyes widening with excitement. After seventeen years of research, breakthrough discoveries still thrilled her. Numbers, equations, and the elegant beauty of mathematics had always been her true passion.`;

/**
 * Gets the audio sample URL for a given model.
 * Samples are pre-generated using the reference text above with optimal default settings.
 */
function getSampleAudioUrl(modelId: string): string {
  return `/audio/tts-samples/${modelId}.opus`;
}

interface TTSModelInfo {
  id: string; // Unique identifier for audio sample files
  name: string;
  version: string;
  releaseDate: string;
  size: string;
  parameters: string;
  performance: string;
  license: string;
  status: 'current' | 'recommended' | 'outdated';
  benchmarks?: { name: string; score: string }[];
  features: string[];
  deployment: string;
  url: string;
  hasSample?: boolean; // Whether a pre-generated sample exists
}

const serverTTS: TTSModelInfo[] = [
  {
    id: 'chatterbox-turbo',
    name: 'Chatterbox Turbo',
    version: '350M',
    releaseDate: 'December 2025',
    size: '~350MB',
    parameters: '350 million',
    performance: '75ms latency, 6x real-time',
    license: 'MIT',
    status: 'recommended',
    hasSample: true,
    benchmarks: [
      { name: 'Latency', score: '75ms' },
      { name: 'RTF', score: '0.16x' },
      { name: 'VRAM', score: '2.5GB' },
    ],
    features: [
      'Ultra-low latency (75ms)',
      'Paralinguistic tags ([laugh], [sigh], [gasp])',
      'Emotion control via exaggeration slider',
      'CFG weight for generation fidelity',
      'Zero-shot voice cloning (future)',
      '23 languages (500M multilingual model)',
      'OpenAI-compatible API',
    ],
    deployment: 'GPU server (CUDA/ROCm), CPU fallback available',
    url: 'https://github.com/resemble-ai/chatterbox',
  },
  {
    id: 'fish-speech-v1.5',
    name: 'Fish Speech V1.5',
    version: 'V1.5',
    releaseDate: 'Late 2025',
    size: '~2GB',
    parameters: 'DualAR Transformer',
    performance: 'Industry-leading (ELO 1339)',
    license: 'BSD-3-Clause',
    status: 'recommended',
    hasSample: true,
    benchmarks: [
      { name: 'ELO Score', score: '1339' },
      { name: 'WER (English)', score: '3.5%' },
      { name: 'CER (English)', score: '1.2%' },
    ],
    features: [
      'DualAR architecture innovation',
      '300k+ hours English/Chinese training',
      '100k+ hours Japanese',
      'Exceptional multilingual support',
      'Industry-leading quality',
      'Low error rates',
    ],
    deployment: 'GPU server, CPU fallback available',
    url: 'https://speech.fish.audio/',
  },
  {
    id: 'kyutai-tts-1.6b',
    name: 'Kyutai TTS 1.6B',
    version: '1.6B',
    releaseDate: 'July 2025',
    size: '~1.6GB',
    parameters: '1.6 billion',
    performance: 'Low-latency delayed streams',
    license: 'MIT',
    status: 'recommended',
    hasSample: true,
    features: [
      'Delayed streams modeling',
      'Starts generating before full text input',
      'Ideal for voice assistants (low latency)',
      'English and French support',
      'Open source from Kyutai Labs',
      '220ms delay with Unmute wrapper',
    ],
    deployment: 'GPU server recommended',
    url: 'https://huggingface.co/kyutai/tts-1.6b-en_fr',
  },
  {
    id: 'index-tts-2',
    name: 'IndexTTS-2',
    version: '2',
    releaseDate: 'Late 2025',
    size: '~1.5GB',
    parameters: 'Transformer-based',
    performance: 'Zero-shot with precise duration control',
    license: 'Apache 2.0',
    status: 'recommended',
    hasSample: false, // TODO: Regenerate - checkpoint version mismatch
    features: [
      'Zero-shot voice synthesis',
      'Precise duration control',
      'Emotional disentanglement',
      'Perfect for video dubbing',
      'Professional expressive speech',
      'Fine-grained timing control',
    ],
    deployment: 'GPU server recommended',
    url: 'https://github.com/alibaba-damo-academy/IndexTTS',
  },
  {
    id: 'vibevoice-1.5b',
    name: 'VibeVoice-1.5B',
    version: '1.5B',
    releaseDate: 'Late 2025',
    size: '~3GB',
    parameters: '1.5 billion',
    performance: 'Long-form, multi-speaker generation',
    license: 'MIT',
    status: 'recommended',
    hasSample: true,
    features: [
      'Microsoft official release',
      'Up to 90 minutes of speech',
      'Four distinct speakers',
      'Highly expressive',
      'Long-form content generation',
      'Multi-speaker scenarios',
    ],
    deployment: 'GPU server (moderate requirements)',
    url: 'https://aka.ms/vibevoice',
  },
];

const onDeviceTTS: TTSModelInfo[] = [
  {
    id: 'kyutai-pocket-tts',
    name: 'Kyutai Pocket TTS',
    version: '100M',
    releaseDate: 'Jan 13, 2026',
    size: '~100MB',
    parameters: '100 million',
    performance: 'Best WER (1.84%), sub-50ms latency',
    license: 'MIT',
    status: 'recommended',
    hasSample: true,
    benchmarks: [
      { name: 'Word Error Rate', score: '1.84% (best)' },
      { name: 'Speed', score: '6x realtime (M4 CPU)' },
      { name: 'First Audio', score: '200ms' },
    ],
    features: [
      'Released Jan 13, 2026 (NEWEST)',
      'Best WER (1.84%) - beats 700M models',
      'Voice cloning from 5 seconds',
      'Sub-50ms latency',
      'CPU-only (no GPU needed)',
      '6x real-time on MacBook Air M4',
      '88,000 hours training data',
      'Full training code published',
      'CALM architecture',
    ],
    deployment: 'Any CPU - iPhone, Android, even low-end devices',
    url: 'https://kyutai.org/blog/2026-01-13-pocket-tts',
  },
  {
    id: 'neutts-air',
    name: 'NeuTTS Air',
    version: 'Air',
    releaseDate: 'Late 2025',
    size: '~500MB (GGUF)',
    parameters: '0.5 billion',
    performance: 'Super-realistic, instant voice cloning',
    license: 'Apache 2.0',
    status: 'recommended',
    hasSample: true,
    features: [
      'On-device super-realistic TTS',
      'Instant voice cloning',
      '0.5B parameters',
      'Near-human speech quality',
      'Real-time performance',
      'GGUF/GGML format (llama.cpp compatible)',
      'Runs on CPU/GPU',
      'Works on Raspberry Pi',
    ],
    deployment: 'iPhone 12+, Android 10+, even Raspberry Pi',
    url: 'https://github.com/neuphonic/neutts',
  },
  {
    id: 'kokoro-82m',
    name: 'Kokoro-82M',
    version: '82M',
    releaseDate: 'Late 2025',
    size: '~80MB',
    parameters: '82 million',
    performance: 'Lightweight, high quality',
    license: 'Apache 2.0',
    status: 'recommended',
    hasSample: true,
    features: [
      'Only 82M parameters',
      'Quality comparable to larger models',
      'Based on StyleTTS2 and ISTFTNet',
      'No encoders or diffusion (faster)',
      'Extremely efficient',
      'Cost-effective deployment',
    ],
    deployment: 'Any modern smartphone, very low requirements',
    url: 'https://github.com/kokoro-ai/kokoro',
  },
  {
    id: 'apple-neural-tts',
    name: 'Apple Neural TTS',
    version: 'iOS 18+',
    releaseDate: '2024',
    size: 'Built-in',
    parameters: 'Unknown (proprietary)',
    performance: 'Efficient but limited quality',
    license: 'Proprietary',
    status: 'current',
    hasSample: false, // Cannot generate samples for proprietary system TTS
    features: [
      'Built into iOS/macOS',
      'Zero download size',
      'Very efficient',
      'Limited naturalness',
      'Good fallback option',
      'Always available',
    ],
    deployment: 'All iOS/macOS devices',
    url: 'https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer',
  },
];

function StatusBadge({ status }: { status: TTSModelInfo['status'] }) {
  const variants = {
    current: 'info',
    recommended: 'success',
    outdated: 'secondary',
  } as const;

  return (
    <Badge variant={variants[status]} className="flex items-center gap-1">
      {status === 'recommended' && <TrendingUp className="w-3 h-3" />}
      {status.toUpperCase()}
    </Badge>
  );
}

interface TTSModelCardProps {
  model: TTSModelInfo;
  isPlaying: boolean;
  isLoading: boolean;
  onPlay: () => void;
  onStop: () => void;
}

function TTSModelCard({ model, isPlaying, isLoading, onPlay, onStop }: TTSModelCardProps) {
  const handlePlayClick = () => {
    if (isPlaying) {
      onStop();
    } else {
      onPlay();
    }
  };

  return (
    <Card className={model.status === 'recommended' ? 'border-emerald-500 border-2' : ''}>
      <CardHeader>
        <div className="flex items-start justify-between">
          <div>
            <CardTitle className="text-xl flex items-center gap-2">
              {model.name}
              <StatusBadge status={model.status} />
            </CardTitle>
            <CardDescription className="mt-1">
              Released: {model.releaseDate} • {model.license}
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            {model.hasSample && (
              <button
                onClick={handlePlayClick}
                disabled={isLoading}
                className={cn(
                  'flex items-center justify-center w-10 h-10 rounded-full transition-all',
                  isPlaying
                    ? 'bg-orange-500 text-white hover:bg-orange-600'
                    : 'bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30 border border-emerald-500/50'
                )}
                title={isPlaying ? 'Stop playback' : 'Preview voice sample'}
              >
                {isLoading ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : isPlaying ? (
                  <Square className="w-4 h-4" />
                ) : (
                  <Play className="w-5 h-5 ml-0.5" />
                )}
              </button>
            )}
            <a
              href={model.url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-400 hover:text-blue-300"
            >
              <ExternalLink className="w-5 h-5" />
            </a>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Audio Sample Info */}
        {model.hasSample && isPlaying && (
          <div className="bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-3 text-sm">
            <div className="flex items-center gap-2 text-emerald-400">
              <Volume2 className="w-4 h-4 animate-pulse" />
              <span>Playing sample audio...</span>
            </div>
          </div>
        )}

        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <div className="font-semibold flex items-center gap-1">
              <Download className="w-4 h-4" />
              Size
            </div>
            <div className="text-slate-400">{model.size}</div>
          </div>
          <div>
            <div className="font-semibold flex items-center gap-1">
              <Volume2 className="w-4 h-4" />
              Parameters
            </div>
            <div className="text-slate-400">{model.parameters}</div>
          </div>
          <div className="col-span-2">
            <div className="font-semibold flex items-center gap-1">
              <Zap className="w-4 h-4" />
              Performance
            </div>
            <div className="text-slate-400">{model.performance}</div>
          </div>
          <div className="col-span-2">
            <div className="font-semibold">Deployment</div>
            <div className="text-slate-400 text-xs">{model.deployment}</div>
          </div>
        </div>

        {model.benchmarks && model.benchmarks.length > 0 && (
          <div>
            <div className="font-semibold mb-2">Benchmarks</div>
            <div className="grid grid-cols-2 gap-2 text-sm">
              {model.benchmarks.map((bench) => (
                <div key={bench.name} className="bg-slate-800/50 p-2 rounded">
                  <div className="font-medium">{bench.name}</div>
                  <div className="text-slate-400">{bench.score}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        <div>
          <div className="font-semibold mb-2">Features</div>
          <ul className="text-sm space-y-1 list-disc list-inside text-slate-400">
            {model.features.map((feature, idx) => (
              <li key={idx}>{feature}</li>
            ))}
          </ul>
        </div>
      </CardContent>
    </Card>
  );
}

export function ModelSelectionPanel() {
  const [playingModelId, setPlayingModelId] = useState<string | null>(null);
  const [loadingModelId, setLoadingModelId] = useState<string | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const handlePlay = (modelId: string) => {
    // Stop any currently playing audio
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current = null;
    }

    setLoadingModelId(modelId);

    const audio = new Audio(getSampleAudioUrl(modelId));
    audioRef.current = audio;

    audio.addEventListener('canplaythrough', () => {
      // Only play if this audio is still the current one (not stopped)
      if (audioRef.current === audio) {
        setLoadingModelId(null);
        setPlayingModelId(modelId);
        audio.play();
      }
    });

    audio.addEventListener('ended', () => {
      if (audioRef.current === audio) {
        setPlayingModelId(null);
      }
    });

    audio.addEventListener('error', () => {
      if (audioRef.current === audio) {
        setLoadingModelId(null);
        setPlayingModelId(null);
        console.warn(`TTS sample for ${modelId} not available yet`);
      }
    });

    audio.load();
  };

  const handleStop = () => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
      audioRef.current = null;
    }
    setPlayingModelId(null);
    setLoadingModelId(null);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-slate-100 mb-2">TTS Model Selection</h1>
        <p className="text-slate-400">
          Current and recommended Text-to-Speech models for UnaMentis (Updated: January 2026)
        </p>
        <p className="text-sm text-blue-400 mt-2">💡 For LLM management, see Operations → Models</p>
      </div>

      {/* Reference Text Info */}
      <Card className="border-indigo-500/30 bg-indigo-500/5">
        <CardHeader className="pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <Volume2 className="w-5 h-5 text-indigo-400" />
            Voice Samples Reference Text
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-slate-300 italic">&quot;{TTS_REFERENCE_TEXT}&quot;</p>
          <p className="text-xs text-slate-500 mt-2">
            Click the play button on any model to hear a sample generated with this text.
          </p>
        </CardContent>
      </Card>

      <Tabs defaultValue="server-tts" className="space-y-4">
        <TabsList className="grid w-full grid-cols-2 max-w-md">
          <TabsTrigger value="server-tts" className="flex items-center gap-2">
            <Server className="w-4 h-4" />
            Server TTS
          </TabsTrigger>
          <TabsTrigger value="on-device-tts" className="flex items-center gap-2">
            <Smartphone className="w-4 h-4" />
            On-Device TTS
          </TabsTrigger>
        </TabsList>

        <TabsContent value="server-tts" className="space-y-6">
          <div className="bg-slate-800/50 p-4 rounded-lg">
            <h3 className="font-semibold mb-2">Use Case: Pre-generated Tutoring Audio</h3>
            <p className="text-sm text-slate-400">
              High-quality text-to-speech for pre-generating tutoring content. Prioritizes
              naturalness, expressiveness, and multilingual support. Deployed on GPU servers for
              batch processing.
            </p>
          </div>
          <div className="grid gap-6 md:grid-cols-2">
            {serverTTS.map((model) => (
              <TTSModelCard
                key={model.id}
                model={model}
                isPlaying={playingModelId === model.id}
                isLoading={loadingModelId === model.id}
                onPlay={() => handlePlay(model.id)}
                onStop={handleStop}
              />
            ))}
          </div>
        </TabsContent>

        <TabsContent value="on-device-tts" className="space-y-6">
          <div className="bg-slate-800/50 p-4 rounded-lg">
            <h3 className="font-semibold mb-2">Use Case: Interactive On-Device TTS Fallback</h3>
            <p className="text-sm text-slate-400">
              Lightweight text-to-speech for real-time interactive responses when server TTS is
              unavailable. Prioritizes efficiency and small size. Last resort fallback, as most
              content will use pre-generated server TTS.
            </p>
          </div>
          <div className="grid gap-6 md:grid-cols-2">
            {onDeviceTTS.map((model) => (
              <TTSModelCard
                key={model.id}
                model={model}
                isPlaying={playingModelId === model.id}
                isLoading={loadingModelId === model.id}
                onPlay={() => handlePlay(model.id)}
                onStop={handleStop}
              />
            ))}
          </div>
        </TabsContent>
      </Tabs>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>TTS Model Selection Guidelines</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <h4 className="font-semibold mb-2">For Server Administrators</h4>
            <ul className="text-sm space-y-1 list-disc list-inside text-slate-400">
              <li>Choose RECOMMENDED models for best quality and latest capabilities</li>
              <li>TTS models can often run on CPU for small batches, GPU for production scale</li>
              <li>On-device TTS models must be under 500MB for mobile constraints</li>
              <li>Consider latency requirements when choosing between server and on-device</li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold mb-2">Current Implementation Status</h4>
            <ul className="text-sm space-y-1 text-slate-400">
              <li>
                ⚠️ <strong>Server TTS:</strong> Needs selection and deployment
              </li>
              <li>
                ✅ <strong>On-Device TTS:</strong> Using Apple Neural TTS (fallback) - UPGRADE to
                Kyutai Pocket TTS (100M, Jan 13 2026, best WER 1.84%)
              </li>
            </ul>
          </div>
          <div className="bg-amber-900/30 p-4 rounded border border-amber-700/50">
            <h4 className="font-semibold mb-2 text-amber-300">Important: Model Updates</h4>
            <p className="text-sm text-amber-200/80">
              The TTS model landscape evolves rapidly. This dashboard was last updated in January
              2026. Check release dates and benchmark sources regularly. New models may have been
              released since this page was created.
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
