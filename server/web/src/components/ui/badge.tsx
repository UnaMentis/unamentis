import { cn } from '@/lib/utils';

type BadgeVariant = 'default' | 'success' | 'warning' | 'error' | 'info';

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant;
  children: React.ReactNode;
}

const variantStyles: Record<BadgeVariant, string> = {
  default: 'bg-slate-600/50 text-slate-300',
  success: 'bg-emerald-500/20 text-emerald-400',
  warning: 'bg-amber-500/20 text-amber-400',
  error: 'bg-red-500/20 text-red-400',
  info: 'bg-blue-500/20 text-blue-400',
};

export function Badge({ variant = 'default', children, className, ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        'text-xs px-2 py-0.5 rounded-full font-medium uppercase',
        variantStyles[variant],
        className
      )}
      {...props}
    >
      {children}
    </span>
  );
}
