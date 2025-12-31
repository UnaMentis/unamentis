
import React, { useState } from 'react';
import { ContentNode, MediaItem, Segment } from '@/types/curriculum';
import { Save, Image as ImageIcon, MessageSquare, Settings, Plus, Trash2, Mic, PlayCircle, Layers } from 'lucide-react';
import { MediaPicker } from './MediaPicker';
import { clsx } from 'clsx';
import { HelpTooltip } from '@/components/ui/tooltip';

// Tooltip content for editor fields
const FIELD_HELP = {
    title: 'The display name for this content node. Keep it concise and descriptive.',
    type: 'The structural type of this node. Choose based on its role in the curriculum hierarchy.',
    orderIndex: 'Controls the display order among sibling nodes. Lower numbers appear first.',
    description: 'A summary of what this node covers. Used for navigation and search.',
    transcript: 'Voice-optimized content broken into segments for conversational AI delivery.',
    segmentType: 'The purpose of this segment: introduction, lecture, explanation, example, checkpoint, transition, or summary.',
    segmentContent: 'The actual spoken content. Write conversationally as if speaking to a student.',
    media: 'Visual assets (images, diagrams) to display during the lesson. Can be timed to specific segments.',
    startSegment: 'The segment index when this media should first appear.',
    endSegment: 'The segment index when this media should disappear.',
    displayMode: 'How the media appears: persistent (stays visible), highlight (emphasized), or popup (modal).',
};

interface NodeEditorProps {
    node: ContentNode;
    onChange: (updatedNode: ContentNode) => void;
    readOnly?: boolean;
}

