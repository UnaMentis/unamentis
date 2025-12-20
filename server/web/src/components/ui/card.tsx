import { cn } from '@/lib/utils';

interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
}

export function Card({ children, className, ...props }: CardProps) {
  return (
    <div
      className={cn(
        'rounded-xl bg-slate-800/50 border border-slate-700/50 overflow-hidden',
        className
      )}
      {...props}
    >
      {children}
    </div>
  );
}

export function CardHeader({ children, className, ...props }: CardProps) {
  return (
    <div
      className={cn(
        'flex items-center justify-between px-4 py-3 border-b border-slate-700/50 bg-slate-800/30',
        className
      )}
      {...props}
    >
      {children}
    </div>
  );
}

export function CardTitle({ children, className, ...props }: CardProps) {
  return (
    <h3
      className={cn('flex items-center gap-2 text-sm font-semibold text-slate-200', className)}
      {...props}
    >
      {children}
    </h3>
  );
}

export function CardContent({ children, className, ...props }: CardProps) {
  return (
    <div className={cn('p-4', className)} {...props}>
      {children}
    </div>
  );
}
