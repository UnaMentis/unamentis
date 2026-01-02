import { NextResponse } from 'next/server';
import type { CurriculumDetail, CurriculumTopic } from '@/types';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8766';

interface RouteContext {
  params: Promise<{ curriculumId: string }>;
}

// UMCF types for transformation
interface UMCFId {
  catalog?: string;
  value: string;
}

interface UMCFVersion {
  number: string;
  date?: string;
  changelog?: string;
}

interface UMCFLifecycle {
  status?: 'draft' | 'review' | 'final' | 'deprecated';
}

interface UMCFEducational {
  typicalAgeRange?: string;
  difficulty?: string;
  typicalLearningTime?: string;
}

interface UMCFMetadata {
  keywords?: string[];
}

interface UMCFTopic {
  id: UMCFId;
  title: string;
  type: string;
  description?: string;
  transcript?: unknown;
  examples?: unknown[];
  assessments?: unknown[];
  misconceptions?: unknown[];
  media?: {
    embedded?: unknown[];
    reference?: unknown[];
  };
  timeEstimates?: unknown;
  prerequisites?: unknown[];
}

interface UMCFContent {
  id: UMCFId;
  title: string;
  type: string;
  children?: UMCFTopic[];
}

interface UMCFDocument {
  umcf: string;
  id: UMCFId;
  title: string;
  description?: string;
  version?: UMCFVersion;
  lifecycle?: UMCFLifecycle;
  metadata?: UMCFMetadata;
  educational?: UMCFEducational;
  content?: UMCFContent[];
  sourceProvenance?: unknown;
  [key: string]: unknown;
}

/**
 * Transform UMCF document format to CurriculumDetail format expected by frontend
 */
function transformUMCFToCurriculumDetail(umcf: UMCFDocument): CurriculumDetail {
  // Extract topics from content structure
  // UMCF has content -> [curriculum node] -> children -> [topics]
  const contentNode = umcf.content?.[0];
  const rawTopics = contentNode?.children || [];

  // Transform topics to expected format
  const topics: CurriculumTopic[] = rawTopics.map((topic, index) => ({
    id: topic.id,
    title: topic.title,
    type: 'topic' as const,
    orderIndex: index,
    description: topic.description,
    transcript: topic.transcript as CurriculumTopic['transcript'],
    examples: topic.examples as CurriculumTopic['examples'],
    assessments: topic.assessments as CurriculumTopic['assessments'],
    misconceptions: topic.misconceptions as CurriculumTopic['misconceptions'],
    media: topic.media as CurriculumTopic['media'],
    timeEstimates: topic.timeEstimates as CurriculumTopic['timeEstimates'],
    prerequisites: topic.prerequisites as CurriculumTopic['prerequisites'],
  }));

  // Count visual assets
  let visualAssetCount = 0;
  for (const topic of rawTopics) {
    if (topic.media?.embedded) {
      visualAssetCount += topic.media.embedded.length;
    }
    if (topic.media?.reference) {
      visualAssetCount += topic.media.reference.length;
    }
  }

  return {
    // CurriculumSummary fields
    id: umcf.id?.value || 'unknown',
    title: umcf.title,
    description: umcf.description || '',
    version: umcf.version?.number,
    status: umcf.lifecycle?.status,
    topicCount: topics.length,
    totalDuration: umcf.educational?.typicalLearningTime,
    difficulty: umcf.educational?.difficulty,
    keywords: umcf.metadata?.keywords,
    hasVisualAssets: visualAssetCount > 0,
    visualAssetCount,

    // CurriculumDetail additional fields
    document: umcf as CurriculumDetail['document'],
    topics,
  };
}

/**
 * GET /api/curricula/[curriculumId]/full
 * Get full curriculum with all topics and content
 */
export async function GET(request: Request, context: RouteContext) {
  try {
    const { curriculumId } = await context.params;
    const response = await fetch(`${BACKEND_URL}/api/curricula/${curriculumId}/full`, {
      headers: {
        'Content-Type': 'application/json',
      },
      next: { revalidate: 0 },
    });

    if (!response.ok) {
      if (response.status === 404) {
        return NextResponse.json(
          { error: 'Curriculum not found' },
          { status: 404 }
        );
      }
      throw new Error(`Backend returned ${response.status}`);
    }

    const umcfData: UMCFDocument = await response.json();
    const curriculum = transformUMCFToCurriculumDetail(umcfData);

    return NextResponse.json({ curriculum });
  } catch (error) {
    console.error('Error fetching full curriculum:', error);
    return NextResponse.json(
      { error: 'Failed to fetch curriculum details' },
      { status: 503 }
    );
  }
}
