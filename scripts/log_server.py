#!/usr/bin/env python3
"""
UnaMentis Remote Log Server with Web Interface

A simple HTTP server that receives logs from the iOS app and provides:
- Real-time terminal output with color-coded formatting
- Web interface for viewing logs in browser
- REST API for log retrieval
- Automatic log rotation

Usage:
    python3 scripts/log_server.py [--port 8765] [--bind 127.0.0.1] [--token TOKEN]

Web Interface:
    http://localhost:8765/           - Main dashboard
    http://localhost:8765/logs       - JSON API for logs (token-protected when a token is set)
    http://localhost:8765/clear      - Clear log buffer (token-protected when a token is set)

Security:
    The server binds to 127.0.0.1 (loopback) by default. Device logs can contain
    transcripts, user ids, emails, and prompts, so the data endpoints must not be
    exposed unauthenticated on a shared network.

    For device testing you must bind a non-loopback address AND set a shared secret:
        UNAMENTIS_LOG_TOKEN=<secret> python3 scripts/log_server.py --bind 0.0.0.0
    The server refuses to start on a non-loopback bind without a token. Clients send
    the token via the X-Log-Token header (or Authorization: Bearer); open the dashboard
    with http://<ip>:8765/?token=<secret>.
"""

import argparse
import json
import secrets
import socket
import sys
import os
import threading
from collections import deque
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional
from urllib.parse import parse_qs, urlparse

# Maximum logs to keep in memory
MAX_LOG_BUFFER = 5000

# Thread-safe log storage
log_buffer = deque(maxlen=MAX_LOG_BUFFER)
log_lock = threading.Lock()


# ANSI color codes for terminal
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    TRACE = "\033[90m"
    DEBUG = "\033[36m"
    INFO = "\033[32m"
    NOTICE = "\033[34m"
    WARNING = "\033[33m"
    ERROR = "\033[31m"
    CRITICAL = "\033[35m"
    TIMESTAMP = "\033[90m"
    LABEL = "\033[94m"
    FILE = "\033[90m"
    METADATA = "\033[33m"


LEVEL_COLORS = {
    "TRACE": Colors.TRACE,
    "DEBUG": Colors.DEBUG,
    "INFO": Colors.INFO,
    "NOTICE": Colors.NOTICE,
    "WARNING": Colors.WARNING,
    "ERROR": Colors.ERROR,
    "CRITICAL": Colors.CRITICAL,
}

LEVEL_ICONS = {
    "TRACE": ".",
    "DEBUG": "*",
    "INFO": "i",
    "NOTICE": "o",
    "WARNING": "!",
    "ERROR": "X",
    "CRITICAL": "!!!",
}

# CSS colors for web interface
WEB_LEVEL_COLORS = {
    "TRACE": "#888",
    "DEBUG": "#17a2b8",
    "INFO": "#28a745",
    "NOTICE": "#007bff",
    "WARNING": "#ffc107",
    "ERROR": "#dc3545",
    "CRITICAL": "#6f42c1",
}

