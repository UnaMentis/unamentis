/**
 * VoiceLearn Management Console - Frontend Application
 * A real-time dashboard for monitoring VoiceLearn services
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

    stats: {
        uptime: 0,
        totalLogs: 0,
        totalMetrics: 0,
        errors: 0,
        warnings: 0
    },

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
            throw new Error(`HTTP ${response.status}`);
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
    entry.innerHTML = `
        <span class="log-time">${formatLogTime(log.timestamp)}</span>
        <span class="log-level log-level-${log.level.toLowerCase()}">${log.level}</span>
        <span class="log-message">${escapeHtml(log.message)}</span>
        <span class="log-source">${log.client_name || log.label || ''}</span>
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
            <div class="flex items-center justify-between mt-3">
                <span class="status-badge status-${model.status === 'available' ? 'online' : 'offline'}">${model.status}</span>
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

function initTabs() {
    const tabs = document.querySelectorAll('.nav-tab');

    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const tabId = tab.dataset.tab;

            // Update tab buttons
            tabs.forEach(t => t.classList.remove('active'));
            tab.classList.add('active');

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
        'voicelearnGateway': { bg: 'bg-accent-primary/20', text: 'text-accent-primary' },
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
        'voicelearnGateway': `<svg class="${size} ${styles.text}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"></path></svg>`,
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
    console.log('VoiceLearn Management Console initializing...');

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

    console.log('VoiceLearn Management Console ready');
}

// Start the application
document.addEventListener('DOMContentLoaded', init);
