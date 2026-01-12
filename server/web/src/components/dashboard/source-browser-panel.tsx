'use client';

import { useState, useEffect, useCallback } from 'react';
import { useQueryState, parseAsString, parseAsInteger, parseAsStringLiteral } from 'nuqs';
import {
  Download,
  ExternalLink,
  Search,
  BookOpen,
  FileText,
  CheckCircle,
  AlertTriangle,
  Clock,
  ChevronRight,
  ChevronLeft,
  RefreshCw,
  Play,
  XCircle,
  Loader2,
  Scale,
  GraduationCap,
  Video,
  FileQuestion,
  Users,
  Building2,
  Tag,
  Filter,
  List,
} from 'lucide-react';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/components/ui/toast';
import { cn } from '@/lib/utils';
import { useMainScrollRestoration } from '@/hooks/useScrollRestoration';
import { AddToListModal } from './add-to-list-modal';

// Types matching the actual backend API responses
interface License {
  type: string;
  name: string;
  url?: string;
  attributionRequired: boolean;
  attributionFormat?: string;
  permissions: string[];
  conditions: string[];
  restrictions: string[];
  holder?: {
    name: string;
    url?: string;
  };
}

interface CurriculumSource {
  id: string;
  name: string;
  description: string;
  logoUrl?: string;
  license: License;
  courseCount: string;
  features: string[];
  status: string;
  baseUrl: string;
}

interface CourseFeature {
  type: string;
  count: number | null;
  available: boolean;
}

interface Course {
  id: string;
  sourceId: string;
  title: string;
  instructors: string[];
  description: string;
  level: string;
  department: string;
  semester: string;
  features: CourseFeature[];
  license: License;
  thumbnailUrl?: string;
  keywords: string[];
}

interface ImportJob {
  jobId: string;
  status: string;
  sourceId: string;
  courseId: string;
  courseName: string;
  currentStage: string;
  stageProgress: number;
  overallProgress: number;
  error?: string;
}

interface CourseImportStatus {
  imported: boolean;
  curriculumId?: string;
  importedAt?: string;
  lists?: { id: string; name: string }[];
}

// Valid view modes for URL state
const VIEW_MODES = ['sources', 'catalog', 'detail'] as const;
type ViewMode = (typeof VIEW_MODES)[number];

// Use relative URLs to go through Next.js API proxy routes
const BACKEND_URL = '';

/**
 * Source Browser Panel
 *
 * First-class browsing experience for curriculum sources like MIT OCW.
 * Allows browsing courses, viewing details, and importing into UMCF format.
 */
