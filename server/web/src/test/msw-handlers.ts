/**
 * MSW (Mock Service Worker) handlers for testing.
 *
 * These handlers intercept HTTP requests at the network level,
 * allowing us to test REAL api-client code instead of mocking.
 *
 * Per "Real Over Mock" philosophy:
 * - External HTTP calls are acceptable to mock at network level
 * - Internal modules should NOT be mocked with vi.mock
 */
import { http, HttpResponse } from 'msw';
import type {
  TTSPregenJob,
  TTSJobItem,
  JobProgress,
  TTSProfile,
  ExtractResponse,
} from '@/types/tts-pregen';

// Test data factory
export const createTestJob = (overrides: Partial<TTSPregenJob> = {}): TTSPregenJob => ({
  id: 'job-1',
  name: 'Test Batch Job',
  job_type: 'batch',
  status: 'pending',
  source_type: 'knowledge-bowl',
  profile_id: 'profile-1',
  output_format: 'wav',
  normalize_volume: false,
  output_dir: '/data/tts-pregenerated/jobs/job-1/audio',
  total_items: 100,
  completed_items: 0,
  failed_items: 0,
  current_item_index: 0,
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
  consecutive_failures: 0,
  ...overrides,
});

export const createTestItem = (overrides: Partial<TTSJobItem> = {}): TTSJobItem => ({
  id: 'item-1',
  job_id: 'job-1',
  item_index: 0,
  text_content: 'What is the capital of France?',
  text_hash: 'hash1',
  status: 'pending',
  attempt_count: 0,
  ...overrides,
});

export const createTestProgress = (overrides: Partial<JobProgress> = {}): JobProgress => ({
  job_id: 'job-1',
  status: 'running',
  percentage: 50,
  completed_items: 50,
  failed_items: 0,
  pending_items: 50,
  total_items: 100,
  current_item_index: 50,
  current_item_text: 'What is the speed of light?',
  ...overrides,
});

export const createTestProfile = (overrides: Partial<TTSProfile> = {}): TTSProfile => ({
  id: 'profile-1',
  name: 'Default Voice',
  provider: 'chatterbox',
  voice_id: 'voice-1',
  tags: ['default', 'warm'],
  is_default: true,
  is_active: true,
  settings: { speed: 1.0 },
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z',
  ...overrides,
});

// Default test data
const defaultJobs: TTSPregenJob[] = [createTestJob()];
const defaultItems: TTSJobItem[] = [
  createTestItem({ status: 'completed', attempt_count: 1 }),
  createTestItem({
    id: 'item-2',
    item_index: 1,
    text_content: 'What is 2 + 2?',
    text_hash: 'hash2',
    status: 'failed',
    attempt_count: 3,
    last_error: 'TTS generation timeout',
  }),
  createTestItem({
    id: 'item-3',
    item_index: 2,
    text_content: 'Name the planets.',
    text_hash: 'hash3',
    status: 'pending',
  }),
];
const defaultProfiles: TTSProfile[] = [
  createTestProfile(),
  createTestProfile({
    id: 'profile-2',
    name: 'Fast Voice',
    provider: 'vibevoice',
    voice_id: 'voice-2',
    tags: ['fast'],
    is_default: false,
  }),
];
const defaultProgress = createTestProgress();

// Handler state for dynamic test scenarios
let testJobs = [...defaultJobs];
let testItems = [...defaultItems];
let testProfiles = [...defaultProfiles];
let testProgress = { ...defaultProgress };
let testExtractResponse: ExtractResponse = {
  success: true,
  items: [
    { text: 'Question 1', source_ref: 'q1:question' },
    { text: 'Answer 1', source_ref: 'q1:answer' },
  ],
  total_count: 100,
  stats: {
    total_questions: 25,
    type_counts: { question: 25, answer: 25, hint: 30, explanation: 20 },
    domain_counts: { Physics: 50, Chemistry: 50 },
  },
};

// State manipulation for tests
export const mswTestState = {
  setJobs: (jobs: TTSPregenJob[]) => {
    testJobs = jobs;
  },
  setItems: (items: TTSJobItem[]) => {
    testItems = items;
  },
  setProfiles: (profiles: TTSProfile[]) => {
    testProfiles = profiles;
  },
  setProgress: (progress: JobProgress) => {
    testProgress = progress;
  },
  setExtractResponse: (response: ExtractResponse) => {
    testExtractResponse = response;
  },
  reset: () => {
    testJobs = [...defaultJobs];
    testItems = [...defaultItems];
    testProfiles = [...defaultProfiles];
    testProgress = { ...defaultProgress };
    testExtractResponse = {
      success: true,
      items: [
        { text: 'Question 1', source_ref: 'q1:question' },
        { text: 'Answer 1', source_ref: 'q1:answer' },
      ],
      total_count: 100,
      stats: {
        total_questions: 25,
        type_counts: { question: 25, answer: 25, hint: 30, explanation: 20 },
        domain_counts: { Physics: 50, Chemistry: 50 },
      },
    };
  },
};

