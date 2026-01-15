/**
 * UnaMentis Management Console - Frontend Application
 * A real-time dashboard for monitoring UnaMentis services
 */

// =============================================================================
// State Management
// =============================================================================

const state = {
    ws: null,
    wsReconnectAttempts: 0,
    maxReconnectAttempts: 10,
    reconnectDelay: 1000,

    logs: [],
    maxLogs: 1000,
    logsPaused: false,
    logFilter: {
        level: '',
        search: ''
    },

    metrics: [],
    clients: [],
    servers: [],
    models: [],
    services: [],

    stats: {
        uptime: 0,
        totalLogs: 0,
        totalMetrics: 0,
        errors: 0,
        warnings: 0
    },

    // Import job tracking
    importJobs: [],
    importJobsPollingInterval: null,

    charts: {},
    updateInterval: null
};

// =============================================================================
// WebSocket Connection
// =============================================================================

function connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws`;

    try {
        state.ws = new WebSocket(wsUrl);

        state.ws.onopen = () => {
            console.log('WebSocket connected');
            state.wsReconnectAttempts = 0;
            updateConnectionStatus('connected');
        };

        state.ws.onclose = () => {
            console.log('WebSocket disconnected');
            updateConnectionStatus('disconnected');
            scheduleReconnect();
        };

        state.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            updateConnectionStatus('error');
        };

        state.ws.onmessage = (event) => {
            try {
                const message = JSON.parse(event.data);
                handleWebSocketMessage(message);
            } catch (e) {
                console.error('Failed to parse WebSocket message:', e);
            }
        };
    } catch (e) {
        console.error('Failed to create WebSocket:', e);
        scheduleReconnect();
    }
}

function scheduleReconnect() {
    if (state.wsReconnectAttempts >= state.maxReconnectAttempts) {
        console.log('Max reconnect attempts reached');
        return;
    }

    const delay = state.reconnectDelay * Math.pow(2, state.wsReconnectAttempts);
    state.wsReconnectAttempts++;

    console.log(`Reconnecting in ${delay}ms (attempt ${state.wsReconnectAttempts})`);
    setTimeout(connectWebSocket, delay);
}

function updateConnectionStatus(status) {
    const dot = document.getElementById('connection-dot');
    const text = document.getElementById('connection-text');

    switch (status) {
        case 'connected':
            dot.className = 'w-2 h-2 rounded-full bg-accent-success status-dot';
            text.textContent = 'Connected';
            text.className = 'text-sm text-accent-success';
            break;
        case 'disconnected':
            dot.className = 'w-2 h-2 rounded-full bg-accent-warning';
            text.textContent = 'Reconnecting...';
            text.className = 'text-sm text-accent-warning';
            break;
        case 'error':
            dot.className = 'w-2 h-2 rounded-full bg-accent-danger';
            text.textContent = 'Error';
            text.className = 'text-sm text-accent-danger';
            break;
        default:
            dot.className = 'w-2 h-2 rounded-full bg-dark-500';
            text.textContent = 'Connecting...';
            text.className = 'text-sm text-dark-400';
    }
}

function handleWebSocketMessage(message) {
    switch (message.type) {
        case 'connected':
            console.log('Server confirmed connection');
            break;

        case 'log':
            handleNewLog(message.data);
            break;

        case 'metrics':
            handleNewMetrics(message.data);
            break;

        case 'client_update':
            handleClientUpdate(message.data);
            break;

        case 'server_added':
        case 'server_deleted':
            refreshServers();
            break;

        case 'service_update':
            handleServiceUpdate(message.data);
            break;

        case 'logs_cleared':
            state.logs = [];
            renderLogs();
            break;

        default:
            console.log('Unknown message type:', message.type);
    }
}

// =============================================================================
// API Functions
// =============================================================================

async function fetchAPI(endpoint, options = {}) {
    try {
        const response = await fetch(`/api${endpoint}`, {
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            ...options
        });

        if (!response.ok) {
            // Try to extract error message from response body
            let errorMessage = `HTTP ${response.status}`;
            try {
                const errorBody = await response.json();
                if (errorBody.error) {
                    errorMessage = errorBody.error;
                } else if (errorBody.message) {
                    errorMessage = errorBody.message;
                }
            } catch (parseErr) {
                // Response wasn't JSON, use status text
                errorMessage = `HTTP ${response.status}: ${response.statusText}`;
            }
            console.error(`API error (${options.method || 'GET'} ${endpoint}):`, errorMessage);
            throw new Error(errorMessage);
        }

        return await response.json();
    } catch (e) {
        console.error(`API error (${endpoint}):`, e);
        throw e;
    }
}

async function refreshStats() {
    try {
        const data = await fetchAPI('/stats');
        state.stats = data;
        updateStatsUI(data);
    } catch (e) {
        console.error('Failed to refresh stats:', e);
    }
}

async function refreshLogs() {
    try {
        const params = new URLSearchParams({ limit: '500' });
        if (state.logFilter.level) params.set('level', state.logFilter.level);
        if (state.logFilter.search) params.set('search', state.logFilter.search);

        const data = await fetchAPI(`/logs?${params}`);
        state.logs = data.logs;
        document.getElementById('logs-count').textContent = `(${data.total} entries)`;
        renderLogs();
    } catch (e) {
        console.error('Failed to refresh logs:', e);
    }
}

async function refreshMetrics() {
    try {
        const data = await fetchAPI('/metrics');
        state.metrics = data.metrics;
        updateMetricsUI(data);
        renderMetricsTable(data.metrics);
    } catch (e) {
        console.error('Failed to refresh metrics:', e);
    }
}

async function refreshClients() {
    try {
        const data = await fetchAPI('/clients');
        state.clients = data.clients;
        updateClientsUI(data);
    } catch (e) {
        console.error('Failed to refresh clients:', e);
    }
}

async function refreshServers() {
    try {
        const data = await fetchAPI('/servers');
        state.servers = data.servers;
        renderServers(data.servers);
        updateDashboardServers(data.servers);
    } catch (e) {
        console.error('Failed to refresh servers:', e);
    }
}

async function refreshModels() {
    try {
        const data = await fetchAPI('/models');
        state.models = data.models;
        renderModels(data);
    } catch (e) {
        console.error('Failed to refresh models:', e);
    }
}

async function refreshServices() {
    try {
        const data = await fetchAPI('/services');
        state.services = data.services;
        updateServicesUI(data);
        renderServices(data.services);
    } catch (e) {
        console.error('Failed to refresh services:', e);
    }
}

async function startService(serviceId) {
    try {
        const response = await fetchAPI(`/services/${serviceId}/start`, { method: 'POST' });
        console.log('Service start response:', response);
        await refreshServices();
    } catch (e) {
        console.error('Failed to start service:', e);
        alert('Failed to start service: ' + e.message);
    }
}

async function stopService(serviceId) {
    try {
        const response = await fetchAPI(`/services/${serviceId}/stop`, { method: 'POST' });
        console.log('Service stop response:', response);
        await refreshServices();
    } catch (e) {
        console.error('Failed to stop service:', e);
        alert('Failed to stop service: ' + e.message);
    }
}

async function restartService(serviceId) {
    try {
        const response = await fetchAPI(`/services/${serviceId}/restart`, { method: 'POST' });
        console.log('Service restart response:', response);
        await refreshServices();
    } catch (e) {
        console.error('Failed to restart service:', e);
        alert('Failed to restart service: ' + e.message);
    }
}

async function startAllServices() {
    try {
        const response = await fetchAPI('/services/start-all', { method: 'POST' });
        console.log('Start all response:', response);
        await refreshServices();
    } catch (e) {
        console.error('Failed to start all services:', e);
        alert('Failed to start all services: ' + e.message);
    }
}

async function stopAllServices() {
    if (!confirm('Are you sure you want to stop all services?')) return;
    try {
        const response = await fetchAPI('/services/stop-all', { method: 'POST' });
        console.log('Stop all response:', response);
        await refreshServices();
    } catch (e) {
        console.error('Failed to stop all services:', e);
        alert('Failed to stop all services: ' + e.message);
    }
}

async function clearLogs() {
    try {
        await fetchAPI('/logs', { method: 'DELETE' });
        state.logs = [];
        renderLogs();
    } catch (e) {
        console.error('Failed to clear logs:', e);
    }
}

// =============================================================================
// UI Update Functions
// =============================================================================

function updateStatsUI(stats) {
    // Update header
    document.getElementById('header-logs').textContent = formatNumber(stats.total_logs);
    document.getElementById('header-clients').textContent = stats.online_clients;

    // Update dashboard stats
    document.getElementById('stat-uptime').textContent = formatUptime(stats.uptime_seconds);
    document.getElementById('stat-healthy-servers').textContent = `${stats.healthy_servers}/${stats.total_servers}`;
    document.getElementById('stat-online-clients').textContent = stats.online_clients;
    document.getElementById('stat-total-logs').textContent = formatNumber(stats.total_logs);
    document.getElementById('stat-warnings').textContent = formatNumber(stats.warnings_count);
    document.getElementById('stat-errors').textContent = formatNumber(stats.errors_count);
}

function updateMetricsUI(data) {
    const agg = data.aggregates;

    document.getElementById('metric-e2e').textContent = `${agg.avg_e2e_latency.toFixed(0)} ms`;
    document.getElementById('metric-llm').textContent = `${agg.avg_llm_ttft.toFixed(0)} ms`;
    document.getElementById('metric-stt').textContent = `${agg.avg_stt_latency.toFixed(0)} ms`;
    document.getElementById('metric-tts').textContent = `${agg.avg_tts_ttfb.toFixed(0)} ms`;

    // Update sparklines
    updateSparklines(data.metrics);

    // Update charts
    updateLatencyDistributionChart(data.metrics);
    updateCostChart(data.metrics);
}

function updateClientsUI(data) {
    document.getElementById('clients-online').textContent = data.online;
    document.getElementById('clients-idle').textContent = data.idle;
    document.getElementById('clients-offline').textContent = data.offline;

    renderClients(data.clients);
    updateDashboardClients(data.clients);
}

// =============================================================================
// Render Functions
// =============================================================================

function renderLogs() {
    const container = document.getElementById('log-container');

    if (state.logs.length === 0) {
        container.innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                </svg>
                <p class="text-lg font-medium">Waiting for logs...</p>
                <p class="text-sm mt-1">Logs will appear here in real-time</p>
            </div>
        `;
        return;
    }

    const html = state.logs.map(log => `
        <div class="log-entry animate-fade-in">
            <span class="log-time">${formatLogTime(log.timestamp)}</span>
            <span class="log-level log-level-${log.level.toLowerCase()}">${log.level}</span>
            <span class="log-message">${escapeHtml(log.message)}</span>
            <span class="log-source">${log.client_name || log.label || ''}</span>
        </div>
    `).join('');

    container.innerHTML = html;
}