export function SourceBrowserPanel() {
  // URL-synced view state using nuqs
  const [viewMode, setViewMode] = useQueryState(
    'view',
    parseAsStringLiteral(VIEW_MODES).withDefault('sources')
  );
  const [selectedSourceId, setSelectedSourceId] = useQueryState('source', parseAsString);
  const [selectedCourseId, setSelectedCourseId] = useQueryState('course', parseAsString);
  const [currentPage, setCurrentPage] = useQueryState('page', parseAsInteger.withDefault(1));
  const [searchQuery, setSearchQuery] = useQueryState('q', parseAsString.withDefault(''));
  const [selectedSubject, setSelectedSubject] = useQueryState(
    'subject',
    parseAsString.withDefault('')
  );
  const [selectedLevel, setSelectedLevel] = useQueryState('level', parseAsString.withDefault(''));
  const [sortBy, setSortBy] = useQueryState('sort', parseAsString.withDefault('relevance'));
  const [sortOrder, setSortOrder] = useQueryState('order', parseAsString.withDefault('asc'));

  // Local state (not URL-synced)
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Data state
  const [sources, setSources] = useState<CurriculumSource[]>([]);
  const [selectedSource, setSelectedSource] = useState<CurriculumSource | null>(null);
  const [courses, setCourses] = useState<Course[]>([]);
  const [selectedCourse, setSelectedCourse] = useState<Course | null>(null);
  const [importJobs, setImportJobs] = useState<ImportJob[]>([]);

  // Import status for courses (keyed by course ID)
  const [courseImportStatus, setCourseImportStatus] = useState<Record<string, CourseImportStatus>>({});

  // Multi-select state
  const [selectedCourseIds, setSelectedCourseIds] = useState<Set<string>>(new Set());
  const [lastSelectedIndex, setLastSelectedIndex] = useState<number | null>(null);
  const [showAddToListModal, setShowAddToListModal] = useState(false);

  // Filter state (available options from API)
  const [availableFilters, setAvailableFilters] = useState<{
    subjects: string[];
    levels: string[];
    features: string[];
  }>({ subjects: [], levels: [], features: [] });

  // Pagination totals
  const [totalPages, setTotalPages] = useState(1);
  const [totalCourses, setTotalCourses] = useState(0);

  // Import state
  const [importing, setImporting] = useState(false);
  const [importOptions, setImportOptions] = useState({
    includeTranscripts: true,
    includeLectureNotes: true,
    includeAssignments: true,
    includeExams: true,
    includeVideos: false,
    generateObjectives: true,
    createCheckpoints: true,
    generateSpokenText: true,
    buildKnowledgeGraph: true,
  });

  // Toast notifications
  const { showToast } = useToast();

  // Scroll restoration
  useMainScrollRestoration('source-browser-panel');

  // Fetch sources on mount and restore state from URL
  useEffect(() => {
    fetchSources();
    fetchImportJobs();

    // Poll for import job updates
    const interval = setInterval(fetchImportJobs, 5000);
    return () => clearInterval(interval);
  }, []);

  // Restore selected source from URL when sources are loaded
  useEffect(() => {
    if (sources.length > 0 && selectedSourceId) {
      const source = sources.find((s) => s.id === selectedSourceId);
      if (source) {
        setSelectedSource(source);
        // If we have a source ID in URL, fetch the catalog
        if (viewMode === 'catalog' || viewMode === 'detail') {
          fetchCatalog(
            source.id,
            currentPage,
            searchQuery || undefined,
            selectedSubject || undefined,
            selectedLevel || undefined,
            sortBy || undefined,
            sortOrder || undefined
          );
        }
      }
    }
  }, [sources, selectedSourceId]);

  // Restore selected course from URL when courses are loaded
  useEffect(() => {
    if (courses.length > 0 && selectedCourseId && selectedSource) {
      const course = courses.find((c) => c.id === selectedCourseId);
      if (course) {
        setSelectedCourse(course);
        if (viewMode === 'detail') {
          fetchCourseDetail(selectedSource.id, course.id);
        }
      }
    }
  }, [courses, selectedCourseId, selectedSource, viewMode]);

  const fetchSources = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch(`${BACKEND_URL}/api/import/sources`);
      const data = await response.json();
      if (data.success) {
        setSources(data.sources);
      } else {
        setError(data.error || 'Failed to fetch sources');
      }
    } catch (err) {
      setError('Failed to connect to server');
      console.error('Error fetching sources:', err);
    } finally {
      setLoading(false);
    }
  };

  const fetchCatalog = useCallback(
    async (
      sourceId: string,
      page: number = 1,
      search?: string,
      subject?: string,
      level?: string,
      sort?: string,
      order?: string
    ) => {
      setLoading(true);
      setError(null);
      try {
        const params = new URLSearchParams();
        params.set('page', String(page));
        params.set('pageSize', '12');
        if (search) params.set('search', search);
        if (subject) params.set('subject', subject);
        if (level) params.set('level', level);
        if (sort) params.set('sortBy', sort);
        if (order) params.set('sortOrder', order);

        const response = await fetch(
          `${BACKEND_URL}/api/import/sources/${sourceId}/courses?${params}`
        );
        const data = await response.json();

        if (data.success) {
          setCourses(data.courses);
          setCurrentPage(data.pagination.page);
          setTotalPages(data.pagination.totalPages);
          setTotalCourses(data.pagination.total);
          if (data.filters) {
            setAvailableFilters(data.filters);
          }
        } else {
          setError(data.error || 'Failed to fetch courses');
        }
      } catch (err) {
        setError('Failed to connect to server');
        console.error('Error fetching catalog:', err);
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const fetchCourseDetail = async (sourceId: string, courseId: string) => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch(
        `${BACKEND_URL}/api/import/sources/${sourceId}/courses/${courseId}`
      );
      const data = await response.json();

      if (data.success) {
        setSelectedCourse(data.course);
      } else {
        setError(data.error || 'Failed to fetch course details');
      }
    } catch (err) {
      setError('Failed to connect to server');
      console.error('Error fetching course:', err);
    } finally {
      setLoading(false);
    }
  };

  const fetchImportJobs = async () => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/import/jobs`);
      const data = await response.json();
      if (data.success) {
        setImportJobs(data.jobs || []);
      }
    } catch (err) {
      console.error('Failed to fetch import jobs:', err);
    }
  };

  // Fetch import status for a list of courses
  const fetchImportStatus = useCallback(async (sourceId: string, courseIds: string[]) => {
    if (courseIds.length === 0) return;

    try {
      // Fetch both import status and list memberships in parallel
      const [statusResponse, membershipsResponse] = await Promise.all([
        fetch(`${BACKEND_URL}/api/import/status?source_id=${sourceId}&course_ids=${courseIds.join(',')}`),
        fetch(`${BACKEND_URL}/api/lists/memberships?source_id=${sourceId}&course_ids=${courseIds.join(',')}`),
      ]);

      const statusData = await statusResponse.json();
      const membershipsData = await membershipsResponse.json();

      // Merge import status with list memberships
      const mergedStatus: Record<string, CourseImportStatus> = {};
      const importedCourses = statusData.success ? statusData.courses || {} : {};
      const memberships = membershipsData.memberships || {};

      // Initialize with import status
      for (const courseId of courseIds) {
        mergedStatus[courseId] = {
          imported: importedCourses[courseId]?.imported || false,
          curriculumId: importedCourses[courseId]?.curriculumId,
          importedAt: importedCourses[courseId]?.importedAt,
          lists: memberships[courseId] || [],
        };
      }

      setCourseImportStatus(mergedStatus);
    } catch (err) {
      console.error('Failed to fetch import status:', err);
    }
  }, []);

  // Fetch import status when courses change
  useEffect(() => {
    if (courses.length > 0 && selectedSource) {
      const courseIds = courses.map((c) => c.id);
      fetchImportStatus(selectedSource.id, courseIds);
    }
  }, [courses, selectedSource, fetchImportStatus]);

  const handleSourceSelect = (source: CurriculumSource) => {
    setSelectedSource(source);
    setSelectedSourceId(source.id);
    setViewMode('catalog');
    setSearchQuery('');
    setSelectedSubject('');
    setSelectedLevel('');
    setCurrentPage(1);
    setSelectedCourseId(null);
    // Reset sort to default when entering a new source
    setSortBy('relevance');
    setSortOrder('asc');
    // Clear any selections
    setSelectedCourseIds(new Set());
    setLastSelectedIndex(null);
    fetchCatalog(source.id, 1, undefined, undefined, undefined, 'relevance', 'asc');
  };

  const handleCourseSelect = (course: Course) => {
    setSelectedCourse(course);
    setSelectedCourseId(course.id);
    setViewMode('detail');
    if (selectedSource) {
      fetchCourseDetail(selectedSource.id, course.id);
    }
  };

  const handleSearch = () => {
    if (!selectedSource) return;
    setCurrentPage(1);
    fetchCatalog(
      selectedSource.id,
      1,
      searchQuery || undefined,
      selectedSubject || undefined,
      selectedLevel || undefined,
      sortBy || undefined,
      sortOrder || undefined
    );
  };

  const handleFilterChange = (type: 'subject' | 'level', value: string) => {
    if (type === 'subject') {
      setSelectedSubject(value);
    } else {
      setSelectedLevel(value);
    }
    if (selectedSource) {
      setCurrentPage(1);
      fetchCatalog(
        selectedSource.id,
        1,
        searchQuery || undefined,
        type === 'subject' ? value : selectedSubject || undefined,
        type === 'level' ? value : selectedLevel || undefined,
        sortBy || undefined,
        sortOrder || undefined
      );
    }
  };

  const handleSortChange = (newSortBy: string, newSortOrder: string) => {
    setSortBy(newSortBy);
    setSortOrder(newSortOrder);
    if (selectedSource) {
      setCurrentPage(1);
      fetchCatalog(
        selectedSource.id,
        1,
        searchQuery || undefined,
        selectedSubject || undefined,
        selectedLevel || undefined,
        newSortBy,
        newSortOrder
      );
    }
  };

  const handlePageChange = (newPage: number) => {
    if (!selectedSource) return;
    setCurrentPage(newPage);
    fetchCatalog(
      selectedSource.id,
      newPage,
      searchQuery || undefined,
      selectedSubject || undefined,
      selectedLevel || undefined,
      sortBy || undefined,
      sortOrder || undefined
    );
  };

  // Multi-select handlers
  const handleSelectionToggle = (courseId: string, index: number, shiftKey: boolean) => {
    setSelectedCourseIds((prev) => {
      const newSet = new Set(prev);

      if (shiftKey && lastSelectedIndex !== null) {
        // Range selection
        const start = Math.min(lastSelectedIndex, index);
        const end = Math.max(lastSelectedIndex, index);
        for (let i = start; i <= end; i++) {
          newSet.add(courses[i].id);
        }
      } else {
        // Toggle single item
        if (newSet.has(courseId)) {
          newSet.delete(courseId);
        } else {
          newSet.add(courseId);
        }
      }

      setLastSelectedIndex(index);
      return newSet;
    });
  };

  const clearSelection = () => {
    setSelectedCourseIds(new Set());
    setLastSelectedIndex(null);
  };

  const handleBulkImport = async () => {
    if (!selectedSource || selectedCourseIds.size === 0) return;

    const courseIdsToImport = Array.from(selectedCourseIds);
    let successCount = 0;
    let failCount = 0;

    for (const courseId of courseIdsToImport) {
      try {
        const response = await fetch(`${BACKEND_URL}/api/import/jobs`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            sourceId: selectedSource.id,
            courseId,
            outputName: courseId.replace(/[^a-z0-9]/gi, '-').toLowerCase(),
            ...importOptions,
          }),
        });

        const data = await response.json();
        if (data.success) {
          successCount++;
        } else {
          failCount++;
        }
      } catch {
        failCount++;
      }
    }

    // Show result toast
    if (failCount === 0) {
      showToast({
        type: 'success',
        title: 'Bulk Import Started',
        message: `Started importing ${successCount} course${successCount > 1 ? 's' : ''}.`,
      });
    } else {
      showToast({
        type: 'warning',
        title: 'Bulk Import Partially Started',
        message: `Started ${successCount}, failed ${failCount}.`,
      });
    }

    clearSelection();
    fetchImportJobs();
  };

  const handleStartImport = async () => {
    if (!selectedSource || !selectedCourse) return;

    setImporting(true);
    setError(null);

    try {
      const response = await fetch(`${BACKEND_URL}/api/import/jobs`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sourceId: selectedSource.id,
          courseId: selectedCourse.id,
          outputName: selectedCourse.id.replace(/[^a-z0-9]/gi, '-').toLowerCase(),
          ...importOptions,
        }),
      });

      const data = await response.json();

      if (data.success) {
        // Show success toast and refresh import jobs
        showToast({
          type: 'success',
          title: 'Import Started',
          message: `"${selectedCourse.title}" is being imported. Check the Sources tab for progress.`,
        });
        fetchImportJobs();
      } else {
        showToast({
          type: 'error',
          title: 'Import Failed',
          message: data.error || 'Failed to start import',
        });
      }
    } catch (err) {
      showToast({
        type: 'error',
        title: 'Import Failed',
        message: 'Failed to start import. Please try again.',
      });
      console.error('Error starting import:', err);
    } finally {
      setImporting(false);
    }
  };

  const handleCancelImport = async (jobId: string) => {
    try {
      await fetch(`${BACKEND_URL}/api/import/jobs/${jobId}`, {
        method: 'DELETE',
      });
      fetchImportJobs();
    } catch (err) {
      console.error('Failed to cancel import:', err);
    }
  };

  const handleBack = () => {
    if (viewMode === 'detail') {
      setViewMode('catalog');
      setSelectedCourse(null);
      setSelectedCourseId(null);
    } else if (viewMode === 'catalog') {
      setViewMode('sources');
      setSelectedSource(null);
      setSelectedSourceId(null);
      setSelectedCourseId(null);
      setCourses([]);
      setSearchQuery('');
      setSelectedSubject('');
      setSelectedLevel('');
      setCurrentPage(1);
    }
  };

  // Get feature icon
  const getFeatureIcon = (type: string) => {
    switch (type) {
      case 'video':
        return Video;
      case 'transcript':
        return FileText;
      case 'lecture_notes':
        return BookOpen;
      case 'assignments':
        return FileQuestion;
      case 'exams':
        return FileQuestion;
      default:
        return FileText;
    }
  };

  // Render sources list
  const renderSources = () => (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h3 className="text-xl font-semibold text-slate-100">Curriculum Sources</h3>
          <p className="text-sm text-slate-400 mt-1">
            Browse and import courses from educational content providers
          </p>
        </div>
        <button
          onClick={fetchSources}
          className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50 transition-all"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh
        </button>
      </div>

      {/* Active Import Jobs */}
      {importJobs.length > 0 && (
        <div className="space-y-3">
          <h4 className="text-sm font-medium text-slate-300 flex items-center gap-2">
            <Loader2 className="w-4 h-4 animate-spin text-orange-400" />
            Active Imports
          </h4>
          {importJobs.map((job) => (
            <Card key={job.jobId} className="bg-slate-800/50">
              <CardContent className="py-3 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  {job.status === 'completed' ? (
                    <CheckCircle className="w-5 h-5 text-emerald-400" />
                  ) : job.status === 'failed' ? (
                    <XCircle className="w-5 h-5 text-red-400" />
                  ) : (
                    <Loader2 className="w-5 h-5 text-orange-400 animate-spin" />
                  )}
                  <div>
                    <p className="font-medium text-slate-100">{job.courseName}</p>
                    <p className="text-sm text-slate-400">{job.currentStage}</p>
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <div className="w-32 h-2 bg-slate-700 rounded-full overflow-hidden">
                    <div
                      className={cn(
                        'h-full transition-all',
                        job.status === 'completed'
                          ? 'bg-emerald-500'
                          : job.status === 'failed'
                            ? 'bg-red-500'
                            : 'bg-orange-500'
                      )}
                      style={{ width: `${job.overallProgress}%` }}
                    />
                  </div>
                  <span className="text-sm text-slate-400 w-12">{job.overallProgress}%</span>
                  {job.status !== 'completed' && job.status !== 'failed' && (
                    <button
                      onClick={() => handleCancelImport(job.jobId)}
                      className="p-1 text-slate-400 hover:text-red-400"
                      title="Cancel import"
                    >
                      <XCircle className="w-4 h-4" />
                    </button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Source Cards */}
      <div className="grid gap-4">
        {sources.map((source) => (
          <Card
            key={source.id}
            className="cursor-pointer hover:border-orange-500/50 transition-all group"
            onClick={() => handleSourceSelect(source)}
          >
            <CardContent className="p-6">
              <div className="flex items-start gap-6">
                {/* Logo/Icon */}
                <div className="w-16 h-16 rounded-xl bg-gradient-to-br from-orange-500/20 to-amber-500/20 flex items-center justify-center flex-shrink-0">
                  <BookOpen className="w-8 h-8 text-orange-400" />
                </div>

                {/* Source Info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <h4 className="text-lg font-semibold text-slate-100 group-hover:text-orange-400 transition-colors">
                        {source.name}
                      </h4>
                      <p className="text-sm text-slate-400 mt-1">{source.description}</p>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <Badge variant="success" className="text-sm">
                        {source.courseCount} courses
                      </Badge>
                      <ChevronRight className="w-5 h-5 text-slate-500 group-hover:text-orange-400 transition-colors" />
                    </div>
                  </div>

                  {/* Features */}
                  <div className="flex flex-wrap gap-2 mt-4">
                    {source.features.map((feature) => {
                      const Icon = getFeatureIcon(feature);
                      return (
                        <div
                          key={feature}
                          className="flex items-center gap-1.5 px-2 py-1 bg-slate-800 rounded-md text-xs text-slate-300"
                        >
                          <Icon className="w-3 h-3" />
                          {feature.replace('_', ' ')}
                        </div>
                      );
                    })}
                  </div>

                  {/* License */}
                  {source.license && (
                    <div className="flex items-center gap-2 mt-4 text-xs text-slate-500">
                      <Scale className="w-3.5 h-3.5" />
                      <span>{source.license.name}</span>
                    </div>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {sources.length === 0 && !loading && (
        <Card>
          <CardContent className="py-12 text-center">
            <BookOpen className="w-12 h-12 text-slate-600 mx-auto mb-4" />
            <p className="text-slate-400">No curriculum sources available</p>
          </CardContent>
        </Card>
      )}
    </div>
  );

  // Render course catalog
  const renderCatalog = () => (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <button
          onClick={handleBack}
          className="p-2 text-slate-400 hover:text-slate-100 hover:bg-slate-800 rounded-lg transition-colors"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h3 className="text-xl font-semibold text-slate-100">{selectedSource?.name}</h3>
          <p className="text-sm text-slate-400">{totalCourses} courses available</p>
        </div>
        {selectedSource?.baseUrl && (
          <a
            href={selectedSource.baseUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-slate-700 text-slate-300 hover:text-slate-100 hover:bg-slate-700/50"
          >
            <ExternalLink className="w-4 h-4" />
            Visit Site
          </a>
        )}
      </div>

      {/* Search and Filters */}
      <div className="flex flex-wrap gap-3">
        <div className="flex-1 min-w-[200px] relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
            placeholder="Search courses..."
            className="w-full pl-10 pr-4 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 placeholder:text-slate-500 focus:outline-none focus:border-orange-500"
          />
        </div>

        {availableFilters.subjects.length > 0 && (
          <select
            value={selectedSubject}
            onChange={(e) => handleFilterChange('subject', e.target.value)}
            className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:border-orange-500"
          >
            <option value="">All Subjects</option>
            {availableFilters.subjects.map((subject) => (
              <option key={subject} value={subject}>
                {subject}
              </option>
            ))}
          </select>
        )}

        {availableFilters.levels.length > 0 && (
          <select
            value={selectedLevel}
            onChange={(e) => handleFilterChange('level', e.target.value)}
            className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:border-orange-500"
          >
            <option value="">All Levels</option>
            {availableFilters.levels.map((level) => (
              <option key={level} value={level}>
                {level}
              </option>
            ))}
          </select>
        )}

        {/* Sort dropdown */}
        <select
          value={`${sortBy}-${sortOrder}`}
          onChange={(e) => {
            const [newSort, newOrder] = e.target.value.split('-');
            handleSortChange(newSort, newOrder);
          }}
          className="px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-slate-100 focus:outline-none focus:border-orange-500"
        >
          <option value="relevance-asc">Sort: Relevance</option>
          <option value="title-asc">Sort: Title (A-Z)</option>
          <option value="title-desc">Sort: Title (Z-A)</option>
          <option value="level-asc">Sort: Level (Easy first)</option>
          <option value="level-desc">Sort: Level (Hard first)</option>
          <option value="date-desc">Sort: Recently Added</option>
        </select>

        <button
          onClick={handleSearch}
          className="px-4 py-2 bg-orange-500 hover:bg-orange-400 text-white font-medium rounded-lg transition-colors"
        >
          Search
        </button>
      </div>

      {/* Course Grid */}
      <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
        {courses.map((course, index) => (
          <Card
            key={course.id}
            className={cn(
              'cursor-pointer hover:border-orange-500/50 transition-all group relative',
              selectedCourseIds.has(course.id) && 'border-orange-500 bg-orange-500/5'
            )}
            onClick={() => handleCourseSelect(course)}
          >
            {/* Selection Checkbox */}
            <div
              className="absolute top-3 left-3 z-10"
              onClick={(e) => e.stopPropagation()}
            >
              <input
                type="checkbox"
                checked={selectedCourseIds.has(course.id)}
                onClick={(e) => {
                  e.stopPropagation();
                  handleSelectionToggle(course.id, index, e.shiftKey);
                }}
                onChange={() => {}} // Required for controlled checkbox
                className="w-4 h-4 rounded border-slate-600 bg-slate-800 text-orange-500 focus:ring-orange-500 focus:ring-offset-0 cursor-pointer"
              />
            </div>

            <CardContent className="p-5 pl-10">
              {/* Status Badges */}
              {(courseImportStatus[course.id]?.imported ||
                (courseImportStatus[course.id]?.lists?.length ?? 0) > 0) && (
                <div className="flex items-center gap-1.5 mb-2 flex-wrap">
                  {courseImportStatus[course.id]?.imported && (
                    <Badge variant="success" className="text-xs">
                      <CheckCircle className="w-3 h-3 mr-1" />
                      Imported
                    </Badge>
                  )}
                  {(courseImportStatus[course.id]?.lists?.length ?? 0) > 0 && (
                    <Badge variant="default" className="text-xs" title={
                      courseImportStatus[course.id]?.lists?.map((l) => l.name).join(', ')
                    }>
                      <List className="w-3 h-3 mr-1" />
                      {courseImportStatus[course.id]?.lists?.length}{' '}
                      {courseImportStatus[course.id]?.lists?.length === 1 ? 'list' : 'lists'}
                    </Badge>
                  )}
                </div>
              )}

              {/* Header */}
              <div className="flex items-start justify-between gap-2 mb-3">
                <h4 className="font-semibold text-slate-100 group-hover:text-orange-400 transition-colors line-clamp-2">
                  {course.title}
                </h4>
                <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-orange-400 flex-shrink-0 mt-1" />
              </div>

              {/* Instructors */}
              <div className="flex items-center gap-2 text-sm text-slate-400 mb-2">
                <Users className="w-3.5 h-3.5" />
                <span className="truncate">{course.instructors.join(', ')}</span>
              </div>

              {/* Department & Level */}
              <div className="flex items-center gap-3 text-xs text-slate-500 mb-3">
                <div className="flex items-center gap-1">
                  <Building2 className="w-3 h-3" />
                  <span>{course.department}</span>
                </div>
                <div className="flex items-center gap-1">
                  <GraduationCap className="w-3 h-3" />
                  <span className="capitalize">{course.level}</span>
                </div>
              </div>

              {/* Description */}
              <p className="text-sm text-slate-400 line-clamp-2 mb-4">{course.description}</p>

              {/* Features */}
              <div className="flex flex-wrap gap-1.5">
                {course.features
                  .filter((f) => f.available)
                  .map((feature) => {
                    const Icon = getFeatureIcon(feature.type);
                    return (
                      <div
                        key={feature.type}
                        className="flex items-center gap-1 px-2 py-0.5 bg-emerald-500/10 text-emerald-400 rounded text-xs"
                      >
                        <Icon className="w-3 h-3" />
                        {feature.count
                          ? `${feature.count} ${feature.type.replace('_', ' ')}`
                          : feature.type.replace('_', ' ')}
                      </div>
                    );
                  })}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex justify-center items-center gap-4">
          <button
            onClick={() => handlePageChange(currentPage - 1)}
            disabled={currentPage <= 1}
            className="p-2 text-slate-400 hover:text-slate-100 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <span className="text-sm text-slate-400">
            Page {currentPage} of {totalPages}
          </span>
          <button
            onClick={() => handlePageChange(currentPage + 1)}
            disabled={currentPage >= totalPages}
            className="p-2 text-slate-400 hover:text-slate-100 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>
      )}

      {courses.length === 0 && !loading && (
        <Card>
          <CardContent className="py-12 text-center">
            <Search className="w-12 h-12 text-slate-600 mx-auto mb-4" />
            <p className="text-slate-400">No courses found matching your criteria</p>
          </CardContent>
        </Card>
      )}

      {/* Floating Selection Action Bar */}
      {selectedCourseIds.size > 0 && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50">
          <div className="flex items-center gap-4 px-6 py-3 bg-slate-800 border border-slate-700 rounded-xl shadow-2xl">
            <span className="text-sm text-slate-300">
              {selectedCourseIds.size} course{selectedCourseIds.size > 1 ? 's' : ''} selected
            </span>
            <div className="w-px h-6 bg-slate-600" />
            <button
              onClick={handleBulkImport}
              className="flex items-center gap-2 px-4 py-2 bg-orange-500 hover:bg-orange-400 text-white font-medium rounded-lg transition-colors"
            >
              <Download className="w-4 h-4" />
              Import Selected
            </button>
            <button
              onClick={() => setShowAddToListModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white font-medium rounded-lg transition-colors"
            >
              <List className="w-4 h-4" />
              Add to List
            </button>
            <button
              onClick={clearSelection}
              className="p-2 text-slate-400 hover:text-slate-100 hover:bg-slate-700 rounded-lg transition-colors"
              title="Clear selection"
            >
              <XCircle className="w-5 h-5" />
            </button>
          </div>
        </div>
      )}

      {/* Add to List Modal */}
      <AddToListModal
        isOpen={showAddToListModal}
        onClose={() => setShowAddToListModal(false)}
        courses={courses
          .filter((c) => selectedCourseIds.has(c.id))
          .map((c) => ({
            sourceId: selectedSource?.id || '',
            courseId: c.id,
            courseTitle: c.title,
            courseThumbnailUrl: c.thumbnailUrl,
          }))}
        onSuccess={() => {
          clearSelection();
        }}
      />
    </div>
  );

  // Render course detail
  const renderDetail = () => {
    if (!selectedCourse) return null;

    return (
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-start gap-4">
          <button
            onClick={handleBack}
            className="p-2 text-slate-400 hover:text-slate-100 hover:bg-slate-800 rounded-lg transition-colors mt-1"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <h3 className="text-xl font-semibold text-slate-100">{selectedCourse.title}</h3>
              {courseImportStatus[selectedCourse.id]?.imported && (
                <Badge variant="success" className="text-xs">
                  <CheckCircle className="w-3 h-3 mr-1" />
                  Imported
                </Badge>
              )}
            </div>
            <div className="flex items-center gap-4 mt-2 text-sm text-slate-400">
              <div className="flex items-center gap-1.5">
                <Users className="w-4 h-4" />
                {selectedCourse.instructors.join(', ')}
              </div>
              <div className="flex items-center gap-1.5">
                <Building2 className="w-4 h-4" />
                {selectedCourse.department}
              </div>
              <div className="flex items-center gap-1.5">
                <Clock className="w-4 h-4" />
                {selectedCourse.semester}
              </div>
            </div>
          </div>
        </div>

        <div className="grid lg:grid-cols-3 gap-6">
          {/* Main Content */}
          <div className="lg:col-span-2 space-y-6">
            {/* Description */}
            <Card>
              <CardHeader>
                <CardTitle>
                  <FileText className="w-5 h-5" />
                  Course Overview
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-slate-300 leading-relaxed">{selectedCourse.description}</p>

                {/* Keywords */}
                {selectedCourse.keywords.length > 0 && (
                  <div className="flex flex-wrap gap-2 mt-4">
                    {selectedCourse.keywords.map((keyword) => (
                      <div
                        key={keyword}
                        className="flex items-center gap-1 px-2 py-1 bg-slate-800 rounded text-xs text-slate-400"
                      >
                        <Tag className="w-3 h-3" />
                        {keyword}
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Available Content */}
            <Card>
              <CardHeader>
                <CardTitle>
                  <BookOpen className="w-5 h-5" />
                  Available Content
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                  {selectedCourse.features.map((feature) => {
                    const Icon = getFeatureIcon(feature.type);
                    return (
                      <div
                        key={feature.type}
                        className={cn(
                          'flex items-center gap-3 p-3 rounded-lg',
                          feature.available
                            ? 'bg-emerald-500/10 text-emerald-400'
                            : 'bg-slate-800 text-slate-500'
                        )}
                      >
                        {feature.available ? (
                          <CheckCircle className="w-5 h-5" />
                        ) : (
                          <XCircle className="w-5 h-5" />
                        )}
                        <div>
                          <p className="text-sm font-medium capitalize">
                            {feature.type.replace('_', ' ')}
                          </p>
                          {feature.count && (
                            <p className="text-xs opacity-75">{feature.count} items</p>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>

            {/* License */}
            {selectedCourse.license && (
              <Card>
                <CardHeader>
                  <CardTitle>
                    <Scale className="w-5 h-5" />
                    License Information
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-3">
                    <div>
                      <p className="text-sm font-medium text-slate-100">
                        {selectedCourse.license.name}
                      </p>
                      <p className="text-xs text-slate-500 mt-1">{selectedCourse.license.type}</p>
                    </div>

                    {selectedCourse.license.attributionFormat && (
                      <div className="p-3 bg-slate-800/50 rounded-lg">
                        <p className="text-xs text-slate-400 mb-1">Required Attribution:</p>
                        <p className="text-sm text-slate-300 italic">
                          &quot;{selectedCourse.license.attributionFormat}&quot;
                        </p>
                      </div>
                    )}

                    {selectedCourse.license.conditions && (
                      <div className="flex flex-wrap gap-2">
                        {selectedCourse.license.conditions.map((condition) => (
                          <Badge key={condition} variant="warning" className="text-xs">
                            {condition}
                          </Badge>
                        ))}
                      </div>
                    )}

                    {selectedCourse.license.url && (
                      <a
                        href={selectedCourse.license.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1.5 text-sm text-orange-400 hover:text-orange-300"
                      >
                        View full license <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    )}
                  </div>
                </CardContent>
              </Card>
            )}
          </div>

          {/* Import Panel */}
          <div className="space-y-6">
            <Card className="sticky top-4">
              <CardHeader>
                <CardTitle>
                  <Download className="w-5 h-5" />
                  Import Course
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-5">
                {/* Content Options */}
                <div className="space-y-3">
                  <h5 className="text-sm font-medium text-slate-100">Include Content</h5>
                  <div className="space-y-2">
                    {selectedCourse.features
                      .filter((f) => f.available)
                      .map((feature) => (
                        <ImportOption
                          key={feature.type}
                          label={feature.type.replace('_', ' ')}
                          checked={
                            feature.type === 'transcript'
                              ? importOptions.includeTranscripts
                              : feature.type === 'lecture_notes'
                                ? importOptions.includeLectureNotes
                                : feature.type === 'assignments'
                                  ? importOptions.includeAssignments
                                  : feature.type === 'exams'
                                    ? importOptions.includeExams
                                    : feature.type === 'video'
                                      ? importOptions.includeVideos
                                      : true
                          }
                          onChange={(v) => {
                            const key =
                              feature.type === 'transcript'
                                ? 'includeTranscripts'
                                : feature.type === 'lecture_notes'
                                  ? 'includeLectureNotes'
                                  : feature.type === 'assignments'
                                    ? 'includeAssignments'
                                    : feature.type === 'exams'
                                      ? 'includeExams'
                                      : feature.type === 'video'
                                        ? 'includeVideos'
                                        : null;
                            if (key) {
                              setImportOptions((prev) => ({ ...prev, [key]: v }));
                            }
                          }}
                        />
                      ))}
                  </div>
                </div>

                {/* AI Enrichment Options */}
                <div className="space-y-3">
                  <h5 className="text-sm font-medium text-slate-100">AI Enrichment</h5>
                  <div className="space-y-2">
                    <ImportOption
                      label="Generate learning objectives"
                      checked={importOptions.generateObjectives}
                      onChange={(v) =>
                        setImportOptions((prev) => ({ ...prev, generateObjectives: v }))
                      }
                    />
                    <ImportOption
                      label="Create checkpoints"
                      checked={importOptions.createCheckpoints}
                      onChange={(v) =>
                        setImportOptions((prev) => ({ ...prev, createCheckpoints: v }))
                      }
                    />
                    <ImportOption
                      label="Generate spoken text"
                      checked={importOptions.generateSpokenText}
                      onChange={(v) =>
                        setImportOptions((prev) => ({ ...prev, generateSpokenText: v }))
                      }
                    />
                    <ImportOption
                      label="Build knowledge graph"
                      checked={importOptions.buildKnowledgeGraph}
                      onChange={(v) =>
                        setImportOptions((prev) => ({ ...prev, buildKnowledgeGraph: v }))
                      }
                    />
                  </div>
                </div>

                {error && (
                  <div className="p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-sm text-red-400">
                    {error}
                  </div>
                )}

                <button
                  onClick={handleStartImport}
                  disabled={importing}
                  className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-orange-500 hover:bg-orange-400 disabled:bg-orange-500/50 disabled:cursor-not-allowed text-white font-medium rounded-lg transition-colors"
                >
                  {importing ? (
                    <>
                      <Loader2 className="w-5 h-5 animate-spin" />
                      Starting Import...
                    </>
                  ) : (
                    <>
                      <Play className="w-5 h-5" />
                      Import to UMCF
                    </>
                  )}
                </button>

                <p className="text-xs text-slate-500 text-center">
                  Content will be processed through the AI enrichment pipeline
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold">Source Browser</h2>
      </div>

      {loading && courses.length === 0 && sources.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16">
          <Loader2 className="w-8 h-8 text-orange-400 animate-spin mb-4" />
          <p className="text-slate-400">Loading...</p>
        </div>
      ) : error && sources.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center">
            <AlertTriangle className="w-12 h-12 text-amber-400 mx-auto mb-4" />
            <p className="text-slate-300 mb-4">{error}</p>
            <button
              onClick={fetchSources}
              className="px-4 py-2 bg-orange-500 hover:bg-orange-400 text-white font-medium rounded-lg"
            >
              Try Again
            </button>
          </CardContent>
        </Card>
      ) : (
        <>
          {viewMode === 'sources' && renderSources()}
          {viewMode === 'catalog' && renderCatalog()}
          {viewMode === 'detail' && renderDetail()}
        </>
      )}
    </div>
  );
}

// Helper component for import options
function ImportOption({
  label,
  checked,
  onChange,
  disabled,
}: {
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <label
      className={cn(
        'flex items-center gap-3 cursor-pointer group',
        disabled && 'opacity-50 cursor-not-allowed'
      )}
    >
      <input
        type="checkbox"
        checked={checked && !disabled}
        onChange={(e) => !disabled && onChange(e.target.checked)}
        disabled={disabled}
        className="w-4 h-4 rounded border-slate-600 bg-slate-800 text-orange-500 focus:ring-orange-500 focus:ring-offset-slate-900"
      />
      <span className="text-sm text-slate-300 capitalize group-hover:text-slate-100">{label}</span>
    </label>
  );
}
