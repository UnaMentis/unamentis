# Mock Test Violations Inventory

**STATUS: CRITICAL - IMMEDIATE REMEDIATION REQUIRED**

These tests are lies. They test mock behavior, not real code. They provide false confidence and must be eliminated.

---

## Violation Summary

| Component | Files with Mocks | Mock Classes | Status |
|-----------|------------------|--------------|--------|
| **Python Management** | 38 | 91 | CRITICAL |
| **Python Importers** | 3 | Unknown | HIGH |
| **TypeScript Web** | 6 | 1 pattern | HIGH |
| **Swift iOS** | 0 | 0 | COMPLIANT |

**Total Mock Classes Identified: 91+**

---

## Python Management API Violations (38 files)

### Files Using MagicMock/AsyncMock

```
test_audio_ws.py
test_auth_api.py
test_auth_middleware.py
test_bonjour_advertiser.py
test_deployment_api.py
test_diagnostic_logging.py
test_fov_context_api.py
test_fov_session.py
test_idle_manager.py
test_import_api.py
test_kb_audio.py
test_kb_packs_api.py
test_kb_questions_repository.py
test_latency_harness_api.py
test_latency_harness_api_extended.py
test_lists_api.py
test_media_api.py
test_modules_api.py
test_plugin_api.py
test_plugin_api_extended.py
test_rate_limiter.py
test_reprocess_api.py
test_resource_monitor.py
test_server.py
test_server_extended.py
test_session_cache_integration.py
test_tts_api.py
test_tts_api_extended.py
test_tts_api_kb.py
test_tts_cache.py
test_tts_prefetcher.py
test_tts_pregen_api.py
test_tts_pregen_comparison_manager.py
test_tts_pregen_job_manager.py
test_tts_pregen_orchestrator.py
test_tts_pregen_profile_manager.py
test_tts_pregen_repository.py
test_tts_resource_pool.py
```

### Mock Classes by Category

#### Database Mocks (CRITICAL - use in-memory SQLite)
- `MockConnection`
- `MockConnectionContext`
- `MockConnectionContextManager`
- `MockDBPool`
- `MockPool`
- `MockPoolContextManager`
- `MockRow`
- `MockRecord`

#### TTS System Mocks (CRITICAL - use real with tmp_path)
- `MockTTSCache`
- `MockTTSCacheEntry`
- `MockTTSCacheStats`
- `MockResourcePool`
- `MockPrefetcher`
- `MockAsyncLock`

#### Session Mocks (HIGH - use real implementations)
- `MockSessionManager`
- `MockSessionCache`
- `MockSession`
- `MockUserSession`
- `MockSessionState`

#### State/Orchestration Mocks (HIGH - use real implementations)
- `MockState`
- `MockOrchestrator`
- `MockOrchestratorRaisesError`
- `MockMassOrchestrator`
- `MockStorage`

#### FOV Context Mocks (HIGH - use real implementations)
- `MockContext`
- `MockContextManager`
- `MockConfidenceAnalysis`
- `MockEpisodicBuffer`
- `MockImmediateBuffer`
- `MockSemanticBuffer`
- `MockWorkingBuffer`
- `MockTurn`
- `MockLearnerSignals`

#### Import System Mocks (MEDIUM - use real with fixtures)
- `MockImportProgress`
- `MockImportProgressComplete`
- `MockSourceHandler`
- `MockSourceHandlerEmptyCourses`
- `MockSourceHandlerRaisesCatalogError`
- `MockSource`
- `MockSourceInfo`
- `MockCourse`
- `MockCourseDetail`

#### Plugin System Mocks (MEDIUM)
- `MockPluginDiscovery`
- `MockPluginInfo`
- `MockPluginState`
- `MockHandlerNoConfig`
- `MockHandlerWithConfig`
- `MockHandlerWithConfigError`

#### Latency Harness Mocks (MEDIUM)
- `MockTestRun`
- `MockTestResult`
- `MockTestScenario`
- `MockTestSuiteDefinition`
- `MockRunStatus`
- `MockSummaryStatistics`
- `MockBaselineMetrics`
- `MockRegressionInfo`
- `MockPerformanceBaseline`
- `MockNetworkProfile`
- `MockParameterSpace`
- `MockBudgetConfig`

#### Diagram/Formula Mocks (LOW)
- `MockDiagramGenerator`
- `MockDiagramResult`
- `MockFormulaGenerator`
- `MockFormulaResult`
- `MockMapGenerator`
- `MockMapResult`

