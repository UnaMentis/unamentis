
import React, { useState } from 'react';
import {
    X,
    HelpCircle,
    BookOpen,
    Layers,
    FileText,
    MessageSquare,
    Image as ImageIcon,
    Settings,
    ExternalLink,
    ChevronRight,
    Sparkles,
    AlertCircle,
    CheckCircle,
    Info,
    Mic,
    Play,
} from 'lucide-react';
import { cn } from '@/lib/utils';

interface StudioHelpProps {
    isOpen: boolean;
    onClose: () => void;
    onStartTour: () => void;
}

type HelpSection = 'overview' | 'structure' | 'transcript' | 'media' | 'glossary' | 'best-practices';

const HELP_SECTIONS: { id: HelpSection; label: string; icon: React.ElementType }[] = [
    { id: 'overview', label: 'Overview', icon: BookOpen },
    { id: 'structure', label: 'Content Structure', icon: Layers },
    { id: 'transcript', label: 'Transcripts', icon: MessageSquare },
    { id: 'media', label: 'Media Assets', icon: ImageIcon },
    { id: 'glossary', label: 'Glossary', icon: FileText },
    { id: 'best-practices', label: 'Best Practices', icon: CheckCircle },
];

export const StudioHelp: React.FC<StudioHelpProps> = ({ isOpen, onClose, onStartTour }) => {
    const [activeSection, setActiveSection] = useState<HelpSection>('overview');

    if (!isOpen) return null;

    return (
        <div className="fixed inset-0 z-[150] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm">
            <div className="w-full max-w-4xl max-h-[85vh] bg-slate-900 border border-slate-700 rounded-xl shadow-2xl flex flex-col overflow-hidden animate-in fade-in-0 zoom-in-95 duration-200">
                {/* Header */}
                <div className="flex items-center justify-between p-4 border-b border-slate-800 bg-slate-900/50">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-indigo-500/20 rounded-lg">
                            <HelpCircle size={20} className="text-indigo-400" />
                        </div>
                        <div>
                            <h2 className="text-lg font-bold text-white">Curriculum Studio Help</h2>
                            <p className="text-xs text-slate-500">Learn about the UMCF format and editor features</p>
                        </div>
                    </div>
                    <button
                        onClick={onClose}
                        className="p-2 text-slate-400 hover:text-white transition-colors hover:bg-slate-800 rounded-lg"
                    >
                        <X size={20} />
                    </button>
                </div>

                <div className="flex flex-1 overflow-hidden">
                    {/* Sidebar */}
                    <div className="w-56 border-r border-slate-800 bg-slate-900/50 p-2 flex flex-col">
                        <button
                            onClick={onStartTour}
                            className="flex items-center gap-2 px-3 py-2 mb-3 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg text-sm font-medium transition-colors"
                        >
                            <Sparkles size={16} />
                            Start Interactive Tour
                        </button>

                        <div className="space-y-1">
                            {HELP_SECTIONS.map((section) => (
                                <button
                                    key={section.id}
                                    onClick={() => setActiveSection(section.id)}
                                    className={cn(
                                        "w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-colors text-left",
                                        activeSection === section.id
                                            ? "bg-slate-800 text-white"
                                            : "text-slate-400 hover:text-slate-200 hover:bg-slate-800/50"
                                    )}
                                >
                                    <section.icon size={16} />
                                    {section.label}
                                </button>
                            ))}
                        </div>

                        <div className="mt-auto pt-4 border-t border-slate-800">
                            <a
                                href="https://github.com/yourusername/unamentis/blob/main/curriculum/README.md"
                                target="_blank"
                                rel="noopener noreferrer"
                                className="flex items-center gap-2 px-3 py-2 text-sm text-slate-500 hover:text-indigo-400 transition-colors"
                            >
                                <ExternalLink size={14} />
                                Full UMCF Docs
                            </a>
                        </div>
                    </div>

                    {/* Content */}
                    <div className="flex-1 overflow-y-auto p-6">
                        {activeSection === 'overview' && <OverviewSection />}
                        {activeSection === 'structure' && <StructureSection />}
                        {activeSection === 'transcript' && <TranscriptSection />}
                        {activeSection === 'media' && <MediaSection />}
                        {activeSection === 'glossary' && <GlossarySection />}
                        {activeSection === 'best-practices' && <BestPracticesSection />}
                    </div>
                </div>
            </div>
        </div>
    );
};

