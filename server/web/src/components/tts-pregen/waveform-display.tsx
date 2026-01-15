'use client';

import { useEffect, useRef, useState } from 'react';
import { cn } from '@/lib/utils';

interface WaveformDisplayProps {
  audioUrl?: string;
  audioData?: number[];
  progress?: number;
  height?: number;
  barWidth?: number;
  barGap?: number;
  primaryColor?: string;
  secondaryColor?: string;
  className?: string;
  onClick?: (progress: number) => void;
}

export function WaveformDisplay({
  audioUrl,
  audioData: externalData,
  progress = 0,
  height = 48,
  barWidth = 2,
  barGap = 1,
  primaryColor = 'rgb(168, 85, 247)',
  secondaryColor = 'rgb(75, 85, 99)',
  className,
  onClick,
}: WaveformDisplayProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [waveformData, setWaveformData] = useState<number[]>(externalData || []);
  const [isLoading, setIsLoading] = useState(false);

  // Generate waveform data from audio URL
  useEffect(() => {
    if (externalData) {
      setWaveformData(externalData);
      return;
    }

    if (!audioUrl) {
      setWaveformData([]);
      return;
    }

    const loadAudioData = async () => {
      setIsLoading(true);
      try {
        const audioContext = new AudioContext();
        const response = await fetch(audioUrl);
        const arrayBuffer = await response.arrayBuffer();
        const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

        // Get audio data from the first channel
        const channelData = audioBuffer.getChannelData(0);

        // Downsample to a reasonable number of bars
        const numBars = Math.min(
          100,
          Math.floor(containerRef.current?.clientWidth || 200 / (barWidth + barGap))
        );
        const samplesPerBar = Math.floor(channelData.length / numBars);
        const bars: number[] = [];

        for (let i = 0; i < numBars; i++) {
          let sum = 0;
          for (let j = 0; j < samplesPerBar; j++) {
            sum += Math.abs(channelData[i * samplesPerBar + j]);
          }
          bars.push(sum / samplesPerBar);
        }

        // Normalize to 0-1 range
        const maxVal = Math.max(...bars);
        const normalized = bars.map((v) => (maxVal > 0 ? v / maxVal : 0));

        setWaveformData(normalized);
        audioContext.close();
      } catch {
        // Generate placeholder waveform on error
        setWaveformData(generatePlaceholderWaveform());
      } finally {
        setIsLoading(false);
      }
    };

    loadAudioData();
  }, [audioUrl, externalData, barWidth, barGap]);

  // Draw waveform
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();

    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    // Clear canvas
    ctx.clearRect(0, 0, rect.width, rect.height);

    if (waveformData.length === 0) {
      // Draw placeholder
      ctx.fillStyle = secondaryColor;
      ctx.fillRect(0, rect.height / 2 - 1, rect.width, 2);
      return;
    }

    const numBars = waveformData.length;
    const totalBarWidth = barWidth + barGap;
    const startX = (rect.width - numBars * totalBarWidth) / 2;
    const progressX = startX + progress * numBars * totalBarWidth;

    waveformData.forEach((value, index) => {
      const x = startX + index * totalBarWidth;
      const barHeight = Math.max(2, value * (rect.height - 4));
      const y = (rect.height - barHeight) / 2;

      ctx.fillStyle = x < progressX ? primaryColor : secondaryColor;
      ctx.fillRect(x, y, barWidth, barHeight);
    });
  }, [waveformData, progress, barWidth, barGap, primaryColor, secondaryColor]);

  const handleClick = (e: React.MouseEvent<HTMLCanvasElement>) => {
    if (!onClick || waveformData.length === 0) return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const totalBarWidth = barWidth + barGap;
    const numBars = waveformData.length;
    const startX = (rect.width - numBars * totalBarWidth) / 2;

    const clickProgress = Math.max(0, Math.min(1, (x - startX) / (numBars * totalBarWidth)));
    onClick(clickProgress);
  };

  return (
    <div ref={containerRef} className={cn('relative w-full', className)} style={{ height }}>
      {isLoading && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="h-1 w-16 bg-muted-foreground/20 rounded overflow-hidden">
            <div className="h-full w-1/3 bg-primary animate-pulse" />
          </div>
        </div>
      )}
      <canvas
        ref={canvasRef}
        className={cn('w-full h-full', onClick && 'cursor-pointer', isLoading && 'opacity-0')}
        onClick={handleClick}
      />
    </div>
  );
}

function generatePlaceholderWaveform(): number[] {
  const numBars = 50;
  const bars: number[] = [];
  for (let i = 0; i < numBars; i++) {
    // Generate a simple sine-like pattern
    const t = i / numBars;
    bars.push(0.3 + 0.4 * Math.sin(t * Math.PI * 4) * Math.sin(t * Math.PI));
  }
  return bars;
}
