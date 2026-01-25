'use client';

import { useState } from 'react';
import { HelpCircle, X, ChevronRight, ExternalLink } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface HelpSection {
  title: string;
  content: React.ReactNode;
}

interface HelpButtonProps {
  title: string;
  description?: string;
  sections: HelpSection[];
  docLink?: string;
  className?: string;
}

export function HelpButton({
  title,
  description,
  sections,
  docLink,
  className = '',
}: HelpButtonProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [expandedSection, setExpandedSection] = useState<number | null>(0);

  return (
    <>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => setIsOpen(true)}
        className={`text-slate-400 hover:text-slate-200 ${className}`}
        aria-label="Help"
      >
        <HelpCircle className="w-5 h-5" />
      </Button>

      {isOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <Card className="bg-slate-900 border-slate-700 w-full max-w-2xl max-h-[85vh] flex flex-col">
            <CardHeader className="flex flex-row items-start justify-between border-b border-slate-800 pb-4 flex-shrink-0">
              <div>
                <CardTitle className="flex items-center gap-2 text-white">
                  <HelpCircle className="w-5 h-5 text-blue-400" />
                  {title}
                </CardTitle>
                {description && <p className="text-sm text-slate-400 mt-1">{description}</p>}
              </div>
              <Button variant="ghost" size="sm" onClick={() => setIsOpen(false)}>
                <X className="w-5 h-5" />
              </Button>
            </CardHeader>

            <CardContent className="pt-4 overflow-y-auto flex-1">
              <div className="space-y-2">
                {sections.map((section, index) => (
                  <div key={index} className="border border-slate-800 rounded-lg overflow-hidden">
                    <button
                      onClick={() => setExpandedSection(expandedSection === index ? null : index)}
                      className="w-full flex items-center justify-between p-3 text-left hover:bg-slate-800/50 transition-colors"
                    >
                      <span className="font-medium text-slate-200">{section.title}</span>
                      <ChevronRight
                        className={`w-4 h-4 text-slate-500 transition-transform ${
                          expandedSection === index ? 'rotate-90' : ''
                        }`}
                      />
                    </button>
                    {expandedSection === index && (
                      <div className="p-4 pt-0 text-sm text-slate-300 border-t border-slate-800">
                        {section.content}
                      </div>
                    )}
                  </div>
                ))}
              </div>

              {docLink && (
                <div className="mt-6 pt-4 border-t border-slate-800">
                  <a
                    href={docLink}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-2 text-sm text-blue-400 hover:text-blue-300"
                  >
                    <ExternalLink className="w-4 h-4" />
                    View Full Documentation
                  </a>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}

// Pre-built help content for Batch Jobs
export const batchJobsHelpSections: HelpSection[] = [
  {
    title: 'What are Batch Jobs?',
    content: (
      <div className="space-y-2">
        <p>
          Batch jobs generate audio files for large content sets like Knowledge Bowl questions.
          Instead of generating audio on-demand during sessions, batch jobs pre-generate audio files
          that can be served instantly.
        </p>
        <p className="text-slate-400">
          This reduces latency during quiz sessions and ensures consistent audio quality.
        </p>
      </div>
    ),
  },
  {
    title: 'Creating a Job',
    content: (
      <div className="space-y-3">
        <p>The job creation wizard has 4 steps:</p>
        <ol className="list-decimal list-inside space-y-2 text-slate-400">
          <li>
            <span className="text-slate-300">Source:</span> Select content source (Knowledge Bowl)
            and what content types to include
          </li>
          <li>
            <span className="text-slate-300">Profile:</span> Choose a TTS voice profile that defines
            voice settings
          </li>
          <li>
            <span className="text-slate-300">Preview:</span> Review how many items will be generated
            and sample the content
          </li>
          <li>
            <span className="text-slate-300">Create:</span> Name your job, select output format, and
            create
          </li>
        </ol>
      </div>
    ),
  },
  {
    title: 'Job Statuses',
    content: (
      <div className="space-y-2">
        <ul className="space-y-2 text-slate-400">
          <li>
            <span className="text-slate-300 font-medium">Pending:</span> Created but not started.
            Click Start to begin.
          </li>
          <li>
            <span className="text-slate-300 font-medium">Running:</span> Actively generating audio.
            Progress updates every 3 seconds.
          </li>
          <li>
            <span className="text-slate-300 font-medium">Paused:</span> Temporarily stopped. Click
            Resume to continue.
          </li>
          <li>
            <span className="text-slate-300 font-medium">Completed:</span> All items processed.
            Check for failed items.
          </li>
          <li>
            <span className="text-slate-300 font-medium">Failed:</span> Job stopped due to repeated
            errors. Review and retry.
          </li>
        </ul>
      </div>
    ),
  },
  {
    title: 'Handling Failed Items',
    content: (
      <div className="space-y-2">
        <p>
          Individual items can fail while the job continues. Failed items are tracked and can be
          retried later.
        </p>
        <ul className="list-disc list-inside space-y-1 text-slate-400 mt-2">
          <li>Click the red &quot;X failed&quot; badge to see failed items</li>
          <li>Use &quot;Retry Failed&quot; to reprocess only failed items</li>
          <li>View error messages in the Items list for troubleshooting</li>
        </ul>
        <p className="text-slate-400 mt-2">
          Common causes: TTS service unavailable, rate limiting, or invalid text content.
        </p>
      </div>
    ),
  },
  {
    title: 'Output Files',
    content: (
      <div className="space-y-2">
        <p>Generated audio files are saved to the server&apos;s data directory:</p>
        <code className="block mt-2 p-2 bg-slate-800 rounded text-xs text-slate-300">
          data/tts-pregenerated/jobs/&#123;job_id&#125;/audio/
        </code>
        <p className="text-slate-400 mt-2">
          Files are named with a hash of the source content for deduplication. The app automatically
          uses these pre-generated files when available.
        </p>
      </div>
    ),
  },
  {
    title: 'Tips & Best Practices',
    content: (
      <ul className="list-disc list-inside space-y-2 text-slate-400">
        <li>
          Start with a small test batch to verify audio quality before processing thousands of items
        </li>
        <li>Use WAV format for highest quality, MP3 for smaller file sizes</li>
        <li>Monitor the first few items of a running job to catch issues early</li>
        <li>
          Create separate jobs for different content types if you want different voice settings
        </li>
        <li>Enable volume normalization when mixing audio from different sources</li>
      </ul>
    ),
  },
];
