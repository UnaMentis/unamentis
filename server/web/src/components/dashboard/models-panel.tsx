'use client';

import { useState, useEffect } from 'react';
import { FlaskConical, RefreshCw, Cpu, Mic, Volume2 } from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { ModelInfo } from '@/types';
import { getModels } from '@/lib/api-client';
import { cn } from '@/lib/utils';

export function ModelsPanel() {
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [counts, setCounts] = useState({ llm: 0, stt: 0, tts: 0 });
  const [loading, setLoading] = useState(true);

  const fetchModels = async () => {
    try {
      const response = await getModels();
      setModels(response.models);
      setCounts(response.by_type);
    } catch (error) {
      console.error('Failed to fetch models:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchModels();
    const interval = setInterval(fetchModels, 60000);
    return () => clearInterval(interval);
  }, []);

  const typeStyles: Record<string, { icon: typeof Cpu; color: string; bgColor: string }> = {
    llm: { icon: Cpu, color: 'text-violet-400', bgColor: 'bg-violet-500/10 border-violet-500/30' },
    stt: { icon: Mic, color: 'text-emerald-400', bgColor: 'bg-emerald-500/10 border-emerald-500/30' },
    tts: { icon: Volume2, color: 'text-blue-400', bgColor: 'bg-blue-500/10 border-blue-500/30' },
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold">Available Models</h2>
        <button
          onClick={fetchModels}
          className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh
        </button>
      </div>

      {/* Type Filters */}
      <div className="flex gap-4">
        {(['llm', 'stt', 'tts'] as const).map((type) => {
          const style = typeStyles[type];
          const Icon = style.icon;
          return (
            <div
              key={type}
              className={cn('flex items-center gap-2 px-4 py-2 rounded-lg border', style.bgColor)}
            >
              <Icon className={cn('w-5 h-5', style.color)} />
              <span className="font-medium">{counts[type]}</span>
              <span className="text-slate-400 uppercase text-sm">{type}</span>
            </div>
          );
        })}
      </div>

      {/* Models Grid */}
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
        {loading ? (
          Array.from({ length: 6 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="h-24 flex items-center justify-center">
                <div className="animate-pulse text-slate-500">Loading...</div>
              </CardContent>
            </Card>
          ))
        ) : models.length === 0 ? (
          <div className="col-span-full text-center text-slate-500 py-12">
            <FlaskConical className="w-16 h-16 mx-auto mb-4 opacity-30" />
            <p className="text-lg font-medium">No models available</p>
            <p className="text-sm mt-1">Models will appear when servers are healthy</p>
          </div>
        ) : (
          models.map((model) => {
            const style = typeStyles[model.type] || typeStyles.llm;
            const Icon = style.icon;

            return (
              <Card key={model.id} className="hover:border-slate-600/50 transition-all">
                <CardContent className="pt-4">
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center gap-2">
                      <Icon className={cn('w-5 h-5', style.color)} />
                      <h3 className="font-semibold text-slate-100">{model.name}</h3>
                    </div>
                    <Badge variant={model.status === 'available' ? 'success' : 'default'}>
                      {model.status}
                    </Badge>
                  </div>

                  <div className="space-y-1 text-sm">
                    <div className="flex justify-between">
                      <span className="text-slate-400">Type</span>
                      <span className="text-slate-200 uppercase">{model.type}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Server</span>
                      <span className="text-slate-200">{model.server_name}</span>
                    </div>
                    {model.parameters && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Params</span>
                        <span className="text-slate-200">{model.parameters}</span>
                      </div>
                    )}
                    {model.quantization && (
                      <div className="flex justify-between">
                        <span className="text-slate-400">Quant</span>
                        <span className="text-slate-200 font-mono text-xs">{model.quantization}</span>
                      </div>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })
        )}
      </div>
    </div>
  );
}