#### WebSocket/Client Mocks (MEDIUM)
- `MockWebSocketResponse`
- `MockConnectedClient`
- `MockClientCapabilities`
- `MockClientStatus`
- `MockClientType`
- `MockMultipartReader`
- `MockMultipartPart`

#### Enum Mocks (LOW - may be acceptable for test data)
- `MockTier`
- `MockConfidenceMarker`
- `MockMessageRole`
- `MockPriority`
- `MockScope`
- `MockTrend`
- `MockPlaybackState`
- `MockVoiceConfig`
- `MockDiagramFormat`
- `MockDiagramRenderMethod`
- `MockFormulaRenderMethod`
- `MockMapRenderMethod`
- `MockMapStyle`
- `MockPosition`

#### Reprocess Mocks (HIGH)
- `MockAnalysis`
- `MockAnalysisReport`
- `MockReprocessProgress`
- `MockPreview`
- `MockExpansionRecommendation`
- `MockLicenseResult`

#### KB Audio Mocks (HIGH)
- `MockKBAudioManager`

---

## TypeScript Web Violations (6 files)

### Pattern
All 6 files use: `vi.mock('@/lib/api-client', () => ({ ... }))`

### Files
```
batch-job-api.test.ts
batch-job-items-list.test.tsx
batch-job-create-form.test.tsx
batch-job-panel.test.tsx
(+ 2 others)
```

### Remediation
Replace `vi.mock` with MSW (Mock Service Worker) to test real api-client code against intercepted network requests.

---

## Remediation Approach

### For Database Mocks
```python
# WRONG
class MockConnection:
    async def fetch(self, query, *args):
        return self.rows

# RIGHT
@pytest.fixture
async def db(tmp_path):
    db_path = tmp_path / "test.db"
    async with aiosqlite.connect(db_path) as conn:
        await conn.execute("CREATE TABLE ...")
        yield conn
```

### For TTS Cache Mocks
```python
# WRONG
@pytest.fixture
def cache():
    return MockTTSCache()

# RIGHT
@pytest.fixture
async def cache(tmp_path):
    cache = TTSCache(cache_dir=tmp_path / "cache")
    await cache.initialize()
    yield cache
    await cache.close()
```

### For Session Mocks
```python
# WRONG
@pytest.fixture
def session_manager():
    return MockSessionManager()

# RIGHT
@pytest.fixture
async def session_manager(db):
    manager = SessionManager(db)
    await manager.initialize()
    yield manager
```

### For TypeScript API Client
```typescript
// WRONG
vi.mock('@/lib/api-client', () => ({
  getBatchJobs: vi.fn(),
}));

// RIGHT - Use MSW
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';

const server = setupServer(
  http.get('/api/tts-pregen/jobs', () => {
    return HttpResponse.json({ jobs: [...] });
  })
);

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

---

## Priority Order for Remediation

### Phase 1: Database & Core (Week 1-2)
1. Remove all MockConnection/MockDBPool - use aiosqlite :memory:
2. Remove MockTTSCache/MockResourcePool - use real with tmp_path
3. Remove MockSessionManager/MockSessionCache - use real implementations

### Phase 2: State & Orchestration (Week 3-4)
1. Remove MockState/MockOrchestrator
2. Remove FOV Context mocks
3. Remove Import system mocks

### Phase 3: Web & Remaining (Week 5-6)
1. Replace TypeScript vi.mock with MSW
2. Remove plugin system mocks
3. Remove latency harness mocks

### Phase 4: Cleanup (Week 7-8)
1. Remove remaining mock classes
2. Update test documentation
3. Add CI checks to prevent new mocks

---

## CI Prevention

Add to CI pipeline:
```bash
# Fail if new mock classes are added
if grep -r "class Mock" tests/*.py | grep -v "# ALLOWED:"; then
    echo "ERROR: New mock class detected. Mocks are not allowed."
    exit 1
fi
```

---

## Files to Delete vs Rewrite

### Rewrite (tests have value, just wrong approach)
- test_tts_api.py
- test_server.py
- test_auth_api.py
- test_fov_context_api.py
- Most API tests

### Potentially Delete (may be testing nothing real)
- Tests that ONLY test mock behavior
- Tests where removing mocks leaves nothing to test

---

**This is technical debt that undermines the entire test suite. Every mock is a lie about code behavior.**
