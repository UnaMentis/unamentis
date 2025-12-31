
import React, { useState } from 'react';
import { ChevronRight, ChevronDown, Folder, FileText, Box, Layers, BookOpen, LucideIcon } from 'lucide-react';
import { ContentNode } from '@/types/curriculum';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

interface RecursiveNodeProps {
    node: ContentNode;
    selectedId: string | null;
    onSelect: (node: ContentNode) => void;
    level?: number;
}

const NODE_ICONS: Record<string, LucideIcon> = {
    curriculum: BookOpen,
    unit: Box,
    module: Layers,
    topic: Folder,
};

// Render the icon based on node type
const NodeIcon: React.FC<{ type: string; size?: number; className?: string }> = ({ type, size, className }) => {
    const IconComponent = NODE_ICONS[type] || FileText;
    return <IconComponent size={size} className={className} />;
};

export const RecursiveNode: React.FC<RecursiveNodeProps> = ({ node, selectedId, onSelect, level = 0 }) => {
    const [isOpen, setIsOpen] = useState(true);
    const hasChildren = node.children && node.children.length > 0;
    const isSelected = selectedId === node.id.value;

    const handleToggle = (e: React.MouseEvent) => {
        e.stopPropagation();
        setIsOpen(!isOpen);
    };

    const handleSelect = (e: React.MouseEvent) => {
        e.stopPropagation();
        onSelect(node);
    };

    return (
        <div className="select-none">
            <div
                className={twMerge(
                    "flex items-center py-1.5 px-2 cursor-pointer transition-all duration-200 group rounded-r-lg border-l-2",
                    isSelected
                        ? "bg-indigo-500/10 border-indigo-500 text-indigo-400"
                        : "border-transparent text-slate-400 hover:bg-slate-800/50 hover:text-slate-200"
                )}
                style={{ paddingLeft: `${level * 12 + 8}px` }}
                onClick={handleSelect}
            >
                <button
                    className={clsx(
                        "p-0.5 rounded mr-1 hover:bg-white/10 transition-colors",
                        !hasChildren && "invisible"
                    )}
                    onClick={handleToggle}
                >
                    {isOpen ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                </button>

                <NodeIcon type={node.type} size={16} className={clsx("mr-2", isSelected ? "text-indigo-400" : "text-slate-500 group-hover:text-slate-300")} />

                <span className="text-sm font-medium truncate">{node.title}</span>
            </div>

            {hasChildren && isOpen && (
                <div className="flex flex-col">
                    {node.children!.map((child) => (
                        <RecursiveNode
                            key={child.id.value}
                            node={child}
                            selectedId={selectedId}
                            onSelect={onSelect}
                            level={level + 1}
                        />
                    ))}
                </div>
            )}
        </div>
    );
};
