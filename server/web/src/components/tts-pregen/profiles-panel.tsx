'use client';

import { useState, useEffect, useCallback } from 'react';
import { Plus, Search, RefreshCw, Loader2, AlertCircle, Volume2 } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ProfileCard } from './profile-card';
import { ProfileEditor } from './profile-editor';
import type { TTSProfile, CreateProfileData, UpdateProfileData } from '@/types';
import {
  getTTSProfiles,
  createTTSProfile,
  updateTTSProfile,
  deleteTTSProfile,
  setDefaultTTSProfile,
} from '@/lib/api-client';

const PROVIDERS = [
  { value: '', label: 'All Providers' },
  { value: 'chatterbox', label: 'Chatterbox' },
  { value: 'vibevoice', label: 'VibeVoice' },
  { value: 'piper', label: 'Piper' },
];

export function ProfilesPanel() {
  const [profiles, setProfiles] = useState<TTSProfile[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [searchQuery, setSearchQuery] = useState('');
  const [providerFilter, setProviderFilter] = useState('');

  // Editor state
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingProfile, setEditingProfile] = useState<TTSProfile | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  const loadProfiles = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await getTTSProfiles({
        provider: providerFilter || undefined,
        is_active: true,
      });
      setProfiles(response.profiles);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load profiles');
    } finally {
      setIsLoading(false);
    }
  }, [providerFilter]);

  useEffect(() => {
    loadProfiles();
  }, [loadProfiles]);

  // Filter profiles by search query
  const filteredProfiles = profiles.filter((profile) => {
    if (!searchQuery) return true;
    const query = searchQuery.toLowerCase();
    return (
      profile.name.toLowerCase().includes(query) ||
      profile.description?.toLowerCase().includes(query) ||
      profile.tags?.some((tag) => tag.toLowerCase().includes(query)) ||
      profile.provider.toLowerCase().includes(query)
    );
  });

  const handleCreateProfile = () => {
    setEditingProfile(null);
    setEditorOpen(true);
  };

  const handleEditProfile = (profile: TTSProfile) => {
    setEditingProfile(profile);
    setEditorOpen(true);
  };

  const handleDuplicateProfile = (profile: TTSProfile) => {
    // Create a copy of the profile with modified name
    const duplicateProfile: TTSProfile = {
      ...profile,
      id: '', // Will be assigned by backend
      name: `${profile.name} (Copy)`,
      is_default: false,
    };
    setEditingProfile(duplicateProfile);
    setEditorOpen(true);
  };

  const handleSaveProfile = async (data: CreateProfileData | UpdateProfileData) => {
    setIsSaving(true);

    try {
      if (editingProfile?.id) {
        await updateTTSProfile(editingProfile.id, data);
      } else {
        await createTTSProfile(data as CreateProfileData);
      }

      setEditorOpen(false);
      setEditingProfile(null);
      await loadProfiles();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save profile');
    } finally {
      setIsSaving(false);
    }
  };

  const handleDeleteProfile = async (profile: TTSProfile) => {
    if (!confirm(`Are you sure you want to delete "${profile.name}"?`)) {
      return;
    }

    try {
      await deleteTTSProfile(profile.id);
      await loadProfiles();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete profile');
    }
  };

  const handleSetDefault = async (profile: TTSProfile) => {
    try {
      await setDefaultTTSProfile(profile.id);
      await loadProfiles();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to set default profile');
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold text-white flex items-center gap-2">
            <Volume2 className="h-5 w-5 text-orange-400" />
            TTS Profiles
          </h2>
          <p className="text-sm text-slate-400 mt-1">
            Manage reusable voice configurations for TTS generation
          </p>
        </div>

        <Button
          onClick={handleCreateProfile}
          className="bg-orange-500 hover:bg-orange-600 text-white"
        >
          <Plus className="h-4 w-4 mr-2" />
          New Profile
        </Button>
      </div>

      {/* Filters */}
      <Card className="bg-slate-800/50 border-slate-700/50">
        <CardContent className="p-4">
          <div className="flex flex-col sm:flex-row gap-4">
            {/* Search */}
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
              <input
                type="text"
                placeholder="Search profiles..."
                value={searchQuery}
                onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                  setSearchQuery(e.target.value)
                }
                className="w-full pl-9 pr-3 py-2 bg-slate-900/50 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-orange-500/50 focus:border-orange-500"
              />
            </div>

            {/* Provider Filter */}
            <select
              value={providerFilter}
              onChange={(e: React.ChangeEvent<HTMLSelectElement>) =>
                setProviderFilter(e.target.value)
              }
              className="px-3 py-2 bg-slate-900/50 border border-slate-700 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-orange-500/50 focus:border-orange-500 min-w-[150px]"
            >
              {PROVIDERS.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </select>

            {/* Refresh */}
            <Button
              variant="outline"
              size="icon"
              onClick={loadProfiles}
              disabled={isLoading}
              className="border-slate-700 text-slate-400 hover:text-white"
            >
              <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Error */}
      {error && (
        <Card className="bg-red-500/10 border-red-500/30">
          <CardContent className="p-4 flex items-center gap-3">
            <AlertCircle className="h-5 w-5 text-red-400" />
            <p className="text-red-300">{error}</p>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setError(null)}
              className="ml-auto text-red-300 hover:text-red-200"
            >
              Dismiss
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Loading */}
      {isLoading && (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-orange-400" />
        </div>
      )}

      {/* Empty State */}
      {!isLoading && filteredProfiles.length === 0 && (
        <Card className="bg-slate-800/30 border-slate-700/30 border-dashed">
          <CardContent className="py-12 text-center">
            <Volume2 className="h-12 w-12 text-slate-600 mx-auto mb-4" />
            <h3 className="text-lg font-medium text-slate-300 mb-2">No profiles found</h3>
            <p className="text-slate-500 mb-4">
              {searchQuery || providerFilter
                ? 'Try adjusting your filters'
                : 'Create your first TTS profile to get started'}
            </p>
            {!searchQuery && !providerFilter && (
              <Button
                onClick={handleCreateProfile}
                className="bg-orange-500 hover:bg-orange-600 text-white"
              >
                <Plus className="h-4 w-4 mr-2" />
                Create Profile
              </Button>
            )}
          </CardContent>
        </Card>
      )}

      {/* Profiles Grid */}
      {!isLoading && filteredProfiles.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredProfiles.map((profile) => (
            <ProfileCard
              key={profile.id}
              profile={profile}
              onEdit={handleEditProfile}
              onDuplicate={handleDuplicateProfile}
              onDelete={handleDeleteProfile}
              onSetDefault={handleSetDefault}
            />
          ))}
        </div>
      )}

      {/* Profile Count */}
      {!isLoading && filteredProfiles.length > 0 && (
        <p className="text-sm text-slate-500 text-center">
          Showing {filteredProfiles.length} of {profiles.length} profiles
        </p>
      )}

      {/* Editor Modal */}
      {editorOpen && (
        <ProfileEditor
          profile={editingProfile}
          onSave={handleSaveProfile}
          onCancel={() => {
            setEditorOpen(false);
            setEditingProfile(null);
          }}
          isLoading={isSaving}
        />
      )}
    </div>
  );
}
