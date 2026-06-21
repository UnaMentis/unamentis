# UnaMentis Management Console

A Next.js web application for monitoring and managing UnaMentis services.

## Features

- **Dashboard**: Overview of system health, latency metrics, and connected clients
- **Metrics**: Detailed performance metrics and session history
- **Logs**: Real-time log viewer with filtering and search
- **Clients**: Monitor connected iOS devices
- **Servers**: Backend server status (Ollama, Whisper, Piper)
- **Models**: Available AI models across servers

## Getting Started

### Development (Standalone Mode)

The frontend runs independently with mock data - no backend required:

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to view the dashboard.

### With Python Backend

1. Start the Python backend:

```bash
cd ../management
python server.py
```

2. Configure the frontend to use the backend:

```bash
# .env.local
NEXT_PUBLIC_USE_MOCK=false
NEXT_PUBLIC_BACKEND_URL=http://localhost:8766
# Optional: dev-time operator token when the management API has auth enabled.
# At runtime, a token can also be entered in the console banner (stored in
# localStorage) and takes precedence over this value.
NEXT_PUBLIC_MGMT_API_TOKEN=
```

3. Start the frontend:

```bash
npm run dev
```

## Environment Variables

| Variable                     | Description                                           | Default |
| ---------------------------- | ----------------------------------------------------- | ------- |
| `NEXT_PUBLIC_USE_MOCK`       | Force mock data mode                                  | `true`  |
| `NEXT_PUBLIC_BACKEND_URL`    | Management API URL (client-side)                      | Empty   |
| `NEXT_PUBLIC_MGMT_API_TOKEN` | Dev operator token for the management API (optional)  | Empty   |

Note: the old server-side `BACKEND_URL` variable is gone. The Next API proxy
routes that read it (`/api/metrics`, `/api/clients`, `/api/logs`, `/api/stats`,
`/api/servers`, `/api/models`) were removed because the console fetches the
management API directly via `NEXT_PUBLIC_BACKEND_URL`, and the proxies served
mock data whenever `BACKEND_URL` was unset.

When the backend is configured but a request fails, the console shows a
warning banner ("Showing sample data: backend unreachable") instead of
silently substituting mock data. A 401/403 from the management API surfaces
a distinct "authentication required" banner with a token entry field; the
token is persisted in localStorage and sent as `Authorization: Bearer`.

## Architecture

```
┌─────────────────────────────────────┐
│  Next.js Frontend + API Routes     │  ← User-facing, UI, orchestration
│  (Vercel, Cloudflare, etc.)        │
└─────────────────┬───────────────────┘
                  │ HTTP/WebSocket (optional)
┌─────────────────▼───────────────────┐
│  Python Backend (FastAPI)           │  ← Model serving, inference,
│  (Railway, Fly.io, GPU cloud)       │     logging, telemetry
└─────────────────────────────────────┘
```

The frontend works in two modes:

1. **Standalone (Mock Mode)**: Uses built-in mock data for development
2. **Connected Mode**: Proxies requests to Python backend

## Deployment

### Vercel

```bash
npm run build
vercel deploy
```

### Cloudflare Pages

```bash
npm run build
npx wrangler pages deploy .next
```

### Docker

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
```

## Project Structure

```
src/
├── app/
│   ├── api/          # API routes (proxy to backend)
│   ├── layout.tsx    # Root layout
│   └── page.tsx      # Main dashboard
├── components/
│   ├── dashboard/    # Dashboard components
│   └── ui/           # Reusable UI components
├── lib/
│   ├── api-client.ts # API client with mock fallback
│   ├── mock-data.ts  # Mock data for development
│   └── utils.ts      # Utility functions
└── types/
    └── index.ts      # TypeScript types
```

## Tech Stack

- **Framework**: Next.js 15 (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Icons**: Lucide React
