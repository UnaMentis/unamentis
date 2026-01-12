'use client';

import React, { useState, useEffect } from 'react';
import { X, Plus, List, Check, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useToast } from '@/components/ui/toast';

interface CurriculumList {
  id: string;
  name: string;
  description?: string;
  isShared: boolean;
  itemCount: number;
}

interface CourseItem {
  sourceId: string;
  courseId: string;
  courseTitle?: string;
  courseThumbnailUrl?: string;
}

interface AddToListModalProps {
  isOpen: boolean;
  onClose: () => void;
  courses: CourseItem[];
  onSuccess?: () => void;
}

export function AddToListModal({
  isOpen,
  onClose,
  courses,
  onSuccess,
}: AddToListModalProps) {
  const { showToast } = useToast();
  const [lists, setLists] = useState<CurriculumList[]>([]);
  const [selectedListId, setSelectedListId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showCreateNew, setShowCreateNew] = useState(false);
  const [newListName, setNewListName] = useState('');
  const [newListDescription, setNewListDescription] = useState('');
  const [isShared, setIsShared] = useState(false);

  // Fetch lists when modal opens
  useEffect(() => {
    if (isOpen) {
      fetchLists();
    }
  }, [isOpen]);

  const fetchLists = async () => {
    setIsLoading(true);
    try {
      const serverUrl = process.env.NEXT_PUBLIC_MANAGEMENT_SERVER_URL || 'http://localhost:8766';
      const response = await fetch(`${serverUrl}/api/lists`);
      if (response.ok) {
        const data = await response.json();
        setLists(data.lists || []);
      }
    } catch (error) {
      console.error('Failed to fetch lists:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCreateList = async () => {
    if (!newListName.trim()) return;

    setIsSubmitting(true);
    try {
      const serverUrl = process.env.NEXT_PUBLIC_MANAGEMENT_SERVER_URL || 'http://localhost:8766';
      const response = await fetch(`${serverUrl}/api/lists`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: newListName.trim(),
          description: newListDescription.trim(),
          isShared,
        }),
      });

      if (response.ok) {
        const newList = await response.json();
        setLists((prev) => [newList, ...prev]);
        setSelectedListId(newList.id);
        setShowCreateNew(false);
        setNewListName('');
        setNewListDescription('');
        setIsShared(false);
        showToast({
          type: 'success',
          title: 'List Created',
          message: `"${newList.name}" has been created`,
        });
      } else {
        const error = await response.json();
        showToast({
          type: 'error',
          title: 'Failed to create list',
          message: error.error || 'Unknown error',
        });
      }
    } catch (error) {
      showToast({
        type: 'error',
        title: 'Failed to create list',
        message: String(error),
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleAddToList = async () => {
    if (!selectedListId || courses.length === 0) return;

    setIsSubmitting(true);
    try {
      const serverUrl = process.env.NEXT_PUBLIC_MANAGEMENT_SERVER_URL || 'http://localhost:8766';
      const response = await fetch(`${serverUrl}/api/lists/${selectedListId}/items`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          items: courses.map((c) => ({
            sourceId: c.sourceId,
            courseId: c.courseId,
            courseTitle: c.courseTitle,
            courseThumbnailUrl: c.courseThumbnailUrl,
          })),
        }),
      });

      if (response.ok) {
        const result = await response.json();
        const selectedList = lists.find((l) => l.id === selectedListId);
        showToast({
          type: 'success',
          title: 'Added to List',
          message: `${result.addedCount} course${result.addedCount !== 1 ? 's' : ''} added to "${selectedList?.name}"`,
        });
        onSuccess?.();
        onClose();
      } else {
        const error = await response.json();
        showToast({
          type: 'error',
          title: 'Failed to add courses',
          message: error.error || 'Unknown error',
        });
      }
    } catch (error) {
      showToast({
        type: 'error',
        title: 'Failed to add courses',
        message: String(error),
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="relative bg-slate-900 border border-slate-700 rounded-xl shadow-2xl w-full max-w-md mx-4 overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-orange-500/20 rounded-lg">
              <List className="w-5 h-5 text-orange-400" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-white">Add to List</h2>
              <p className="text-sm text-slate-400">
                {courses.length} course{courses.length !== 1 ? 's' : ''} selected
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white hover:bg-slate-800 rounded-lg transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6">
          {isLoading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="w-6 h-6 text-orange-400 animate-spin" />
            </div>
          ) : showCreateNew ? (
            /* Create New List Form */
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  List Name
                </label>
                <input
                  type="text"
                  value={newListName}
                  onChange={(e) => setNewListName(e.target.value)}
                  placeholder="e.g., Watch Later, Math Courses"
                  className="w-full px-4 py-2.5 bg-slate-800 border border-slate-600 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent"
                  autoFocus
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-300 mb-2">
                  Description (optional)
                </label>
                <textarea
                  value={newListDescription}
                  onChange={(e) => setNewListDescription(e.target.value)}
                  placeholder="A brief description of this list"
                  rows={2}
                  className="w-full px-4 py-2.5 bg-slate-800 border border-slate-600 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent resize-none"
                />
              </div>
              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={isShared}
                  onChange={(e) => setIsShared(e.target.checked)}
                  className="w-4 h-4 rounded border-slate-600 bg-slate-800 text-orange-500 focus:ring-orange-500"
                />
                <span className="text-sm text-slate-300">Share this list with others</span>
              </label>

              <div className="flex gap-3 pt-2">
                <button
                  onClick={() => setShowCreateNew(false)}
                  className="flex-1 px-4 py-2.5 bg-slate-800 text-slate-300 rounded-lg hover:bg-slate-700 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleCreateList}
                  disabled={!newListName.trim() || isSubmitting}
                  className="flex-1 px-4 py-2.5 bg-orange-600 text-white rounded-lg hover:bg-orange-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center justify-center gap-2"
                >
                  {isSubmitting ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Plus className="w-4 h-4" />
                  )}
                  Create List
                </button>
              </div>
            </div>
          ) : (
            /* List Selection */
            <div className="space-y-4">
              {lists.length === 0 ? (
                <div className="text-center py-6">
                  <List className="w-12 h-12 text-slate-600 mx-auto mb-3" />
                  <p className="text-slate-400 mb-4">No lists yet</p>
                  <button
                    onClick={() => setShowCreateNew(true)}
                    className="px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-500 transition-colors inline-flex items-center gap-2"
                  >
                    <Plus className="w-4 h-4" />
                    Create Your First List
                  </button>
                </div>
              ) : (
                <>
                  <div className="space-y-2 max-h-60 overflow-y-auto">
                    {lists.map((list) => (
                      <button
                        key={list.id}
                        onClick={() => setSelectedListId(list.id)}
                        className={cn(
                          'w-full px-4 py-3 rounded-lg text-left transition-colors flex items-center justify-between',
                          selectedListId === list.id
                            ? 'bg-orange-600/20 border border-orange-500'
                            : 'bg-slate-800 border border-slate-700 hover:border-slate-600'
                        )}
                      >
                        <div>
                          <div className="font-medium text-white">{list.name}</div>
                          <div className="text-sm text-slate-400">
                            {list.itemCount} course{list.itemCount !== 1 ? 's' : ''}
                            {list.isShared && ' · Shared'}
                          </div>
                        </div>
                        {selectedListId === list.id && (
                          <Check className="w-5 h-5 text-orange-400" />
                        )}
                      </button>
                    ))}
                  </div>

                  <button
                    onClick={() => setShowCreateNew(true)}
                    className="w-full px-4 py-3 border border-dashed border-slate-600 rounded-lg text-slate-400 hover:text-white hover:border-slate-500 transition-colors flex items-center justify-center gap-2"
                  >
                    <Plus className="w-4 h-4" />
                    Create New List
                  </button>
                </>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        {!showCreateNew && lists.length > 0 && (
          <div className="px-6 py-4 border-t border-slate-700 flex justify-end gap-3">
            <button
              onClick={onClose}
              className="px-4 py-2.5 bg-slate-800 text-slate-300 rounded-lg hover:bg-slate-700 transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleAddToList}
              disabled={!selectedListId || isSubmitting}
              className="px-4 py-2.5 bg-orange-600 text-white rounded-lg hover:bg-orange-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
            >
              {isSubmitting ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Plus className="w-4 h-4" />
              )}
              Add to List
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
