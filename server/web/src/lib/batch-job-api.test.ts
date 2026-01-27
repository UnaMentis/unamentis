/**
 * Batch Job API Client Tests
 *
 * Tests the REAL api-client code using MSW for network-level HTTP mocking.
 * No vi.mock of internal modules - per "Real Over Mock" philosophy.
 */
import { describe, it, expect, beforeAll, beforeEach, afterAll, afterEach } from 'vitest';
import { server, mswTestState, http, HttpResponse } from '@/test/msw-server';
import {
  getBatchJobs,
  getBatchJob,
  createBatchJob,
  deleteBatchJob,
  startBatchJob,
  pauseBatchJob,
  resumeBatchJob,
  getJobProgress,
  getJobItems,
  retryFailedItems,
  extractContent,
} from './api-client';
import { createTestJob, createTestItem, createTestProgress } from '@/test/msw-handlers';

// Set environment to use real backend (not mock mode)
process.env.NEXT_PUBLIC_BACKEND_URL = 'http://localhost:8766';
process.env.NEXT_PUBLIC_USE_MOCK = 'false';

describe('Batch Job API Client', () => {
  // Start MSW server for this test file
  beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
  afterEach(() => {
    server.resetHandlers();
    mswTestState.reset();
  });
  afterAll(() => server.close());

  describe('getBatchJobs', () => {
    it('fetches jobs without filters', async () => {
      mswTestState.setJobs([createTestJob({ id: 'job-1', name: 'Test Job' })]);

      const result = await getBatchJobs();
      expect(result.jobs).toHaveLength(1);
      expect(result.jobs[0].name).toBe('Test Job');
    });

    it('fetches jobs with status filter', async () => {
      mswTestState.setJobs([
        createTestJob({ id: 'job-1', status: 'running' }),
        createTestJob({ id: 'job-2', status: 'pending' }),
      ]);

      const result = await getBatchJobs({ status: 'running' });
      expect(result.jobs).toHaveLength(1);
      expect(result.jobs[0].status).toBe('running');
    });

    it('returns empty array when no jobs exist', async () => {
      mswTestState.setJobs([]);

      const result = await getBatchJobs();
      expect(result.jobs).toHaveLength(0);
      expect(result.total).toBe(0);
    });
  });

  describe('getBatchJob', () => {
    it('fetches a single job by ID', async () => {
      mswTestState.setJobs([createTestJob({ id: 'job-123', name: 'Test Job', status: 'running' })]);

      const result = await getBatchJob('job-123');
      expect(result.job.id).toBe('job-123');
      expect(result.job.status).toBe('running');
    });

    it('returns error for non-existent job', async () => {
      mswTestState.setJobs([]);

      const result = await getBatchJob('non-existent');
      expect(result.success).toBe(false);
    });
  });

  describe('createBatchJob', () => {
    it('creates a new batch job', async () => {
      const result = await createBatchJob({
        name: 'KB Audio Batch',
        source_type: 'knowledge-bowl',
        profile_id: 'profile-1',
        include_questions: true,
        include_answers: true,
      });

      expect(result.success).toBe(true);
      expect(result.job.name).toBe('KB Audio Batch');
      expect(result.job.source_type).toBe('knowledge-bowl');
    });

    it('returns error on creation failure', async () => {
      // Override handler to return error
      server.use(
        http.post('*/api/tts/pregen/jobs', () => {
          return HttpResponse.json(
            { success: false, error: 'Invalid profile ID' },
            { status: 400 }
          );
        })
      );

      await expect(
        createBatchJob({
          name: 'Test',
          source_type: 'knowledge-bowl',
          profile_id: 'invalid',
        })
      ).rejects.toThrow();
    });
  });

  describe('deleteBatchJob', () => {
    it('deletes a job', async () => {
      mswTestState.setJobs([createTestJob({ id: 'job-123' })]);

      const result = await deleteBatchJob('job-123');
      expect(result.success).toBe(true);
    });
  });

  describe('job control operations', () => {
    beforeEach(() => {
      mswTestState.setJobs([createTestJob({ id: 'job-1', status: 'pending' })]);
    });

    it('starts a pending job', async () => {
      const result = await startBatchJob('job-1');
      expect(result.job.status).toBe('running');
    });

    it('pauses a running job', async () => {
      mswTestState.setJobs([createTestJob({ id: 'job-1', status: 'running' })]);

      const result = await pauseBatchJob('job-1');
      expect(result.job.status).toBe('paused');
    });

    it('resumes a paused job', async () => {
      mswTestState.setJobs([createTestJob({ id: 'job-1', status: 'paused' })]);

      const result = await resumeBatchJob('job-1');
      expect(result.job.status).toBe('running');
    });
  });

  describe('getJobProgress', () => {
    it('returns progress information', async () => {
      mswTestState.setProgress(
        createTestProgress({
          job_id: 'job-1',
          percentage: 45.5,
          completed_items: 45,
          failed_items: 2,
          pending_items: 53,
          total_items: 100,
          current_item_text: 'What is photosynthesis?',
        })
      );

      const result = await getJobProgress('job-1');
      expect(result.percentage).toBe(45.5);
      expect(result.completed_items).toBe(45);
      expect(result.current_item_text).toBe('What is photosynthesis?');
    });
  });

  describe('getJobItems', () => {
    it('fetches items with pagination', async () => {
      mswTestState.setItems([
        createTestItem({ id: 'item-1', text_content: 'Question 1', status: 'completed' }),
        createTestItem({ id: 'item-2', text_content: 'Question 2', status: 'failed' }),
      ]);

      const result = await getJobItems('job-1', { limit: 20, offset: 0 });
      expect(result.items).toHaveLength(2);
      expect(result.total).toBe(2);
    });

    it('filters by status', async () => {
      mswTestState.setItems([
        createTestItem({ id: 'item-1', status: 'completed' }),
        createTestItem({ id: 'item-2', status: 'failed' }),
      ]);

      const result = await getJobItems('job-1', { status: 'failed' });
      expect(result.items).toHaveLength(1);
      expect(result.items[0].status).toBe('failed');
    });
  });

  describe('retryFailedItems', () => {
    it('resets failed items for retry', async () => {
      mswTestState.setItems([
        createTestItem({ id: 'item-1', status: 'failed' }),
        createTestItem({ id: 'item-2', status: 'failed' }),
        createTestItem({ id: 'item-3', status: 'completed' }),
      ]);

      const result = await retryFailedItems('job-1');
      expect(result.success).toBe(true);
      expect(result.reset_count).toBe(2);
    });
  });

  describe('extractContent', () => {
    it('extracts Knowledge Bowl content', async () => {
      mswTestState.setExtractResponse({
        success: true,
        items: [
          { text: 'What is gravity?', source_ref: 'q1:question' },
          { text: '9.8 m/s²', source_ref: 'q1:answer' },
        ],
        total_count: 200,
        stats: {
          total_questions: 50,
          type_counts: { question: 50, answer: 50, hint: 60, explanation: 40 },
        },
      });

      const result = await extractContent({
        source_type: 'knowledge-bowl',
        include_questions: true,
        include_answers: true,
        include_hints: true,
        include_explanations: true,
      });

      expect(result.success).toBe(true);
      expect(result.total_count).toBe(200);
      expect(result.stats?.total_questions).toBe(50);
    });

    it('handles extraction errors', async () => {
      mswTestState.setExtractResponse({
        success: false,
        items: [],
        total_count: 0,
        error: 'No content found',
      });

      const result = await extractContent({
        source_type: 'knowledge-bowl',
        include_questions: true,
      });

      expect(result.success).toBe(false);
      expect(result.error).toBe('No content found');
    });
  });
});
