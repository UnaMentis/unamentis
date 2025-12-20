# VoiceLearn Management Console

A Next.js web application for monitoring and managing VoiceLearn services.

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
BACKEND_URL=http://localhost:8766
NEXT_PUBLIC_USE_MOCK=false
NEXT_PUBLIC_BACKEND_URL=http://localhost:8766
```

3. Start the frontend:
```bash
npm run dev
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BACKEND_URL` | Python backend URL (server-side) | Empty (mock) |
| `NEXT_PUBLIC_USE_MOCK` | Force mock data mode | `true` |
| `NEXT_PUBLIC_BACKEND_URL` | Backend URL (client-side) | Empty |

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