function handleNewLog(log) {
    if (state.logsPaused) return;

    // Add to logs array
    state.logs.unshift(log);
    if (state.logs.length > state.maxLogs) {
        state.logs.pop();
    }

    // Filter check
    if (state.logFilter.level && log.level !== state.logFilter.level) return;
    if (state.logFilter.search && !log.message.toLowerCase().includes(state.logFilter.search.toLowerCase())) return;

    // Update UI
    const container = document.getElementById('log-container');
    const isEmpty = container.querySelector('.text-center');

    if (isEmpty) {
        container.innerHTML = '';
    }

    const entry = document.createElement('div');
    entry.className = 'log-entry animate-fade-in';
    // Sanitize log level for use in class name (only allow alphanumeric)
    const safeLevel = (log.level || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    entry.innerHTML = `
        <span class="log-time">${escapeHtml(formatLogTime(log.timestamp))}</span>
        <span class="log-level log-level-${safeLevel}">${escapeHtml(log.level || '')}</span>
        <span class="log-message">${escapeHtml(log.message)}</span>
        <span class="log-source">${escapeHtml(log.client_name || log.label || '')}</span>
    `;

    container.insertBefore(entry, container.firstChild);

    // Limit DOM entries
    while (container.children.length > 200) {
        container.removeChild(container.lastChild);
    }

    // Update count
    const count = document.getElementById('logs-count');
    const currentCount = parseInt(count.textContent.match(/\d+/)?.[0] || '0');
    count.textContent = `(${currentCount + 1} entries)`;

    // Update recent activity on dashboard
    addRecentActivity(log);
}

function handleNewMetrics(metrics) {
    state.metrics.unshift(metrics);
    if (state.metrics.length > 100) {
        state.metrics.pop();
    }

    // Update charts if on metrics tab
    if (document.getElementById('tab-metrics').classList.contains('active')) {
        updateMetricsUI({ metrics: state.metrics, aggregates: calculateAggregates(state.metrics) });
    }
}

function handleClientUpdate(client) {
    const index = state.clients.findIndex(c => c.id === client.id);
    if (index >= 0) {
        state.clients[index] = client;
    } else {
        state.clients.push(client);
    }
    updateClientsUI({ clients: state.clients, online: 0, idle: 0, offline: 0 });
}

function handleServiceUpdate(service) {
    const index = state.services.findIndex(s => s.id === service.id);
    if (index >= 0) {
        state.services[index] = service;
    } else {
        state.services.push(service);
    }
    renderServices(state.services);
    updateServicesStatsUI();
}

function updateServicesUI(data) {
    document.getElementById('services-running').textContent = data.running;
    document.getElementById('services-stopped').textContent = data.stopped;
    document.getElementById('services-error').textContent = data.error;

    // Update memory stats if elements exist
    const memUsedEl = document.getElementById('services-memory-used');
    const memTotalEl = document.getElementById('services-memory-total');
    const memPercentEl = document.getElementById('services-memory-percent');

    if (memUsedEl && data.total_memory_mb !== undefined) {
        memUsedEl.textContent = formatBytes(data.total_memory_mb * 1024 * 1024);
    }
    if (data.system_memory) {
        if (memTotalEl) {
            memTotalEl.textContent = `${data.system_memory.total_gb} GB`;
        }
        if (memPercentEl) {
            memPercentEl.textContent = `${data.system_memory.percent_used}%`;
        }
        // Update progress bar if it exists
        const memBar = document.getElementById('services-memory-bar');
        if (memBar) {
            memBar.style.width = `${data.system_memory.percent_used}%`;
        }
    }
}

function updateServicesStatsUI() {
    const running = state.services.filter(s => s.status === 'running').length;
    const stopped = state.services.filter(s => s.status === 'stopped').length;
    const error = state.services.filter(s => s.status === 'error').length;
    document.getElementById('services-running').textContent = running;
    document.getElementById('services-stopped').textContent = stopped;
    document.getElementById('services-error').textContent = error;
}

function getServiceTypeStyles(type) {
    const styles = {
        'vibevoice': { bg: 'bg-accent-info/20', text: 'text-accent-info' },
        'nextjs': { bg: 'bg-accent-secondary/20', text: 'text-accent-secondary' },
        'default': { bg: 'bg-dark-600/20', text: 'text-dark-400' }
    };
    return styles[type] || styles.default;
}

function getServiceTypeIcon(type, size = 'w-5 h-5') {
    const styles = getServiceTypeStyles(type);
    const icons = {
        'vibevoice': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15.536a5 5 0 001.414 1.414m2.828-9.9a9 9 0 0112.728 0"></path></svg>`,
        'nextjs': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path></svg>`,
        'default': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"></path></svg>`
    };
    return icons[type] || icons.default;
}

function renderServices(services) {
    const container = document.getElementById('services-grid');
    if (!container) return;

    if (services.length === 0) {
        container.innerHTML = `
            <div class="col-span-full text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                </svg>
                <p class="text-lg font-medium">No managed services configured</p>
            </div>
        `;
        return;
    }

    const html = services.map(service => {
        const styles = getServiceTypeStyles(service.service_type);
        const statusColors = {
            'running': 'bg-accent-success/20 text-accent-success',
            'stopped': 'bg-dark-600/50 text-dark-400',
            'starting': 'bg-accent-warning/20 text-accent-warning',
            'error': 'bg-accent-danger/20 text-accent-danger'
        };
        const statusColor = statusColors[service.status] || statusColors.stopped;
        const isRunning = service.status === 'running';
        const isStarting = service.status === 'starting';

        return `
            <div class="card">
                <div class="p-4">
                    <div class="flex items-center justify-between mb-4">
                        <div class="flex items-center gap-3">
                            <div class="w-12 h-12 rounded-lg ${styles.bg} flex items-center justify-center">
                                ${getServiceTypeIcon(service.service_type, 'w-6 h-6')}
                            </div>
                            <div>
                                <div class="font-semibold text-dark-100">${escapeHtml(service.name)}</div>
                                <div class="text-xs text-dark-400">Port ${service.port}</div>
                            </div>
                        </div>
                        <div class="status-badge ${statusColor}">${service.status}</div>
                    </div>

                    <div class="space-y-2 text-sm mb-4">
                        ${service.pid ? `
                        <div class="flex justify-between">
                            <span class="text-dark-400">PID</span>
                            <span class="text-dark-200 font-mono">${service.pid}</span>
                        </div>
                        ` : ''}
                        ${service.memory && service.memory.rss_mb > 0 ? `
                        <div class="flex justify-between">
                            <span class="text-dark-400">Memory</span>
                            <span class="text-accent-warning font-semibold">${formatBytes(service.memory.rss_mb * 1024 * 1024)}</span>
                        </div>
                        ` : ''}
                        ${service.started_at ? `
                        <div class="flex justify-between">
                            <span class="text-dark-400">Uptime</span>
                            <span class="text-dark-200">${formatUptime(Date.now()/1000 - service.started_at)}</span>
                        </div>
                        ` : ''}
                        <div class="flex justify-between">
                            <span class="text-dark-400">Health URL</span>
                            <a href="${service.health_url}" target="_blank" class="text-accent-primary hover:underline text-xs font-mono truncate max-w-[200px]">${service.health_url}</a>
                        </div>
                        ${service.error_message ? `
                        <div class="mt-2 p-2 rounded bg-accent-danger/10 border border-accent-danger/30">
                            <div class="text-xs text-accent-danger">${escapeHtml(service.error_message)}</div>
                        </div>
                        ` : ''}
                    </div>

                    <div class="flex gap-2">
                        ${isRunning ? `
                            <button onclick="stopService('${service.id}')" class="flex-1 btn-danger-sm">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z"></path>
                                </svg>
                                Stop
                            </button>
                            <button onclick="restartService('${service.id}')" class="flex-1 btn-secondary-sm">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                                </svg>
                                Restart
                            </button>
                        ` : isStarting ? `
                            <button disabled class="flex-1 btn-secondary-sm opacity-50 cursor-not-allowed">
                                <svg class="w-4 h-4 animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                                </svg>
                                Starting...
                            </button>
                        ` : `
                            <button onclick="startService('${service.id}')" class="flex-1 btn-success-sm">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"></path>
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                                </svg>
                                Start
                            </button>
                        `}
                    </div>
                </div>
            </div>
        `;
    }).join('');

    container.innerHTML = html;
}

function renderClients(clients) {
    const container = document.getElementById('clients-list');

    if (clients.length === 0) {
        container.innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                </svg>
                <p class="text-lg font-medium">No clients connected</p>
                <p class="text-sm mt-1">Clients will appear here when they connect</p>
            </div>
        `;
        return;
    }

    const html = clients.map(client => `
        <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 mb-3">
            <div class="flex items-center gap-4">
                <div class="w-12 h-12 rounded-xl bg-gradient-to-br from-accent-primary/20 to-accent-secondary/20 flex items-center justify-center">
                    <svg class="w-6 h-6 text-accent-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                    </svg>
                </div>
                <div>
                    <div class="font-medium text-dark-100">${escapeHtml(client.name)}</div>
                    <div class="text-sm text-dark-400">${client.device_model || 'Unknown Device'} • ${client.os_version || 'Unknown OS'}</div>
                    <div class="text-xs text-dark-500 mt-1">${client.ip_address}</div>
                </div>
            </div>
            <div class="text-right">
                <div class="status-badge status-${client.status}">${client.status}</div>
                <div class="text-xs text-dark-500 mt-2">
                    ${client.total_sessions} sessions • ${client.total_logs} logs
                </div>
                <div class="text-xs text-dark-500">
                    Last seen: ${formatRelativeTime(client.last_seen)}
                </div>
            </div>
        </div>
    `).join('');

    container.innerHTML = html;
}

function renderServers(servers) {
    const container = document.getElementById('servers-grid');

    const html = servers.map(server => `
        <div class="card">
            <div class="p-4">
                <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-3">
                        <div class="w-10 h-10 rounded-lg ${getServerTypeStyles(server.type).bg} flex items-center justify-center">
                            ${getServerTypeIcon(server.type)}
                        </div>
                        <div>
                            <div class="font-medium text-dark-100">${escapeHtml(server.name)}</div>
                            <div class="text-xs text-dark-400">${server.type}</div>
                        </div>
                    </div>
                    <div class="status-badge status-${server.status}">${server.status}</div>
                </div>
                <div class="space-y-2 text-sm">
                    <div class="flex justify-between">
                        <span class="text-dark-400">URL</span>
                        <span class="text-dark-200 font-mono text-xs">${server.url}</span>
                    </div>
                    <div class="flex justify-between">
                        <span class="text-dark-400">Response Time</span>
                        <span class="text-dark-200">${server.response_time_ms.toFixed(0)} ms</span>
                    </div>
                    ${server.models && server.models.length > 0 ? `
                    <div class="flex justify-between">
                        <span class="text-dark-400">Models</span>
                        <span class="text-dark-200">${server.models.length}</span>
                    </div>
                    ` : ''}
                    ${server.error_message ? `
                    <div class="text-accent-danger text-xs mt-2">${escapeHtml(server.error_message)}</div>
                    ` : ''}
                </div>
            </div>
            <div class="border-t border-dark-700/50 px-4 py-2 flex justify-end gap-2">
                <button onclick="deleteServer('${server.id}')" class="text-xs text-dark-400 hover:text-accent-danger transition-colors">
                    Remove
                </button>
            </div>
        </div>
    `).join('');

    container.innerHTML = html;
}

function renderModels(data) {
    const container = document.getElementById('models-grid');

    document.getElementById('models-llm-count').textContent = data.by_type.llm;
    document.getElementById('models-stt-count').textContent = data.by_type.stt;
    document.getElementById('models-tts-count').textContent = data.by_type.tts;

    if (data.models.length === 0) {
        container.innerHTML = `
            <div class="col-span-full text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"></path>
                </svg>
                <p class="text-lg font-medium">No models available</p>
                <p class="text-sm mt-1">Models will appear here when servers are connected</p>
            </div>
        `;
        return;
    }

    const html = data.models.map(model => `
        <div class="card p-4">
            <div class="flex items-center gap-3 mb-3">
                <div class="w-10 h-10 rounded-lg ${getModelTypeStyles(model.type).bg} flex items-center justify-center">
                    ${getModelTypeIcon(model.type)}
                </div>
                <div>
                    <div class="font-medium text-dark-100">${escapeHtml(model.name)}</div>
                    <div class="text-xs text-dark-400">${model.type.toUpperCase()} • ${model.server_name}</div>
                </div>
            </div>
            <div class="space-y-2 text-sm mb-3">
                ${model.size_gb > 0 ? `
                <div class="flex justify-between">
                    <span class="text-dark-400">Size</span>
                    <span class="text-dark-200 font-mono">${model.size_gb.toFixed(1)} GB</span>
                </div>
                ` : ''}
                ${model.parameter_size ? `
                <div class="flex justify-between">
                    <span class="text-dark-400">Parameters</span>
                    <span class="text-dark-200">${model.parameter_size}</span>
                </div>
                ` : ''}
                ${model.quantization ? `
                <div class="flex justify-between">
                    <span class="text-dark-400">Quantization</span>
                    <span class="text-dark-200 font-mono text-xs">${model.quantization}</span>
                </div>
                ` : ''}
                ${model.vram_gb > 0 ? `
                <div class="flex justify-between">
                    <span class="text-dark-400">VRAM Used</span>
                    <span class="text-accent-warning font-semibold">${model.vram_gb.toFixed(1)} GB</span>
                </div>
                ` : ''}
            </div>
            <div class="flex items-center justify-between">
                <span class="status-badge ${model.status === 'loaded' ? 'bg-accent-success/20 text-accent-success' : model.status === 'available' ? 'bg-dark-600/50 text-dark-300' : 'bg-dark-600/50 text-dark-400'}">${model.status}</span>
            </div>
        </div>
    `).join('');

    container.innerHTML = html;
}

function renderMetricsTable(metrics) {
    const tbody = document.getElementById('metrics-table-body');

    if (metrics.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-dark-500 py-8">No session data yet</td></tr>';
        return;
    }

    const html = metrics.slice(0, 50).map(m => `
        <tr class="border-b border-dark-700/30 hover:bg-dark-800/30">
            <td class="table-cell text-dark-300">${formatLogTime(m.timestamp)}</td>
            <td class="table-cell text-dark-200">${escapeHtml(m.client_name)}</td>
            <td class="table-cell">${formatDuration(m.session_duration)}</td>
            <td class="table-cell">${m.turns_total}</td>
            <td class="table-cell">${m.e2e_latency_median.toFixed(0)} ms</td>
            <td class="table-cell">${m.llm_ttft_median.toFixed(0)} ms</td>
            <td class="table-cell text-accent-success">$${m.total_cost.toFixed(4)}</td>
        </tr>
    `).join('');

    tbody.innerHTML = html;
}

function updateDashboardServers(servers) {
    const container = document.getElementById('dashboard-servers');

    const html = servers.slice(0, 4).map(server => `
        <div class="flex items-center justify-between p-3 rounded-lg bg-dark-800/30 mb-2 last:mb-0">
            <div class="flex items-center gap-3">
                <div class="w-8 h-8 rounded-lg ${getServerTypeStyles(server.type).bg} flex items-center justify-center">
                    ${getServerTypeIcon(server.type, 'w-4 h-4')}
                </div>
                <div>
                    <div class="text-sm font-medium text-dark-200">${escapeHtml(server.name)}</div>
                    <div class="text-xs text-dark-500">${server.response_time_ms.toFixed(0)} ms</div>
                </div>
            </div>
            <div class="status-dot-${server.status}"></div>
        </div>
    `).join('');

    container.innerHTML = html;
}

function updateDashboardClients(clients) {
    const container = document.getElementById('dashboard-clients');
    const onlineClients = clients.filter(c => c.status === 'online');

    if (onlineClients.length === 0) {
        container.innerHTML = `
            <div class="text-center text-dark-500 py-8">
                <svg class="w-12 h-12 mx-auto mb-2 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                </svg>
                <p>No clients connected</p>
            </div>
        `;
        return;
    }

    const html = `<div class="grid md:grid-cols-2 lg:grid-cols-3 gap-3">` + onlineClients.slice(0, 6).map(client => `
        <div class="flex items-center gap-3 p-3 rounded-lg bg-dark-800/30">
            <div class="w-10 h-10 rounded-lg bg-gradient-to-br from-accent-primary/20 to-accent-secondary/20 flex items-center justify-center">
                <svg class="w-5 h-5 text-accent-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                </svg>
            </div>
            <div>
                <div class="text-sm font-medium text-dark-200">${escapeHtml(client.name)}</div>
                <div class="text-xs text-dark-500">${client.device_model || 'Unknown'}</div>
            </div>
        </div>
    `).join('') + '</div>';

    container.innerHTML = html;
}

function addRecentActivity(log) {
    const container = document.getElementById('recent-activity');
    const isEmpty = container.querySelector('.text-center');

    if (isEmpty) {
        container.innerHTML = '';
    }

    const levelColors = {
        'DEBUG': 'text-dark-400',
        'INFO': 'text-accent-info',
        'WARNING': 'text-accent-warning',
        'ERROR': 'text-accent-danger',
        'CRITICAL': 'text-accent-danger'
    };

    const entry = document.createElement('div');
    entry.className = 'flex items-start gap-3 p-2 rounded-lg hover:bg-dark-800/30 animate-fade-in';
    entry.innerHTML = `
        <div class="w-2 h-2 rounded-full mt-2 ${levelColors[log.level] || 'bg-dark-400'}"></div>
        <div class="flex-1 min-w-0">
            <div class="text-sm text-dark-200 truncate">${escapeHtml(log.message)}</div>
            <div class="text-xs text-dark-500">${formatRelativeTime(log.received_at)}</div>
        </div>
    `;

    container.insertBefore(entry, container.firstChild);

    // Limit entries
    while (container.children.length > 20) {
        container.removeChild(container.lastChild);
    }
}

// =============================================================================
// Charts
// =============================================================================

function initCharts() {
    // Latency overview chart
    const latencyCtx = document.getElementById('latency-chart').getContext('2d');
    state.charts.latency = new Chart(latencyCtx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [
                {
                    label: 'E2E',
                    data: [],
                    borderColor: '#6366f1',
                    backgroundColor: 'rgba(99, 102, 241, 0.1)',
                    fill: true,
                    tension: 0.4
                },
                {
                    label: 'LLM TTFT',
                    data: [],
                    borderColor: '#8b5cf6',
                    backgroundColor: 'transparent',
                    tension: 0.4
                },
                {
                    label: 'STT',
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'transparent',
                    tension: 0.4
                },
                {
                    label: 'TTS',
                    data: [],
                    borderColor: '#3b82f6',
                    backgroundColor: 'transparent',
                    tension: 0.4
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                    labels: { color: '#94a3b8', usePointStyle: true }
                }
            },
            scales: {
                x: {
                    grid: { color: 'rgba(51, 65, 85, 0.5)' },
                    ticks: { color: '#64748b' }
                },
                y: {
                    grid: { color: 'rgba(51, 65, 85, 0.5)' },
                    ticks: { color: '#64748b' },
                    title: { display: true, text: 'ms', color: '#64748b' }
                }
            }
        }
    });

    // Latency distribution chart
    const distCtx = document.getElementById('latency-distribution-chart').getContext('2d');
    state.charts.distribution = new Chart(distCtx, {
        type: 'bar',
        data: {
            labels: ['E2E', 'LLM TTFT', 'STT', 'TTS TTFB'],
            datasets: [
                {
                    label: 'Median',
                    data: [0, 0, 0, 0],
                    backgroundColor: 'rgba(99, 102, 241, 0.8)'
                },
                {
                    label: 'P99',
                    data: [0, 0, 0, 0],
                    backgroundColor: 'rgba(139, 92, 246, 0.8)'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                    labels: { color: '#94a3b8' }
                }
            },
            scales: {
                x: {
                    grid: { display: false },
                    ticks: { color: '#64748b' }
                },
                y: {
                    grid: { color: 'rgba(51, 65, 85, 0.5)' },
                    ticks: { color: '#64748b' },
                    title: { display: true, text: 'ms', color: '#64748b' }
                }
            }
        }
    });

    // Cost chart
    const costCtx = document.getElementById('cost-chart').getContext('2d');
    state.charts.cost = new Chart(costCtx, {
        type: 'doughnut',
        data: {
            labels: ['STT', 'LLM', 'TTS'],
            datasets: [{
                data: [0, 0, 0],
                backgroundColor: ['#10b981', '#8b5cf6', '#3b82f6'],
                borderColor: '#1e293b',
                borderWidth: 2
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'right',
                    labels: { color: '#94a3b8', usePointStyle: true }
                }
            }
        }
    });
}

function updateSparklines(metrics) {
    // Simple sparkline update - would need mini charts for full implementation
}

function updateLatencyChart(metrics) {
    if (!state.charts.latency || metrics.length === 0) return;

    const labels = metrics.slice(0, 20).reverse().map((_, i) => `${i + 1}`);
    const reversed = metrics.slice(0, 20).reverse();

    state.charts.latency.data.labels = labels;
    state.charts.latency.data.datasets[0].data = reversed.map(m => m.e2e_latency_median);
    state.charts.latency.data.datasets[1].data = reversed.map(m => m.llm_ttft_median);
    state.charts.latency.data.datasets[2].data = reversed.map(m => m.stt_latency_median);
    state.charts.latency.data.datasets[3].data = reversed.map(m => m.tts_ttfb_median);
    state.charts.latency.update('none');
}

function updateLatencyDistributionChart(metrics) {
    if (!state.charts.distribution || metrics.length === 0) return;

    const agg = calculateAggregates(metrics);

    state.charts.distribution.data.datasets[0].data = [
        agg.e2e_median,
        agg.llm_median,
        agg.stt_median,
        agg.tts_median
    ];
    state.charts.distribution.data.datasets[1].data = [
        agg.e2e_p99,
        agg.llm_p99,
        agg.stt_p99,
        agg.tts_p99
    ];
    state.charts.distribution.update('none');
}

function updateCostChart(metrics) {
    if (!state.charts.cost || metrics.length === 0) return;

    const sttTotal = metrics.reduce((sum, m) => sum + m.stt_cost, 0);
    const llmTotal = metrics.reduce((sum, m) => sum + m.llm_cost, 0);
    const ttsTotal = metrics.reduce((sum, m) => sum + m.tts_cost, 0);

    state.charts.cost.data.datasets[0].data = [sttTotal, llmTotal, ttsTotal];
    state.charts.cost.update('none');
}

function calculateAggregates(metrics) {
    if (metrics.length === 0) {
        return {
            e2e_median: 0, e2e_p99: 0,
            llm_median: 0, llm_p99: 0,
            stt_median: 0, stt_p99: 0,
            tts_median: 0, tts_p99: 0
        };
    }

    const median = arr => {
        const sorted = arr.slice().sort((a, b) => a - b);
        const mid = Math.floor(sorted.length / 2);
        return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    };

    const p99 = arr => {
        const sorted = arr.slice().sort((a, b) => a - b);
        const idx = Math.floor(sorted.length * 0.99);
        return sorted[idx] || sorted[sorted.length - 1];
    };

    return {
        e2e_median: median(metrics.map(m => m.e2e_latency_median)),
        e2e_p99: p99(metrics.map(m => m.e2e_latency_p99)),
        llm_median: median(metrics.map(m => m.llm_ttft_median)),
        llm_p99: p99(metrics.map(m => m.llm_ttft_p99)),
        stt_median: median(metrics.map(m => m.stt_latency_median)),
        stt_p99: p99(metrics.map(m => m.stt_latency_p99)),
        tts_median: median(metrics.map(m => m.tts_ttfb_median)),
        tts_p99: p99(metrics.map(m => m.tts_ttfb_p99))
    };
}

// =============================================================================
// Tab Navigation
// =============================================================================

// CSS classes for tab states (CDN Tailwind doesn't support @apply in <style> tags)
// Note: Classes with special chars like / work fine with classList - the issue was elsewhere
const TAB_ACTIVE_CLASSES = ['bg-dark-700\\/80', 'text-white', 'border-dark-600', 'shadow-sm'];
const TAB_INACTIVE_CLASSES = ['text-dark-400', 'border-transparent', 'hover:text-dark-200', 'hover:bg-dark-700\\/40', 'hover:border-dark-600\\/50'];

// Actual class names as they appear in the DOM (unescaped for classList operations)
const TAB_ACTIVE_CLASSES_RAW = ['bg-dark-700/80', 'text-white', 'border-dark-600', 'shadow-sm'];
const TAB_INACTIVE_CLASSES_RAW = ['text-dark-400', 'border-transparent', 'hover:text-dark-200', 'hover:bg-dark-700/40', 'hover:border-dark-600/50'];

function setTabActive(tab, isActive) {
    const svg = tab.querySelector('svg');
    if (isActive) {
        // Remove inactive classes, add active classes
        TAB_INACTIVE_CLASSES_RAW.forEach(cls => tab.classList.remove(cls));
        TAB_ACTIVE_CLASSES_RAW.forEach(cls => tab.classList.add(cls));
        tab.classList.add('active');
        if (svg) svg.classList.add('text-accent-primary');
    } else {
        // Remove active classes, add inactive classes
        TAB_ACTIVE_CLASSES_RAW.forEach(cls => tab.classList.remove(cls));
        TAB_INACTIVE_CLASSES_RAW.forEach(cls => tab.classList.add(cls));
        tab.classList.remove('active');
        if (svg) svg.classList.remove('text-accent-primary');
    }
}

function initTabs() {
    const tabs = document.querySelectorAll('.nav-tab');

    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const tabId = tab.dataset.tab;

            // Update tab buttons - toggle active/inactive styles
            tabs.forEach(t => setTabActive(t, false));
            setTabActive(tab, true);

            // Show/hide tab content
            document.querySelectorAll('.tab-content').forEach(content => {
                content.classList.add('hidden');
            });
            document.getElementById(`tab-${tabId}`).classList.remove('hidden');

            // Load data for specific tabs
            switch (tabId) {
                case 'metrics':
                    refreshMetrics();
                    updateLatencyChart(state.metrics);
                    break;
                case 'logs':
                    refreshLogs();
                    break;
                case 'clients':
                    refreshClients();
                    break;
                case 'servers':
                    refreshServers();
                    break;
                case 'models':
                    refreshModels();
                    break;
                case 'services':
                    refreshServices();
                    break;
                case 'curriculum':
                    refreshCurricula();
                    fetchArchivedCurricula();
                    break;
                case 'sources':
                    initSourcesTab();
                    break;
                case 'plugins':
                    refreshPlugins();
                    break;
            }
        });
    });
}

// =============================================================================
// Log Controls
// =============================================================================

function initLogControls() {
    // Level filter buttons
    document.querySelectorAll('.log-level-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.log-level-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            state.logFilter.level = btn.dataset.level;
            refreshLogs();
        });
    });

    // Search input
    const searchInput = document.getElementById('log-search');
    let searchTimeout;
    searchInput.addEventListener('input', () => {
        clearTimeout(searchTimeout);
        searchTimeout = setTimeout(() => {
            state.logFilter.search = searchInput.value;
            refreshLogs();
        }, 300);
    });
}

function toggleLogsPause() {
    state.logsPaused = !state.logsPaused;
    const btn = document.getElementById('logs-pause-btn');
    const indicator = document.getElementById('logs-live-indicator');

    if (state.logsPaused) {
        btn.innerHTML = `
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"></path>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            Resume
        `;
        indicator.innerHTML = `
            <div class="w-2 h-2 rounded-full bg-accent-warning"></div>
            Paused
        `;
        indicator.className = 'flex items-center gap-1.5 text-sm text-accent-warning';
    } else {
        btn.innerHTML = `
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            Pause
        `;
        indicator.innerHTML = `
            <div class="w-2 h-2 rounded-full bg-accent-success status-dot"></div>
            Live
        `;
        indicator.className = 'flex items-center gap-1.5 text-sm text-accent-success';
    }
}

// =============================================================================
// Server Management
// =============================================================================

function showAddServerModal() {
    document.getElementById('add-server-modal').classList.remove('hidden');
}

function hideAddServerModal() {
    document.getElementById('add-server-modal').classList.add('hidden');
    document.getElementById('add-server-form').reset();
}

async function addServer(event) {
    event.preventDefault();

    const form = event.target;
    const formData = new FormData(form);

    try {
        await fetchAPI('/servers', {
            method: 'POST',
            body: JSON.stringify({
                name: formData.get('name'),
                type: formData.get('type'),
                url: formData.get('url'),
                port: parseInt(new URL(formData.get('url')).port) || 80
            })
        });

        hideAddServerModal();
        refreshServers();
    } catch (e) {
        alert('Failed to add server: ' + e.message);
    }
}

async function deleteServer(serverId) {
    if (!confirm('Are you sure you want to remove this server?')) return;

    try {
        await fetchAPI(`/servers/${serverId}`, { method: 'DELETE' });
        refreshServers();
    } catch (e) {
        alert('Failed to delete server: ' + e.message);
    }
}

// =============================================================================
// Utility Functions
// =============================================================================

function formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
}

function formatUptime(seconds) {
    if (seconds < 60) return `${Math.floor(seconds)}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
    return `${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
}

function formatDuration(seconds) {
    if (seconds < 60) return `${seconds.toFixed(0)}s`;
    return `${Math.floor(seconds / 60)}m ${Math.floor(seconds % 60)}s`;
}

function formatLogTime(timestamp) {
    try {
        const date = new Date(timestamp);
        return date.toLocaleTimeString('en-US', { hour12: false });
    } catch {
        return '--:--:--';
    }
}

function formatRelativeTime(timestamp) {
    const seconds = Math.floor((Date.now() / 1000) - timestamp);
    if (seconds < 60) return 'just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function getServerTypeStyles(type) {
    const styles = {
        'ollama': { bg: 'bg-accent-secondary/20', text: 'text-accent-secondary' },
        'whisper': { bg: 'bg-accent-success/20', text: 'text-accent-success' },
        'piper': { bg: 'bg-accent-info/20', text: 'text-accent-info' },
        'unamentisGateway': { bg: 'bg-accent-primary/20', text: 'text-accent-primary' },
        'default': { bg: 'bg-dark-600/20', text: 'text-dark-400' }
    };
    return styles[type] || styles.default;
}

function getServerTypeIcon(type, size = 'w-5 h-5') {
    const styles = getServerTypeStyles(type);
    const icons = {
        'ollama': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path></svg>`,
        'whisper': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"></path></svg>`,
        'piper': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15.536a5 5 0 001.414 1.414m2.828-9.9a9 9 0 0112.728 0"></path></svg>`,
        'unamentisGateway': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"></path></svg>`,
        'default': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2"></path></svg>`
    };
    return icons[type] || icons.default;
}

function getModelTypeStyles(type) {
    const styles = {
        'llm': { bg: 'bg-accent-secondary/20', text: 'text-accent-secondary' },
        'stt': { bg: 'bg-accent-success/20', text: 'text-accent-success' },
        'tts': { bg: 'bg-accent-info/20', text: 'text-accent-info' }
    };
    return styles[type] || { bg: 'bg-dark-600/20', text: 'text-dark-400' };
}

function getModelTypeIcon(type) {
    const styles = getModelTypeStyles(type);
    const icons = {
        'llm': `<svg class="w-5 h-5 ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path></svg>`,
        'stt': `<svg class="w-5 h-5 ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"></path></svg>`,
        'tts': `<svg class="w-5 h-5 ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15.536a5 5 0 001.414 1.414m2.828-9.9a9 9 0 0112.728 0"></path></svg>`
    };
    return icons[type] || '';
}

// Add CSS for status badges
const style = document.createElement('style');
style.textContent = `
    .status-badge {
        @apply text-xs font-medium px-2 py-1 rounded-full;
    }
    .status-online, .status-healthy {
        @apply bg-accent-success/20 text-accent-success;
    }
    .status-idle, .status-degraded {
        @apply bg-accent-warning/20 text-accent-warning;
    }
    .status-offline, .status-unhealthy, .status-unknown {
        @apply bg-dark-600/50 text-dark-400;
    }
    .status-dot-healthy {
        @apply w-3 h-3 rounded-full bg-accent-success;
    }
    .status-dot-degraded {
        @apply w-3 h-3 rounded-full bg-accent-warning;
    }
    .status-dot-unhealthy, .status-dot-unknown {
        @apply w-3 h-3 rounded-full bg-dark-500;
    }
`;
document.head.appendChild(style);

// =============================================================================
// Curriculum Management
// =============================================================================

// Store curriculum data in state
state.curricula = [];
state.selectedCurriculum = null;

async function refreshCurricula() {
    try {
        const data = await fetchAPI('/curricula');
        state.curricula = data.curricula;
        updateCurriculaStats(data);
        renderCurricula(data.curricula);
    } catch (e) {
        console.error('Failed to refresh curricula:', e);
        const grid = document.getElementById('curricula-grid');
        grid.innerHTML = `
            <div class="text-center text-dark-500 py-12 col-span-full">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium">Failed to load curricula</p>
                <p class="text-sm mt-1">${e.message}</p>
            </div>
        `;
    }
}

function updateCurriculaStats(data) {
    document.getElementById('curricula-total').textContent = data.total;

    // Calculate total topics
    const totalTopics = state.curricula.reduce((sum, c) => sum + c.topic_count, 0);
    document.getElementById('curricula-topics').textContent = totalTopics;

    // Calculate total duration (approximate from curriculum durations)
    let totalMinutes = 0;
    state.curricula.forEach(c => {
        if (c.total_duration) {
            // Parse PT format (e.g., PT6H, PT30M, PT1H30M)
            const match = c.total_duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?/);
            if (match) {
                const hours = parseInt(match[1] || 0);
                const minutes = parseInt(match[2] || 0);
                totalMinutes += hours * 60 + minutes;
            }
        }
    });
    const hours = Math.floor(totalMinutes / 60);
    document.getElementById('curricula-duration').textContent = hours > 0 ? `${hours}h` : `${totalMinutes}m`;

    // Calculate unique keywords
    const allKeywords = new Set();
    state.curricula.forEach(c => {
        (c.keywords || []).forEach(k => allKeywords.add(k.toLowerCase()));
    });
    document.getElementById('curricula-keywords').textContent = allKeywords.size;
}

