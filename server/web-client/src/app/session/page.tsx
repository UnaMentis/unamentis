'use client';

/**
 * Session Page
 *
 * Voice tutoring session interface with transcript and visual panel.
 * Uses the SessionContext for real voice interaction via OpenAI Realtime API.
 */

import * as React from 'react';
import dynamic from 'next/dynamic';
import { useRouter } from 'next/navigation';
import { ArrowLeft, BookOpen, AlertCircle } from 'lucide-react';
import { useAuth } from '@/components/auth/AuthProvider';
import { Button } from '@/components/ui';
import { Transcript, SessionControls, SessionHeader } from '@/components/session';
import { useSession, SessionProvider } from '@/contexts';

// Dynamic imports for components that may use browser APIs
const VoiceWaveform = dynamic(
  () => import('@/components/session').then((mod) => mod.VoiceWaveform),
  { ssr: false }
);
const VisualPanel = dynamic(
  () => import('@/components/visual').then((mod) => mod.VisualPanel),
  { ssr: false }
);

// ===== Session Content Component =====

function SessionContent() {
  const router = useRouter();
  const session = useSession();
  const [visualIndex, setVisualIndex] = React.useState(0);

  // Handle session start
  const handleStart = React.useCallback(async () => {
    try {
      await session.startSession({
        voice: 'coral',
        instructions: 'You are a helpful AI tutor. Be encouraging and clear in your explanations.',
      });
    } catch (error) {
      console.error('Failed to start session:', error);
    }
  }, [session]);

  return (
    <main className="flex flex-col h-screen">
      {/* Navigation Header */}
      <div className="flex items-center gap-2 px-4 py-2 border-b bg-muted/30">
        <Button variant="ghost" size="icon" onClick={() => router.push('/')}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <span className="text-sm font-medium">Voice Session</span>
        <div className="flex-1" />
        <Button variant="outline" size="sm" onClick={() => router.push('/curriculum')}>
          <BookOpen className="h-4 w-4 mr-2" />
          Select Topic
        </Button>
      </div>

      {/* Error Display */}
      {session.error && (
        <div className="mx-4 mt-2 p-3 bg-destructive/10 border border-destructive/20 rounded-lg flex items-center gap-2">
          <AlertCircle className="h-4 w-4 text-destructive" />
          <span className="text-sm text-destructive">{session.error.message}</span>
          <Button
            variant="ghost"
            size="sm"
            className="ml-auto"
            onClick={session.clearError}
          >
            Dismiss
          </Button>
        </div>
      )}

      {/* Session Header with status */}
      <SessionHeader
        state={session.state}
        topicTitle="General Tutoring"
        curriculumTitle="Open Session"
        duration={session.duration}
      />

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col lg:flex-row overflow-hidden">
        {/* Transcript Panel */}
        <div className="flex-1 flex flex-col min-h-0 lg:w-1/2">
          <Transcript
            conversationHistory={session.conversationHistory}
            currentUtterance={session.currentUtterance}
            state={session.state}
            className="flex-1"
          />
        </div>

        {/* Visual Panel (Desktop: side panel, Mobile: bottom sheet) */}
        <div className="h-64 lg:h-auto lg:w-1/2 border-t lg:border-t-0 lg:border-l bg-muted/20">
          <VisualPanel
            assets={session.visualAssets}
            currentIndex={visualIndex}
            onIndexChange={setVisualIndex}
            className="h-full"
          />
        </div>
      </div>

      {/* Voice Waveform */}
      <div className="h-16 border-t bg-muted/30 flex items-center justify-center px-4">
        <VoiceWaveform
          state={session.state}
          audioLevel={0.5}
          className="w-full max-w-md"
        />
      </div>

      {/* Session Controls */}
      <div className="border-t bg-background py-4 px-4">
        <SessionControls
          state={session.state}
          isMuted={session.isMuted}
          isSpeakerMuted={session.isSpeakerMuted}
          onStart={handleStart}
          onStop={session.stopSession}
          onPause={session.pauseSession}
          onResume={session.resumeSession}
          onMuteToggle={session.toggleMute}
          onSpeakerToggle={session.toggleSpeaker}
          isConnecting={session.isConnecting}
        />
      </div>
    </main>
  );
}

// ===== Session Page =====

export default function SessionPage() {
  const router = useRouter();
  const { isAuthenticated, isLoading } = useAuth();

  // Redirect if not authenticated
  React.useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      router.push('/login');
    }
  }, [isAuthenticated, isLoading, router]);

  if (isLoading) {
    return (
      <main className="flex min-h-screen items-center justify-center">
        <div className="text-center">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent mx-auto" />
          <p className="mt-4 text-muted-foreground">Loading...</p>
        </div>
      </main>
    );
  }

  if (!isAuthenticated) {
    return null;
  }

  return (
    <SessionProvider>
      <SessionContent />
    </SessionProvider>
  );
}