// MSW handlers for TTS Pregen API
export const handlers = [
  // GET /api/tts/pregen/jobs - List jobs
  http.get('*/api/tts/pregen/jobs', ({ request }) => {
    const url = new URL(request.url);
    const status = url.searchParams.get('status');
    const jobType = url.searchParams.get('job_type');

    let filtered = [...testJobs];
    if (status) {
      filtered = filtered.filter((j) => j.status === status);
    }
    if (jobType) {
      filtered = filtered.filter((j) => j.job_type === jobType);
    }

    return HttpResponse.json({
      success: true,
      jobs: filtered,
      total: filtered.length,
      limit: 50,
      offset: 0,
    });
  }),

  // GET /api/tts/pregen/jobs/:id - Get single job
  http.get('*/api/tts/pregen/jobs/:jobId', ({ params }) => {
    const job = testJobs.find((j) => j.id === params.jobId);
    if (!job) {
      return HttpResponse.json({ success: false, error: 'Job not found' }, { status: 404 });
    }
    return HttpResponse.json({ success: true, job });
  }),

  // POST /api/tts/pregen/jobs - Create job
  http.post('*/api/tts/pregen/jobs', async ({ request }) => {
    const data = (await request.json()) as Record<string, unknown>;
    const newJob = createTestJob({
      id: `new-job-${Date.now()}`,
      name: data.name as string,
      source_type: data.source_type as string,
      profile_id: data.profile_id as string,
    });
    testJobs.push(newJob);
    return HttpResponse.json({ success: true, job: newJob });
  }),

  // DELETE /api/tts/pregen/jobs/:id - Delete job
  http.delete('*/api/tts/pregen/jobs/:jobId', ({ params }) => {
    const index = testJobs.findIndex((j) => j.id === params.jobId);
    if (index !== -1) {
      testJobs.splice(index, 1);
    }
    return HttpResponse.json({ success: true });
  }),

  // POST /api/tts/pregen/jobs/:id/start - Start job
  http.post('*/api/tts/pregen/jobs/:jobId/start', ({ params }) => {
    const job = testJobs.find((j) => j.id === params.jobId);
    if (job) {
      job.status = 'running';
    }
    return HttpResponse.json({ success: true, job });
  }),

  // POST /api/tts/pregen/jobs/:id/pause - Pause job
  http.post('*/api/tts/pregen/jobs/:jobId/pause', ({ params }) => {
    const job = testJobs.find((j) => j.id === params.jobId);
    if (job) {
      job.status = 'paused';
    }
    return HttpResponse.json({ success: true, job });
  }),

  // POST /api/tts/pregen/jobs/:id/resume - Resume job
  http.post('*/api/tts/pregen/jobs/:jobId/resume', ({ params }) => {
    const job = testJobs.find((j) => j.id === params.jobId);
    if (job) {
      job.status = 'running';
    }
    return HttpResponse.json({ success: true, job });
  }),

  // GET /api/tts/pregen/jobs/:id/progress - Get progress
  http.get('*/api/tts/pregen/jobs/:jobId/progress', () => {
    return HttpResponse.json(testProgress);
  }),

  // GET /api/tts/pregen/jobs/:id/items - Get items
  http.get('*/api/tts/pregen/jobs/:jobId/items', ({ request }) => {
    const url = new URL(request.url);
    const status = url.searchParams.get('status');
    const limit = parseInt(url.searchParams.get('limit') || '20');
    const offset = parseInt(url.searchParams.get('offset') || '0');

    let filtered = [...testItems];
    if (status) {
      filtered = filtered.filter((i) => i.status === status);
    }

    return HttpResponse.json({
      success: true,
      items: filtered.slice(offset, offset + limit),
      total: filtered.length,
      limit,
      offset,
    });
  }),

  // POST /api/tts/pregen/jobs/:id/retry-failed - Retry failed
  http.post('*/api/tts/pregen/jobs/:jobId/retry-failed', () => {
    const failedCount = testItems.filter((i) => i.status === 'failed').length;
    testItems = testItems.map((i) =>
      i.status === 'failed' ? { ...i, status: 'pending' as const, attempt_count: 0 } : i
    );
    return HttpResponse.json({ success: true, reset_count: failedCount });
  }),

  // POST /api/tts/pregen/extract - Extract content
  http.post('*/api/tts/pregen/extract', () => {
    return HttpResponse.json(testExtractResponse);
  }),

  // GET /api/tts/profiles - Get profiles
  http.get('*/api/tts/profiles', () => {
    return HttpResponse.json({ profiles: testProfiles, total: testProfiles.length });
  }),
];