function renderCurricula(curricula) {
    const container = document.getElementById('curricula-grid');

    if (curricula.length === 0) {
        container.innerHTML = `
            <div class="text-center text-dark-500 py-12 col-span-full">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path>
                </svg>
                <p class="text-lg font-medium">No curricula found</p>
                <p class="text-sm mt-1">Add UMCF files to the curriculum/examples/realistic/ folder</p>
            </div>
        `;
        return;
    }

    const getDifficultyStyles = (difficulty) => {
        const styles = {
            'beginner': 'bg-accent-success/20 text-accent-success',
            'intermediate': 'bg-accent-warning/20 text-accent-warning',
            'advanced': 'bg-accent-danger/20 text-accent-danger',
            'default': 'bg-dark-600/50 text-dark-400'
        };
        return styles[difficulty?.toLowerCase()] || styles.default;
    };

    const html = curricula.map(curriculum => `
        <div class="card cursor-pointer hover:border-accent-primary/50 transition-all group" onclick="selectCurriculum('${curriculum.id}')">
            <div class="p-4">
                <div class="flex items-start justify-between mb-3">
                    <div class="flex items-center gap-3">
                        <div class="w-12 h-12 rounded-lg bg-accent-primary/20 flex items-center justify-center">
                            <svg class="w-6 h-6 text-accent-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path>
                            </svg>
                        </div>
                        <div>
                            <div class="font-semibold text-dark-100">${escapeHtml(curriculum.title)}</div>
                            <div class="text-xs text-dark-400">v${curriculum.version}</div>
                        </div>
                    </div>
                    <div class="flex items-center gap-2">
                        <span class="px-2 py-0.5 rounded text-xs font-medium ${getDifficultyStyles(curriculum.difficulty)}">${curriculum.difficulty || 'Unknown'}</span>
                        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                            <button onclick="showArchiveConfirm('${curriculum.id}', '${escapeHtml(curriculum.title).replace(/'/g, "\\'")}', event)"
                                    class="p-1.5 text-dark-400 hover:text-accent-warning hover:bg-dark-700 rounded transition-colors" title="Archive">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"></path>
                                </svg>
                            </button>
                            <button onclick="showDeleteConfirm('${curriculum.id}', '${escapeHtml(curriculum.title).replace(/'/g, "\\'")}', event)"
                                    class="p-1.5 text-dark-400 hover:text-accent-danger hover:bg-dark-700 rounded transition-colors" title="Delete">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                                </svg>
                            </button>
                        </div>
                    </div>
                </div>

                <p class="text-sm text-dark-300 mb-3 line-clamp-2">${escapeHtml(curriculum.description)}</p>

                <div class="flex flex-wrap gap-1 mb-3">
                    ${(curriculum.keywords || []).slice(0, 3).map(k => `
                        <span class="px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-300">${escapeHtml(k)}</span>
                    `).join('')}
                    ${(curriculum.keywords || []).length > 3 ? `
                        <span class="px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">+${curriculum.keywords.length - 3}</span>
                    ` : ''}
                </div>

                <div class="grid grid-cols-4 gap-2 text-xs">
                    <div class="text-center p-2 rounded bg-dark-800/30">
                        <div class="font-semibold text-dark-200">${curriculum.topic_count}</div>
                        <div class="text-dark-500">Topics</div>
                    </div>
                    <div class="text-center p-2 rounded bg-dark-800/30">
                        <div class="font-semibold text-dark-200">${formatDurationPT(curriculum.total_duration)}</div>
                        <div class="text-dark-500">Duration</div>
                    </div>
                    <div class="text-center p-2 rounded bg-dark-800/30">
                        <div class="font-semibold text-dark-200">${curriculum.age_range || 'All'}</div>
                        <div class="text-dark-500">Ages</div>
                    </div>
                    <div class="text-center p-2 rounded ${curriculum.has_visual_assets ? 'bg-accent-info/10' : 'bg-dark-800/30'}">
                        <div class="font-semibold ${curriculum.has_visual_assets ? 'text-accent-info' : 'text-dark-200'}">${curriculum.visual_asset_count || 0}</div>
                        <div class="text-dark-500">Assets</div>
                    </div>
                </div>
            </div>
        </div>
    `).join('');

    container.innerHTML = html;
}

function formatDurationPT(ptDuration) {
    if (!ptDuration) return '--';
    const match = ptDuration.match(/PT(?:(\d+)H)?(?:(\d+)M)?/);
    if (!match) return ptDuration;
    const hours = parseInt(match[1] || 0);
    const minutes = parseInt(match[2] || 0);
    if (hours > 0 && minutes > 0) return `${hours}h${minutes}m`;
    if (hours > 0) return `${hours}h`;
    return `${minutes}m`;
}

function filterCurricula() {
    const searchTerm = document.getElementById('curriculum-search').value.toLowerCase();
    const difficultyFilter = document.getElementById('curriculum-difficulty-filter').value;

    const filtered = state.curricula.filter(c => {
        // Search filter
        const matchesSearch = !searchTerm ||
            c.title.toLowerCase().includes(searchTerm) ||
            c.description.toLowerCase().includes(searchTerm) ||
            (c.keywords || []).some(k => k.toLowerCase().includes(searchTerm));

        // Difficulty filter
        const matchesDifficulty = !difficultyFilter ||
            (c.difficulty && c.difficulty.toLowerCase() === difficultyFilter);

        return matchesSearch && matchesDifficulty;
    });

    renderCurricula(filtered);
}

async function selectCurriculum(curriculumId) {
    try {
        const data = await fetchAPI(`/curricula/${curriculumId}`);
        state.selectedCurriculum = data;
        showCurriculumDetail(data);
    } catch (e) {
        console.error('Failed to load curriculum detail:', e);
        alert('Failed to load curriculum: ' + e.message);
    }
}

function showCurriculumDetail(curriculum) {
    const panel = document.getElementById('curriculum-detail-panel');

    // Update title
    document.getElementById('curriculum-detail-title').textContent = curriculum.title;

    // Update description
    document.getElementById('curriculum-detail-description').textContent = curriculum.description;

    // Update metadata
    const getDifficultyStyles = (difficulty) => {
        const styles = {
            'beginner': 'bg-accent-success/20 text-accent-success',
            'intermediate': 'bg-accent-warning/20 text-accent-warning',
            'advanced': 'bg-accent-danger/20 text-accent-danger',
            'default': 'bg-dark-600/50 text-dark-400'
        };
        return styles[difficulty?.toLowerCase()] || styles.default;
    };

    const difficultyEl = document.getElementById('curriculum-detail-difficulty');
    difficultyEl.textContent = curriculum.difficulty || 'Unknown';
    difficultyEl.className = `px-2 py-0.5 rounded text-xs font-medium ${getDifficultyStyles(curriculum.difficulty)}`;

    document.getElementById('curriculum-detail-age').textContent = curriculum.age_range || 'All ages';
    document.getElementById('curriculum-detail-duration').textContent = formatDurationPT(curriculum.duration);
    document.getElementById('curriculum-detail-version').textContent = curriculum.version;

    // Update keywords
    const keywordsEl = document.getElementById('curriculum-detail-keywords');
    keywordsEl.innerHTML = (curriculum.keywords || []).map(k => `
        <span class="px-2 py-1 text-xs rounded-full bg-accent-primary/10 text-accent-primary border border-accent-primary/30">${escapeHtml(k)}</span>
    `).join('');

    // Update learning objectives
    const objectivesEl = document.getElementById('curriculum-detail-objectives');
    if (curriculum.learning_objectives && curriculum.learning_objectives.length > 0) {
        objectivesEl.innerHTML = curriculum.learning_objectives.map(obj => `
            <li class="flex items-start gap-2">
                <svg class="w-4 h-4 text-accent-success mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <span>${escapeHtml(typeof obj === 'string' ? obj : obj.objective || obj.text || JSON.stringify(obj))}</span>
            </li>
        `).join('');
    } else {
        objectivesEl.innerHTML = '<li class="text-dark-500">No learning objectives defined</li>';
    }

    // Update glossary
    const glossaryEl = document.getElementById('curriculum-detail-glossary');
    if (curriculum.glossary_terms && curriculum.glossary_terms.length > 0) {
        glossaryEl.innerHTML = curriculum.glossary_terms.map(term => `
            <div class="p-3 rounded-lg bg-dark-800/30 border border-dark-700/50">
                <div class="font-medium text-dark-200 mb-1">${escapeHtml(term.term)}</div>
                <div class="text-xs text-dark-400">${escapeHtml(term.definition || term.spokenDefinition || '')}</div>
                ${term.pronunciation ? `<div class="text-xs text-accent-info mt-1">/${term.pronunciation}/</div>` : ''}
            </div>
        `).join('');
    } else {
        glossaryEl.innerHTML = '<div class="text-dark-500">No glossary terms defined</div>';
    }

    // Update topics
    const topicsEl = document.getElementById('curriculum-detail-topics');
    if (curriculum.topics && curriculum.topics.length > 0) {
        topicsEl.innerHTML = curriculum.topics.map((topic, index) => `
            <div class="flex items-center gap-3 p-3 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-dark-600/50 transition-all cursor-pointer" onclick="viewTopicTranscript('${curriculum.id}', '${topic.id}')">
                <div class="w-8 h-8 rounded-lg bg-accent-secondary/20 flex items-center justify-center text-accent-secondary font-semibold text-sm">
                    ${index + 1}
                </div>
                <div class="flex-1">
                    <div class="font-medium text-dark-200">${escapeHtml(topic.title)}</div>
                    <div class="text-xs text-dark-400">${escapeHtml(topic.description || '')}</div>
                </div>
                <div class="text-right text-xs">
                    <div class="text-dark-300">${formatDurationPT(topic.duration)}</div>
                    ${topic.has_transcript ? `<div class="text-accent-success">${topic.segment_count || 0} segments</div>` : '<div class="text-dark-500">No transcript</div>'}
                    ${(topic.embedded_asset_count || 0) + (topic.reference_asset_count || 0) > 0 ?
                        `<div class="text-accent-info flex items-center gap-1 justify-end mt-0.5">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                            </svg>
                            ${(topic.embedded_asset_count || 0) + (topic.reference_asset_count || 0)} assets
                        </div>` : ''
                    }
                </div>
                <svg class="w-5 h-5 text-dark-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                </svg>
            </div>
        `).join('');
    } else {
        topicsEl.innerHTML = '<div class="text-dark-500">No topics defined</div>';
    }

    // Show panel
    panel.classList.remove('hidden');

    // Scroll to panel
    panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function closeCurriculumDetail() {
    document.getElementById('curriculum-detail-panel').classList.add('hidden');
    state.selectedCurriculum = null;
}

async function viewTopicTranscript(curriculumId, topicId) {
    try {
        const data = await fetchAPI(`/curricula/${curriculumId}/topics/${topicId}/transcript`);

        // Extract segments from the transcript object
        const segments = data.transcript?.segments || data.segments || [];
        const examples = data.examples || [];
        const assessments = data.assessments || [];
        const misconceptions = data.misconceptions || [];

        // Extract visual assets
        const media = data.media || {};
        const embeddedAssets = media.embedded || [];
        const referenceAssets = media.reference || [];
        const totalAssets = embeddedAssets.length + referenceAssets.length;

        // Show transcript in a modal
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 z-50 flex items-center justify-center p-4';
        modal.innerHTML = `
            <div class="absolute inset-0 bg-dark-950/80 backdrop-blur-sm" onclick="this.parentElement.remove()"></div>
            <div class="relative w-full max-w-4xl max-h-[85vh] overflow-hidden rounded-xl bg-dark-800 border border-dark-700 shadow-xl">
                <div class="flex items-center justify-between px-4 py-3 border-b border-dark-700/50 bg-dark-850">
                    <div>
                        <h3 class="font-semibold text-dark-100">${escapeHtml(data.topic_title || 'Transcript')}</h3>
                        <div class="text-xs text-dark-500 mt-0.5">${segments.length} segments${examples.length ? `, ${examples.length} examples` : ''}${assessments.length ? `, ${assessments.length} assessments` : ''}${totalAssets > 0 ? `, ${totalAssets} visual assets` : ''}</div>
                    </div>
                    <button onclick="this.closest('.fixed').remove()" class="text-dark-400 hover:text-dark-200">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                        </svg>
                    </button>
                </div>
                <div class="p-4 overflow-y-auto max-h-[calc(85vh-60px)] space-y-6">
                    <!-- Transcript Segments -->
                    ${segments.length > 0 ? `
                        <div>
                            <h4 class="text-sm font-medium text-dark-300 mb-3 flex items-center gap-2">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                                </svg>
                                Transcript
                            </h4>
                            <div class="space-y-3">
                                ${segments.map((seg, i) => `
                                    <div class="p-3 rounded-lg ${getSegmentTypeStyles(seg.type)}">
                                        <div class="flex items-center gap-2 mb-2">
                                            <span class="px-2 py-0.5 text-xs rounded ${getSegmentTypeBadge(seg.type)}">${seg.type || 'content'}</span>
                                            <span class="text-xs text-dark-500">#${i + 1}</span>
                                        </div>
                                        <div class="text-dark-200 leading-relaxed">${escapeHtml(seg.content || seg.text || '')}</div>
                                        ${seg.checkpoint ? `
                                            <div class="mt-3 p-2 rounded bg-accent-warning/10 border border-accent-warning/20">
                                                <div class="text-xs font-medium text-accent-warning mb-1">Checkpoint: ${seg.checkpoint.type}</div>
                                                <div class="text-sm text-dark-300">${escapeHtml(seg.checkpoint.prompt || '')}</div>
                                            </div>
                                        ` : ''}
                                        ${seg.stoppingPoint ? `
                                            <div class="mt-2 text-xs text-dark-500 italic flex items-center gap-1">
                                                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                                                </svg>
                                                Natural stopping point${seg.stoppingPoint.suggestedPrompt ? `: "${seg.stoppingPoint.suggestedPrompt}"` : ''}
                                            </div>
                                        ` : ''}
                                        ${seg.speakingNotes ? `
                                            <div class="mt-2 text-xs text-dark-500 border-t border-dark-700/30 pt-2 flex flex-wrap gap-2">
                                                ${seg.speakingNotes.emotionalTone ? `<span class="px-1.5 py-0.5 rounded bg-dark-700/50">Tone: ${seg.speakingNotes.emotionalTone}</span>` : ''}
                                                ${seg.speakingNotes.pace ? `<span class="px-1.5 py-0.5 rounded bg-dark-700/50">Pace: ${seg.speakingNotes.pace}</span>` : ''}
                                                ${seg.speakingNotes.emphasis ? `<span class="px-1.5 py-0.5 rounded bg-dark-700/50">Emphasis: ${seg.speakingNotes.emphasis.join(', ')}</span>` : ''}
                                            </div>
                                        ` : ''}
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    ` : '<div class="text-dark-500 text-center py-8">No transcript segments available</div>'}

                    <!-- Examples -->
                    ${examples.length > 0 ? `
                        <div>
                            <h4 class="text-sm font-medium text-dark-300 mb-3 flex items-center gap-2">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>
                                </svg>
                                Examples
                            </h4>
                            <div class="space-y-3">
                                ${examples.map(ex => `
                                    <div class="p-3 rounded-lg bg-accent-success/5 border border-accent-success/20">
                                        <div class="flex items-center gap-2 mb-2">
                                            <span class="font-medium text-dark-200">${escapeHtml(ex.title || 'Example')}</span>
                                            <span class="px-1.5 py-0.5 text-xs rounded bg-accent-success/20 text-accent-success">${ex.type || 'example'}</span>
                                        </div>
                                        <div class="text-dark-300 text-sm leading-relaxed">${escapeHtml(ex.spokenContent || ex.content || '')}</div>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    ` : ''}

                    <!-- Misconceptions -->
                    ${misconceptions.length > 0 ? `
                        <div>
                            <h4 class="text-sm font-medium text-dark-300 mb-3 flex items-center gap-2">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
                                </svg>
                                Common Misconceptions
                            </h4>
                            <div class="space-y-3">
                                ${misconceptions.map(mis => `
                                    <div class="p-3 rounded-lg bg-accent-danger/5 border border-accent-danger/20">
                                        <div class="font-medium text-accent-danger mb-1">${escapeHtml(mis.misconception || '')}</div>
                                        <div class="text-dark-300 text-sm">${escapeHtml(mis.spokenCorrection || mis.correction || '')}</div>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    ` : ''}

                    <!-- Assessments -->
                    ${assessments.length > 0 ? `
                        <div>
                            <h4 class="text-sm font-medium text-dark-300 mb-3 flex items-center gap-2">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"></path>
                                </svg>
                                Assessments
                            </h4>
                            <div class="space-y-3">
                                ${assessments.map(assess => `
                                    <div class="p-3 rounded-lg bg-accent-info/5 border border-accent-info/20">
                                        <div class="flex items-center gap-2 mb-2">
                                            <span class="px-1.5 py-0.5 text-xs rounded bg-accent-info/20 text-accent-info">${assess.type || 'question'}</span>
                                            <span class="text-xs text-dark-500">Difficulty: ${Math.round((assess.difficulty || 0.5) * 100)}%</span>
                                        </div>
                                        <div class="font-medium text-dark-200 mb-2">${escapeHtml(assess.prompt || assess.spokenPrompt || '')}</div>
                                        ${assess.choices ? `
                                            <div class="space-y-1 ml-2">
                                                ${assess.choices.map(choice => `
                                                    <div class="flex items-center gap-2 text-sm ${choice.correct ? 'text-accent-success' : 'text-dark-400'}">
                                                        ${choice.correct ?
                                                            '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>' :
                                                            '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"></circle></svg>'
                                                        }
                                                        <span>${escapeHtml(choice.text || '')}</span>
                                                    </div>
                                                `).join('')}
                                            </div>
                                        ` : ''}
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    ` : ''}

                    <!-- Visual Assets -->
                    ${totalAssets > 0 ? `
                        <div>
                            <h4 class="text-sm font-medium text-dark-300 mb-3 flex items-center gap-2">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                                </svg>
                                Visual Assets (${totalAssets})
                            </h4>

                            <!-- Embedded Assets -->
                            ${embeddedAssets.length > 0 ? `
                                <div class="mb-4">
                                    <h5 class="text-xs font-medium text-dark-400 mb-2 uppercase tracking-wide">Embedded (${embeddedAssets.length})</h5>
                                    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                                        ${embeddedAssets.map(asset => renderAssetCard(asset)).join('')}
                                    </div>
                                </div>
                            ` : ''}

                            <!-- Reference Assets -->
                            ${referenceAssets.length > 0 ? `
                                <div>
                                    <h5 class="text-xs font-medium text-dark-400 mb-2 uppercase tracking-wide">Reference (${referenceAssets.length})</h5>
                                    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                                        ${referenceAssets.map(asset => renderAssetCard(asset)).join('')}
                                    </div>
                                </div>
                            ` : ''}
                        </div>
                    ` : ''}
                </div>
            </div>
        `;
        document.body.appendChild(modal);
    } catch (e) {
        console.error('Failed to load topic transcript:', e);
        alert('Failed to load transcript: ' + e.message);
    }
}

function renderAssetCard(asset) {
    const hasLocalPath = !!asset.localPath;
    // localPath is relative to project root (e.g., "curriculum/assets/renaissance/topic1/img1.jpg")
    const assetUrl = asset.localPath ? `/assets/${asset.localPath}` : asset.url;
    const isImage = asset.type === 'image' || asset.type === 'diagram' || asset.type === 'slideImage';

    return `
        <div class="rounded-lg border ${hasLocalPath ? 'border-accent-success/30 bg-accent-success/5' : 'border-dark-600 bg-dark-800/30'} p-2 text-xs">
            ${isImage && assetUrl ? `
                <div class="aspect-video rounded bg-dark-700 mb-2 overflow-hidden flex items-center justify-center">
                    <img src="${escapeHtml(assetUrl)}"
                         alt="${escapeHtml(asset.alt || asset.title || 'Asset')}"
                         class="max-w-full max-h-full object-contain"
                         onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                    <div class="hidden items-center justify-center w-full h-full text-dark-500 flex-col gap-1">
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
                        </svg>
                        <span>Load failed</span>
                    </div>
                </div>
            ` : `
                <div class="aspect-video rounded bg-dark-700 mb-2 flex items-center justify-center text-dark-400">
                    <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                    </svg>
                </div>
            `}
            <div class="font-medium text-dark-200 truncate" title="${escapeHtml(asset.title || asset.alt || 'Untitled')}">${escapeHtml(asset.title || asset.alt || 'Untitled')}</div>
            <div class="flex items-center gap-1 mt-1">
                <span class="px-1.5 py-0.5 rounded bg-dark-700/50 text-dark-400">${asset.type || 'image'}</span>
                ${hasLocalPath ? `
                    <span class="px-1.5 py-0.5 rounded bg-accent-success/20 text-accent-success flex items-center gap-0.5">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                        </svg>
                        cached
                    </span>
                ` : asset.url ? `
                    <span class="px-1.5 py-0.5 rounded bg-accent-warning/20 text-accent-warning">remote</span>
                ` : `
                    <span class="px-1.5 py-0.5 rounded bg-dark-600 text-dark-500">no source</span>
                `}
            </div>
            ${asset.segmentTiming ? `
                <div class="text-dark-500 mt-1">Segments ${asset.segmentTiming.startSegment + 1}-${asset.segmentTiming.endSegment + 1}</div>
            ` : ''}
        </div>
    `;
}

function getSegmentTypeBadge(type) {
    const badges = {
        'introduction': 'bg-accent-primary/20 text-accent-primary',
        'explanation': 'bg-dark-600 text-dark-300',
        'lecture': 'bg-accent-info/20 text-accent-info',
        'example': 'bg-accent-success/20 text-accent-success',
        'checkpoint': 'bg-accent-warning/20 text-accent-warning',
        'summary': 'bg-accent-info/20 text-accent-info',
        'transition': 'bg-dark-600 text-dark-400',
        'default': 'bg-dark-600 text-dark-300'
    };
    return badges[type] || badges.default;
}

function getSegmentTypeStyles(type) {
    const styles = {
        'introduction': 'bg-accent-primary/5 border-l-2 border-accent-primary',
        'explanation': 'bg-dark-800/30',
        'example': 'bg-accent-success/5 border-l-2 border-accent-success',
        'checkpoint': 'bg-accent-warning/5 border-l-2 border-accent-warning',
        'summary': 'bg-accent-info/5 border-l-2 border-accent-info',
        'transition': 'bg-dark-700/30',
        'default': 'bg-dark-800/30'
    };
    return styles[type] || styles.default;
}

// =============================================================================
// Clock Update
// =============================================================================

function updateClock() {
    const now = new Date();
    document.getElementById('current-time').textContent = now.toLocaleTimeString('en-US', { hour12: false });
}

// =============================================================================
// Initialization
// =============================================================================

async function init() {
    console.log('UnaMentis Management Console initializing...');

    // Initialize UI
    initTabs();
    initLogControls();
    initCharts();

    // Start clock
    updateClock();
    setInterval(updateClock, 1000);

    // Connect WebSocket
    connectWebSocket();

    // Initial data load
    await Promise.all([
        refreshStats(),
        refreshServers(),
        refreshClients()
    ]);

    // Update latency chart with any initial metrics
    if (state.metrics.length > 0) {
        updateLatencyChart(state.metrics);
    }

    // Start periodic updates
    state.updateInterval = setInterval(() => {
        refreshStats();
    }, 5000);

    console.log('UnaMentis Management Console ready');

    // Start import jobs polling
    startImportJobsPolling();
}

// =============================================================================
// Import Jobs Tracking
// =============================================================================

/**
 * Start polling for import job status updates
 */
function startImportJobsPolling() {
    // Initial fetch
    refreshImportJobs();

    // Poll every 2 seconds for active jobs
    state.importJobsPollingInterval = setInterval(() => {
        if (state.importJobs.some(job => ['queued', 'downloading', 'validating', 'extracting', 'enriching', 'generating'].includes(job.status))) {
            refreshImportJobs();
        }
    }, 2000);
}

/**
 * Fetch current import jobs from the server
 */
async function refreshImportJobs() {
    try {
        const response = await fetchAPI('/import/jobs');
        if (response.success) {
            state.importJobs = response.jobs || [];
            updateImportProgressIndicator();
        }
    } catch (e) {
        console.error('Failed to fetch import jobs:', e);
    }
}

/**
 * Update the import progress indicator in the header
 */
function updateImportProgressIndicator() {
    const container = document.getElementById('import-progress-indicator');
    if (!container) return;

    const activeJobs = state.importJobs.filter(job =>
        ['queued', 'downloading', 'validating', 'extracting', 'enriching', 'generating'].includes(job.status)
    );
    const completedJobs = state.importJobs.filter(job => job.status === 'complete');
    const failedJobs = state.importJobs.filter(job => job.status === 'failed');

    if (activeJobs.length === 0 && completedJobs.length === 0 && failedJobs.length === 0) {
        container.classList.add('hidden');
        return;
    }

    container.classList.remove('hidden');

    // Calculate overall progress for active jobs
    let overallProgress = 0;
    if (activeJobs.length > 0) {
        overallProgress = activeJobs.reduce((sum, job) => sum + (job.overallProgress || 0), 0) / activeJobs.length;
    }

    // Build status text
    let statusText = '';
    let statusClass = 'text-accent-info';
    let pulseClass = '';

    if (activeJobs.length > 0) {
        statusText = `${activeJobs.length} importing`;
        pulseClass = 'animate-pulse';
        statusClass = 'text-accent-warning';
    } else if (failedJobs.length > 0) {
        statusText = `${failedJobs.length} failed`;
        statusClass = 'text-accent-error';
    } else if (completedJobs.length > 0) {
        statusText = `${completedJobs.length} complete`;
        statusClass = 'text-accent-success';
    }

    container.innerHTML = `
        <button onclick="showImportJobsPanel()" class="flex items-center gap-2 px-2 sm:px-3 py-1 sm:py-1.5 rounded-full bg-dark-800/50 border border-dark-700/50 hover:border-accent-primary/50 transition-all cursor-pointer ${pulseClass}">
            <div class="relative">
                <svg class="w-4 h-4 ${statusClass}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                </svg>
                ${activeJobs.length > 0 ? `
                    <div class="absolute -top-1 -right-1 w-2 h-2 bg-accent-warning rounded-full animate-ping"></div>
                    <div class="absolute -top-1 -right-1 w-2 h-2 bg-accent-warning rounded-full"></div>
                ` : ''}
            </div>
            <span class="text-xs sm:text-sm ${statusClass}">${statusText}</span>
            ${activeJobs.length > 0 ? `
                <div class="w-16 h-1.5 bg-dark-700 rounded-full overflow-hidden hidden sm:block">
                    <div class="h-full bg-accent-warning rounded-full transition-all duration-300" style="width: ${overallProgress}%"></div>
                </div>
            ` : ''}
        </button>
    `;
}

/**
 * Show the import jobs panel/modal
 */
function showImportJobsPanel() {
    // Create modal if it doesn't exist
    let modal = document.getElementById('import-jobs-modal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'import-jobs-modal';
        modal.className = 'fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm';
        document.body.appendChild(modal);
    }

    modal.classList.remove('hidden');
    renderImportJobsPanel();
}

/**
 * Hide the import jobs panel
 */
function hideImportJobsPanel() {
    const modal = document.getElementById('import-jobs-modal');
    if (modal) {
        modal.classList.add('hidden');
    }
}

/**
 * Render the import jobs panel content
 */
function renderImportJobsPanel() {
    const modal = document.getElementById('import-jobs-modal');
    if (!modal) return;

    const activeJobs = state.importJobs.filter(job =>
        ['queued', 'downloading', 'validating', 'extracting', 'enriching', 'generating'].includes(job.status)
    );
    const completedJobs = state.importJobs.filter(job => job.status === 'complete');
    const failedJobs = state.importJobs.filter(job => job.status === 'failed');

    modal.innerHTML = `
        <div class="bg-dark-800 rounded-xl border border-dark-700 shadow-2xl w-full max-w-2xl max-h-[80vh] overflow-hidden" onclick="event.stopPropagation()">
            <!-- Header -->
            <div class="flex items-center justify-between px-6 py-4 border-b border-dark-700">
                <div class="flex items-center gap-3">
                    <svg class="w-6 h-6 text-accent-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                    </svg>
                    <h2 class="text-lg font-semibold text-dark-100">Import Jobs</h2>
                </div>
                <button onclick="hideImportJobsPanel()" class="p-2 rounded-lg hover:bg-dark-700 transition-colors">
                    <svg class="w-5 h-5 text-dark-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                    </svg>
                </button>
            </div>

            <!-- Content -->
            <div class="p-6 overflow-y-auto max-h-[60vh]">
                ${state.importJobs.length === 0 ? `
                    <div class="text-center py-12 text-dark-500">
                        <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"></path>
                        </svg>
                        <p>No import jobs</p>
                        <p class="text-sm mt-2">Go to Source Browser to import curricula</p>
                    </div>
                ` : `
                    <!-- Active Jobs -->
                    ${activeJobs.length > 0 ? `
                        <div class="mb-6">
                            <h3 class="text-sm font-medium text-dark-400 uppercase tracking-wider mb-3">Active (${activeJobs.length})</h3>
                            <div class="space-y-3">
                                ${activeJobs.map(job => renderImportJobCard(job)).join('')}
                            </div>
                        </div>
                    ` : ''}

                    <!-- Completed Jobs -->
                    ${completedJobs.length > 0 ? `
                        <div class="mb-6">
                            <h3 class="text-sm font-medium text-dark-400 uppercase tracking-wider mb-3">Completed (${completedJobs.length})</h3>
                            <div class="space-y-3">
                                ${completedJobs.map(job => renderImportJobCard(job)).join('')}
                            </div>
                        </div>
                    ` : ''}

                    <!-- Failed Jobs -->
                    ${failedJobs.length > 0 ? `
                        <div>
                            <h3 class="text-sm font-medium text-dark-400 uppercase tracking-wider mb-3">Failed (${failedJobs.length})</h3>
                            <div class="space-y-3">
                                ${failedJobs.map(job => renderImportJobCard(job)).join('')}
                            </div>
                        </div>
                    ` : ''}
                `}
            </div>

            <!-- Footer -->
            <div class="px-6 py-4 border-t border-dark-700 flex justify-between items-center">
                <button onclick="refreshImportJobs()" class="text-sm text-dark-400 hover:text-dark-200 flex items-center gap-2">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                    </svg>
                    Refresh
                </button>
                <button onclick="hideImportJobsPanel()" class="btn-secondary">Close</button>
            </div>
        </div>
    `;

    // Close on backdrop click
    modal.onclick = hideImportJobsPanel;
}

/**
 * Render a single import job card
 */
function renderImportJobCard(job) {
    const statusColors = {
        queued: 'text-dark-400',
        downloading: 'text-accent-warning',
        validating: 'text-accent-info',
        extracting: 'text-accent-info',
        enriching: 'text-accent-primary',
        generating: 'text-accent-primary',
        complete: 'text-accent-success',
        failed: 'text-accent-error',
        cancelled: 'text-dark-500'
    };

    const statusIcons = {
        queued: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>',
        downloading: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>',
        validating: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>',
        extracting: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"></path>',
        enriching: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"></path>',
        generating: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 4a2 2 0 114 0v1a1 1 0 001 1h3a1 1 0 011 1v3a1 1 0 01-1 1h-1a2 2 0 100 4h1a1 1 0 011 1v3a1 1 0 01-1 1h-3a1 1 0 01-1-1v-1a2 2 0 10-4 0v1a1 1 0 01-1 1H7a1 1 0 01-1-1v-3a1 1 0 00-1-1H4a2 2 0 110-4h1a1 1 0 001-1V7a1 1 0 011-1h3a1 1 0 001-1V4z"></path>',
        complete: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>',
        failed: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>',
        cancelled: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>'
    };

    const isActive = ['queued', 'downloading', 'validating', 'extracting', 'enriching', 'generating'].includes(job.status);
    const progress = job.overallProgress || 0;

    return `
        <div class="bg-dark-900/50 rounded-lg border border-dark-700/50 p-4">
            <div class="flex items-start justify-between gap-4">
                <div class="flex items-start gap-3 flex-1 min-w-0">
                    <div class="w-10 h-10 rounded-lg bg-dark-700/50 flex items-center justify-center flex-shrink-0 ${isActive ? 'animate-pulse' : ''}">
                        <svg class="w-5 h-5 ${statusColors[job.status] || 'text-dark-400'}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            ${statusIcons[job.status] || statusIcons.queued}
                        </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium text-dark-200 truncate">${escapeHtml(job.config?.courseId || job.id)}</div>
                        <div class="text-sm text-dark-500 truncate">${escapeHtml(job.currentActivity || job.currentStage || job.status)}</div>
                        ${job.config?.selectedLectures?.length ? `
                            <div class="text-xs text-dark-500 mt-1">${job.config.selectedLectures.length} lecture(s) selected</div>
                        ` : ''}
                    </div>
                </div>
                <div class="text-right flex-shrink-0">
                    <div class="text-sm font-medium ${statusColors[job.status] || 'text-dark-400'} capitalize">${job.status}</div>
                    ${isActive ? `<div class="text-xs text-dark-500">${Math.round(progress)}%</div>` : ''}
                </div>
            </div>
            ${isActive ? `
                <div class="mt-3">
                    <div class="w-full h-2 bg-dark-700 rounded-full overflow-hidden">
                        <div class="h-full bg-gradient-to-r from-accent-primary to-accent-secondary rounded-full transition-all duration-500" style="width: ${progress}%"></div>
                    </div>
                </div>
            ` : ''}
            ${job.error ? `
                <div class="mt-3 p-2 bg-accent-error/10 border border-accent-error/30 rounded text-sm text-accent-error">
                    ${escapeHtml(job.error)}
                </div>
            ` : ''}
        </div>
    `;
}

/**
 * Track a new import job by ID
 */
function trackImportJob(jobId) {
    // Immediately refresh to pick up the new job
    refreshImportJobs();
    showToast('Import started! Check progress in the header.', 'info');
}

// =============================================================================
// Import & Source Browser Functions
// =============================================================================

// Store file for upload
state.selectedFile = null;

function showImportModal() {
    document.getElementById('import-curriculum-modal').classList.remove('hidden');
}

function hideImportModal() {
    document.getElementById('import-curriculum-modal').classList.add('hidden');
    // Reset forms
    document.getElementById('import-url-form')?.reset();
    document.getElementById('import-paste-form')?.reset();
    document.getElementById('curriculum-file-input').value = '';
    document.getElementById('file-upload-text').textContent = 'Click or drag to upload .umcf file';
    document.getElementById('file-upload-btn').disabled = true;
    state.selectedFile = null;
}

function switchImportTab(tab) {
    // Update tab buttons
    document.querySelectorAll('.import-tab').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.importTab === tab);
    });
    // Show/hide tab content
    document.querySelectorAll('.import-tab-content').forEach(content => {
        content.classList.add('hidden');
    });
    document.getElementById(`import-tab-${tab}`).classList.remove('hidden');
}

async function importFromUrl(event) {
    event.preventDefault();
    const form = event.target;
    const url = form.url.value;

    try {
        showImportLoading('Importing from URL...');
        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ url: url })
        });
        hideImportModal();
        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import curriculum: ' + e.message, 'error');
    }
}

