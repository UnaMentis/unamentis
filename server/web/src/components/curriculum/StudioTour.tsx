
import React, { useState, useLayoutEffect, useRef } from 'react';
import { X, ChevronRight, ChevronLeft, Sparkles, Check } from 'lucide-react';
import { cn } from '@/lib/utils';

export interface TourStep {
    id: string;
    target: string; // CSS selector for the element to highlight
    title: string;
    content: React.ReactNode;
    placement?: 'top' | 'bottom' | 'left' | 'right';
    highlightPadding?: number;
}

interface StudioTourProps {
    steps: TourStep[];
    isOpen: boolean;
    onClose: () => void;
    onComplete: () => void;
}

// Calculate highlight and tooltip positions
function calculatePositions(step: TourStep) {
    const element = document.querySelector(step.target);
    if (!element) return null;

    const rect = element.getBoundingClientRect();
    const padding = step.highlightPadding || 8;
    const tooltipWidth = 360;
    const tooltipHeight = 200;
    const gap = 16;

    let top = 0;
    let left = 0;

    switch (step.placement || 'bottom') {
        case 'top':
            top = rect.top - tooltipHeight - gap - padding;
            left = rect.left + rect.width / 2 - tooltipWidth / 2;
            break;
        case 'bottom':
            top = rect.bottom + gap + padding;
            left = rect.left + rect.width / 2 - tooltipWidth / 2;
            break;
        case 'left':
            top = rect.top + rect.height / 2 - tooltipHeight / 2;
            left = rect.left - tooltipWidth - gap - padding;
            break;
        case 'right':
            top = rect.top + rect.height / 2 - tooltipHeight / 2;
            left = rect.right + gap + padding;
            break;
    }

    // Keep within viewport
    const viewportPadding = 20;
    left = Math.max(viewportPadding, Math.min(left, window.innerWidth - tooltipWidth - viewportPadding));
    top = Math.max(viewportPadding, Math.min(top, window.innerHeight - tooltipHeight - viewportPadding));

    return { rect, tooltipPosition: { top, left } };
}