export const NodeEditor: React.FC<NodeEditorProps> = ({ node, onChange, readOnly }) => {
    const [activeTab, setActiveTab] = useState<'general' | 'transcript' | 'media'>('general');
    const [showMediaPicker, setShowMediaPicker] = useState(false);

    const handleFieldChange = <K extends keyof ContentNode>(field: K, value: ContentNode[K]) => {
        onChange({ ...node, [field]: value });
    };

    const handleAddMedia = (media: Partial<MediaItem>) => {
        const newMedia = {
            ...media,
            id: Math.random().toString(36).substr(2, 9),
            segmentTiming: {
                startSegment: 0,
                endSegment: 0,
                displayMode: 'persistent'
            }
        } as MediaItem;

        const currentMedia = node.media || { embedded: [], reference: [] };
        onChange({
            ...node,
            media: {
                ...currentMedia,
                embedded: [...(currentMedia.embedded || []), newMedia]
            }
        });
    };

    const handleRemoveMedia = (id: string) => {
        if (!node.media?.embedded) return;
        onChange({
            ...node,
            media: {
                ...node.media,
                embedded: node.media.embedded.filter(m => m.id !== id)
            }
        });
    };

    const updateMediaTiming = (id: string, field: 'startSegment' | 'endSegment' | 'displayMode', value: number | string) => {
        if (!node.media?.embedded) return;
        onChange({
            ...node,
            media: {
                ...node.media,
                embedded: node.media.embedded.map(m => {
                    if (m.id !== id) return m;
                    return {
                        ...m,
                        segmentTiming: {
                            ...m.segmentTiming!,
                            [field]: value
                        }
                    };
                })
            }
        });
    };

    const tabs = [
        { id: 'general', label: 'General', icon: Settings },
        { id: 'transcript', label: 'Transcript', icon: MessageSquare },
        { id: 'media', label: 'Media & Visuals', icon: ImageIcon },
    ] as const;

    return (
        <div className="h-full flex flex-col bg-slate-900 text-slate-200">
            {/* Header */}
            <div className="flex items-center justify-between p-6 border-b border-slate-800 bg-slate-900/50 backdrop-blur-sm sticky top-0 z-10">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-indigo-500/10 rounded-lg border border-indigo-500/20 text-indigo-400">
                        <Layers size={20} />
                    </div>
                    <div>
                        <h2 className="text-lg font-bold text-white tracking-tight">{node.title}</h2>
                        <div className="flex items-center gap-2 text-xs text-slate-500 font-mono">
                            <span className="uppercase">{node.type}</span>
                            <span className="w-1 h-1 rounded-full bg-slate-700"></span>
                            <span>ID: {node.id.value}</span>
                        </div>
                    </div>
                </div>
                {!readOnly && (
                    <button className="flex items-center gap-2 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-all shadow-lg shadow-indigo-500/20 font-medium text-sm">
                        <Save size={16} />
                        <span>Save Changes</span>
                    </button>
                )}
            </div>

            {/* Tabs */}
            <div className="flex gap-1 px-6 pt-4 border-b border-slate-800">
                {tabs.map(tab => (
                    <button
                        key={tab.id}
                        data-tour={`${tab.id}-tab`}
                        onClick={() => setActiveTab(tab.id)}
                        className={clsx(
                            "flex items-center gap-2 px-4 py-3 text-sm font-medium transition-all rounded-t-lg relative",
                            activeTab === tab.id
                                ? "text-indigo-400 bg-slate-800/50"
                                : "text-slate-500 hover:text-slate-300 hover:bg-slate-800/30"
                        )}
                    >
                        <tab.icon size={16} />
                        {tab.label}
                        {activeTab === tab.id && (
                            <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-indigo-500 shadow-[0_0_10px_rgba(99,102,241,0.5)]"></div>
                        )}
                    </button>
                ))}
            </div>

            {/* Content Area */}
            <div className="flex-1 overflow-y-auto p-6 scrollbar-thin scrollbar-thumb-slate-700 scrollbar-track-transparent">

                {/* GENERAL TAB */}
                {activeTab === 'general' && (
                    <div className="space-y-6 max-w-3xl animate-in">
                        <div className="grid gap-6">
                            <div className="space-y-2">
                                <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider flex items-center gap-1">
                                    Title
                                    <HelpTooltip content={FIELD_HELP.title} />
                                </label>
                                <input
                                    type="text"
                                    value={node.title}
                                    onChange={(e) => handleFieldChange('title', e.target.value)}
                                    disabled={readOnly}
                                    className="w-full bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-white focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                                    placeholder="Enter node title..."
                                />
                            </div>

                            <div className="grid grid-cols-2 gap-6">
                                <div className="space-y-2">
                                    <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider flex items-center gap-1">
                                        Type
                                        <HelpTooltip content={FIELD_HELP.type} />
                                    </label>
                                    <select
                                        value={node.type}
                                        onChange={(e) => handleFieldChange('type', e.target.value as ContentNode['type'])}
                                        disabled={readOnly}
                                        className="w-full bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-white focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all appearance-none disabled:opacity-50 disabled:cursor-not-allowed"
                                    >
                                        {['unit', 'module', 'topic', 'lesson', 'segment'].map(t => (
                                            <option key={t} value={t}>{t.charAt(0).toUpperCase() + t.slice(1)}</option>
                                        ))}
                                    </select>
                                </div>
                                <div className="space-y-2">
                                    <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider flex items-center gap-1">
                                        Order Index
                                        <HelpTooltip content={FIELD_HELP.orderIndex} />
                                    </label>
                                    <input
                                        type="number"
                                        value={node.orderIndex || 0}
                                        onChange={(e) => handleFieldChange('orderIndex', parseInt(e.target.value))}
                                        disabled={readOnly}
                                        className="w-full bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-white focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                                    />
                                </div>
                            </div>

                            <div className="space-y-2">
                                <label className="text-xs font-semibold text-slate-400 uppercase tracking-wider flex items-center gap-1">
                                    Description
                                    <HelpTooltip content={FIELD_HELP.description} />
                                </label>
                                <textarea
                                    value={node.description || ''}
                                    onChange={(e) => handleFieldChange('description', e.target.value)}
                                    rows={4}
                                    disabled={readOnly}
                                    className="w-full bg-slate-800/50 border border-slate-700 rounded-lg p-3 text-white focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all resize-none disabled:opacity-50 disabled:cursor-not-allowed"
                                    placeholder="Describe the learning goals for this section..."
                                />
                            </div>
                        </div>
                    </div>
                )}

                {/* TRANSCRIPT TAB */}
                {activeTab === 'transcript' && (
                    <div className="space-y-6 max-w-3xl animate-in">
                        <div className="flex items-center justify-between">
                            <h3 className="text-lg font-medium text-white">Spoken Segments</h3>
                            {!readOnly && (
                                <button
                                    className="flex items-center gap-2 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-indigo-400 rounded-lg text-xs font-bold uppercase tracking-wider transition-colors border border-slate-700 hover:border-indigo-500/30"
                                    onClick={() => {
                                        const newSegment: Segment = {
                                            id: `seg-${Date.now()}`,
                                            type: 'explanation',
                                            content: 'New spoken content...'
                                        };
                                        const segments = node.transcript?.segments || [];
                                        handleFieldChange('transcript', { ...node.transcript, segments: [...segments, newSegment] });
                                    }}
                                >
                                    <Plus size={14} /> Add Segment
                                </button>
                            )}
                        </div>

                        <div className="space-y-4">
                            {(node.transcript?.segments || []).map((seg, idx) => (
                                <div key={seg.id} className="bg-slate-800/40 border border-slate-700/50 rounded-xl p-4 flex gap-4 group hover:border-indigo-500/30 transition-all">
                                    <div className="flex flex-col items-center gap-2 pt-2">
                                        <div className="w-6 h-6 rounded-full bg-slate-700 flex items-center justify-center text-xs font-mono text-slate-400">
                                            {idx + 1}
                                        </div>
                                        <div className="w-0.5 flex-1 bg-slate-700/50 group-last:hidden"></div>
                                    </div>
                                    <div className="flex-1 space-y-3">
                                        <div className="flex gap-3">
                                            <select
                                                value={seg.type}
                                                onChange={(e) => {
                                                    const updated = [...(node.transcript?.segments || [])];
                                                    updated[idx] = { ...updated[idx], type: e.target.value as Segment['type'] };
                                                    handleFieldChange('transcript', { ...node.transcript, segments: updated });
                                                }}
                                                disabled={readOnly}
                                                className="bg-slate-900 border border-slate-700 rounded text-xs text-indigo-400 font-semibold px-2 py-1 uppercase disabled:opacity-50"
                                            >
                                                {['introduction', 'lecture', 'explanation', 'example', 'checkpoint', 'transition', 'summary'].map(t => (
                                                    <option key={t} value={t}>{t}</option>
                                                ))}
                                            </select>
                                        </div>
                                        <textarea
                                            value={seg.content}
                                            onChange={(e) => {
                                                const updated = [...(node.transcript?.segments || [])];
                                                updated[idx] = { ...updated[idx], content: e.target.value };
                                                handleFieldChange('transcript', { ...node.transcript, segments: updated });
                                            }}
                                            rows={2}
                                            disabled={readOnly}
                                            className="w-full bg-slate-900/50 border border-slate-700 rounded-lg p-3 text-slate-300 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all disabled:opacity-50"
                                        />
                                    </div>
                                    {!readOnly && (
                                        <button
                                            onClick={() => {
                                                const updated = node.transcript?.segments.filter(s => s.id !== seg.id) ?? [];
                                                handleFieldChange('transcript', { segments: updated });
                                            }}
                                            className="text-slate-600 hover:text-red-400 p-2 transition-colors self-start"
                                        >
                                            <Trash2 size={16} />
                                        </button>
                                    )}
                                </div>
                            ))}

                            {(node.transcript?.segments?.length || 0) === 0 && (
                                <div className="text-center py-12 border-2 border-dashed border-slate-800 rounded-xl text-slate-500">
                                    <Mic size={32} className="mx-auto mb-3 opacity-50" />
                                    <p>No transcript segments yet. Add one to start the conversation.</p>
                                </div>
                            )}
                        </div>
                    </div>
                )}

                {/* MEDIA TAB */}
                {activeTab === 'media' && (
                    <div className="space-y-8 animate-in">
                        <div className="bg-gradient-to-r from-indigo-500/10 to-purple-500/10 border border-indigo-500/20 rounded-xl p-6">
                            <div className="flex justify-between items-start mb-6">
                                <div>
                                    <h3 className="text-lg font-bold text-white mb-1">Visual Assets</h3>
                                    <p className="text-sm text-slate-400">Manage images, diagrams, and videos that appear during the lesson.</p>
                                </div>
                                <button
                                    onClick={() => setShowMediaPicker(true)}
                                    className="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg shadow-lg shadow-indigo-500/20 transition-all flex items-center gap-2 font-medium"
                                >
                                    <Plus size={18} />
                                    Find Images
                                </button>
                            </div>

                            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                                {(node.media?.embedded || []).map((media) => (
                                    <div key={media.id} className="bg-slate-900 border border-slate-700 rounded-xl overflow-hidden group hover:border-indigo-500/50 transition-all hover:shadow-xl">
                                        <div className="relative aspect-video bg-slate-800">
                                            <img src={media.url} alt={media.alt} className="w-full h-full object-cover" />
                                            <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2 backdrop-blur-sm">
                                                <button className="p-2 bg-white/10 hover:bg-white/20 rounded-full text-white transition-colors">
                                                    <PlayCircle size={20} />
                                                </button>
                                                <button
                                                    onClick={() => handleRemoveMedia(media.id)}
                                                    className="p-2 bg-red-500/20 hover:bg-red-500/40 text-red-400 rounded-full transition-colors"
                                                >
                                                    <Trash2 size={20} />
                                                </button>
                                            </div>
                                            <div className="absolute top-2 left-2 bg-black/60 backdrop-blur px-2 py-1 rounded text-xs font-medium text-white">
                                                Segments {media.segmentTiming?.startSegment} - {media.segmentTiming?.endSegment}
                                            </div>
                                        </div>

                                        <div className="p-4 space-y-4">
                                            <div className="space-y-1">
                                                <input
                                                    value={media.title || ''}
                                                    onChange={() => {
                                                        // Deep update logic would go here
                                                    }}
                                                    className="bg-transparent border-none p-0 text-white font-medium w-full focus:ring-0 placeholder:text-slate-600"
                                                    placeholder="Untitled Asset"
                                                />
                                                <p className="text-xs text-slate-500 truncate">{media.url}</p>
                                            </div>

                                            <div className="bg-slate-800/50 rounded-lg p-3 space-y-3">
                                                <div className="flex items-center justify-between text-xs">
                                                    <span className="text-slate-400 uppercase tracking-wider font-semibold">Display Timing</span>
                                                </div>
                                                <div className="flex gap-2 items-center">
                                                    <div className="flex-1">
                                                        <label className="text-[10px] text-slate-500 block mb-1">Start Segment</label>
                                                        <input
                                                            type="number"
                                                            value={media.segmentTiming?.startSegment}
                                                            onChange={(e) => updateMediaTiming(media.id, 'startSegment', parseInt(e.target.value))}
                                                            className="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-white"
                                                        />
                                                    </div>
                                                    <span className="text-slate-600 pt-3">→</span>
                                                    <div className="flex-1">
                                                        <label className="text-[10px] text-slate-500 block mb-1">End Segment</label>
                                                        <input
                                                            type="number"
                                                            value={media.segmentTiming?.endSegment}
                                                            onChange={(e) => updateMediaTiming(media.id, 'endSegment', parseInt(e.target.value))}
                                                            className="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-white"
                                                        />
                                                    </div>
                                                </div>
                                                <div>
                                                    <label className="text-[10px] text-slate-500 block mb-1">Mode</label>
                                                    <select
                                                        value={media.segmentTiming?.displayMode}
                                                        onChange={(e) => updateMediaTiming(media.id, 'displayMode', e.target.value)}
                                                        className="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-white"
                                                    >
                                                        <option value="persistent">Persistent (Stays on screen)</option>
                                                        <option value="highlight">Highlight (Fades later)</option>
                                                        <option value="popup">Popup (Modal)</option>
                                                    </select>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                ))}

                                {(!node.media?.embedded || node.media.embedded.length === 0) && (
                                    <div
                                        onClick={() => setShowMediaPicker(true)}
                                        className="col-span-1 md:col-span-2 border-2 border-dashed border-slate-700 hover:border-indigo-500/50 hover:bg-slate-800/30 rounded-xl p-12 flex flex-col items-center justify-center cursor-pointer transition-all group"
                                    >
                                        <div className="w-16 h-16 rounded-full bg-slate-800 group-hover:bg-indigo-500/20 flex items-center justify-center mb-4 transition-colors">
                                            <ImageIcon size={32} className="text-slate-500 group-hover:text-indigo-400" />
                                        </div>
                                        <p className="text-slate-300 font-medium">No visuals attached</p>
                                        <p className="text-slate-500 text-sm mt-1">Click to browse the creative commons library</p>
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>
                )}
            </div>

            {showMediaPicker && (
                <MediaPicker
                    onSelect={handleAddMedia}
                    onClose={() => setShowMediaPicker(false)}
                />
            )}
        </div>
    );
};