# HTML template for web interface
WEB_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UnaMentis Log Viewer</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Mono', Monaco, monospace;
            background: #1a1a2e;
            color: #eee;
            min-height: 100vh;
        }
        .header {
            background: #16213e;
            padding: 15px 20px;
            border-bottom: 1px solid #0f3460;
            display: flex;
            justify-content: space-between;
            align-items: center;
            position: sticky;
            top: 0;
            z-index: 100;
        }
        .header h1 {
            font-size: 18px;
            font-weight: 600;
            color: #e94560;
        }
        .header-info {
            display: flex;
            gap: 20px;
            align-items: center;
            font-size: 13px;
        }
        .header-info span { color: #888; }
        .header-info .value { color: #4ecca3; font-weight: 500; }
        .controls {
            display: flex;
            gap: 10px;
            padding: 10px 20px;
            background: #16213e;
            border-bottom: 1px solid #0f3460;
            flex-wrap: wrap;
            align-items: center;
        }
        .controls label { font-size: 12px; color: #888; }
        .controls select, .controls input {
            background: #1a1a2e;
            border: 1px solid #0f3460;
            color: #eee;
            padding: 6px 10px;
            border-radius: 4px;
            font-size: 12px;
        }
        .controls button {
            background: #e94560;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
        }
        .controls button:hover { background: #c73e54; }
        .controls button.secondary {
            background: #0f3460;
        }
        .controls button.secondary:hover { background: #1a4a7a; }
        .stats {
            display: flex;
            gap: 15px;
            margin-left: auto;
            font-size: 11px;
        }
        .stats .stat { color: #888; }
        .stats .stat-value { color: #4ecca3; }
        #log-container {
            padding: 10px;
            overflow-y: auto;
            height: calc(100vh - 130px);
        }
        .log-entry {
            display: grid;
            grid-template-columns: 90px 60px 120px 1fr;
            gap: 10px;
            padding: 6px 10px;
            border-radius: 4px;
            margin-bottom: 2px;
            font-size: 12px;
            line-height: 1.4;
            align-items: start;
        }
        .log-entry:hover { background: rgba(255,255,255,0.05); }
        .log-entry.TRACE { border-left: 3px solid #888; }
        .log-entry.DEBUG { border-left: 3px solid #17a2b8; }
        .log-entry.INFO { border-left: 3px solid #28a745; }
        .log-entry.NOTICE { border-left: 3px solid #007bff; }
        .log-entry.WARNING { border-left: 3px solid #ffc107; background: rgba(255,193,7,0.1); }
        .log-entry.ERROR { border-left: 3px solid #dc3545; background: rgba(220,53,69,0.1); }
        .log-entry.CRITICAL { border-left: 3px solid #6f42c1; background: rgba(111,66,193,0.15); }
        .log-time { color: #666; font-family: 'SF Mono', Monaco, monospace; }
        .log-level { font-weight: 600; text-transform: uppercase; font-size: 10px; }
        .log-level.TRACE { color: #888; }
        .log-level.DEBUG { color: #17a2b8; }
        .log-level.INFO { color: #28a745; }
        .log-level.NOTICE { color: #007bff; }
        .log-level.WARNING { color: #ffc107; }
        .log-level.ERROR { color: #dc3545; }
        .log-level.CRITICAL { color: #6f42c1; }
        .log-label { color: #4ecca3; font-weight: 500; overflow: hidden; text-overflow: ellipsis; }
        .log-message { color: #eee; word-break: break-word; }
        .log-file { color: #666; font-size: 10px; margin-top: 2px; }
        .log-metadata { color: #ffc107; font-size: 10px; margin-top: 2px; }
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #666;
        }
        .empty-state h2 { font-size: 16px; margin-bottom: 10px; color: #888; }
        .connection-info {
            background: #0f3460;
            border-radius: 8px;
            padding: 20px;
            max-width: 400px;
            margin: 20px auto;
            font-size: 13px;
        }
        .connection-info code {
            background: #1a1a2e;
            padding: 2px 6px;
            border-radius: 3px;
            color: #4ecca3;
        }
        #auto-scroll-indicator {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #e94560;
            color: white;
            padding: 8px 12px;
            border-radius: 20px;
            font-size: 11px;
            display: none;
        }
        #auto-scroll-indicator.active { display: block; }
    </style>
</head>
<body>
    <div class="header">
        <h1>UnaMentis Log Viewer</h1>
        <div class="header-info">
            <span>Server: <span class="value" id="server-ip">{{SERVER_IP}}</span></span>
            <span>Port: <span class="value">{{PORT}}</span></span>
            <span>Logs: <span class="value" id="log-count">0</span></span>
        </div>
    </div>
    <div class="controls">
        <label>Level:</label>
        <select id="level-filter">
            <option value="all">All Levels</option>
            <option value="TRACE">Trace</option>
            <option value="DEBUG">Debug</option>
            <option value="INFO">Info</option>
            <option value="WARNING">Warning</option>
            <option value="ERROR">Error</option>
            <option value="CRITICAL">Critical</option>
        </select>
        <label>Search:</label>
        <input type="text" id="search-filter" placeholder="Filter messages...">
        <label>Label:</label>
        <input type="text" id="label-filter" placeholder="Filter by label...">
        <button onclick="clearLogs()" class="secondary">Clear</button>
        <button onclick="downloadLogs()">Download</button>
        <div class="stats">
            <span class="stat">Errors: <span class="stat-value" id="error-count">0</span></span>
            <span class="stat">Warnings: <span class="stat-value" id="warning-count">0</span></span>
        </div>
    </div>
    <div id="log-container"></div>
    <div id="auto-scroll-indicator">Auto-scroll ON</div>

    <script>
        let logs = [];
        let autoScroll = true;
        let lastLogCount = 0;
        const container = document.getElementById('log-container');
        const levelFilter = document.getElementById('level-filter');
        const searchFilter = document.getElementById('search-filter');
        const labelFilter = document.getElementById('label-filter');

        function formatTime(timestamp) {
            try {
                const d = new Date(timestamp);
                return d.toLocaleTimeString('en-US', { hour12: false }) + '.' +
                       d.getMilliseconds().toString().padStart(3, '0');
            } catch { return timestamp.substring(11, 23); }
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function renderLogs() {
            const level = levelFilter.value;
            const search = searchFilter.value.toLowerCase();
            const label = labelFilter.value.toLowerCase();

            let filtered = logs.filter(log => {
                if (level !== 'all' && log.level !== level) return false;
                if (search && !log.message.toLowerCase().includes(search)) return false;
                if (label && !log.label.toLowerCase().includes(label)) return false;
                return true;
            });

            // Only show last 500 for performance
            filtered = filtered.slice(-500);

            const html = filtered.map(log => `
                <div class="log-entry ${log.level}">
                    <span class="log-time">${formatTime(log.timestamp)}</span>
                    <span class="log-level ${log.level}">${log.level}</span>
                    <span class="log-label" title="${escapeHtml(log.label)}">${escapeHtml(log.label.split('.').pop())}</span>
                    <div>
                        <div class="log-message">${escapeHtml(log.message)}</div>
                        ${log.file ? `<div class="log-file">${escapeHtml(log.file)}:${log.line}</div>` : ''}
                        ${log.metadata ? `<div class="log-metadata">${escapeHtml(JSON.stringify(log.metadata))}</div>` : ''}
                    </div>
                </div>
            `).join('');

            if (filtered.length === 0) {
                container.innerHTML = `
                    <div class="empty-state">
                        <h2>Waiting for logs...</h2>
                        <p>Logs will appear here when the app sends them.</p>
                        <div class="connection-info">
                            <p><strong>For Simulator:</strong> Logs should appear automatically.</p>
                            <p style="margin-top:10px"><strong>For Device:</strong> Set log server IP in app Settings to:</p>
                            <p style="margin-top:5px"><code>{{SERVER_IP}}</code></p>
                        </div>
                    </div>`;
            } else {
                container.innerHTML = html;
            }

            document.getElementById('log-count').textContent = logs.length;
            document.getElementById('error-count').textContent = logs.filter(l => l.level === 'ERROR' || l.level === 'CRITICAL').length;
            document.getElementById('warning-count').textContent = logs.filter(l => l.level === 'WARNING').length;

            if (autoScroll) {
                container.scrollTop = container.scrollHeight;
            }
        }

        const LOG_TOKEN = new URLSearchParams(location.search).get('token') || '';
        function authHeaders() { return LOG_TOKEN ? { 'X-Log-Token': LOG_TOKEN } : {}; }

        function fetchLogs() {
            fetch('/logs', { headers: authHeaders() })
                .then(r => r.json())
                .then(data => {
                    if (data.length !== lastLogCount) {
                        logs = data;
                        lastLogCount = data.length;
                        renderLogs();
                    }
                })
                .catch(() => {});
        }

        function clearLogs() {
            fetch('/clear', { method: 'POST', headers: authHeaders() })
                .then(() => { logs = []; lastLogCount = 0; renderLogs(); });
        }

        function downloadLogs() {
            const blob = new Blob([JSON.stringify(logs, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `unamentis-logs-${new Date().toISOString().slice(0,19).replace(/:/g,'-')}.json`;
            a.click();
        }

        // Auto-scroll toggle on manual scroll
        container.addEventListener('scroll', () => {
            const atBottom = container.scrollHeight - container.scrollTop <= container.clientHeight + 50;
            autoScroll = atBottom;
            document.getElementById('auto-scroll-indicator').classList.toggle('active', autoScroll);
        });

        levelFilter.addEventListener('change', renderLogs);
        searchFilter.addEventListener('input', renderLogs);
        labelFilter.addEventListener('input', renderLogs);

        // Poll for new logs
        setInterval(fetchLogs, 500);
        fetchLogs();
    </script>
</body>
</html>
"""


class LogHandler(BaseHTTPRequestHandler):
    """HTTP handler for receiving log entries and serving web interface."""

    log_file: Optional[str] = None
    quiet: bool = False
    server_ip: str = "localhost"
    port: int = 8765
    auth_token: Optional[str] = None

    def log_message(self, format, *args):
        """Suppress default HTTP logging."""
        pass

    def _is_authorized(self) -> bool:
        """
        Authorize a request to a protected endpoint.

        When no token is configured (the loopback-only dev default) all requests
        are allowed. When a token is configured, the request must present it via
        the X-Log-Token header, an Authorization: Bearer header, or a ?token=
        query parameter (so the browser dashboard can carry it). Comparison is
        constant-time.
        """
        token = self.auth_token
        if not token:
            return True

        presented = self.headers.get("X-Log-Token", "")
        if not presented:
            auth = self.headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                presented = auth[len("Bearer ") :].strip()
        if not presented:
            presented = parse_qs(urlparse(self.path).query).get("token", [""])[0]

        return bool(presented) and secrets.compare_digest(presented, token)

    def _reject_unauthorized(self):
        """Send a 401 for an unauthorized request to a protected endpoint."""
        self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("WWW-Authenticate", "Bearer")
        self.end_headers()
        self.wfile.write(b'{"error": "unauthorized"}')

    def do_POST(self):
        """Handle POST requests."""
        if self.path == "/log":
            if not self._is_authorized():
                self._reject_unauthorized()
                return
            self._handle_log()
        elif self.path == "/clear":
            if not self._is_authorized():
                self._reject_unauthorized()
                return
            self._handle_clear()
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        # The dashboard shell and health check carry no log data and stay open;
        # everything that returns or mutates buffered logs is token-protected.
        if path == "/" or path == "/index.html":
            self._serve_web_interface()
        elif path == "/logs":
            if not self._is_authorized():
                self._reject_unauthorized()
                return
            self._serve_logs_json()
        elif path == "/health":
            self._serve_health()
        else:
            self.send_response(404)
            self.end_headers()

    def _handle_log(self):
        """Handle incoming log entry."""
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            entry = json.loads(body.decode("utf-8"))

            # Store in buffer
            with log_lock:
                log_buffer.append(entry)

            # Display in terminal
            if not self.quiet:
                self._display_log(entry)

            # Save to file if configured
            if self.log_file:
                self._save_log(entry)

            self.send_response(200)
            self.end_headers()

        except Exception as e:
            if not self.quiet:
                print(f"{Colors.ERROR}Error processing log: {e}{Colors.RESET}")
            self.send_response(500)
            self.end_headers()

    def _handle_clear(self):
        """Clear log buffer."""
        with log_lock:
            log_buffer.clear()
        self.send_response(200)
        self.end_headers()
        if not self.quiet:
            print(f"{Colors.INFO}Log buffer cleared{Colors.RESET}")

    def _serve_web_interface(self):
        """Serve the web interface."""
        html = WEB_TEMPLATE.replace("{{SERVER_IP}}", self.server_ip).replace(
            "{{PORT}}", str(self.port)
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", len(html.encode()))
        self.end_headers()
        self.wfile.write(html.encode())

    def _serve_logs_json(self):
        """Serve logs as JSON."""
        with log_lock:
            data = json.dumps(list(log_buffer))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(data.encode()))
        self.end_headers()
        self.wfile.write(data.encode())

    def _serve_health(self):
        """Health check endpoint."""
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"OK")

    def _display_log(self, entry: dict):
        """Display a log entry with color formatting in terminal."""
        level = entry.get("level", "INFO")
        level_color = LEVEL_COLORS.get(level, Colors.INFO)
        icon = LEVEL_ICONS.get(level, "?")

        timestamp = entry.get("timestamp", "")
        try:
            dt = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            time_str = dt.strftime("%H:%M:%S.%f")[:-3]
        except (ValueError, AttributeError, TypeError):
            time_str = timestamp[:12] if timestamp else "??:??:??"

        label = entry.get("label", "unknown")
        short_label = label.split(".")[-1] if "." in label else label
        message = entry.get("message", "")
        file_info = f"{entry.get('file', '?')}:{entry.get('line', '?')}"

        output = (
            f"{Colors.TIMESTAMP}{time_str}{Colors.RESET} "
            f"{level_color}{Colors.BOLD}[{icon}]{Colors.RESET} "
            f"{Colors.LABEL}{short_label:>15}{Colors.RESET} "
            f"{level_color}{message}{Colors.RESET}"
        )

        if level in ("DEBUG", "TRACE"):
            output += f" {Colors.FILE}({file_info}){Colors.RESET}"

        metadata = entry.get("metadata")
        if metadata:
            meta_str = ", ".join(f"{k}={v}" for k, v in metadata.items())
            output += (
                f"\n                    {Colors.METADATA}  [{meta_str}]{Colors.RESET}"
            )

        print(output)
        sys.stdout.flush()

    def _save_log(self, entry: dict):
        """Save log entry to file."""
        if self.log_file:
            with open(self.log_file, "a") as f:
                f.write(json.dumps(entry) + "\n")


def get_local_ip():
    """Get the local IP address of this machine."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def print_banner(host: str, port: int, local_ip: str):
    """Print startup banner with connection info."""
    print(f"""
{Colors.BOLD}╔══════════════════════════════════════════════════════════════╗
║           UnaMentis Remote Log Server v2.0                    ║
╚══════════════════════════════════════════════════════════════╝{Colors.RESET}

{Colors.INFO}Server running on:{Colors.RESET}
  - Terminal logs:  Displayed below
  - Web interface:  {Colors.BOLD}http://localhost:{port}/{Colors.RESET}
  - Network access: {Colors.BOLD}http://{local_ip}:{port}/{Colors.RESET}

{Colors.WARNING}For device testing:{Colors.RESET}
  1. Ensure Mac and device are on same network
  2. In app Settings > Debug, set log server IP to: {Colors.BOLD}{local_ip}{Colors.RESET}
  3. Open web interface to view logs from any browser

{Colors.DIM}Press Ctrl+C to stop{Colors.RESET}

{Colors.BOLD}═══════════════════════════════════════════════════════════════{Colors.RESET}
""")


def main():
    parser = argparse.ArgumentParser(description="UnaMentis Remote Log Server")
    parser.add_argument(
        "--port", "-p", type=int, default=8765, help="Port to listen on"
    )
    parser.add_argument(
        "--bind",
        "-b",
        default="127.0.0.1",
        help="Address to bind to (default: 127.0.0.1, loopback only)",
    )
    parser.add_argument(
        "--token",
        "-t",
        default=os.environ.get("UNAMENTIS_LOG_TOKEN"),
        help="Shared secret required on /log, /logs, /clear "
        "(or set UNAMENTIS_LOG_TOKEN). Required for any non-loopback bind.",
    )
    parser.add_argument("--output", "-o", help="File to save logs to")
    parser.add_argument(
        "--quiet", "-q", action="store_true", help="Suppress terminal output"
    )
    args = parser.parse_args()

    # Fail closed: a non-loopback bind exposes potentially PII-bearing logs to
    # the network, so it must be protected by a shared secret.
    loopback_binds = {"127.0.0.1", "localhost", "::1", ""}
    if args.bind not in loopback_binds and not args.token:
        print(
            f"{Colors.ERROR}Refusing to bind {args.bind} without a token.{Colors.RESET}\n"
            f"Device logs may contain PII. Set a shared secret first, e.g.:\n"
            f"  UNAMENTIS_LOG_TOKEN=$(openssl rand -hex 16) "
            f"python3 scripts/log_server.py --bind {args.bind}",
            file=sys.stderr,
        )
        sys.exit(1)

    local_ip = get_local_ip()

    LogHandler.log_file = args.output
    LogHandler.quiet = args.quiet
    LogHandler.server_ip = local_ip
    LogHandler.port = args.port
    LogHandler.auth_token = args.token

    server = HTTPServer((args.bind, args.port), LogHandler)

    if not args.quiet:
        print_banner(args.bind, args.port, local_ip)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print(f"\n{Colors.INFO}Server stopped.{Colors.RESET}")
        server.shutdown()


if __name__ == "__main__":
    main()