function handleFileSelect(event) {
    const file = event.target.files[0];
    if (file) {
        state.selectedFile = file;
        document.getElementById('file-upload-text').textContent = file.name;
        document.getElementById('file-upload-btn').disabled = false;
    }
}

async function importFromFile(event) {
    event.preventDefault();
    if (!state.selectedFile) return;

    try {
        const content = await state.selectedFile.text();
        const json = JSON.parse(content);

        showImportLoading('Importing file...');
        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ content: json })
        });
        hideImportModal();
        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import curriculum: ' + e.message, 'error');
    }
}

async function importFromPaste(event) {
    event.preventDefault();
    const form = event.target;
    const jsonText = form.json.value;

    try {
        const json = JSON.parse(jsonText);

        showImportLoading('Importing...');
        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ content: json })
        });
        hideImportModal();
        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        if (e instanceof SyntaxError) {
            showToast('Invalid JSON format', 'error');
        } else {
            showToast('Failed to import curriculum: ' + e.message, 'error');
        }
    }
}

function showImportLoading(message) {
    // Could add a loading overlay to the modal
    console.log(message);
}

// ============================================================================
// Source Browser Functions (Full Page Tab)
// ============================================================================

// State for sources
let mitOCWCourses = [];
let mitOCWSubjects = [];
let mitFilteredCourses = [];
let currentSourceId = null;

// Pagination state for MIT courses
let mitCurrentPage = 1;
let mitPageSize = 20;
let mitTotalPages = 1;

// Show source cards (initial view)
function showSourceCards() {
    document.getElementById('source-cards').classList.remove('hidden');
    document.getElementById('source-content-area').classList.add('hidden');
    currentSourceId = null;
}

// Select a source and show its content
async function selectSource(sourceId) {
    console.log('selectSource called with:', sourceId);
    currentSourceId = sourceId;

    // Hide source cards, show content area
    document.getElementById('source-cards').classList.add('hidden');
    document.getElementById('no-sources-message').classList.add('hidden');
    document.getElementById('source-content-area').classList.remove('hidden');

    // Hide all source views
    document.querySelectorAll('.source-view').forEach(v => v.classList.add('hidden'));
    console.log('All source views hidden');

    // Built-in sources that have special handling (not plugins)
    const builtinSources = ['github', 'custom'];

    if (builtinSources.includes(sourceId)) {
        // Use dedicated view for built-in sources
        console.log('Using builtin view for:', sourceId);
        const sourceView = document.getElementById(`source-view-${sourceId}`);
        if (sourceView) {
            sourceView.classList.remove('hidden');
        }
    } else {
        // ALL plugin sources use the generic view
        console.log('Using generic view for plugin:', sourceId);
        const genericView = document.getElementById('source-view-generic');
        genericView.classList.remove('hidden');
        console.log('Generic view is now visible');

        // Get plugin info to populate the generic view header
        try {
            const data = await fetchAPI('/plugins');
            if (data.success) {
                const plugin = data.plugins.find(p => p.plugin_id === sourceId);
                if (plugin) {
                    document.getElementById('generic-source-name').textContent = plugin.name;
                    document.getElementById('generic-source-desc').textContent = plugin.description;
                }
            }
        } catch (e) {
            console.error('Failed to fetch plugin info:', e);
        }

        // Load courses using the generic loader
        loadSourceCourses(sourceId);
    }

    // Update header info
    const headerInfo = document.getElementById('source-header-info');
    const builtinNames = {
        'github': 'GitHub',
        'custom': 'Custom URL'
    };

    if (builtinNames[sourceId]) {
        headerInfo.innerHTML = `<span class="text-lg font-semibold">${builtinNames[sourceId]}</span>`;
    } else {
        // For plugin sources, get the real name
        try {
            const data = await fetchAPI('/plugins');
            if (data.success) {
                const plugin = data.plugins.find(p => p.plugin_id === sourceId);
                if (plugin) {
                    headerInfo.innerHTML = `<span class="text-lg font-semibold">${escapeHtml(plugin.name)}</span>`;
                } else {
                    headerInfo.innerHTML = `<span class="text-lg font-semibold">${sourceId}</span>`;
                }
            }
        } catch (e) {
            headerInfo.innerHTML = `<span class="text-lg font-semibold">${sourceId}</span>`;
        }
    }
}

// Initialize sources tab when it becomes active
async function initSourcesTab() {
    await loadEnabledSources();
    showSourceCards();
}

// Load enabled plugin sources and render them as cards
async function loadEnabledSources() {
    const container = document.getElementById('plugin-sources-container');
    const noSourcesMsg = document.getElementById('no-sources-message');

    try {
        // Fetch enabled plugins
        const data = await fetchAPI('/plugins');
        if (!data.success) {
            console.error('Failed to fetch plugins');
            return;
        }

        // Filter to only enabled source plugins
        const enabledSources = data.plugins.filter(p => p.enabled && p.plugin_type === 'sources');

        if (enabledSources.length === 0) {
            container.innerHTML = '';
            noSourcesMsg.classList.remove('hidden');
            return;
        }

        noSourcesMsg.classList.add('hidden');

        // Render source cards for enabled plugins
        container.innerHTML = enabledSources.map(plugin => `
            <div class="source-card rounded-xl bg-dark-800/50 border border-dark-700/50 p-4 cursor-pointer hover:border-accent-primary/50 transition-all" onclick="selectSource('${plugin.plugin_id}')">
                <div class="flex items-start gap-4">
                    <div class="w-12 h-12 rounded-lg bg-accent-success/20 flex items-center justify-center flex-shrink-0">
                        <svg class="w-6 h-6 text-accent-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"></path>
                        </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                        <h3 class="font-semibold text-dark-100">${escapeHtml(plugin.name)}</h3>
                        <p class="text-sm text-dark-400 mt-1">${escapeHtml(plugin.description)}</p>
                        <div class="flex flex-wrap gap-2 mt-3">
                            ${plugin.license_type ? `<span class="px-2 py-0.5 text-xs rounded-full bg-accent-info/10 text-accent-info">${escapeHtml(plugin.license_type)}</span>` : ''}
                            <span class="px-2 py-0.5 text-xs rounded-full bg-accent-success/10 text-accent-success">v${plugin.version}</span>
                        </div>
                    </div>
                    <svg class="w-5 h-5 text-dark-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                    </svg>
                </div>
            </div>
        `).join('');

    } catch (e) {
        console.error('Failed to load enabled sources:', e);
    }
}

// Helper to switch to a different tab
function switchToTab(tabId) {
    const tab = document.querySelector(`[data-tab="${tabId}"]`);
    if (tab) {
        tab.click();
    }
}

// ============================================================================
// Generic Plugin UI Functions (Source-Agnostic)
// ============================================================================

// State for the current source being viewed (currentSourceId declared above at line 2523)
let currentSourceCourses = [];
let currentFilteredCourses = [];
let currentSourcePage = 1;
const COURSES_PER_PAGE = 20;

/**
 * Load courses for any enabled source plugin.
 * Uses the generic /api/sources/{source_id}/courses endpoint.
 */
async function loadSourceCourses(sourceId) {
    console.log('loadSourceCourses called with:', sourceId);
    currentSourceId = sourceId;

    // Get container elements
    const loadingEl = document.getElementById('generic-courses-loading');
    const emptyEl = document.getElementById('generic-courses-empty');
    const listEl = document.getElementById('generic-courses-list');
    const paginationEl = document.getElementById('generic-courses-pagination');

    // Show loading state
    if (loadingEl) loadingEl.classList.remove('hidden');
    if (emptyEl) emptyEl.classList.add('hidden');
    if (listEl) listEl.classList.add('hidden');
    if (paginationEl) paginationEl.classList.add('hidden');

    try {
        const response = await fetchAPI(`/sources/${sourceId}/courses?page=1&page_size=100`);

        currentSourceCourses = response.courses || [];

        // Populate filter dropdowns if available
        if (response.filters) {
            populateFilterDropdowns(response.filters);
        }

        // Initialize filtered courses and display
        currentFilteredCourses = currentSourceCourses;
        currentSourcePage = 1;
        renderGenericCoursesPage();

        if (loadingEl) loadingEl.classList.add('hidden');
    } catch (e) {
        console.error(`Failed to load courses for ${sourceId}:`, e);
        if (loadingEl) loadingEl.classList.add('hidden');
        if (listEl) {
            listEl.innerHTML = `
                <div class="text-center text-dark-500 py-12">
                    <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <p class="text-lg font-medium text-accent-danger">Failed to load courses</p>
                    <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
                    <button class="btn-secondary mt-4" onclick="loadSourceCourses('${escapeHtml(sourceId)}')">Try Again</button>
                </div>
            `;
            listEl.classList.remove('hidden');
        }
    }
}

/**
 * Populate filter dropdowns from API response.
 */
function populateFilterDropdowns(filters) {
    const subjectSelect = document.getElementById('generic-subject-filter');
    const levelSelect = document.getElementById('generic-level-filter');

    if (subjectSelect && filters.subjects) {
        subjectSelect.innerHTML = '<option value="">All Subjects</option>' +
            filters.subjects.map(s => `<option value="${escapeHtml(s)}">${escapeHtml(s)}</option>`).join('');
    }

    if (levelSelect && filters.levels) {
        levelSelect.innerHTML = '<option value="">All Levels</option>' +
            filters.levels.map(l => `<option value="${escapeHtml(l)}">${escapeHtml(l.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()))}</option>`).join('');
    }
}

/**
 * Filter courses based on search and filter inputs.
 */
