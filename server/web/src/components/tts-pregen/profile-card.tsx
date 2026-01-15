'use client';

import { useState, useRef, useEffect } from 'react';
import { Play, Pause, Star, MoreVertical, Edit, Copy, Trash2, Settings2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import type { TTSProfile } from '@/types';

interface ProfileCardProps {
  profile: TTSProfile;
  onEdit?: (profile: TTSProfile) => void;
  onDuplicate?: (profile: TTSProfile) => void;
  onDelete?: (profile: TTSProfile) => void;
  onSetDefault?: (profile: TTSProfile) => void;
}

const providerColors: Record<string, string> = {
  chatterbox: 'bg-purple-500/20 text-purple-400 border-purple-500/30',
  vibevoice: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
  piper: 'bg-green-500/20 text-green-400 border-green-500/30',
};

export function ProfileCard({
  profile,
  onEdit,
  onDuplicate,
  onDelete,
  onSetDefault,
}: ProfileCardProps) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [audioError, setAudioError] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  const hasSampleAudio = Boolean(profile.sample_audio_path);

  useEffect(() => {
    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
    };
  }, []);

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setMenuOpen(false);
      }
    };

    if (menuOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [menuOpen]);

  const handlePlayPause = async () => {
    if (!hasSampleAudio) return;

    if (isPlaying && audioRef.current) {
      audioRef.current.pause();
      setIsPlaying(false);
      return;
    }

    try {
      setAudioError(null);

      if (!audioRef.current) {
        audioRef.current = new Audio(`/api/tts/profiles/${profile.id}/audio`);
        audioRef.current.onended = () => setIsPlaying(false);
        audioRef.current.onerror = () => {
          setAudioError('Failed to load audio');
          setIsPlaying(false);
        };
      }

      await audioRef.current.play();
      setIsPlaying(true);
    } catch {
      setAudioError('Failed to play audio');
      setIsPlaying(false);
    }
  };

  const handleMenuAction = (action: () => void) => {
    setMenuOpen(false);
    action();
  };

  return (
    <Card className="bg-slate-800/50 border-slate-700/50 hover:border-slate-600/50 transition-colors">
      <CardContent className="p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1 min-w-0">
            {/* Header */}
            <div className="flex items-center gap-2 mb-2">
              <h3 className="font-medium text-white truncate">{profile.name}</h3>
              {profile.is_default && (
                <Star className="w-4 h-4 text-yellow-400 fill-yellow-400 flex-shrink-0" />
              )}
            </div>

            {/* Provider & Voice */}
            <div className="flex items-center gap-2 mb-2">
              <Badge
                variant="outline"
                className={providerColors[profile.provider] || 'bg-slate-500/20'}
              >
                {profile.provider}
              </Badge>
              <span className="text-sm text-slate-400 truncate">{profile.voice_id}</span>
            </div>

            {/* Description */}
            {profile.description && (
              <p className="text-sm text-slate-400 line-clamp-2 mb-2">{profile.description}</p>
            )}

            {/* Tags */}
            {profile.tags && profile.tags.length > 0 && (
              <div className="flex flex-wrap gap-1 mb-2">
                {profile.tags.map((tag) => (
                  <Badge
                    key={tag}
                    variant="outline"
                    className="text-xs bg-slate-700/50 border-slate-600/50"
                  >
                    {tag}
                  </Badge>
                ))}
              </div>
            )}

            {/* Settings Preview */}
            <div className="flex items-center gap-3 text-xs text-slate-500">
              <span className="flex items-center gap-1">
                <Settings2 className="w-3 h-3" />
                Speed: {profile.settings.speed?.toFixed(1) ?? '1.0'}x
              </span>
              {profile.settings.exaggeration !== undefined && (
                <span>Expr: {profile.settings.exaggeration.toFixed(1)}</span>
              )}
              {profile.settings.cfg_weight !== undefined && (
                <span>CFG: {profile.settings.cfg_weight.toFixed(1)}</span>
              )}
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center gap-1">
            {/* Play Button */}
            <Button
              variant="ghost"
              size="icon"
              className={`h-8 w-8 ${hasSampleAudio ? 'text-slate-300 hover:text-white' : 'text-slate-600 cursor-not-allowed'}`}
              onClick={handlePlayPause}
              disabled={!hasSampleAudio}
              title={hasSampleAudio ? (isPlaying ? 'Pause' : 'Play sample') : 'No sample audio'}
            >
              {isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
            </Button>

            {/* Menu */}
            <div className="relative" ref={menuRef}>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 text-slate-400"
                onClick={() => setMenuOpen(!menuOpen)}
              >
                <MoreVertical className="h-4 w-4" />
              </Button>

              {menuOpen && (
                <div className="absolute right-0 top-full mt-1 w-40 bg-slate-800 border border-slate-700 rounded-md shadow-lg z-10 py-1">
                  {onEdit && (
                    <button
                      className="w-full px-3 py-2 text-sm text-left text-slate-300 hover:bg-slate-700 flex items-center gap-2"
                      onClick={() => handleMenuAction(() => onEdit(profile))}
                    >
                      <Edit className="h-4 w-4" />
                      Edit
                    </button>
                  )}
                  {onDuplicate && (
                    <button
                      className="w-full px-3 py-2 text-sm text-left text-slate-300 hover:bg-slate-700 flex items-center gap-2"
                      onClick={() => handleMenuAction(() => onDuplicate(profile))}
                    >
                      <Copy className="h-4 w-4" />
                      Duplicate
                    </button>
                  )}
                  {onSetDefault && !profile.is_default && (
                    <button
                      className="w-full px-3 py-2 text-sm text-left text-slate-300 hover:bg-slate-700 flex items-center gap-2"
                      onClick={() => handleMenuAction(() => onSetDefault(profile))}
                    >
                      <Star className="h-4 w-4" />
                      Set as Default
                    </button>
                  )}
                  {onDelete && (
                    <>
                      <div className="border-t border-slate-700 my-1" />
                      <button
                        className="w-full px-3 py-2 text-sm text-left text-red-400 hover:bg-slate-700 flex items-center gap-2"
                        onClick={() => handleMenuAction(() => onDelete(profile))}
                      >
                        <Trash2 className="h-4 w-4" />
                        Delete
                      </button>
                    </>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Audio Error */}
        {audioError && <p className="text-xs text-red-400 mt-2">{audioError}</p>}
      </CardContent>
    </Card>
  );
}
