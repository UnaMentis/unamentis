import { describe, it, expect } from 'vitest';
import type {
  TTSPregenJob,
  TTSJobItem,
  JobProgress,
  ExtractResponse,
  CreateBatchJobData,
  JobStatus,
  ItemStatus,
} from './tts-pregen';

describe('TTS Pregen Types', () => {
  describe('TTSPregenJob', () => {
    it('should have all required fields', () => {
      const job: TTSPregenJob = {
        id: 'job-1',
        name: 'Test Job',
        job_type: 'batch',
        status: 'pending',
        source_type: 'knowledge-bowl',
        output_format: 'wav',
        normalize_volume: false,
        output_dir: '/data/output',
        total_items: 100,
        completed_items: 0,
        failed_items: 0,
        current_item_index: 0,
        created_at: '2024-01-15T10:00:00Z',
        updated_at: '2024-01-15T10:00:00Z',
        consecutive_failures: 0,
      };

      expect(job.id).toBe('job-1');
      expect(job.job_type).toBe('batch');
      expect(job.status).toBe('pending');
    });

    it('should support all job statuses', () => {
      const statuses: JobStatus[] = [
        'pending',
        'running',
        'paused',
        'completed',
        'failed',
        'cancelled',
      ];

      statuses.forEach((status) => {
        const job: Partial<TTSPregenJob> = { status };
        expect(job.status).toBe(status);
      });
    });
  });

  describe('TTSJobItem', () => {
    it('should have all required fields', () => {
      const item: TTSJobItem = {
        id: 'item-1',
        job_id: 'job-1',
        item_index: 0,
        text_content: 'What is the speed of light?',
        text_hash: 'abc123',
        status: 'pending',
        attempt_count: 0,
      };

      expect(item.id).toBe('item-1');
      expect(item.text_content).toBe('What is the speed of light?');
    });

    it('should support all item statuses', () => {
      const statuses: ItemStatus[] = ['pending', 'processing', 'completed', 'failed', 'skipped'];

      statuses.forEach((status) => {
        const item: Partial<TTSJobItem> = { status };
        expect(item.status).toBe(status);
      });
    });

    it('should support optional output fields', () => {
      const completedItem: TTSJobItem = {
        id: 'item-1',
        job_id: 'job-1',
        item_index: 0,
        text_content: 'Question text',
        text_hash: 'abc123',
        status: 'completed',
        attempt_count: 1,
        output_file: '/data/audio/item-1.wav',
        duration_seconds: 2.5,
        file_size_bytes: 120000,
        sample_rate: 24000,
        processing_completed_at: '2024-01-15T10:05:00Z',
      };

      expect(completedItem.output_file).toBeDefined();
      expect(completedItem.duration_seconds).toBe(2.5);
    });
  });

  describe('JobProgress', () => {
    it('should have all progress fields', () => {
      const progress: JobProgress = {
        job_id: 'job-1',
        status: 'running',
        percentage: 45.5,
        completed_items: 45,
        failed_items: 2,
        pending_items: 53,
        total_items: 100,
        current_item_index: 47,
        current_item_text: 'Current question text',
      };

      expect(progress.percentage).toBe(45.5);
      expect(progress.completed_items + progress.failed_items + progress.pending_items).toBe(
        progress.total_items
      );
    });

    it('should support estimated time remaining', () => {
      const progress: JobProgress = {
        job_id: 'job-1',
        status: 'running',
        percentage: 50,
        completed_items: 50,
        failed_items: 0,
        pending_items: 50,
        total_items: 100,
        current_item_index: 50,
        estimated_time_remaining: 300, // 5 minutes
      };

      expect(progress.estimated_time_remaining).toBe(300);
    });
  });

  describe('ExtractResponse', () => {
    it('should handle successful extraction', () => {
      const response: ExtractResponse = {
        success: true,
        items: [
          { text: 'Question 1', source_ref: 'q1:question' },
          { text: 'Answer 1', source_ref: 'q1:answer' },
        ],
        total_count: 200,
        stats: {
          total_domains: 3,
          total_questions: 50,
          domain_counts: { Physics: 20, Chemistry: 15, Biology: 15 },
          type_counts: { question: 50, answer: 50, hint: 60, explanation: 40 },
        },
      };

      expect(response.success).toBe(true);
      expect(response.items).toHaveLength(2);
      expect(response.stats?.total_questions).toBe(50);
    });

    it('should handle extraction errors', () => {
      const response: ExtractResponse = {
        success: false,
        items: [],
        total_count: 0,
        error: 'No content found for the specified filters',
      };

      expect(response.success).toBe(false);
      expect(response.error).toBeDefined();
    });
  });

  describe('CreateBatchJobData', () => {
    it('should support Knowledge Bowl options', () => {
      const data: CreateBatchJobData = {
        name: 'KB Physics Batch',
        source_type: 'knowledge-bowl',
        profile_id: 'profile-1',
        include_questions: true,
        include_answers: true,
        include_hints: true,
        include_explanations: false,
        domains: ['Physics', 'Chemistry'],
        difficulties: [1, 2, 3],
      };

      expect(data.source_type).toBe('knowledge-bowl');
      expect(data.include_questions).toBe(true);
      expect(data.domains).toContain('Physics');
    });

    it('should support custom items', () => {
      const data: CreateBatchJobData = {
        name: 'Custom Batch',
        source_type: 'custom',
        items: [
          { text: 'Custom text 1', source_ref: 'custom:1' },
          { text: 'Custom text 2', source_ref: 'custom:2' },
        ],
      };

      expect(data.source_type).toBe('custom');
      expect(data.items).toHaveLength(2);
    });

    it('should support output configuration', () => {
      const data: CreateBatchJobData = {
        name: 'Test Job',
        source_type: 'knowledge-bowl',
        output_format: 'mp3',
        normalize_volume: true,
      };

      expect(data.output_format).toBe('mp3');
      expect(data.normalize_volume).toBe(true);
    });
  });
});