function filterGenericCourses() {
    const searchInput = document.getElementById('generic-search-input');
    const subjectFilter = document.getElementById('generic-subject-filter');
    const levelFilter = document.getElementById('generic-level-filter');

    const search = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const subject = subjectFilter ? subjectFilter.value : '';
    const level = levelFilter ? levelFilter.value : '';

    let filtered = currentSourceCourses;

    // Filter by search term
    if (search) {
        filtered = filtered.filter(course =>
            course.title?.toLowerCase().includes(search) ||
            course.description?.toLowerCase().includes(search) ||
            course.instructors?.some(i => i.toLowerCase().includes(search)) ||
            course.keywords?.some(k => k.toLowerCase().includes(search))
        );
    }

    // Filter by subject/department
    if (subject) {
        filtered = filtered.filter(course => course.department === subject);
    }

    // Filter by level
    if (level) {
        filtered = filtered.filter(course => course.level === level);
    }

    currentFilteredCourses = filtered;
    currentSourcePage = 1;
    renderGenericCoursesPage();
}

/**
 * Render a page of courses with pagination.
 */
function renderGenericCoursesPage() {
    const listEl = document.getElementById('generic-courses-list');
    const emptyEl = document.getElementById('generic-courses-empty');
    const paginationEl = document.getElementById('generic-courses-pagination');

    if (!currentFilteredCourses || currentFilteredCourses.length === 0) {
        if (emptyEl) emptyEl.classList.remove('hidden');
        if (listEl) listEl.classList.add('hidden');
        if (paginationEl) paginationEl.classList.add('hidden');
        return;
    }

    if (emptyEl) emptyEl.classList.add('hidden');
    if (listEl) listEl.classList.remove('hidden');

    // Calculate pagination
    const totalPages = Math.ceil(currentFilteredCourses.length / COURSES_PER_PAGE);
    const start = (currentSourcePage - 1) * COURSES_PER_PAGE;
    const end = start + COURSES_PER_PAGE;
    const pageCourses = currentFilteredCourses.slice(start, end);

    // Render course list
    listEl.innerHTML = `
        <div class="mb-4 text-sm text-dark-400">${currentFilteredCourses.length} course${currentFilteredCourses.length !== 1 ? 's' : ''} available</div>
        <div class="space-y-3">
            ${pageCourses.map(course => renderCourseCard(course)).join('')}
        </div>
    `;

    // Render pagination
    if (paginationEl && totalPages > 1) {
        paginationEl.classList.remove('hidden');
        paginationEl.innerHTML = `
            <div class="flex items-center justify-between px-4 py-3 bg-dark-800/30 border border-dark-700/50 rounded-lg">
                <button class="btn-secondary text-sm ${currentSourcePage <= 1 ? 'opacity-50 cursor-not-allowed' : ''}"
                        onclick="goToGenericPage(${currentSourcePage - 1})"
                        ${currentSourcePage <= 1 ? 'disabled' : ''}>
                    Previous
                </button>
                <span class="text-sm text-dark-400">Page ${currentSourcePage} of ${totalPages}</span>
                <button class="btn-secondary text-sm ${currentSourcePage >= totalPages ? 'opacity-50 cursor-not-allowed' : ''}"
                        onclick="goToGenericPage(${currentSourcePage + 1})"
                        ${currentSourcePage >= totalPages ? 'disabled' : ''}>
                    Next
                </button>
            </div>
        `;
    } else if (paginationEl) {
        paginationEl.classList.add('hidden');
    }
}

/**
 * Navigate to a specific page.
 */
function goToGenericPage(page) {
    const totalPages = Math.ceil(currentFilteredCourses.length / COURSES_PER_PAGE);
    if (page < 1 || page > totalPages) return;
    currentSourcePage = page;
    renderGenericCoursesPage();
    scrollToGenericCoursesTop();
}

function scrollToGenericCoursesTop() {
    const container = document.getElementById('generic-courses-container');
    if (container) {
        container.scrollTop = 0;
    }
}

/**
 * Render a single course card.
 */
function renderCourseCard(course) {
    return `
        <div class="p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-accent-primary/50 transition-all cursor-pointer"
             onclick="viewGenericCourseDetail('${escapeHtml(currentSourceId)}', '${escapeHtml(course.id)}')">
            <div class="flex items-start justify-between gap-4">
                <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-1">
                        <h4 class="font-medium text-dark-200 truncate">${escapeHtml(course.title)}</h4>
                        ${course.level ? `<span class="px-2 py-0.5 text-xs rounded bg-accent-info/20 text-accent-info">${escapeHtml(course.level.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()))}</span>` : ''}
                    </div>
                    <div class="text-sm text-dark-400 mb-2">
                        ${course.department ? `<span class="mr-3">${escapeHtml(course.department)}</span>` : ''}
                        ${course.semester ? `<span class="text-dark-500">${escapeHtml(course.semester)}</span>` : ''}
                    </div>
                    ${course.instructors?.length ? `<div class="text-xs text-dark-500 mb-2">By: ${course.instructors.map(i => escapeHtml(i)).join(', ')}</div>` : ''}
                    ${course.description ? `<p class="text-sm text-dark-400 line-clamp-2 mb-2">${escapeHtml(course.description)}</p>` : ''}
                    <div class="flex flex-wrap gap-2">
                        ${(course.features || []).filter(f => f.available).map(f => `
                            <span class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">
                                ${getFeatureIcon(f.type)}
                                ${escapeHtml(f.type)}${f.count ? ` (${f.count})` : ''}
                            </span>
                        `).join('')}
                    </div>
                </div>
                <svg class="w-5 h-5 text-dark-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                </svg>
            </div>
        </div>
    `;
}

/**
 * View course detail using normalized API response.
 * Works with ANY source plugin.
 */
async function viewGenericCourseDetail(sourceId, courseId) {
    console.log('viewGenericCourseDetail called:', { sourceId, courseId });
    try {
        showToast('Loading course details...', 'info');
        const response = await fetchAPI(`/sources/${sourceId}/courses/${courseId}`);
        console.log('API response:', response);
        const course = response.course;

        // Hide pagination when viewing course details
        const paginationEl = document.getElementById('generic-courses-pagination');
        if (paginationEl) paginationEl.classList.add('hidden');

        // Render the detail view
        const container = document.getElementById('generic-courses-list');
        container.innerHTML = renderGenericCourseDetail(sourceId, course);
        container.classList.remove('hidden');
    } catch (e) {
        showToast('Failed to load course details: ' + e.message, 'error');
    }
}

/**
 * Render the course detail view using normalized data.
 */
function renderGenericCourseDetail(sourceId, course) {
    const contentStructure = course.contentStructure || {};
    const unitLabel = contentStructure.unitLabel || 'Unit';
    const topicLabel = contentStructure.topicLabel || 'Topic';
    const isFlat = contentStructure.isFlat || false;
    const units = contentStructure.units || [];

    // Calculate total topics
    const totalTopics = units.reduce((sum, u) => sum + (u.topics?.length || 0), 0);

    // Debug logging
    console.log('renderGenericCourseDetail:', {
        sourceId,
        courseId: course.id,
        unitLabel,
        topicLabel,
        isFlat,
        unitsCount: units.length,
        totalTopics,
        units: units.map(u => ({ id: u.id, title: u.title, topicsCount: u.topics?.length || 0 }))
    });

    return `
        <div class="mb-4">
            <button class="btn-secondary text-sm" onclick="renderGenericCoursesPage()">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
                </svg>
                Back to Courses
            </button>
        </div>
        <div class="rounded-lg bg-dark-800/50 border border-dark-700/50 overflow-hidden">
            <div class="flex items-center justify-between px-4 py-3 border-b border-dark-700/50 bg-dark-800/30">
                <h3 class="font-semibold text-dark-100">${escapeHtml(course.title)}</h3>
                <span class="px-2 py-0.5 text-xs rounded bg-accent-info/20 text-accent-info">${escapeHtml(course.levelLabel || course.level || 'N/A')}</span>
            </div>
            <div class="p-4 space-y-4">
                <div class="grid md:grid-cols-2 gap-4">
                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-1">Subject</h4>
                        <p class="text-dark-200">${escapeHtml(course.department || 'N/A')}</p>
                    </div>
                    ${course.semester ? `
                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-1">Semester</h4>
                        <p class="text-dark-200">${escapeHtml(course.semester)}</p>
                    </div>
                    ` : ''}
                </div>

                ${course.instructors?.length ? `
                <div>
                    <h4 class="text-sm font-medium text-dark-400 mb-1">By</h4>
                    <p class="text-dark-200">${course.instructors.map(i => escapeHtml(i)).join(', ')}</p>
                </div>
                ` : ''}

                <div>
                    <h4 class="text-sm font-medium text-dark-400 mb-1">Description</h4>
                    <p class="text-dark-200">${escapeHtml(course.description || 'No description available')}</p>
                </div>

                <div>
                    <h4 class="text-sm font-medium text-dark-400 mb-2">Available Content</h4>
                    <div class="flex flex-wrap gap-2">
                        ${(course.features || []).map(f => `
                            <span class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg ${f.available ? 'bg-accent-success/10 text-accent-success border border-accent-success/20' : 'bg-dark-800/50 text-dark-500 border border-dark-700/50'}">
                                ${getFeatureIcon(f.type)}
                                ${escapeHtml(f.type.replace(/_/g, ' '))}
                                ${f.count ? `<span class="text-xs opacity-75">(${f.count})</span>` : ''}
                            </span>
                        `).join('')}
                    </div>
                </div>

                ${course.keywords?.length ? `
                <div>
                    <h4 class="text-sm font-medium text-dark-400 mb-2">Keywords</h4>
                    <div class="flex flex-wrap gap-1">
                        ${course.keywords.map(k => `<span class="px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">${escapeHtml(k)}</span>`).join('')}
                    </div>
                </div>
                ` : ''}

                <div class="border-t border-dark-700/50 pt-4">
                    <h4 class="text-sm font-medium text-dark-400 mb-2">License</h4>
                    <div class="flex items-center gap-2 text-sm">
                        <span class="px-2 py-1 rounded bg-accent-info/10 text-accent-info border border-accent-info/20">${escapeHtml(course.license?.name || 'Unknown')}</span>
                        ${course.license?.holder ? `<span class="text-dark-400">by ${escapeHtml(course.license.holder.name)}</span>` : ''}
                    </div>
                </div>

                <!-- Content Selection using normalized structure -->
                ${totalTopics > 0 ? `
                <div class="border-t border-dark-700/50 pt-4">
                    <div class="flex items-center justify-between mb-3">
                        <h4 class="text-sm font-medium text-dark-400">Select ${isFlat ? topicLabel + 's' : unitLabel + 's (' + topicLabel + 's)'} to Import</h4>
                        <div class="flex items-center gap-2">
                            <span id="content-selection-count" class="text-xs text-dark-500">0 of ${totalTopics} selected</span>
                            ${!isFlat ? `<button class="text-xs text-dark-400 hover:text-dark-300" onclick="expandAllUnits()">Expand All</button><span class="text-dark-600">|</span>` : ''}
                            <button class="text-xs text-accent-primary hover:text-accent-primary/80" onclick="selectAllGenericContent(true)">Select All</button>
                            <span class="text-dark-600">|</span>
                            <button class="text-xs text-dark-400 hover:text-dark-300" onclick="selectAllGenericContent(false)">Clear</button>
                        </div>
                    </div>
                    <div class="max-h-80 overflow-y-auto rounded-lg border border-dark-700/50 bg-dark-900/50">
                        ${renderContentStructure(units, unitLabel, topicLabel, isFlat)}
                    </div>
                    <p class="text-xs text-dark-500 mt-2">Tip: Click on a ${unitLabel.toLowerCase()} to expand/collapse. Start with a few ${topicLabel.toLowerCase()}s to evaluate the content.</p>
                </div>
                ` : `
                <div class="border-t border-dark-700/50 pt-4">
                    <div class="flex items-center gap-3 p-4 rounded-lg bg-accent-warning/10 border border-accent-warning/20">
                        <svg class="w-6 h-6 text-accent-warning flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
                        </svg>
                        <div>
                            <h4 class="text-sm font-medium text-accent-warning">Content Structure Not Available</h4>
                            <p class="text-sm text-dark-400 mt-1">This course does not have detailed chapter/lesson data in our catalog. You can still import the entire course using the button below, which will download all available content.</p>
                        </div>
                    </div>
                </div>
                `}

                <div class="border-t border-dark-700/50 pt-4">
                    <h4 class="text-sm font-medium text-dark-400 mb-2">AI Enrichment Options</h4>
                    <div class="space-y-2">
                        <label class="flex items-center gap-2 cursor-pointer">
                            <input type="checkbox" id="import-opt-objectives" checked class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                            <span class="text-sm text-dark-300">Generate learning objectives</span>
                        </label>
                        <label class="flex items-center gap-2 cursor-pointer">
                            <input type="checkbox" id="import-opt-checkpoints" checked class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                            <span class="text-sm text-dark-300">Generate knowledge checkpoints</span>
                        </label>
                        <label class="flex items-center gap-2 cursor-pointer">
                            <input type="checkbox" id="import-opt-spoken" class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                            <span class="text-sm text-dark-300">Generate spoken text from notes</span>
                        </label>
                    </div>
                </div>

                <div class="flex gap-2 pt-2">
                    <button class="btn-primary flex-1" onclick="importGenericCourse('${escapeHtml(sourceId)}', '${escapeHtml(course.id)}')">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                        </svg>
                        ${totalTopics > 0 ? 'Import Selected' : 'Import Entire Course'}
                    </button>
                    ${course.sourceUrl ? `
                    <a href="${escapeHtml(course.sourceUrl)}" target="_blank" rel="noopener" class="btn-secondary">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                        </svg>
                        View Source
                    </a>
                    ` : ''}
                </div>
            </div>
        </div>
    `;
}

/**
 * Render the content structure (units and topics) for selection.
 */
function renderContentStructure(units, unitLabel, topicLabel, isFlat) {
    if (isFlat && units.length === 1) {
        // Flat structure: just show topics directly
        const topics = units[0].topics || [];
        return `
            <div class="divide-y divide-dark-700/30">
                ${topics.map((topic, idx) => renderTopicCheckbox(topic, topicLabel)).join('')}
            </div>
        `;
    }

    // Nested structure: show units with collapsible topics
    // First unit is expanded by default so users see there are selectable items
    return `
        <div class="divide-y divide-dark-700/30">
            ${units.map((unit, unitIdx) => `
                <div class="bg-dark-800/20">
                    <div class="flex items-center gap-2 px-3 py-2 bg-dark-700/30 cursor-pointer" onclick="toggleUnitExpand(${unitIdx})">
                        <svg id="unit-chevron-${unitIdx}" class="w-4 h-4 text-dark-500 transform transition-transform ${unitIdx === 0 ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                        </svg>
                        <input type="checkbox" class="unit-checkbox rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary"
                               data-unit-idx="${unitIdx}"
                               onchange="toggleUnitSelection(${unitIdx}); event.stopPropagation();">
                        <span class="text-sm font-medium text-dark-300">${unitLabel} ${unit.number}: ${escapeHtml(unit.title)}</span>
                        <span class="text-xs text-dark-500 ml-auto">${unit.topics?.length || 0} ${topicLabel.toLowerCase()}${(unit.topics?.length || 0) !== 1 ? 's' : ''}</span>
                    </div>
                    <div id="unit-topics-${unitIdx}" class="${unitIdx === 0 ? '' : 'hidden '}pl-6">
                        ${(unit.topics || []).map(topic => renderTopicCheckbox(topic, topicLabel, unitIdx)).join('')}
                    </div>
                </div>
            `).join('')}
        </div>
    `;
}

/**
 * Render a topic checkbox.
 */
function renderTopicCheckbox(topic, topicLabel, unitIdx = null) {
    return `
        <label class="flex items-center gap-3 px-3 py-2 hover:bg-dark-800/50 cursor-pointer transition-colors">
            <input type="checkbox" class="content-checkbox rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary"
                   data-content-id="${escapeHtml(topic.id)}"
                   data-unit-idx="${unitIdx !== null ? unitIdx : ''}"
                   onchange="updateGenericSelectionCount()">
            <span class="flex-1 flex items-center gap-2">
                ${topic.number ? `<span class="text-xs text-dark-500 w-6">${topic.number}.</span>` : ''}
                <span class="text-sm text-dark-200">${escapeHtml(topic.title)}</span>
            </span>
            <span class="flex items-center gap-1 text-dark-500">
                ${topic.hasVideo ? '<span title="Video available" class="text-accent-info">🎥</span>' : ''}
                ${topic.hasTranscript ? '<span title="Transcript available" class="text-accent-success">📝</span>' : ''}
                ${topic.hasPractice ? '<span title="Practice available" class="text-accent-warning">📝</span>' : ''}
            </span>
        </label>
    `;
}

/**
 * Toggle unit expansion.
 */
function toggleUnitExpand(unitIdx) {
    const topicsDiv = document.getElementById(`unit-topics-${unitIdx}`);
    const chevron = document.getElementById(`unit-chevron-${unitIdx}`);
    if (topicsDiv) {
        topicsDiv.classList.toggle('hidden');
    }
    if (chevron) {
        chevron.classList.toggle('rotate-90');
    }
}

/**
 * Expand all units to show all topics.
 */
function expandAllUnits() {
    // Find all unit topic containers and expand them
    let idx = 0;
    while (true) {
        const topicsDiv = document.getElementById(`unit-topics-${idx}`);
        const chevron = document.getElementById(`unit-chevron-${idx}`);
        if (!topicsDiv) break;
        topicsDiv.classList.remove('hidden');
        if (chevron) chevron.classList.add('rotate-90');
        idx++;
    }
}

/**
 * Toggle all topics in a unit when unit checkbox changes.
 */
function toggleUnitSelection(unitIdx) {
    const unitCheckbox = document.querySelector(`.unit-checkbox[data-unit-idx="${unitIdx}"]`);
    const topicCheckboxes = document.querySelectorAll(`.content-checkbox[data-unit-idx="${unitIdx}"]`);
    topicCheckboxes.forEach(cb => cb.checked = unitCheckbox.checked);
    updateGenericSelectionCount();
}

/**
 * Select/deselect all content.
 */
function selectAllGenericContent(checked) {
    const checkboxes = document.querySelectorAll('.content-checkbox');
    const unitCheckboxes = document.querySelectorAll('.unit-checkbox');
    checkboxes.forEach(cb => cb.checked = checked);
    unitCheckboxes.forEach(cb => cb.checked = checked);
    updateGenericSelectionCount();
}

/**
 * Update selection count display.
 */
function updateGenericSelectionCount() {
    const checkboxes = document.querySelectorAll('.content-checkbox');
    const checked = document.querySelectorAll('.content-checkbox:checked');
    const countEl = document.getElementById('content-selection-count');
    if (countEl) {
        countEl.textContent = `${checked.length} of ${checkboxes.length} selected`;
    }

    // Update unit checkbox states
    const unitCheckboxes = document.querySelectorAll('.unit-checkbox');
    unitCheckboxes.forEach(unitCb => {
        const unitIdx = unitCb.dataset.unitIdx;
        const unitTopics = document.querySelectorAll(`.content-checkbox[data-unit-idx="${unitIdx}"]`);
        const unitChecked = document.querySelectorAll(`.content-checkbox[data-unit-idx="${unitIdx}"]:checked`);
        unitCb.checked = unitTopics.length > 0 && unitTopics.length === unitChecked.length;
        unitCb.indeterminate = unitChecked.length > 0 && unitChecked.length < unitTopics.length;
    });
}

/**
 * Get selected content IDs.
 */
function getSelectedGenericContent() {
    const checked = document.querySelectorAll('.content-checkbox:checked');
    return Array.from(checked).map(cb => cb.dataset.contentId);
}

/**
 * Import a course using the generic API.
 */
async function importGenericCourse(sourceId, courseId) {
    const selectedContent = getSelectedGenericContent();

    if (selectedContent.length === 0) {
        showToast('Please select at least one item to import', 'warning');
        return;
    }

    try {
        showToast(`Importing ${selectedContent.length} item(s)...`, 'info');

        const response = await fetchAPI(`/sources/${sourceId}/courses/${courseId}/import`, {
            method: 'POST',
            body: JSON.stringify({
                selectedContent: selectedContent,
            }),
        });

        if (response.success) {
            showToast('Import started successfully!', 'success');
        } else {
            showToast('Import failed: ' + (response.error || 'Unknown error'), 'error');
        }
    } catch (e) {
        showToast('Import failed: ' + e.message, 'error');
    }
}

// ============================================================================
// MIT OpenCourseWare Functions
// ============================================================================

