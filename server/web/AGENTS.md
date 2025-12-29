# Operations Console

Next.js/React web application for DevOps monitoring and system health.

**URL:** http://localhost:3000

## Purpose

- System health monitoring (CPU, memory, thermal, battery)
- Service status (Ollama, VibeVoice, Piper, etc.)
- Power/idle management profiles
- Logs, metrics, and performance data
- Client connection monitoring

## Tech Stack

- **Next.js 16.1.0** with App Router
- **React 19.2.3**
- **TypeScript 5**
- **Tailwind CSS 4** for styling
- **Lucide React** for icons
- **clsx** + **tailwind-merge** for class utilities

## Project Structure

```
src/
├── app/           # Next.js App Router pages
├── components/    # React components
└── ...
public/            # Static assets
```

## Commands

```bash
npm run dev     # Start development server (auto-reloads)
npm run build   # Production build
npm run start   # Start production server
npm run lint    # Run ESLint
```

## Conventions

- Use TypeScript for all new files
- Use functional components with hooks
- Use Tailwind CSS for styling (no separate CSS files)
- Use Lucide React for icons
- Follow Next.js App Router patterns

## Development

The Next.js dev server auto-reloads on file changes, so manual restart is rarely needed. If you need to force restart:

```bash
cd server/web && npm run dev
```

## Testing

Run ESLint and build to verify changes:

```bash
npm run lint
npm run build
```

## Writing Style

Never use em dashes or en dashes as sentence interrupters. Use commas for parenthetical phrases or periods to break up long sentences.
