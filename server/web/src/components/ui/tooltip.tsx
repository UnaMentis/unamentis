
import React, { useState, useRef, useEffect } from 'react';
import { cn } from '@/lib/utils';
import { HelpCircle } from 'lucide-react';

interface TooltipProps {
    content: React.ReactNode;
    children: React.ReactNode;
    side?: 'top' | 'bottom' | 'left' | 'right';
    align?: 'start' | 'center' | 'end';
    className?: string;
    delayMs?: number;
}

export const Tooltip: React.FC<TooltipProps> = ({
    content,
    children,
    side = 'top',
    align = 'center',
    className,
    delayMs = 200,
}) => {
    const [isVisible, setIsVisible] = useState(false);
    const [position, setPosition] = useState({ top: 0, left: 0 });
    const triggerRef = useRef<HTMLDivElement>(null);
    const tooltipRef = useRef<HTMLDivElement>(null);
    const timeoutRef = useRef<NodeJS.Timeout>();

    const calculatePosition = () => {
        if (!triggerRef.current || !tooltipRef.current) return;

        const triggerRect = triggerRef.current.getBoundingClientRect();
        const tooltipRect = tooltipRef.current.getBoundingClientRect();
        const gap = 8;

        let top = 0;
        let left = 0;

        // Calculate position based on side
        switch (side) {
            case 'top':
                top = triggerRect.top - tooltipRect.height - gap;
                break;
            case 'bottom':
                top = triggerRect.bottom + gap;
                break;
            case 'left':
                left = triggerRect.left - tooltipRect.width - gap;
                top = triggerRect.top + (triggerRect.height - tooltipRect.height) / 2;
                break;
            case 'right':
                left = triggerRect.right + gap;
                top = triggerRect.top + (triggerRect.height - tooltipRect.height) / 2;
                break;
        }

        // Calculate alignment for top/bottom
        if (side === 'top' || side === 'bottom') {
            switch (align) {
                case 'start':
                    left = triggerRect.left;
                    break;
                case 'center':
                    left = triggerRect.left + (triggerRect.width - tooltipRect.width) / 2;
                    break;
                case 'end':
                    left = triggerRect.right - tooltipRect.width;
                    break;
            }
        }

        // Keep tooltip within viewport
        const padding = 10;
        left = Math.max(padding, Math.min(left, window.innerWidth - tooltipRect.width - padding));
        top = Math.max(padding, Math.min(top, window.innerHeight - tooltipRect.height - padding));

        setPosition({ top, left });
    };

    useEffect(() => {
        if (isVisible) {
            calculatePosition();
        }
    }, [isVisible]);

    const handleMouseEnter = () => {
        timeoutRef.current = setTimeout(() => {
            setIsVisible(true);
        }, delayMs);
    };

    const handleMouseLeave = () => {
        if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
        }
        setIsVisible(false);
    };

    return (
        <>
            <div
                ref={triggerRef}
                onMouseEnter={handleMouseEnter}
                onMouseLeave={handleMouseLeave}
                className="inline-flex"
            >
                {children}
            </div>
            {isVisible && (
                <div
                    ref={tooltipRef}
                    className={cn(
                        "fixed z-[100] px-3 py-2 text-sm bg-slate-800 border border-slate-700 rounded-lg shadow-xl",
                        "text-slate-200 max-w-xs animate-in fade-in-0 zoom-in-95 duration-200",
                        className
                    )}
                    style={{ top: position.top, left: position.left }}
                >
                    {content}
                    <div
                        className={cn(
                            "absolute w-2 h-2 bg-slate-800 border-slate-700 rotate-45",
                            side === 'top' && "bottom-[-5px] border-r border-b",
                            side === 'bottom' && "top-[-5px] border-l border-t",
                            side === 'left' && "right-[-5px] border-t border-r",
                            side === 'right' && "left-[-5px] border-b border-l",
                            align === 'center' && (side === 'top' || side === 'bottom') && "left-1/2 -translate-x-1/2",
                            align === 'start' && (side === 'top' || side === 'bottom') && "left-4",
                            align === 'end' && (side === 'top' || side === 'bottom') && "right-4",
                        )}
                    />
                </div>
            )}
        </>
    );
};

// Help icon with tooltip for field explanations
interface HelpTooltipProps {
    content: React.ReactNode;
    side?: 'top' | 'bottom' | 'left' | 'right';
}

export const HelpTooltip: React.FC<HelpTooltipProps> = ({ content, side = 'top' }) => {
    return (
        <Tooltip content={content} side={side}>
            <button
                type="button"
                className="text-slate-500 hover:text-slate-300 transition-colors ml-1"
                onClick={(e) => e.preventDefault()}
            >
                <HelpCircle size={14} />
            </button>
        </Tooltip>
    );
};