// Section Components
const OverviewSection: React.FC = () => (
    <div className="space-y-6">
        <div>
            <h3 className="text-xl font-bold text-white mb-3">What is UMCF?</h3>
            <p className="text-slate-400 leading-relaxed">
                The <strong className="text-white">Una Mentis Curriculum Format (UMCF)</strong> is a JSON-based
                specification for representing educational content optimized for conversational AI tutoring.
                Unlike traditional e-learning formats designed for Learning Management Systems, UMCF is
                purpose-built for voice-first, real-time tutoring interactions.
            </p>
        </div>

        <div className="grid grid-cols-2 gap-4">
            <InfoCard
                icon={Mic}
                title="Voice-Native"
                description="Every text field has optional spoken variants optimized for text-to-speech"
            />
            <InfoCard
                icon={MessageSquare}
                title="Tutoring-First"
                description="Stopping points, comprehension checks, and misconception handling built-in"
            />
            <InfoCard
                icon={Layers}
                title="Unlimited Hierarchy"
                description="Topics can nest to any depth, not limited like SCORM's 4 levels"
            />
            <InfoCard
                icon={Sparkles}
                title="AI-Ready"
                description="Designed for automated content enrichment and generation"
            />
        </div>

        <div className="p-4 bg-slate-800/50 rounded-lg border border-slate-700">
            <h4 className="font-semibold text-white mb-2 flex items-center gap-2">
                <Info size={16} className="text-blue-400" />
                Key Differentiators
            </h4>
            <ul className="space-y-2 text-sm text-slate-400">
                <li className="flex items-start gap-2">
                    <ChevronRight size={14} className="text-indigo-400 mt-1 flex-shrink-0" />
                    <span><strong className="text-slate-300">Transcript segments</strong> with stopping points for natural conversation flow</span>
                </li>
                <li className="flex items-start gap-2">
                    <ChevronRight size={14} className="text-indigo-400 mt-1 flex-shrink-0" />
                    <span><strong className="text-slate-300">Alternative explanations</strong> (simpler, technical, analogy) for adaptive teaching</span>
                </li>
                <li className="flex items-start gap-2">
                    <ChevronRight size={14} className="text-indigo-400 mt-1 flex-shrink-0" />
                    <span><strong className="text-slate-300">Misconception handling</strong> with trigger phrases and remediation content</span>
                </li>
                <li className="flex items-start gap-2">
                    <ChevronRight size={14} className="text-indigo-400 mt-1 flex-shrink-0" />
                    <span><strong className="text-slate-300">Tutoring configuration</strong> for Socratic method, scaffolding, and checkpoint frequency</span>
                </li>
            </ul>
        </div>
    </div>
);