export const StudioTour: React.FC<StudioTourProps> = ({
    steps,
    isOpen,
    onClose,
    onComplete,
}) => {
    const [currentStep, setCurrentStep] = useState(0);
    const [highlightRect, setHighlightRect] = useState<DOMRect | null>(null);
    const [tooltipPosition, setTooltipPosition] = useState({ top: 0, left: 0 });
    const rafRef = useRef<number>();

    const step = steps[currentStep];

    // Use useLayoutEffect for synchronous DOM measurements
    useLayoutEffect(() => {
        if (!isOpen || !step) return;

        const updatePositions = () => {
            const positions = calculatePositions(step);
            if (positions) {
                setHighlightRect(positions.rect);
                setTooltipPosition(positions.tooltipPosition);
            }
        };

        // Initial calculation
        updatePositions();

        // Event handlers with RAF for smooth updates
        const handleUpdate = () => {
            if (rafRef.current) cancelAnimationFrame(rafRef.current);
            rafRef.current = requestAnimationFrame(updatePositions);
        };

        window.addEventListener('resize', handleUpdate);
        window.addEventListener('scroll', handleUpdate, true);

        return () => {
            window.removeEventListener('resize', handleUpdate);
            window.removeEventListener('scroll', handleUpdate, true);
            if (rafRef.current) cancelAnimationFrame(rafRef.current);
        };
    }, [isOpen, currentStep, step]);


    const handleNext = () => {
        if (currentStep < steps.length - 1) {
            setCurrentStep(currentStep + 1);
        } else {
            onComplete();
        }
    };

    const handlePrev = () => {
        if (currentStep > 0) {
            setCurrentStep(currentStep - 1);
        }
    };

    const handleSkip = () => {
        onClose();
    };

    if (!isOpen || !step) return null;

    return (
        <div className="fixed inset-0 z-[200]">
            {/* Overlay with cutout */}
            <svg className="absolute inset-0 w-full h-full pointer-events-none">
                <defs>
                    <mask id="tour-mask">
                        <rect x="0" y="0" width="100%" height="100%" fill="white" />
                        {highlightRect && (
                            <rect
                                x={highlightRect.left - (step.highlightPadding || 8)}
                                y={highlightRect.top - (step.highlightPadding || 8)}
                                width={highlightRect.width + (step.highlightPadding || 8) * 2}
                                height={highlightRect.height + (step.highlightPadding || 8) * 2}
                                rx="8"
                                fill="black"
                            />
                        )}
                    </mask>
                </defs>
                <rect
                    x="0"
                    y="0"
                    width="100%"
                    height="100%"
                    fill="rgba(0, 0, 0, 0.75)"
                    mask="url(#tour-mask)"
                />
            </svg>

            {/* Highlight border */}
            {highlightRect && (
                <div
                    className="absolute border-2 border-indigo-500 rounded-lg pointer-events-none animate-pulse"
                    style={{
                        top: highlightRect.top - (step.highlightPadding || 8),
                        left: highlightRect.left - (step.highlightPadding || 8),
                        width: highlightRect.width + (step.highlightPadding || 8) * 2,
                        height: highlightRect.height + (step.highlightPadding || 8) * 2,
                    }}
                />
            )}

            {/* Tooltip */}
            <div
                className="absolute w-[360px] bg-slate-900 border border-slate-700 rounded-xl shadow-2xl animate-in fade-in-0 slide-in-from-bottom-4 duration-300"
                style={{ top: tooltipPosition.top, left: tooltipPosition.left }}
            >
                {/* Header */}
                <div className="flex items-center justify-between p-4 border-b border-slate-800">
                    <div className="flex items-center gap-2">
                        <div className="p-1.5 bg-indigo-500/20 rounded-lg">
                            <Sparkles size={16} className="text-indigo-400" />
                        </div>
                        <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
                            Step {currentStep + 1} of {steps.length}
                        </span>
                    </div>
                    <button
                        onClick={handleSkip}
                        className="p-1 text-slate-500 hover:text-slate-300 transition-colors"
                    >
                        <X size={16} />
                    </button>
                </div>

                {/* Content */}
                <div className="p-4">
                    <h3 className="text-lg font-bold text-white mb-2">{step.title}</h3>
                    <div className="text-sm text-slate-400 leading-relaxed">
                        {step.content}
                    </div>
                </div>

                {/* Progress dots */}
                <div className="flex justify-center gap-1.5 pb-3">
                    {steps.map((_, idx) => (
                        <button
                            key={idx}
                            onClick={() => setCurrentStep(idx)}
                            className={cn(
                                "w-2 h-2 rounded-full transition-all",
                                idx === currentStep
                                    ? "bg-indigo-500 w-4"
                                    : idx < currentStep
                                        ? "bg-indigo-500/50"
                                        : "bg-slate-700"
                            )}
                        />
                    ))}
                </div>

                {/* Footer */}
                <div className="flex items-center justify-between p-4 border-t border-slate-800 bg-slate-900/50">
                    <button
                        onClick={handleSkip}
                        className="text-sm text-slate-500 hover:text-slate-300 transition-colors"
                    >
                        Skip tour
                    </button>
                    <div className="flex items-center gap-2">
                        {currentStep > 0 && (
                            <button
                                onClick={handlePrev}
                                className="flex items-center gap-1 px-3 py-1.5 text-sm text-slate-300 hover:text-white transition-colors"
                            >
                                <ChevronLeft size={16} />
                                Back
                            </button>
                        )}
                        <button
                            onClick={handleNext}
                            className="flex items-center gap-1 px-4 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg text-sm font-medium transition-colors"
                        >
                            {currentStep === steps.length - 1 ? (
                                <>
                                    <Check size={16} />
                                    Finish
                                </>
                            ) : (
                                <>
                                    Next
                                    <ChevronRight size={16} />
                                </>
                            )}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
};

// Tour steps for the Curriculum Studio
export const STUDIO_TOUR_STEPS: TourStep[] = [
    {
        id: 'welcome',
        target: '[data-tour="studio-header"]',
        title: 'Welcome to Curriculum Studio',
        placement: 'bottom',
        content: (
            <div>
                <p className="mb-2">
                    Curriculum Studio is your workspace for viewing and editing educational content
                    in the UMCF format.
                </p>
                <p className="text-indigo-400">
                    Let&apos;s take a quick tour of the key features.
                </p>
            </div>
        ),
    },
    {
        id: 'content-tree',
        target: '[data-tour="content-tree"]',
        title: 'Content Structure',
        placement: 'right',
        content: (
            <div>
                <p className="mb-2">
                    The sidebar shows your curriculum&apos;s hierarchical structure. UMCF supports
                    unlimited nesting depth.
                </p>
                <ul className="list-disc list-inside text-slate-500 text-xs mt-2 space-y-1">
                    <li><strong>Units</strong> - Major course divisions</li>
                    <li><strong>Modules</strong> - Chapter-like sections</li>
                    <li><strong>Topics</strong> - Individual teachable concepts</li>
                    <li><strong>Segments</strong> - Conversational chunks</li>
                </ul>
            </div>
        ),
    },
    {
        id: 'node-editor',
        target: '[data-tour="node-editor"]',
        title: 'Node Editor',
        placement: 'left',
        content: (
            <div>
                <p className="mb-2">
                    Select any node to view and edit its properties. The editor has three tabs:
                </p>
                <ul className="list-disc list-inside text-slate-500 text-xs mt-2 space-y-1">
                    <li><strong>General</strong> - Title, type, description</li>
                    <li><strong>Transcript</strong> - Voice-optimized content segments</li>
                    <li><strong>Media</strong> - Images, diagrams, and visual assets</li>
                </ul>
            </div>
        ),
    },
    {
        id: 'transcript',
        target: '[data-tour="transcript-tab"]',
        title: 'Transcript Segments',
        placement: 'bottom',
        content: (
            <div>
                <p className="mb-2">
                    UMCF is designed for conversational AI tutoring. Transcripts are broken into
                    segments for natural turn-by-turn dialogue.
                </p>
                <p className="text-xs text-slate-500">
                    Each segment can have its own type (lecture, explanation, example, checkpoint)
                    and speaking notes for the AI tutor.
                </p>
            </div>
        ),
    },
    {
        id: 'media',
        target: '[data-tour="media-tab"]',
        title: 'Visual Assets',
        placement: 'bottom',
        content: (
            <div>
                <p className="mb-2">
                    Attach images, diagrams, and other media to your content. Each asset can be
                    timed to specific transcript segments.
                </p>
                <p className="text-xs text-slate-500">
                    The AI tutor will display these visuals at the appropriate moments during
                    the lesson.
                </p>
            </div>
        ),
    },
    {
        id: 'read-only',
        target: '[data-tour="mode-indicator"]',
        title: 'Editing Modes',
        placement: 'top',
        content: (
            <div>
                <p className="mb-2">
                    Curriculum can be in <strong>Studio Mode</strong> (editable) or <strong>Read Only Mode</strong> (locked).
                </p>
                <p className="text-xs text-slate-500">
                    External curricula imported from sources like MIT OCW are automatically locked
                    to preserve their original content.
                </p>
            </div>
        ),
    },
    {
        id: 'help',
        target: '[data-tour="help-button"]',
        title: 'Need Help?',
        placement: 'left',
        content: (
            <div>
                <p className="mb-2">
                    Click the help button anytime to access documentation, restart this tour,
                    or learn more about the UMCF format.
                </p>
                <p className="text-indigo-400 text-xs">
                    You&apos;re all set! Start exploring your curriculum.
                </p>
            </div>
        ),
    },
];