async function loadMITCourses() {
    // Show loading state
    document.getElementById('mit-courses-loading').classList.remove('hidden');
    document.getElementById('mit-courses-empty').classList.add('hidden');
    document.getElementById('mit-courses-list').classList.add('hidden');

    try {
        const response = await fetchAPI('/import/sources/mit_ocw/courses');
        mitOCWCourses = response.courses || [];

        // Extract unique subjects for filter dropdown
        const subjects = new Set();
        mitOCWCourses.forEach(course => {
            if (course.department) subjects.add(course.department);
        });
        mitOCWSubjects = Array.from(subjects).sort();

        // Populate subject dropdown
        const subjectSelect = document.getElementById('mit-subject-filter');
        if (subjectSelect) {
            subjectSelect.innerHTML = '<option value="">All Subjects</option>' +
                mitOCWSubjects.map(s => `<option value="${escapeHtml(s)}">${escapeHtml(s)}</option>`).join('');
        }

        // Initialize filtered courses and display
        mitFilteredCourses = mitOCWCourses;
        mitCurrentPage = 1;
        renderMITCoursesPage();
    } catch (e) {
        console.error('Failed to load MIT OCW courses:', e);
        document.getElementById('mit-courses-loading').classList.add('hidden');
        document.getElementById('mit-courses-list').innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Failed to load MIT OCW courses</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
                <button class="btn-secondary mt-4" onclick="loadMITCourses()">Try Again</button>
            </div>
        `;
        document.getElementById('mit-courses-list').classList.remove('hidden');
    }
}

function filterMITCourses() {
    const search = document.getElementById('mit-search-input').value.toLowerCase().trim();
    const subject = document.getElementById('mit-subject-filter').value;
    const level = document.getElementById('mit-level-filter').value;

    let filtered = mitOCWCourses;

    // Filter by search term
    if (search) {
        filtered = filtered.filter(course =>
            course.title.toLowerCase().includes(search) ||
            course.description?.toLowerCase().includes(search) ||
            course.instructors?.some(i => i.toLowerCase().includes(search)) ||
            course.keywords?.some(k => k.toLowerCase().includes(search))
        );
    }

    // Filter by subject
    if (subject) {
        filtered = filtered.filter(course => course.department === subject);
    }

    // Filter by level
    if (level) {
        filtered = filtered.filter(course => course.level?.toLowerCase().includes(level));
    }

    // Store filtered results and reset to page 1
    mitFilteredCourses = filtered;
    mitCurrentPage = 1;
    renderMITCoursesPage();
}

function renderMITCoursesList(courses) {
    document.getElementById('mit-courses-loading').classList.add('hidden');

    if (!courses || courses.length === 0) {
        document.getElementById('mit-courses-empty').classList.remove('hidden');
        document.getElementById('mit-courses-list').classList.add('hidden');
        return;
    }

    document.getElementById('mit-courses-empty').classList.add('hidden');
    const container = document.getElementById('mit-courses-list');

    container.innerHTML = `
        <div class="mb-4 text-sm text-dark-400">${courses.length} course${courses.length !== 1 ? 's' : ''} available</div>
        <div class="space-y-3">
            ${courses.map(course => `
                <div class="p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-accent-primary/50 transition-all cursor-pointer" onclick="viewMITCourseDetail('${escapeHtml(course.id)}')">
                    <div class="flex items-start justify-between gap-4">
                        <div class="flex-1 min-w-0">
                            <div class="flex items-center gap-2 mb-1">
                                <h4 class="font-medium text-dark-200 truncate">${escapeHtml(course.title)}</h4>
                                ${course.level ? `<span class="px-2 py-0.5 text-xs rounded ${course.level.toLowerCase().includes('graduate') ? 'bg-accent-secondary/20 text-accent-secondary' : 'bg-accent-info/20 text-accent-info'}">${escapeHtml(course.level)}</span>` : ''}
                            </div>
                            <div class="text-sm text-dark-400 mb-2">
                                ${course.department ? `<span class="mr-3">${escapeHtml(course.department)}</span>` : ''}
                                ${course.semester ? `<span class="text-dark-500">${escapeHtml(course.semester)}</span>` : ''}
                            </div>
                            ${course.instructors?.length ? `<div class="text-xs text-dark-500 mb-2">Instructors: ${course.instructors.map(i => escapeHtml(i)).join(', ')}</div>` : ''}
                            ${course.description ? `<p class="text-sm text-dark-400 line-clamp-2 mb-2">${escapeHtml(course.description)}</p>` : ''}
                            <div class="flex flex-wrap gap-2">
                                ${(course.features || []).filter(f => f.available).map(f => `
                                    <span class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">
                                        ${getFeatureIcon(f.type)}
                                        ${escapeHtml(f.type)}${f.count ? ` (${f.count})` : ''}
                                    </span>
                                `).join('')}
                            </div>
                        </div>
                        <div class="flex-shrink-0">
                            <svg class="w-5 h-5 text-dark-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                            </svg>
                        </div>
                    </div>
                </div>
            `).join('')}
        </div>
    `;

    container.classList.remove('hidden');
}

function getFeatureIcon(type) {
    const icons = {
        'video_lectures': '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"></path></svg>',
        'lecture_notes': '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>',
        'assignments': '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"></path></svg>',
        'exams': '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>',
        'transcripts': '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"></path></svg>'
    };
    return icons[type] || '<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>';
}

// ============================================================================
// MIT OCW Pagination Functions
// ============================================================================

function renderMITCoursesPage() {
    const total = mitFilteredCourses.length;

    if (total === 0) {
        document.getElementById('mit-courses-loading').classList.add('hidden');
        document.getElementById('mit-courses-empty').classList.remove('hidden');
        document.getElementById('mit-courses-list').classList.add('hidden');
        document.getElementById('mit-courses-pagination').classList.add('hidden');
        return;
    }

    // Calculate pagination
    mitTotalPages = Math.ceil(total / mitPageSize);
    if (mitCurrentPage > mitTotalPages) {
        mitCurrentPage = mitTotalPages;
    }

    const start = (mitCurrentPage - 1) * mitPageSize;
    const end = Math.min(start + mitPageSize, total);
    const pageItems = mitFilteredCourses.slice(start, end);

    // Render the page of courses
    renderMITCoursesList(pageItems);

    // Update pagination controls
    updateMITPagination(start + 1, end, total);
}

function updateMITPagination(start, end, total) {
    // Update info text
    document.getElementById('mit-page-start').textContent = start;
    document.getElementById('mit-page-end').textContent = end;
    document.getElementById('mit-total-count').textContent = total;
    document.getElementById('mit-current-page').textContent = mitCurrentPage;
    document.getElementById('mit-total-pages').textContent = mitTotalPages;

    // Update button states
    const prevBtn = document.getElementById('mit-prev-page');
    const nextBtn = document.getElementById('mit-next-page');

    prevBtn.disabled = mitCurrentPage <= 1;
    nextBtn.disabled = mitCurrentPage >= mitTotalPages;

    // Show pagination if there are courses
    document.getElementById('mit-courses-pagination').classList.remove('hidden');
}

function mitPrevPage() {
    if (mitCurrentPage > 1) {
        mitCurrentPage--;
        renderMITCoursesPage();
        scrollToMITCoursesTop();
    }
}

function mitNextPage() {
    if (mitCurrentPage < mitTotalPages) {
        mitCurrentPage++;
        renderMITCoursesPage();
        scrollToMITCoursesTop();
    }
}

function changeMITPageSize() {
    const select = document.getElementById('mit-page-size');
    mitPageSize = parseInt(select.value, 10);
    mitCurrentPage = 1;
    renderMITCoursesPage();
}

function scrollToMITCoursesTop() {
    const container = document.getElementById('mit-courses-container');
    if (container) {
        container.scrollTop = 0;
    }
}

async function viewMITCourseDetail(courseId) {
    try {
        showToast('Loading course details...', 'info');
        const response = await fetchAPI(`/import/sources/mit_ocw/courses/${courseId}`);
        const course = response.course;

        // Hide pagination when viewing course details
        document.getElementById('mit-courses-pagination').classList.add('hidden');

        // Display course detail in the courses list area
        const container = document.getElementById('mit-courses-list');
        container.innerHTML = `
            <div class="mb-4">
                <button class="btn-secondary text-sm" onclick="renderMITCoursesPage()">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
                    </svg>
                    Back to Courses
                </button>
            </div>
            <div class="rounded-lg bg-dark-800/50 border border-dark-700/50 overflow-hidden">
                <div class="flex items-center justify-between px-4 py-3 border-b border-dark-700/50 bg-dark-800/30">
                    <h3 class="font-semibold text-dark-100">${escapeHtml(course.title)}</h3>
                    <span class="px-2 py-0.5 text-xs rounded ${course.level?.toLowerCase().includes('graduate') ? 'bg-accent-secondary/20 text-accent-secondary' : 'bg-accent-info/20 text-accent-info'}">${escapeHtml(course.level || 'N/A')}</span>
                </div>
                <div class="p-4 space-y-4">
                    <div class="grid md:grid-cols-2 gap-4">
                        <div>
                            <h4 class="text-sm font-medium text-dark-400 mb-1">Department</h4>
                            <p class="text-dark-200">${escapeHtml(course.department || 'N/A')}</p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-dark-400 mb-1">Semester</h4>
                            <p class="text-dark-200">${escapeHtml(course.semester || 'N/A')}</p>
                        </div>
                    </div>

                    ${course.instructors?.length ? `
                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-1">Instructors</h4>
                        <p class="text-dark-200">${course.instructors.map(i => escapeHtml(i)).join(', ')}</p>
                    </div>
                    ` : ''}

                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-1">Description</h4>
                        <p class="text-dark-200">${escapeHtml(course.description || 'No description available')}</p>
                    </div>

                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-2">Available Content</h4>
                        <div class="flex flex-wrap gap-2">
                            ${(course.features || []).map(f => `
                                <span class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg ${f.available ? 'bg-accent-success/10 text-accent-success border border-accent-success/20' : 'bg-dark-800/50 text-dark-500 border border-dark-700/50'}">
                                    ${getFeatureIcon(f.type)}
                                    ${escapeHtml(f.type.replace(/_/g, ' '))}
                                    ${f.count ? `<span class="text-xs opacity-75">(${f.count})</span>` : ''}
                                </span>
                            `).join('')}
                        </div>
                    </div>

                    ${course.keywords?.length ? `
                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-2">Keywords</h4>
                        <div class="flex flex-wrap gap-1">
                            ${course.keywords.map(k => `<span class="px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">${escapeHtml(k)}</span>`).join('')}
                        </div>
                    </div>
                    ` : ''}

                    <div class="border-t border-dark-700/50 pt-4">
                        <h4 class="text-sm font-medium text-dark-400 mb-2">License</h4>
                        <div class="flex items-center gap-2 text-sm">
                            <span class="px-2 py-1 rounded bg-accent-info/10 text-accent-info border border-accent-info/20">${escapeHtml(course.license?.name || 'CC-BY-NC-SA 4.0')}</span>
                            ${course.license?.holder ? `<span class="text-dark-400">by ${escapeHtml(course.license.holder.name)}</span>` : ''}
                        </div>
                    </div>

                    <!-- Lecture Selection -->
                    ${course.lectures?.length ? `
                    <div class="border-t border-dark-700/50 pt-4">
                        <div class="flex items-center justify-between mb-3">
                            <h4 class="text-sm font-medium text-dark-400">Select Lectures to Import</h4>
                            <div class="flex items-center gap-2">
                                <span id="lecture-selection-count" class="text-xs text-dark-500">0 of ${course.lectures.length} selected</span>
                                <button class="text-xs text-accent-primary hover:text-accent-primary/80" onclick="selectAllLectures(true)">Select All</button>
                                <span class="text-dark-600">|</span>
                                <button class="text-xs text-dark-400 hover:text-dark-300" onclick="selectAllLectures(false)">Clear</button>
                            </div>
                        </div>
                        <div class="max-h-64 overflow-y-auto rounded-lg border border-dark-700/50 bg-dark-900/50">
                            <div class="divide-y divide-dark-700/30">
                                ${course.lectures.map((lec, idx) => `
                                    <label class="flex items-center gap-3 px-3 py-2 hover:bg-dark-800/50 cursor-pointer transition-colors">
                                        <input type="checkbox" class="lecture-checkbox rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary"
                                               data-lecture-id="${escapeHtml(lec.id)}"
                                               data-lecture-num="${lec.number}"
                                               onchange="updateLectureSelectionCount()">
                                        <span class="flex-1 flex items-center gap-2">
                                            <span class="text-xs text-dark-500 w-6">${lec.number}.</span>
                                            <span class="text-sm text-dark-200">${escapeHtml(lec.title)}</span>
                                        </span>
                                        <span class="flex items-center gap-1 text-dark-500">
                                            ${lec.hasVideo ? '<span title="Video available" class="text-accent-info">🎥</span>' : ''}
                                            ${lec.hasTranscript ? '<span title="Transcript available" class="text-accent-success">📝</span>' : ''}
                                            ${lec.hasNotes ? '<span title="Notes available" class="text-accent-warning">📄</span>' : ''}
                                        </span>
                                        ${lec.videoUrl ? `<a href="${escapeHtml(lec.videoUrl)}" target="_blank" rel="noopener" class="text-xs text-accent-primary hover:underline" onclick="event.stopPropagation()">Watch</a>` : ''}
                                    </label>
                                `).join('')}
                            </div>
                        </div>
                        <p class="text-xs text-dark-500 mt-2">💡 Tip: Start with 1-2 lectures to evaluate the content before importing the full course.</p>
                    </div>
                    ` : ''}

                    <div class="border-t border-dark-700/50 pt-4">
                        <h4 class="text-sm font-medium text-dark-400 mb-2">AI Enrichment Options</h4>
                        <div class="space-y-2">
                            <label class="flex items-center gap-2 cursor-pointer">
                                <input type="checkbox" id="import-opt-objectives" checked class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                                <span class="text-sm text-dark-300">Generate learning objectives</span>
                            </label>
                            <label class="flex items-center gap-2 cursor-pointer">
                                <input type="checkbox" id="import-opt-checkpoints" checked class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                                <span class="text-sm text-dark-300">Generate knowledge checkpoints</span>
                            </label>
                            <label class="flex items-center gap-2 cursor-pointer">
                                <input type="checkbox" id="import-opt-spoken" class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                                <span class="text-sm text-dark-300">Generate spoken text from notes</span>
                            </label>
                        </div>
                    </div>

                    <div class="flex gap-2 pt-2">
                        <button class="btn-primary flex-1" onclick="importMITCourse('${escapeHtml(course.id)}')">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                            </svg>
                            Import Selected
                        </button>
                        <a href="${course.downloadUrl || 'https://ocw.mit.edu'}" target="_blank" rel="noopener" class="btn-secondary">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                            </svg>
                            View on OCW
                        </a>
                    </div>
                </div>
            </div>
        `;
    } catch (e) {
        showToast('Failed to load course details: ' + e.message, 'error');
    }
}

// Lecture selection helpers
function selectAllLectures(checked) {
    const checkboxes = document.querySelectorAll('.lecture-checkbox');
    checkboxes.forEach(cb => cb.checked = checked);
    updateLectureSelectionCount();
}

function updateLectureSelectionCount() {
    const checkboxes = document.querySelectorAll('.lecture-checkbox');
    const checked = document.querySelectorAll('.lecture-checkbox:checked');
    const countEl = document.getElementById('lecture-selection-count');
    if (countEl) {
        countEl.textContent = `${checked.length} of ${checkboxes.length} selected`;
    }
}

function getSelectedLectures() {
    const checked = document.querySelectorAll('.lecture-checkbox:checked');
    return Array.from(checked).map(cb => ({
        id: cb.dataset.lectureId,
        number: parseInt(cb.dataset.lectureNum)
    }));
}

async function importMITCourse(courseId) {
    // Get selected lectures
    const selectedLectures = getSelectedLectures();

    if (selectedLectures.length === 0) {
        showToast('Please select at least one lecture to import', 'warning');
        return;
    }

    const options = {
        generate_objectives: document.getElementById('import-opt-objectives')?.checked ?? true,
        generate_checkpoints: document.getElementById('import-opt-checkpoints')?.checked ?? true,
        generate_spoken_text: document.getElementById('import-opt-spoken')?.checked ?? false
    };

    try {
        showToast(`Starting import of ${selectedLectures.length} lecture(s)...`, 'info');
        const response = await fetchAPI('/import/jobs', {
            method: 'POST',
            body: JSON.stringify({
                sourceId: 'mit_ocw',
                courseId: courseId,
                outputName: courseId,  // Default to course ID
                selectedLectures: selectedLectures.map(l => l.id),
                includeTranscripts: true,
                includeLectureNotes: true,
                includeAssignments: true,
                includeExams: true,
                includeVideos: false,
                generateObjectives: options.generate_objectives,
                createCheckpoints: options.generate_checkpoints,
                generateSpokenText: options.generate_spoken_text,
                buildKnowledgeGraph: true,
                generatePracticeProblems: false
            })
        });

        // Track the new import job and update UI
        trackImportJob(response.jobId);

        // Go back to course list and refresh curricula
        renderMITCoursesPage();
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import course: ' + e.message, 'error');
    }
}

// ============================================================================
// CK-12 FlexBooks Functions
// ============================================================================

let ck12Courses = [];
let ck12FilteredCourses = [];

async function loadCK12Courses() {
    // Show loading state
    document.getElementById('ck12-courses-loading').classList.remove('hidden');
    document.getElementById('ck12-courses-empty').classList.add('hidden');
    document.getElementById('ck12-courses-list').classList.add('hidden');

    try {
        const response = await fetchAPI('/import/sources/ck12_flexbook/courses');

        ck12Courses = response.courses || [];

        document.getElementById('ck12-courses-loading').classList.add('hidden');

        if (ck12Courses.length === 0) {
            document.getElementById('ck12-courses-empty').classList.remove('hidden');
            return;
        }

        // Initialize filtered courses and display
        ck12FilteredCourses = ck12Courses;
        renderCK12Courses();
    } catch (e) {
        console.error('Failed to load CK-12 courses:', e);
        document.getElementById('ck12-courses-loading').classList.add('hidden');
        document.getElementById('ck12-courses-list').innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Failed to load CK-12 content</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
                <button class="btn-secondary mt-4" onclick="loadCK12Courses()">Try Again</button>
            </div>
        `;
        document.getElementById('ck12-courses-list').classList.remove('hidden');
    }
}

function filterCK12Courses() {
    const search = document.getElementById('ck12-search-input').value.toLowerCase().trim();
    const subject = document.getElementById('ck12-subject-filter').value;

    let filtered = ck12Courses;

    if (search) {
        filtered = filtered.filter(c =>
            c.title?.toLowerCase().includes(search) ||
            c.description?.toLowerCase().includes(search)
        );
    }

    if (subject) {
        filtered = filtered.filter(c =>
            c.subject?.toLowerCase().includes(subject) ||
            c.category?.toLowerCase().includes(subject)
        );
    }

    ck12FilteredCourses = filtered;
    renderCK12Courses();
}

function renderCK12Courses() {
    const container = document.getElementById('ck12-courses-list');
    const emptyState = document.getElementById('ck12-courses-empty');

    if (ck12FilteredCourses.length === 0) {
        emptyState.classList.remove('hidden');
        container.classList.add('hidden');
        return;
    }

    emptyState.classList.add('hidden');
    container.classList.remove('hidden');

    container.innerHTML = ck12FilteredCourses.map(course => `
        <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-accent-primary/50 transition-all cursor-pointer" onclick="viewCK12CourseDetail('${escapeHtml(course.id)}')">
            <div class="flex items-start gap-3 flex-1 min-w-0">
                <div class="w-10 h-10 rounded-lg bg-accent-success/20 flex items-center justify-center flex-shrink-0">
                    <svg class="w-5 h-5 text-accent-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"></path>
                    </svg>
                </div>
                <div class="flex-1 min-w-0">
                    <h4 class="font-medium text-dark-100 truncate">${escapeHtml(course.title)}</h4>
                    <p class="text-sm text-dark-400 mt-1 line-clamp-2">${escapeHtml(course.description || '')}</p>
                    <div class="flex flex-wrap gap-2 mt-2">
                        ${course.subject ? `<span class="px-2 py-0.5 text-xs rounded-full bg-accent-info/10 text-accent-info">${escapeHtml(course.subject)}</span>` : ''}
                        ${course.gradeLevel ? `<span class="px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">${escapeHtml(course.gradeLevel)}</span>` : ''}
                    </div>
                </div>
            </div>
            <svg class="w-5 h-5 text-dark-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
            </svg>
        </div>
    `).join('');
}

async function viewCK12CourseDetail(courseId) {
    try {
        showToast('Loading course details...', 'info');
        const response = await fetchAPI(`/import/sources/ck12_flexbook/courses/${courseId}`);
        const course = response.course;

        // Display course detail in the courses list area
        const container = document.getElementById('ck12-courses-list');
        container.innerHTML = `
            <div class="mb-4">
                <button class="btn-secondary text-sm" onclick="renderCK12Courses()">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
                    </svg>
                    Back to FlexBooks
                </button>
            </div>
            <div class="rounded-lg bg-dark-800/50 border border-dark-700/50 overflow-hidden">
                <div class="flex items-center justify-between px-4 py-3 border-b border-dark-700/50 bg-dark-800/30">
                    <h3 class="font-semibold text-dark-100">${escapeHtml(course.title)}</h3>
                    <span class="px-2 py-0.5 text-xs rounded bg-accent-success/20 text-accent-success">${escapeHtml(course.level || 'K-12')}</span>
                </div>
                <div class="p-4 space-y-4">
                    <div class="grid md:grid-cols-2 gap-4">
                        <div>
                            <h4 class="text-sm font-medium text-dark-400 mb-1">Subject</h4>
                            <p class="text-dark-200">${escapeHtml(course.department || course.subject || 'N/A')}</p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-dark-400 mb-1">Grade Level</h4>
                            <p class="text-dark-200">${escapeHtml(course.semester || course.gradeLevel || 'N/A')}</p>
                        </div>
                    </div>

                    ${course.instructors?.length ? `
                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-1">Authors</h4>
                        <p class="text-dark-200">${course.instructors.map(i => escapeHtml(i)).join(', ')}</p>
                    </div>
                    ` : ''}

                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-1">Description</h4>
                        <p class="text-dark-200">${escapeHtml(course.description || 'No description available')}</p>
                    </div>

                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-2">Available Content</h4>
                        <div class="flex flex-wrap gap-2">
                            ${(course.features || []).map(f => `
                                <span class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg ${f.available ? 'bg-accent-success/10 text-accent-success border border-accent-success/20' : 'bg-dark-800/50 text-dark-500 border border-dark-700/50'}">
                                    ${getFeatureIcon(f.type)}
                                    ${escapeHtml(f.type.replace(/_/g, ' '))}
                                    ${f.count ? `<span class="text-xs opacity-75">(${f.count})</span>` : ''}
                                </span>
                            `).join('')}
                        </div>
                    </div>

                    ${course.keywords?.length ? `
                    <div>
                        <h4 class="text-sm font-medium text-dark-400 mb-2">Keywords</h4>
                        <div class="flex flex-wrap gap-1">
                            ${course.keywords.map(k => `<span class="px-2 py-0.5 text-xs rounded-full bg-dark-700/50 text-dark-400">${escapeHtml(k)}</span>`).join('')}
                        </div>
                    </div>
                    ` : ''}

                    <div class="border-t border-dark-700/50 pt-4">
                        <h4 class="text-sm font-medium text-dark-400 mb-2">License</h4>
                        <div class="flex items-center gap-2 text-sm">
                            <span class="px-2 py-1 rounded bg-accent-info/10 text-accent-info border border-accent-info/20">${escapeHtml(course.license?.name || 'CC-BY-NC 3.0')}</span>
                            <span class="text-dark-400">by CK-12 Foundation</span>
                        </div>
                    </div>

                    <!-- Lesson Selection -->
                    ${course.lectures?.length ? `
                    <div class="border-t border-dark-700/50 pt-4">
                        <div class="flex items-center justify-between mb-3">
                            <h4 class="text-sm font-medium text-dark-400">Select Lessons to Import</h4>
                            <div class="flex items-center gap-2">
                                <span id="ck12-lesson-selection-count" class="text-xs text-dark-500">0 of ${course.lectures.length} selected</span>
                                <button class="text-xs text-accent-primary hover:text-accent-primary/80" onclick="selectAllCK12Lessons(true)">Select All</button>
                                <span class="text-dark-600">|</span>
                                <button class="text-xs text-dark-400 hover:text-dark-300" onclick="selectAllCK12Lessons(false)">Clear</button>
                            </div>
                        </div>
                        <div class="max-h-64 overflow-y-auto rounded-lg border border-dark-700/50 bg-dark-900/50">
                            <div class="divide-y divide-dark-700/30">
                                ${course.lectures.map((lec, idx) => `
                                    <label class="flex items-center gap-3 px-3 py-2 hover:bg-dark-800/50 cursor-pointer transition-colors">
                                        <input type="checkbox" class="ck12-lesson-checkbox rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary"
                                               data-lesson-id="${escapeHtml(lec.id)}"
                                               data-lesson-num="${lec.number}"
                                               onchange="updateCK12LessonSelectionCount()">
                                        <span class="flex-1 flex items-center gap-2">
                                            <span class="text-xs text-dark-500 w-6">${lec.number}.</span>
                                            <span class="text-sm text-dark-200">${escapeHtml(lec.title)}</span>
                                        </span>
                                        <span class="flex items-center gap-1 text-dark-500">
                                            ${lec.hasVideo ? '<span title="Video available" class="text-accent-info">🎥</span>' : ''}
                                            ${lec.hasTranscript ? '<span title="Transcript available" class="text-accent-success">📝</span>' : ''}
                                            ${lec.hasNotes ? '<span title="Notes available" class="text-accent-warning">📄</span>' : ''}
                                        </span>
                                    </label>
                                `).join('')}
                            </div>
                        </div>
                        <p class="text-xs text-dark-500 mt-2">💡 Tip: Start with 1-2 lessons to evaluate the content before importing the full FlexBook.</p>
                    </div>
                    ` : ''}

                    <div class="border-t border-dark-700/50 pt-4">
                        <h4 class="text-sm font-medium text-dark-400 mb-2">AI Enrichment Options</h4>
                        <div class="space-y-2">
                            <label class="flex items-center gap-2 cursor-pointer">
                                <input type="checkbox" id="ck12-import-opt-objectives" checked class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                                <span class="text-sm text-dark-300">Generate learning objectives</span>
                            </label>
                            <label class="flex items-center gap-2 cursor-pointer">
                                <input type="checkbox" id="ck12-import-opt-checkpoints" checked class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                                <span class="text-sm text-dark-300">Generate knowledge checkpoints</span>
                            </label>
                            <label class="flex items-center gap-2 cursor-pointer">
                                <input type="checkbox" id="ck12-import-opt-spoken" class="rounded border-dark-600 bg-dark-800 text-accent-primary focus:ring-accent-primary">
                                <span class="text-sm text-dark-300">Generate spoken text from notes</span>
                            </label>
                        </div>
                    </div>

                    <div class="flex gap-2 pt-2">
                        <button class="btn-primary flex-1" onclick="importCK12Course('${escapeHtml(course.id)}')">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                            </svg>
                            Import Selected
                        </button>
                        <a href="${course.downloadUrl || 'https://www.ck12.org'}" target="_blank" rel="noopener" class="btn-secondary">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                            </svg>
                            View on CK-12
                        </a>
                    </div>
                </div>
            </div>
        `;
    } catch (e) {
        console.error('Failed to load CK-12 course details:', e);
        showToast('Failed to load course details: ' + e.message, 'error');
    }
}