const StructureSection: React.FC = () => (
    <div className="space-y-6">
        <div>
            <h3 className="text-xl font-bold text-white mb-3">Content Structure</h3>
            <p className="text-slate-400 leading-relaxed mb-4">
                UMCF organizes content in a hierarchical tree structure. Each node in the tree is called
                a <strong className="text-white">ContentNode</strong> and can contain child nodes to any depth.
            </p>
        </div>

        <div className="space-y-3">
            <h4 className="font-semibold text-white">Node Types</h4>
            <div className="space-y-2">
                <NodeTypeCard
                    type="curriculum"
                    description="The root node representing the entire course"
                    color="purple"
                />
                <NodeTypeCard
                    type="unit"
                    description="Major division of a course (like a textbook part)"
                    color="blue"
                />
                <NodeTypeCard
                    type="module"
                    description="Chapter-like section within a unit"
                    color="cyan"
                />
                <NodeTypeCard
                    type="topic"
                    description="Individual teachable concept or lesson"
                    color="green"
                />
                <NodeTypeCard
                    type="subtopic"
                    description="Subdivision of a topic for detailed coverage"
                    color="yellow"
                />
                <NodeTypeCard
                    type="lesson"
                    description="Structured learning session with clear objectives"
                    color="orange"
                />
                <NodeTypeCard
                    type="segment"
                    description="Atomic conversational unit for AI delivery"
                    color="red"
                />
            </div>
        </div>

        <div className="p-4 bg-slate-800/50 rounded-lg border border-slate-700">
            <h4 className="font-semibold text-white mb-2">Node Properties</h4>
            <div className="grid grid-cols-2 gap-3 text-sm">
                <PropertyItem name="id" description="Unique identifier" />
                <PropertyItem name="title" description="Display name" />
                <PropertyItem name="type" description="Node type from list above" />
                <PropertyItem name="description" description="Summary of content" />
                <PropertyItem name="orderIndex" description="Sort order among siblings" />
                <PropertyItem name="children" description="Nested child nodes" />
                <PropertyItem name="transcript" description="Voice content segments" />
                <PropertyItem name="media" description="Visual assets" />
            </div>
        </div>
    </div>
);

const TranscriptSection: React.FC = () => (
    <div className="space-y-6">
        <div>
            <h3 className="text-xl font-bold text-white mb-3">Transcripts & Segments</h3>
            <p className="text-slate-400 leading-relaxed">
                Transcripts are the heart of UMCF&apos;s voice-first design. Each transcript contains
                a sequence of <strong className="text-white">segments</strong> designed for natural
                turn-by-turn dialogue with an AI tutor.
            </p>
        </div>

        <div className="space-y-3">
            <h4 className="font-semibold text-white">Segment Types</h4>
            <div className="grid grid-cols-2 gap-3">
                <SegmentTypeCard
                    type="introduction"
                    description="Opens a topic, sets context and expectations"
                />
                <SegmentTypeCard
                    type="lecture"
                    description="Core instructional content delivery"
                />
                <SegmentTypeCard
                    type="explanation"
                    description="Clarifies concepts in detail"
                />
                <SegmentTypeCard
                    type="example"
                    description="Illustrates concepts with concrete cases"
                />
                <SegmentTypeCard
                    type="checkpoint"
                    description="Pauses for comprehension check"
                />
                <SegmentTypeCard
                    type="transition"
                    description="Bridges between topics smoothly"
                />
                <SegmentTypeCard
                    type="summary"
                    description="Recaps key points covered"
                />
            </div>
        </div>

        <div className="p-4 bg-indigo-500/10 rounded-lg border border-indigo-500/30">
            <h4 className="font-semibold text-white mb-2 flex items-center gap-2">
                <Play size={16} className="text-indigo-400" />
                Speaking Notes
            </h4>
            <p className="text-sm text-slate-400 mb-3">
                Each segment can include speaking notes to guide the AI tutor&apos;s delivery:
            </p>
            <ul className="space-y-1 text-sm text-slate-400">
                <li><strong className="text-slate-300">pace</strong> - slow, normal, or fast delivery</li>
                <li><strong className="text-slate-300">emotionalTone</strong> - curious, serious, encouraging, etc.</li>
                <li><strong className="text-slate-300">emphasis</strong> - words/phrases to stress</li>
                <li><strong className="text-slate-300">pauseAfter</strong> - natural stopping point flag</li>
            </ul>
        </div>
    </div>
);

