'use client';

import { useState } from 'react';
import { useQueryState, parseAsString } from 'nuqs';
import { QuestionPacksPanel } from './question-packs-panel';
import { PackDetail, AddQuestionsModal, BundlePacksModal } from '@/components/question-packs';

type ViewMode = 'list' | 'detail';

export function QuestionPacksContainer() {
  // URL-synced state for selected pack
  const [selectedPackId, setSelectedPackId] = useQueryState('packId', parseAsString);

  // Modal state
  const [showAddQuestions, setShowAddQuestions] = useState(false);
  const [showBundlePacks, setShowBundlePacks] = useState(false);
  const [addQuestionsPackId, setAddQuestionsPackId] = useState<string | null>(null);
  const [addQuestionsPackName, setAddQuestionsPackName] = useState<string>('');

  // Determine view mode based on URL state
  const viewMode: ViewMode = selectedPackId ? 'detail' : 'list';

  // Handlers for list view
  const handleSelectPack = (packId: string) => {
    setSelectedPackId(packId);
  };

  const handleCreatePack = () => {
    // For now, just show the bundle modal which has create option
    // In future, could show a create pack modal
    setShowBundlePacks(true);
  };

  const handleCreateBundle = () => {
    setShowBundlePacks(true);
  };

  // Handlers for detail view
  const handleBackToList = () => {
    setSelectedPackId(null);
  };

  const handleAddQuestions = () => {
    if (selectedPackId) {
      setAddQuestionsPackId(selectedPackId);
      // Would need to fetch pack name here, or pass it through state
      setAddQuestionsPackName('Selected Pack');
      setShowAddQuestions(true);
    }
  };

  const handleBundleFromDetail = () => {
    setShowBundlePacks(true);
  };

  const handleGenerateAudio = () => {
    // Would navigate to voice lab or trigger audio generation
    console.log('Generate audio for pack:', selectedPackId);
  };

  // Modal callbacks
  const handleAddQuestionsSuccess = () => {
    // Refresh would happen via the panel's internal state
    setShowAddQuestions(false);
    setAddQuestionsPackId(null);
  };

  const handleBundleSuccess = (newPackId: string) => {
    setShowBundlePacks(false);
    // Navigate to the new bundle
    setSelectedPackId(newPackId);
  };

  return (
    <>
      {viewMode === 'list' ? (
        <QuestionPacksPanel
          onSelectPack={handleSelectPack}
          onCreatePack={handleCreatePack}
          onCreateBundle={handleCreateBundle}
        />
      ) : (
        <PackDetail
          packId={selectedPackId!}
          onBack={handleBackToList}
          onAddQuestions={handleAddQuestions}
          onBundlePacks={handleBundleFromDetail}
          onGenerateAudio={handleGenerateAudio}
        />
      )}

      {/* Add Questions Modal */}
      {showAddQuestions && addQuestionsPackId && (
        <AddQuestionsModal
          packId={addQuestionsPackId}
          packName={addQuestionsPackName}
          onClose={() => {
            setShowAddQuestions(false);
            setAddQuestionsPackId(null);
          }}
          onSuccess={handleAddQuestionsSuccess}
        />
      )}

      {/* Bundle Packs Modal */}
      {showBundlePacks && (
        <BundlePacksModal
          onClose={() => setShowBundlePacks(false)}
          onSuccess={handleBundleSuccess}
          preselectedPackId={selectedPackId || undefined}
        />
      )}
    </>
  );
}