function selectAllCK12Lessons(select) {
    document.querySelectorAll('.ck12-lesson-checkbox').forEach(cb => {
        cb.checked = select;
    });
    updateCK12LessonSelectionCount();
}

function updateCK12LessonSelectionCount() {
    const checkboxes = document.querySelectorAll('.ck12-lesson-checkbox');
    const checked = document.querySelectorAll('.ck12-lesson-checkbox:checked');
    const countEl = document.getElementById('ck12-lesson-selection-count');
    if (countEl) {
        countEl.textContent = `${checked.length} of ${checkboxes.length} selected`;
    }
}

async function importCK12Course(courseId) {
    try {
        // Get selected lessons
        const selectedLessons = [];
        document.querySelectorAll('.ck12-lesson-checkbox:checked').forEach(cb => {
            selectedLessons.push({
                id: cb.dataset.lessonId,
                number: parseInt(cb.dataset.lessonNum)
            });
        });

        if (selectedLessons.length === 0) {
            showToast('Please select at least one lesson to import', 'warning');
            return;
        }

        // Get enrichment options
        const options = {
            generateObjectives: document.getElementById('ck12-import-opt-objectives')?.checked ?? true,
            generateCheckpoints: document.getElementById('ck12-import-opt-checkpoints')?.checked ?? true,
            generateSpokenText: document.getElementById('ck12-import-opt-spoken')?.checked ?? false,
        };

        showToast(`Importing ${selectedLessons.length} lesson(s)...`, 'info');

        const response = await fetchAPI('/import/start', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                sourceId: 'ck12_flexbook',
                courseId: courseId,
                selectedLectures: selectedLessons.map(l => l.id),
                enrichmentOptions: options
            })
        });

        showToast('Import started! Check the Import Jobs panel for progress.', 'success');

        // Track the new import job and update UI
        trackImportJob(response.jobId);

        // Go back to course list and refresh curricula
        renderCK12Courses();
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import course: ' + e.message, 'error');
    }
}

// ============================================================================
// GitHub Source Functions
// ============================================================================

async function searchGitHubRepos() {
    const query = document.getElementById('github-search-input').value.trim();
    if (!query) return;

    const container = document.getElementById('github-results-container');
    container.innerHTML = `
        <div class="flex items-center justify-center py-12">
            <svg class="w-8 h-8 text-accent-primary animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
            </svg>
            <span class="ml-3 text-dark-400">Searching GitHub...</span>
        </div>
    `;

    try {
        const searchQuery = encodeURIComponent(`${query} extension:umcf OR extension:json umcf`);
        const response = await fetch(`https://api.github.com/search/code?q=${searchQuery}&per_page=20`, {
            headers: { 'Accept': 'application/vnd.github.v3+json' }
        });

        if (!response.ok) {
            if (response.status === 403) {
                throw new Error('GitHub API rate limit exceeded. Please try again later.');
            }
            throw new Error('GitHub API error');
        }

        const data = await response.json();

        if (data.items && data.items.length > 0) {
            container.innerHTML = `
                <div class="mb-4 text-sm text-dark-400">Found ${data.total_count} results</div>
                <div class="space-y-3">
                    ${data.items.map(item => `
                        <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-accent-primary/50 transition-all">
                            <div class="flex items-center gap-3 flex-1 min-w-0">
                                <div class="w-10 h-10 rounded-lg bg-dark-700/50 flex items-center justify-center flex-shrink-0">
                                    <svg class="w-5 h-5 text-dark-400" fill="currentColor" viewBox="0 0 24 24">
                                        <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                                    </svg>
                                </div>
                                <div class="flex-1 min-w-0">
                                    <div class="font-medium text-dark-200 truncate">${escapeHtml(item.name)}</div>
                                    <div class="text-xs text-dark-400 truncate">${escapeHtml(item.repository.full_name)}</div>
                                    <div class="text-xs text-dark-500 truncate">${escapeHtml(item.path)}</div>
                                </div>
                            </div>
                            <button class="btn-primary text-sm flex-shrink-0" onclick="importFromGitHubRepo('${escapeHtml(item.repository.full_name)}', '${escapeHtml(item.path)}')">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                                </svg>
                                Import
                            </button>
                        </div>
                    `).join('')}
                </div>
            `;
        } else {
            container.innerHTML = `
                <div class="text-center py-12 text-dark-500">
                    <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <p class="text-lg font-medium">No curricula found</p>
                    <p class="text-sm mt-1">Try different search terms</p>
                </div>
            `;
        }
    } catch (e) {
        container.innerHTML = `
            <div class="text-center py-12 text-dark-500">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Search failed</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
            </div>
        `;
    }
}

async function importFromGitHubRepo(repo, path) {
    try {
        const rawUrl = `https://raw.githubusercontent.com/${repo}/main/${path}`;
        showToast('Importing from GitHub...', 'info');

        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ url: rawUrl })
        });

        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import: ' + e.message, 'error');
    }
}

// ============================================================================
// Custom URL Source Functions
// ============================================================================

async function browseCustomURL() {
    const url = document.getElementById('custom-url-input').value.trim();
    if (!url) return;

    const container = document.getElementById('custom-results-container');
    container.innerHTML = `
        <div class="flex items-center justify-center py-12">
            <svg class="w-8 h-8 text-accent-primary animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
            </svg>
            <span class="ml-3 text-dark-400">Fetching URL...</span>
        </div>
    `;

    try {
        // Check if it's a direct UMCF file
        if (url.endsWith('.umcf') || url.endsWith('.json')) {
            container.innerHTML = `
                <div class="p-4 rounded-lg bg-dark-800/30 border border-dark-700/50">
                    <div class="flex items-center justify-between">
                        <div>
                            <p class="font-medium text-dark-200">Direct curriculum file detected</p>
                            <p class="text-sm text-dark-400 mt-1">${escapeHtml(url)}</p>
                        </div>
                        <button class="btn-primary" onclick="importFromCustomURL('${escapeHtml(url)}')">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                            </svg>
                            Import
                        </button>
                    </div>
                </div>
            `;
        } else {
            container.innerHTML = `
                <div class="text-center py-12 text-dark-500">
                    <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"></path>
                    </svg>
                    <p class="text-lg font-medium">Enter a .umcf or .json URL</p>
                    <p class="text-sm mt-1">Direct links to curriculum files work best</p>
                </div>
            `;
        }
    } catch (e) {
        container.innerHTML = `
            <div class="text-center py-12 text-dark-500">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Failed to fetch URL</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
            </div>
        `;
    }
}

async function importFromCustomURL(url) {
    try {
        showToast('Importing from URL...', 'info');
        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ url: url })
        });
        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import: ' + e.message, 'error');
    }
}

async function searchGitHub() {
    const query = document.getElementById('github-search').value.trim();
    if (!query) return;

    const resultsContainer = document.getElementById('source-results');
    resultsContainer.innerHTML = `
        <div class="text-center py-12">
            <svg class="w-12 h-12 mx-auto mb-4 text-accent-primary animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
            </svg>
            <p class="text-dark-400">Searching GitHub...</p>
        </div>
    `;

    try {
        // Search GitHub for repositories containing UMCF files
        const searchQuery = encodeURIComponent(`${query} extension:umcf OR extension:json umcf`);
        const response = await fetch(`https://api.github.com/search/code?q=${searchQuery}&per_page=20`, {
            headers: { 'Accept': 'application/vnd.github.v3+json' }
        });

        if (!response.ok) {
            if (response.status === 403) {
                throw new Error('GitHub API rate limit exceeded. Please try again later.');
            }
            throw new Error('GitHub API error');
        }

        const data = await response.json();

        if (data.items && data.items.length > 0) {
            resultsContainer.innerHTML = `
                <div class="mb-4 text-sm text-dark-400">Found ${data.total_count} results</div>
                <div class="space-y-3">
                    ${data.items.map(item => `
                        <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-accent-primary/50 transition-all">
                            <div class="flex items-center gap-3 flex-1 min-w-0">
                                <div class="w-10 h-10 rounded-lg bg-dark-700/50 flex items-center justify-center flex-shrink-0">
                                    <svg class="w-5 h-5 text-dark-400" fill="currentColor" viewBox="0 0 24 24">
                                        <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                                    </svg>
                                </div>
                                <div class="flex-1 min-w-0">
                                    <div class="font-medium text-dark-200 truncate">${escapeHtml(item.name)}</div>
                                    <div class="text-xs text-dark-400 truncate">${escapeHtml(item.repository.full_name)}</div>
                                    <div class="text-xs text-dark-500 truncate">${escapeHtml(item.path)}</div>
                                </div>
                            </div>
                            <button class="btn-primary text-sm flex-shrink-0" onclick="importFromGitHub('${escapeHtml(item.repository.full_name)}', '${escapeHtml(item.path)}')">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                                </svg>
                                Import
                            </button>
                        </div>
                    `).join('')}
                </div>
            `;
        } else {
            resultsContainer.innerHTML = `
                <div class="text-center text-dark-500 py-12">
                    <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <p class="text-lg font-medium">No curricula found</p>
                    <p class="text-sm mt-1">Try different search terms</p>
                </div>
            `;
        }
    } catch (e) {
        resultsContainer.innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Search failed</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
            </div>
        `;
    }
}

async function importFromGitHub(repo, path) {
    try {
        const rawUrl = `https://raw.githubusercontent.com/${repo}/main/${path}`;
        showToast('Importing from GitHub...', 'info');

        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ url: rawUrl })
        });

        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import: ' + e.message, 'error');
    }
}

async function searchHuggingFace() {
    const query = document.getElementById('hf-search').value.trim();
    if (!query) return;

    const resultsContainer = document.getElementById('source-results');
    resultsContainer.innerHTML = `
        <div class="text-center py-12">
            <svg class="w-12 h-12 mx-auto mb-4 text-accent-primary animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
            </svg>
            <p class="text-dark-400">Searching Hugging Face...</p>
        </div>
    `;

    try {
        const searchQuery = encodeURIComponent(query);
        const response = await fetch(`https://huggingface.co/api/datasets?search=${searchQuery}&limit=20`);

        if (!response.ok) {
            throw new Error('Hugging Face API error');
        }

        const data = await response.json();

        if (data && data.length > 0) {
            resultsContainer.innerHTML = `
                <div class="mb-4 text-sm text-dark-400">Found ${data.length} datasets</div>
                <div class="space-y-3">
                    ${data.map(item => `
                        <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50 hover:border-accent-primary/50 transition-all">
                            <div class="flex items-center gap-3 flex-1 min-w-0">
                                <div class="w-10 h-10 rounded-lg bg-accent-warning/20 flex items-center justify-center flex-shrink-0">
                                    <svg class="w-5 h-5 text-accent-warning" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm0 18c-4.411 0-8-3.589-8-8s3.589-8 8-8 8 3.589 8 8-3.589 8-8 8z"/>
                                        <circle cx="8.5" cy="10.5" r="1.5"/>
                                        <circle cx="15.5" cy="10.5" r="1.5"/>
                                        <path d="M12 16c-2.206 0-4-1.346-4-3h8c0 1.654-1.794 3-4 3z"/>
                                    </svg>
                                </div>
                                <div class="flex-1 min-w-0">
                                    <div class="font-medium text-dark-200 truncate">${escapeHtml(item.id)}</div>
                                    <div class="text-xs text-dark-400">${item.downloads ? item.downloads.toLocaleString() + ' downloads' : 'No download info'}</div>
                                    ${item.tags ? `<div class="flex flex-wrap gap-1 mt-1">${item.tags.slice(0, 3).map(tag => `<span class="px-1.5 py-0.5 text-xs rounded bg-dark-700/50 text-dark-400">${escapeHtml(tag)}</span>`).join('')}</div>` : ''}
                                </div>
                            </div>
                            <a href="https://huggingface.co/datasets/${item.id}" target="_blank" class="btn-secondary text-sm flex-shrink-0">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                                </svg>
                                View
                            </a>
                        </div>
                    `).join('')}
                </div>
                <div class="mt-4 p-4 rounded-lg bg-dark-800/30 border border-dark-700/50">
                    <p class="text-sm text-dark-400">
                        <svg class="w-4 h-4 inline mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                        To import a Hugging Face dataset, download the UMCF file from the dataset page and use the "Upload File" option in the Import dialog.
                    </p>
                </div>
            `;
        } else {
            resultsContainer.innerHTML = `
                <div class="text-center text-dark-500 py-12">
                    <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <p class="text-lg font-medium">No datasets found</p>
                    <p class="text-sm mt-1">Try different search terms</p>
                </div>
            `;
        }
    } catch (e) {
        resultsContainer.innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Search failed</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
            </div>
        `;
    }
}

async function browseCustomUrl() {
    const url = document.getElementById('custom-source-url').value.trim();
    if (!url) return;

    const resultsContainer = document.getElementById('source-results');
    resultsContainer.innerHTML = `
        <div class="text-center py-12">
            <svg class="w-12 h-12 mx-auto mb-4 text-accent-primary animate-spin" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
            </svg>
            <p class="text-dark-400">Fetching from URL...</p>
        </div>
    `;

    try {
        // Try to fetch the URL - if it's a UMCF file, offer to import directly
        // If it's a directory listing or JSON array, show the list
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }

        const contentType = response.headers.get('content-type') || '';
        const text = await response.text();

        if (contentType.includes('application/json') || url.endsWith('.umcf') || url.endsWith('.json')) {
            try {
                const json = JSON.parse(text);

                // Check if it's a single UMCF curriculum
                if (json.formatIdentifier === 'umcf') {
                    resultsContainer.innerHTML = `
                        <div class="p-4 rounded-lg bg-dark-800/30 border border-dark-700/50">
                            <div class="flex items-center justify-between">
                                <div>
                                    <div class="font-medium text-dark-200">${escapeHtml(json.metadata?.title || 'Untitled Curriculum')}</div>
                                    <div class="text-sm text-dark-400">${escapeHtml(json.metadata?.description || 'No description')}</div>
                                </div>
                                <button class="btn-primary" onclick="importFromCustomUrl('${escapeHtml(url)}')">
                                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path>
                                    </svg>
                                    Import
                                </button>
                            </div>
                        </div>
                    `;
                } else if (Array.isArray(json)) {
                    // Array of curricula or URLs
                    resultsContainer.innerHTML = `
                        <div class="mb-4 text-sm text-dark-400">Found ${json.length} items</div>
                        <div class="space-y-3">
                            ${json.map((item, i) => {
                                const itemUrl = typeof item === 'string' ? item : item.url || item.href;
                                const itemTitle = typeof item === 'string' ? item.split('/').pop() : (item.title || item.name || `Item ${i + 1}`);
                                return `
                                    <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50">
                                        <div class="font-medium text-dark-200">${escapeHtml(itemTitle)}</div>
                                        <button class="btn-primary text-sm" onclick="importFromCustomUrl('${escapeHtml(itemUrl)}')">Import</button>
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    `;
                } else {
                    resultsContainer.innerHTML = `
                        <div class="text-center text-dark-500 py-12">
                            <p class="text-lg font-medium">Unknown JSON format</p>
                            <p class="text-sm mt-1">The URL returned JSON but it's not a recognized UMCF format</p>
                        </div>
                    `;
                }
            } catch (parseError) {
                throw new Error('Invalid JSON at URL');
            }
        } else {
            // Try to parse as HTML and look for links to .umcf files
            const parser = new DOMParser();
            const doc = parser.parseFromString(text, 'text/html');
            const links = Array.from(doc.querySelectorAll('a[href]'))
                .filter(a => a.href.endsWith('.umcf') || a.href.endsWith('.json'))
                .map(a => ({
                    href: new URL(a.getAttribute('href'), url).href,
                    text: a.textContent.trim() || a.getAttribute('href')
                }));

            if (links.length > 0) {
                resultsContainer.innerHTML = `
                    <div class="mb-4 text-sm text-dark-400">Found ${links.length} curriculum files</div>
                    <div class="space-y-3">
                        ${links.map(link => `
                            <div class="flex items-center justify-between p-4 rounded-lg bg-dark-800/30 border border-dark-700/50">
                                <div class="flex-1 min-w-0">
                                    <div class="font-medium text-dark-200 truncate">${escapeHtml(link.text)}</div>
                                    <div class="text-xs text-dark-500 truncate">${escapeHtml(link.href)}</div>
                                </div>
                                <button class="btn-primary text-sm flex-shrink-0" onclick="importFromCustomUrl('${escapeHtml(link.href)}')">Import</button>
                            </div>
                        `).join('')}
                    </div>
                `;
            } else {
                resultsContainer.innerHTML = `
                    <div class="text-center text-dark-500 py-12">
                        <p class="text-lg font-medium">No curriculum files found</p>
                        <p class="text-sm mt-1">The URL doesn't appear to contain UMCF files</p>
                    </div>
                `;
            }
        }
    } catch (e) {
        resultsContainer.innerHTML = `
            <div class="text-center text-dark-500 py-12">
                <svg class="w-16 h-16 mx-auto mb-4 text-accent-danger opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-lg font-medium text-accent-danger">Failed to fetch URL</p>
                <p class="text-sm mt-1">${escapeHtml(e.message)}</p>
            </div>
        `;
    }
}

async function importFromCustomUrl(url) {
    try {
        showToast('Importing...', 'info');
        const response = await fetchAPI('/curricula/import', {
            method: 'POST',
            body: JSON.stringify({ url: url })
        });
        showToast(`Curriculum "${response.title}" imported successfully!`, 'success');
        await refreshCurricula();
    } catch (e) {
        showToast('Failed to import: ' + e.message, 'error');
    }
}