const MediaSection: React.FC = () => (
    <div className="space-y-6">
        <div>
            <h3 className="text-xl font-bold text-white mb-3">Media & Visual Assets</h3>
            <p className="text-slate-400 leading-relaxed">
                UMCF supports rich media assets that can be synchronized with transcript segments.
                The AI tutor displays these visuals at appropriate moments during lessons.
            </p>
        </div>

        <div className="space-y-3">
            <h4 className="font-semibold text-white">Supported Media Types</h4>
            <div className="grid grid-cols-2 gap-3">
                <MediaTypeCard type="image" description="Photos, illustrations" />
                <MediaTypeCard type="diagram" description="Flowcharts, schematics" />
                <MediaTypeCard type="equation" description="Mathematical formulas" />
                <MediaTypeCard type="chart" description="Graphs, data visualizations" />
                <MediaTypeCard type="slideImage" description="Individual slide captures" />
                <MediaTypeCard type="slideDeck" description="Full presentation" />
                <MediaTypeCard type="video" description="Short clips" />
                <MediaTypeCard type="videoLecture" description="Full lecture recordings" />
            </div>
        </div>

        <div className="p-4 bg-slate-800/50 rounded-lg border border-slate-700">
            <h4 className="font-semibold text-white mb-2">Segment Timing</h4>
            <p className="text-sm text-slate-400 mb-3">
                Each media asset can specify when it appears relative to transcript segments:
            </p>
            <div className="grid grid-cols-3 gap-3 text-sm">
                <div className="p-2 bg-slate-900 rounded">
                    <div className="font-medium text-white">startSegment</div>
                    <div className="text-slate-500">When to show</div>
                </div>
                <div className="p-2 bg-slate-900 rounded">
                    <div className="font-medium text-white">endSegment</div>
                    <div className="text-slate-500">When to hide</div>
                </div>
                <div className="p-2 bg-slate-900 rounded">
                    <div className="font-medium text-white">displayMode</div>
                    <div className="text-slate-500">persistent / highlight / popup</div>
                </div>
            </div>
        </div>
    </div>
);

const GlossarySection: React.FC = () => (
    <div className="space-y-6">
        <div>
            <h3 className="text-xl font-bold text-white mb-3">UMCF Glossary</h3>
            <p className="text-slate-400 leading-relaxed mb-4">
                Key terms and concepts used throughout the UMCF format.
            </p>
        </div>

        <div className="space-y-4">
            <GlossaryItem
                term="UMCF"
                definition="Una Mentis Curriculum Format - a JSON-based specification for conversational AI tutoring content"
            />
            <GlossaryItem
                term="ContentNode"
                definition="The fundamental building block of UMCF structure. A recursive element that can contain children."
            />
            <GlossaryItem
                term="Transcript"
                definition="Voice-optimized content broken into segments for turn-by-turn AI tutoring delivery."
            />
            <GlossaryItem
                term="Segment"
                definition="An atomic unit of spoken content within a transcript, designed for natural conversation flow."
            />
            <GlossaryItem
                term="Stopping Point"
                definition="A marker in the transcript where the AI should pause for comprehension checking or student response."
            />
            <GlossaryItem
                term="Misconception"
                definition="A common error in understanding, with trigger phrases that detect it and remediation content to correct it."
            />
            <GlossaryItem
                term="Tutoring Config"
                definition="Settings that control how the AI delivers content: depth, interaction mode, scaffolding level."
            />
            <GlossaryItem
                term="Learning Objective"
                definition="A measurable statement of what the learner will be able to do, aligned with Bloom's Taxonomy."
            />
        </div>
    </div>
);

const BestPracticesSection: React.FC = () => (
    <div className="space-y-6">
        <div>
            <h3 className="text-xl font-bold text-white mb-3">Best Practices</h3>
            <p className="text-slate-400 leading-relaxed">
                Guidelines for creating effective conversational curriculum content.
            </p>
        </div>

        <div className="space-y-4">
            <BestPracticeCard
                icon={CheckCircle}
                title="Keep segments conversational"
                description="Write as if speaking to a student. Use 'you' and 'we'. Avoid academic formality."
            />
            <BestPracticeCard
                icon={CheckCircle}
                title="Add natural stopping points"
                description="Every 2-3 concepts, add a checkpoint segment to verify understanding before proceeding."
            />
            <BestPracticeCard
                icon={CheckCircle}
                title="Provide alternative explanations"
                description="Include simpler and more technical versions of key concepts for adaptive teaching."
            />
            <BestPracticeCard
                icon={CheckCircle}
                title="Anticipate misconceptions"
                description="Think about common errors students make and add misconception handlers with remediation."
            />
            <BestPracticeCard
                icon={CheckCircle}
                title="Time your media"
                description="Sync visual assets to specific segments so they appear exactly when relevant."
            />
            <BestPracticeCard
                icon={AlertCircle}
                title="Avoid walls of text"
                description="Break long explanations into multiple segments. Each segment should be 1-3 paragraphs max."
                variant="warning"
            />
            <BestPracticeCard
                icon={AlertCircle}
                title="Don't skip context"
                description="Always include introduction segments that set expectations and connect to prior knowledge."
                variant="warning"
            />
        </div>
    </div>
);

// Helper Components
const InfoCard: React.FC<{ icon: React.ElementType; title: string; description: string }> = ({
    icon: Icon,
    title,
    description,
}) => (
    <div className="p-4 bg-slate-800/50 rounded-lg border border-slate-700">
        <div className="flex items-center gap-2 mb-2">
            <Icon size={18} className="text-indigo-400" />
            <span className="font-semibold text-white">{title}</span>
        </div>
        <p className="text-sm text-slate-400">{description}</p>
    </div>
);

const NodeTypeCard: React.FC<{ type: string; description: string; color: string }> = ({
    type,
    description,
    color,
}) => {
    const colors: Record<string, string> = {
        purple: 'bg-purple-500/20 text-purple-400 border-purple-500/30',
        blue: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
        cyan: 'bg-cyan-500/20 text-cyan-400 border-cyan-500/30',
        green: 'bg-green-500/20 text-green-400 border-green-500/30',
        yellow: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30',
        orange: 'bg-orange-500/20 text-orange-400 border-orange-500/30',
        red: 'bg-red-500/20 text-red-400 border-red-500/30',
    };

    return (
        <div className="flex items-center gap-3 p-3 bg-slate-800/30 rounded-lg border border-slate-700">
            <span className={cn("px-2 py-1 text-xs font-mono font-bold rounded border", colors[color])}>
                {type}
            </span>
            <span className="text-sm text-slate-400">{description}</span>
        </div>
    );
};

const SegmentTypeCard: React.FC<{ type: string; description: string }> = ({ type, description }) => (
    <div className="p-3 bg-slate-800/30 rounded-lg border border-slate-700">
        <div className="font-medium text-indigo-400 text-sm mb-1">{type}</div>
        <div className="text-xs text-slate-500">{description}</div>
    </div>
);

const MediaTypeCard: React.FC<{ type: string; description: string }> = ({ type, description }) => (
    <div className="p-3 bg-slate-800/30 rounded-lg border border-slate-700">
        <div className="font-medium text-violet-400 text-sm mb-1">{type}</div>
        <div className="text-xs text-slate-500">{description}</div>
    </div>
);

const PropertyItem: React.FC<{ name: string; description: string }> = ({ name, description }) => (
    <div className="flex items-center gap-2">
        <code className="text-xs bg-slate-900 px-1.5 py-0.5 rounded text-indigo-400">{name}</code>
        <span className="text-slate-500">{description}</span>
    </div>
);

const GlossaryItem: React.FC<{ term: string; definition: string }> = ({ term, definition }) => (
    <div className="p-3 bg-slate-800/30 rounded-lg border border-slate-700">
        <div className="font-semibold text-white mb-1">{term}</div>
        <div className="text-sm text-slate-400">{definition}</div>
    </div>
);

const BestPracticeCard: React.FC<{
    icon: React.ElementType;
    title: string;
    description: string;
    variant?: 'success' | 'warning';
}> = ({ icon: Icon, title, description, variant = 'success' }) => (
    <div className={cn(
        "p-4 rounded-lg border",
        variant === 'success'
            ? "bg-emerald-500/10 border-emerald-500/30"
            : "bg-amber-500/10 border-amber-500/30"
    )}>
        <div className="flex items-start gap-3">
            <Icon
                size={18}
                className={cn(
                    "mt-0.5 flex-shrink-0",
                    variant === 'success' ? "text-emerald-400" : "text-amber-400"
                )}
            />
            <div>
                <div className="font-medium text-white mb-1">{title}</div>
                <div className="text-sm text-slate-400">{description}</div>
            </div>
        </div>
    </div>
);