// Toast notification system
function showToast(message, type = 'info') {
    // Remove existing toasts
    document.querySelectorAll('.toast-notification').forEach(t => t.remove());

    const colors = {
        'success': 'bg-accent-success',
        'error': 'bg-accent-danger',
        'warning': 'bg-accent-warning',
        'info': 'bg-accent-info'
    };

    const toast = document.createElement('div');
    toast.className = `toast-notification fixed bottom-4 right-4 z-[100] px-4 py-3 rounded-lg ${colors[type]} text-white shadow-lg animate-slide-up`;
    toast.textContent = message;

    document.body.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.3s';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// =============================================================================
// Curriculum Delete/Archive Functions
// =============================================================================

// State for confirmation modal
let confirmModalState = {
    action: null,
    curriculumId: null,
    curriculumTitle: null,
    fileName: null,
    isArchived: false
};

// State for archived curricula
state.archivedCurricula = [];

// Show confirmation modal for delete
function showDeleteConfirm(curriculumId, title, event) {
    if (event) event.stopPropagation();

    confirmModalState = {
        action: 'delete',
        curriculumId: curriculumId,
        curriculumTitle: title,
        fileName: null,
        isArchived: false
    };

    document.getElementById('confirm-modal-title').textContent = 'Delete Curriculum';
    document.getElementById('confirm-modal-message').textContent =
        `Are you sure you want to permanently delete "${title}"? This action cannot be undone.`;
    document.getElementById('confirm-modal-btn').textContent = 'Delete Permanently';
    document.getElementById('confirm-modal-btn').className = 'btn-primary bg-accent-danger hover:bg-accent-danger/80';
    document.getElementById('confirm-modal-alt-btn').classList.remove('hidden');
    document.getElementById('confirm-modal-alt-btn').textContent = 'Archive Instead';
    document.getElementById('confirm-modal-icon').className = 'w-10 h-10 rounded-lg flex items-center justify-center bg-accent-danger/20';
    document.getElementById('confirm-modal-icon').innerHTML = `
        <svg class="w-5 h-5 text-accent-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
        </svg>
    `;

    document.getElementById('confirm-action-modal').classList.remove('hidden');
}

// Show confirmation modal for archive
function showArchiveConfirm(curriculumId, title, event) {
    if (event) event.stopPropagation();

    confirmModalState = {
        action: 'archive',
        curriculumId: curriculumId,
        curriculumTitle: title,
        fileName: null,
        isArchived: false
    };

    document.getElementById('confirm-modal-title').textContent = 'Archive Curriculum';
    document.getElementById('confirm-modal-message').textContent =
        `Archive "${title}"? It will be moved to the archived folder and can be restored later.`;
    document.getElementById('confirm-modal-btn').textContent = 'Archive';
    document.getElementById('confirm-modal-btn').className = 'btn-primary bg-accent-warning hover:bg-accent-warning/80';
    document.getElementById('confirm-modal-alt-btn').classList.add('hidden');
    document.getElementById('confirm-modal-icon').className = 'w-10 h-10 rounded-lg flex items-center justify-center bg-accent-warning/20';
    document.getElementById('confirm-modal-icon').innerHTML = `
        <svg class="w-5 h-5 text-accent-warning" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"></path>
        </svg>
    `;

    document.getElementById('confirm-action-modal').classList.remove('hidden');
}

// Show confirmation modal for unarchive
function showUnarchiveConfirm(fileName, title, event) {
    if (event) event.stopPropagation();

    confirmModalState = {
        action: 'unarchive',
        curriculumId: null,
        curriculumTitle: title,
        fileName: fileName,
        isArchived: true
    };

    document.getElementById('confirm-modal-title').textContent = 'Restore Curriculum';
    document.getElementById('confirm-modal-message').textContent =
        `Restore "${title}" from the archive? It will become active again.`;
    document.getElementById('confirm-modal-btn').textContent = 'Restore';
    document.getElementById('confirm-modal-btn').className = 'btn-primary bg-accent-success hover:bg-accent-success/80';
    document.getElementById('confirm-modal-alt-btn').classList.add('hidden');
    document.getElementById('confirm-modal-icon').className = 'w-10 h-10 rounded-lg flex items-center justify-center bg-accent-success/20';
    document.getElementById('confirm-modal-icon').innerHTML = `
        <svg class="w-5 h-5 text-accent-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
        </svg>
    `;

    document.getElementById('confirm-action-modal').classList.remove('hidden');
}

// Show confirmation modal for delete archived
function showDeleteArchivedConfirm(fileName, title, event) {
    if (event) event.stopPropagation();

    confirmModalState = {
        action: 'delete-archived',
        curriculumId: null,
        curriculumTitle: title,
        fileName: fileName,
        isArchived: true
    };

    document.getElementById('confirm-modal-title').textContent = 'Delete Archived Curriculum';
    document.getElementById('confirm-modal-message').textContent =
        `Are you sure you want to permanently delete "${title}" from the archive? This action cannot be undone.`;
    document.getElementById('confirm-modal-btn').textContent = 'Delete Permanently';
    document.getElementById('confirm-modal-btn').className = 'btn-primary bg-accent-danger hover:bg-accent-danger/80';
    document.getElementById('confirm-modal-alt-btn').classList.add('hidden');
    document.getElementById('confirm-modal-icon').className = 'w-10 h-10 rounded-lg flex items-center justify-center bg-accent-danger/20';
    document.getElementById('confirm-modal-icon').innerHTML = `
        <svg class="w-5 h-5 text-accent-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
        </svg>
    `;

    document.getElementById('confirm-action-modal').classList.remove('hidden');
}

function hideConfirmModal() {
    document.getElementById('confirm-action-modal').classList.add('hidden');
    confirmModalState = { action: null, curriculumId: null, curriculumTitle: null, fileName: null, isArchived: false };
}

async function executeConfirmAction() {
    const { action, curriculumId, curriculumTitle, fileName } = confirmModalState;

    try {
        switch (action) {
            case 'delete':
                await fetchAPI(`/curricula/${curriculumId}?confirm=true`, { method: 'DELETE' });
                showToast(`Deleted "${curriculumTitle}"`, 'success');
                await refreshCurricula();
                break;

            case 'archive':
                await fetchAPI(`/curricula/${curriculumId}/archive`, { method: 'POST' });
                showToast(`Archived "${curriculumTitle}"`, 'success');
                await refreshCurricula();
                await fetchArchivedCurricula();
                break;

            case 'unarchive':
                await fetchAPI(`/curricula/archived/${encodeURIComponent(fileName)}/unarchive`, { method: 'POST' });
                showToast(`Restored "${curriculumTitle}"`, 'success');
                await refreshCurricula();
                await fetchArchivedCurricula();
                break;

            case 'delete-archived':
                await fetchAPI(`/curricula/archived/${encodeURIComponent(fileName)}?confirm=true`, { method: 'DELETE' });
                showToast(`Permanently deleted "${curriculumTitle}"`, 'success');
                await fetchArchivedCurricula();
                break;
        }
    } catch (e) {
        showToast('Action failed: ' + e.message, 'error');
    }

    hideConfirmModal();
}

function executeAltAction() {
    // Switch from delete to archive
    if (confirmModalState.action === 'delete') {
        showArchiveConfirm(confirmModalState.curriculumId, confirmModalState.curriculumTitle);
    }
}

// Fetch archived curricula
async function fetchArchivedCurricula() {
    try {
        const data = await fetchAPI('/curricula/archived');
        state.archivedCurricula = data.archived || [];
        updateArchivedSection();
    } catch (e) {
        console.error('Failed to fetch archived curricula:', e);
    }
}

function updateArchivedSection() {
    const section = document.getElementById('archived-curricula-section');
    const countEl = document.getElementById('archived-count');
    const listEl = document.getElementById('archived-curricula-list');

    if (state.archivedCurricula.length === 0) {
        section.classList.add('hidden');
        return;
    }

    section.classList.remove('hidden');
    countEl.textContent = state.archivedCurricula.length;

    const html = state.archivedCurricula.map(archived => `
        <div class="card bg-dark-800/30 p-4 flex items-center justify-between gap-4 group">
            <div class="flex items-center gap-3 min-w-0">
                <svg class="w-4 h-4 text-dark-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"></path>
                </svg>
                <div class="min-w-0">
                    <div class="font-medium text-dark-300 truncate">${escapeHtml(archived.title)}</div>
                    <div class="text-xs text-dark-500">Archived ${formatArchivedDate(archived.archived_at)} &middot; ${formatBytes(archived.size_bytes)}</div>
                </div>
            </div>
            <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                <button onclick="showUnarchiveConfirm('${escapeHtml(archived.file_name)}', '${escapeHtml(archived.title)}', event)"
                        class="p-2 text-dark-400 hover:text-accent-success hover:bg-dark-700 rounded-lg transition-colors" title="Restore">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                    </svg>
                </button>
                <button onclick="showDeleteArchivedConfirm('${escapeHtml(archived.file_name)}', '${escapeHtml(archived.title)}', event)"
                        class="p-2 text-dark-400 hover:text-accent-danger hover:bg-dark-700 rounded-lg transition-colors" title="Delete permanently">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                    </svg>
                </button>
            </div>
        </div>
    `).join('');

    listEl.innerHTML = html;
}

function toggleArchivedSection() {
    const listEl = document.getElementById('archived-curricula-list');
    const chevron = document.getElementById('archived-chevron');

    if (listEl.classList.contains('hidden')) {
        listEl.classList.remove('hidden');
        chevron.style.transform = 'rotate(180deg)';
    } else {
        listEl.classList.add('hidden');
        chevron.style.transform = 'rotate(0deg)';
    }
}

function formatArchivedDate(dateStr) {
    const date = new Date(dateStr);
    return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// =============================================================================
// Plugin Manager Functions
// =============================================================================

let pluginsData = { plugins: [], first_run: false };
let pluginConfigSchemas = {};  // Cache for plugin configuration schemas

async function refreshPlugins() {
    try {
        const data = await fetchAPI('/plugins');
        if (data.success) {
            pluginsData = data;
            updatePluginStats(data.plugins);
            renderPlugins(data.plugins);

            // Show first-run banner if needed
            const banner = document.getElementById('plugins-first-run-banner');
            if (data.first_run && banner) {
                banner.classList.remove('hidden');
            } else if (banner) {
                banner.classList.add('hidden');
            }

            // Fetch config schemas for all plugins (in background)
            for (const plugin of data.plugins) {
                fetchPluginConfigSchema(plugin.plugin_id);
            }
        }
    } catch (e) {
        console.error('Failed to refresh plugins:', e);
    }
}

async function fetchPluginConfigSchema(pluginId) {
    try {
        const data = await fetchAPI(`/plugins/${pluginId}/config-schema`);
        if (data.success && data.has_config) {
            pluginConfigSchemas[pluginId] = data.schema;
        }
    } catch (e) {
        console.debug(`No config schema for ${pluginId}`);
    }
}

function updatePluginStats(plugins) {
    const discovered = plugins.length;
    const enabled = plugins.filter(p => p.enabled).length;
    const disabled = discovered - enabled;
    const sources = plugins.filter(p => p.plugin_type === 'sources').length;

    document.getElementById('plugins-discovered').textContent = discovered;
    document.getElementById('plugins-enabled').textContent = enabled;
    document.getElementById('plugins-disabled').textContent = disabled;
    document.getElementById('plugins-sources').textContent = sources;
}

function renderPlugins(plugins) {
    const grid = document.getElementById('plugins-grid');
    const emptyState = document.getElementById('plugins-empty');

    if (plugins.length === 0) {
        grid.innerHTML = '';
        emptyState.classList.remove('hidden');
        return;
    }

    emptyState.classList.add('hidden');

    grid.innerHTML = plugins.map(plugin => {
        const hasConfig = plugin.features && plugin.features.includes('configurable');
        const needsConfig = !plugin.enabled && hasConfig;

        return `
        <div class="rounded-xl bg-dark-800/50 border ${plugin.enabled ? 'border-accent-success/30' : needsConfig ? 'border-accent-warning/30' : 'border-dark-700/50'} p-4 transition-all hover:border-dark-600">
            <div class="flex items-start justify-between gap-4">
                <div class="flex items-start gap-3 flex-1 min-w-0">
                    <div class="w-10 h-10 rounded-lg ${plugin.enabled ? 'bg-accent-success/20' : needsConfig ? 'bg-accent-warning/20' : 'bg-dark-700'} flex items-center justify-center flex-shrink-0">
                        ${getPluginIcon(plugin.plugin_type, plugin.enabled)}
                    </div>
                    <div class="flex-1 min-w-0">
                        <div class="flex items-center gap-2 flex-wrap">
                            <h3 class="font-medium truncate">${escapeHtml(plugin.name)}</h3>
                            <span class="text-xs px-2 py-0.5 rounded ${plugin.enabled ? 'bg-accent-success/20 text-accent-success' : 'bg-dark-700 text-dark-400'}">
                                ${plugin.enabled ? 'Enabled' : 'Disabled'}
                            </span>
                            ${needsConfig ? '<span class="text-xs px-2 py-0.5 rounded bg-accent-warning/20 text-accent-warning">Needs Config</span>' : ''}
                        </div>
                        <p class="text-sm text-dark-400 mt-1 line-clamp-2">${escapeHtml(plugin.description)}</p>
                        <div class="flex items-center gap-3 mt-2 text-xs text-dark-500">
                            <span class="capitalize">${plugin.plugin_type}</span>
                            ${plugin.license_type ? `<span>${escapeHtml(plugin.license_type)}</span>` : ''}
                            <span>v${plugin.version}</span>
                        </div>
                        ${hasConfig ? `
                        <div class="mt-3 pt-3 border-t border-dark-700/50">
                            <button onclick="showPluginConfig('${plugin.plugin_id}')"
                                    class="text-xs px-3 py-1.5 rounded-lg bg-dark-700 hover:bg-dark-600 text-dark-300 hover:text-white transition-colors flex items-center gap-1.5">
                                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path>
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                                </svg>
                                Configure
                            </button>
                        </div>
                        ` : ''}
                    </div>
                </div>
                <div class="flex-shrink-0">
                    <button onclick="togglePlugin('${plugin.plugin_id}', ${!plugin.enabled})"
                            class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${plugin.enabled ? 'bg-accent-success' : 'bg-dark-600'}">
                        <span class="inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${plugin.enabled ? 'translate-x-6' : 'translate-x-1'}"></span>
                    </button>
                </div>
            </div>
        </div>
    `}).join('');
}

function getPluginIcon(pluginType, enabled) {
    const color = enabled ? 'text-accent-success' : 'text-dark-500';
    if (pluginType === 'sources') {
        return `<svg class="w-5 h-5 ${color}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"></path>
        </svg>`;
    } else if (pluginType === 'parsers') {
        return `<svg class="w-5 h-5 ${color}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
        </svg>`;
    } else {
        return `<svg class="w-5 h-5 ${color}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
        </svg>`;
    }
}

async function togglePlugin(pluginId, enable) {
    try {
        const endpoint = enable ? 'enable' : 'disable';
        const response = await fetchAPI(`/plugins/${pluginId}/${endpoint}`, { method: 'POST' });
        if (response.success) {
            await refreshPlugins();
        } else {
            alert(`Failed to ${endpoint} plugin: ${response.error || 'Unknown error'}`);
        }
    } catch (e) {
        console.error(`Failed to toggle plugin ${pluginId}:`, e);
        alert(`Failed to toggle plugin: ${e.message}`);
    }
}

function showFirstRunWizard() {
    // For now, just show a confirmation dialog
    const enableAll = confirm('Would you like to enable all discovered plugins?\n\nClick OK to enable all, or Cancel to keep them disabled and configure manually.');

    if (enableAll) {
        initializeAllPlugins();
    }
}

async function initializeAllPlugins() {
    try {
        const pluginIds = pluginsData.plugins.map(p => p.plugin_id);
        const response = await fetchAPI('/plugins/initialize', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enabled_plugins: pluginIds })
        });

        if (response.success) {
            await refreshPlugins();
            // Hide the first-run banner
            const banner = document.getElementById('plugins-first-run-banner');
            if (banner) banner.classList.add('hidden');
        } else {
            alert('Failed to initialize plugins: ' + (response.error || 'Unknown error'));
        }
    } catch (e) {
        console.error('Failed to initialize plugins:', e);
        alert('Failed to initialize plugins: ' + e.message);
    }
}

// =============================================================================
// Plugin Configuration Modal
// =============================================================================

let currentConfigPlugin = null;

async function showPluginConfig(pluginId) {
    currentConfigPlugin = pluginId;

    // Find the plugin data
    const plugin = pluginsData.plugins.find(p => p.plugin_id === pluginId);
    if (!plugin) {
        alert('Plugin not found');
        return;
    }

    // Fetch schema if not cached
    if (!pluginConfigSchemas[pluginId]) {
        try {
            const data = await fetchAPI(`/plugins/${pluginId}/config-schema`);
            if (data.success && data.has_config) {
                pluginConfigSchemas[pluginId] = data.schema;
            } else {
                alert('This plugin does not have configurable settings');
                return;
            }
        } catch (e) {
            alert('Failed to load configuration schema');
            return;
        }
    }

    const schema = pluginConfigSchemas[pluginId];
    const currentSettings = plugin.settings || {};

    // Build the modal
    const modalHtml = `
        <div id="plugin-config-modal" class="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
            <div class="bg-dark-800 rounded-2xl border border-dark-700 w-full max-w-lg max-h-[90vh] overflow-hidden flex flex-col">
                <div class="p-6 border-b border-dark-700">
                    <div class="flex items-center justify-between">
                        <div>
                            <h2 class="text-xl font-semibold">Configure ${escapeHtml(plugin.name)}</h2>
                            <p class="text-sm text-dark-400 mt-1">${escapeHtml(plugin.description)}</p>
                        </div>
                        <button onclick="closePluginConfig()" class="p-2 rounded-lg hover:bg-dark-700 transition-colors">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                            </svg>
                        </button>
                    </div>
                </div>
                <div class="p-6 overflow-y-auto flex-1">
                    <form id="plugin-config-form" class="space-y-6">
                        ${renderConfigFields(schema.settings, currentSettings)}
                    </form>
                    <div id="plugin-test-result" class="hidden mt-4 p-3 rounded-lg"></div>
                </div>
                <div class="p-6 border-t border-dark-700 flex items-center justify-between gap-4">
                    <button onclick="testPluginConfig('${pluginId}')" type="button"
                            class="px-4 py-2 rounded-lg bg-dark-700 hover:bg-dark-600 text-dark-300 hover:text-white transition-colors flex items-center gap-2">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                        Test Connection
                    </button>
                    <div class="flex items-center gap-3">
                        <button onclick="closePluginConfig()" type="button"
                                class="px-4 py-2 rounded-lg bg-dark-700 hover:bg-dark-600 text-dark-300 hover:text-white transition-colors">
                            Cancel
                        </button>
                        <button onclick="savePluginConfig('${pluginId}')" type="button"
                                class="px-4 py-2 rounded-lg bg-accent-primary hover:bg-accent-primary/80 text-white transition-colors flex items-center gap-2">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                            </svg>
                            Save Configuration
                        </button>
                    </div>
                </div>
            </div>
        </div>
    `;

    // Add modal to DOM
    document.body.insertAdjacentHTML('beforeend', modalHtml);

    // Add keyboard listener for escape key
    document.addEventListener('keydown', handleConfigModalKeydown);
}

function renderConfigFields(settings, currentValues) {
    return settings.map(setting => {
        const value = currentValues[setting.key] || '';
        const inputType = setting.type === 'password' ? 'password' : 'text';
        const required = setting.required ? 'required' : '';

        return `
            <div class="space-y-2">
                <label for="config-${setting.key}" class="block text-sm font-medium">
                    ${escapeHtml(setting.label)}
                    ${setting.required ? '<span class="text-accent-error">*</span>' : ''}
                </label>
                <div class="relative">
                    <input type="${inputType}"
                           id="config-${setting.key}"
                           name="${setting.key}"
                           value="${escapeHtml(value)}"
                           placeholder="${escapeHtml(setting.placeholder || '')}"
                           ${required}
                           class="w-full px-4 py-2.5 rounded-lg bg-dark-700 border border-dark-600 focus:border-accent-primary focus:ring-1 focus:ring-accent-primary outline-none transition-colors text-white placeholder-dark-500">
                    ${inputType === 'password' ? `
                        <button type="button" onclick="togglePasswordVisibility('config-${setting.key}')"
                                class="absolute right-3 top-1/2 -translate-y-1/2 text-dark-400 hover:text-white transition-colors">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"></path>
                            </svg>
                        </button>
                    ` : ''}
                </div>
                ${setting.help_text ? `
                    <p class="text-xs text-dark-400">
                        ${escapeHtml(setting.help_text)}
                        ${setting.help_url ? `<a href="${setting.help_url}" target="_blank" rel="noopener" class="text-accent-primary hover:underline ml-1">Learn more</a>` : ''}
                    </p>
                ` : ''}
            </div>
        `;
    }).join('');
}

function togglePasswordVisibility(inputId) {
    const input = document.getElementById(inputId);
    if (input) {
        input.type = input.type === 'password' ? 'text' : 'password';
    }
}

function closePluginConfig() {
    const modal = document.getElementById('plugin-config-modal');
    if (modal) {
        modal.remove();
    }
    document.removeEventListener('keydown', handleConfigModalKeydown);
    currentConfigPlugin = null;
}

function handleConfigModalKeydown(e) {
    if (e.key === 'Escape') {
        closePluginConfig();
    }
}

function getConfigFormValues() {
    const form = document.getElementById('plugin-config-form');
    if (!form) return {};

    const formData = new FormData(form);
    const values = {};
    for (const [key, value] of formData.entries()) {
        values[key] = value;
    }
    return values;
}

async function testPluginConfig(pluginId) {
    const resultDiv = document.getElementById('plugin-test-result');
    const settings = getConfigFormValues();

    resultDiv.className = 'mt-4 p-3 rounded-lg bg-dark-700 text-dark-300';
    resultDiv.classList.remove('hidden');
    resultDiv.innerHTML = '<span class="animate-pulse">Testing connection...</span>';

    try {
        const response = await fetchAPI(`/plugins/${pluginId}/test`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ settings })
        });

        if (response.success && response.test_result) {
            const result = response.test_result;
            if (result.valid) {
                resultDiv.className = 'mt-4 p-3 rounded-lg bg-accent-success/20 text-accent-success flex items-center gap-2';
                resultDiv.innerHTML = `
                    <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <span>${escapeHtml(result.message)}</span>
                `;
            } else {
                resultDiv.className = 'mt-4 p-3 rounded-lg bg-accent-error/20 text-accent-error flex items-center gap-2';
                resultDiv.innerHTML = `
                    <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <span>${escapeHtml(result.message)}</span>
                `;
            }
        } else {
            throw new Error(response.error || 'Test failed');
        }
    } catch (e) {
        resultDiv.className = 'mt-4 p-3 rounded-lg bg-accent-error/20 text-accent-error flex items-center gap-2';
        resultDiv.innerHTML = `
            <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            <span>Test failed: ${escapeHtml(e.message)}</span>
        `;
    }
}

async function savePluginConfig(pluginId) {
    const settings = getConfigFormValues();

    try {
        const response = await fetchAPI(`/plugins/${pluginId}/configure`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ settings })
        });

        if (response.success) {
            closePluginConfig();
            await refreshPlugins();

            // Show success toast (or alert for now)
            showToast('Configuration saved successfully', 'success');
        } else {
            alert('Failed to save configuration: ' + (response.error || 'Unknown error'));
        }
    } catch (e) {
        console.error('Failed to save plugin config:', e);
        alert('Failed to save configuration: ' + e.message);
    }
}

function showToast(message, type = 'info') {
    // Simple toast notification
    const toast = document.createElement('div');
    const bgColor = type === 'success' ? 'bg-accent-success' : type === 'error' ? 'bg-accent-error' : 'bg-accent-primary';
    toast.className = `fixed bottom-4 right-4 ${bgColor} text-white px-4 py-3 rounded-lg shadow-lg z-50 flex items-center gap-2 animate-slide-up`;
    toast.innerHTML = `
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <span>${escapeHtml(message)}</span>
    `;
    document.body.appendChild(toast);

    setTimeout(() => {
        toast.remove();
    }, 3000);
}

// Start the application
document.addEventListener('DOMContentLoaded', init);
