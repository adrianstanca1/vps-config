# AGENTS.md - CortexBuild Ultimate

## Project Overview
AI-Powered Unified Construction Management Platform for UK contractors. **Stack**: React + TypeScript + Vite (frontend) / Express.js + PostgreSQL (backend, raw SQL via `pg` pool) / Zustand (state) / WebSocket (real-time).

> Note: `prisma/` contains schema definitions for reference only — the backend uses raw SQL, not Prisma ORM.

---

## Build & Development Commands

### Frontend (Vite)
```bash
npm run dev              # Dev server on http://localhost:5173 (proxies /api → localhost:3001)
npm run build            # Production build → dist/
npm run lint             # ESLint check
npm run lint:fix         # Auto-fix ESLint
npm run test             # Run Vitest tests (jsdom environment)
npm run test:coverage    # Coverage report
```

**Running single tests:**
```bash
npx vitest run path/to/file.test.ts
npx vitest run -t "test name pattern"
```

**E2E Tests (Playwright):**
```bash
npm run test:e2e         # Run all E2E tests
npm run test:e2e:ui      # Interactive UI mode
npm run test:e2e:headed  # Run in visible browser
```

### Backend (Express.js)
```bash
cd server
npm install
npm run dev              # nodemon auto-reload on port 3001
npm start                # Production (plain node)
```

### Database Migrations
```bash
psql -d cortexbuild -f server/migrations/001_add_audit_log.sql
```

---

## Code Style Guidelines

### TypeScript Configuration
- **Target**: ES2022, **Module**: ESNext, **ModuleResolution**: bundler
- **Strict mode**: enabled
- **Paths**: `@/*` maps to `src/`
- Root package is ESM (`"type": "module"`); server is CommonJS (`"type": "commonjs"`)

### Import Order
```typescript
// 1. React
import { useState, useEffect } from 'react'

// 2. Third-party libraries
import { z } from 'zod'
import { clsx } from 'clsx'

// 3. Internal modules (aliased)
import { useAppStore } from '@/lib/store/useAppStore'
import { makeHooks } from '@/hooks/useData'

// 4. Components
import { ProjectsList } from '@/components/construction/ProjectsList'
```

### Naming Conventions
- **Files**: PascalCase for components (`ProjectsList.tsx`), camelCase for utilities (`utils.ts`)
- **Components**: PascalCase, `export function ComponentName()`
- **Types/Interfaces**: PascalCase, suffix with `Props`, `Config`, `Response`
- **Constants**: UPPER_SNAKE_CASE
- **Database tables/columns**: snake_case ( PostgreSQL convention)

### Component Pattern
```typescript
interface ComponentProps {
  title: string
  projectId?: string
  onSubmit: (data: FormData) => void
}

export function ComponentName({ title, projectId, onSubmit }: ComponentProps) {
  return <div>{title}</div>
}
```

### Error Handling
```typescript
// API routes - return consistent JSON error format
try {
  const result = await someAsyncOperation()
  return res.json({ data: result })
} catch (error) {
  console.error('Operation failed:', error)
  return res.status(500).json({ error: 'User-friendly message' })
}

// Zod validation (v4)
const schema = z.object({
  title: z.string().min(1),
  priority: z.enum(['LOW', 'MEDIUM', 'HIGH']).optional(),
})
const parsed = schema.safeParse(body)
if (!parsed.success) {
  return res.status(400).json({ error: parsed.error })
}
```

### Async/Await Pattern
- Always use async/await over `.then()`
- Use `Promise.all()` for parallel independent operations

### Database Queries (raw SQL via `pg`)
```typescript
// Always use parameterized queries (no string interpolation)
const result = await pool.query(
  'SELECT * FROM tasks WHERE project_id = $1 AND organization_id = $2',
  [projectId, organizationId]
)

// Multi-tenancy: ALWAYS filter by organization_id
await pool.query(
  'SELECT * FROM projects WHERE organization_id = $1',
  [session.user.organizationId]
)
```

### Backend Generic CRUD Router
`server/routes/generic.js` exports `makeRouter(tableName)` with:
- SQL injection prevention via `ALLOWED_COLUMNS` whitelist
- Order-by validation via `VALID_ORDER_COLS` set
- Automatic audit logging on mutations
- WebSocket broadcast on changes

Adding a new table route:
1. Add table columns to `ALLOWED_COLUMNS` in `generic.js`
2. Register in `server/index.js`: `app.use('/api/your-table', makeRouter('your_table'))`

### Authentication Pattern
```typescript
// JWT required on all /api/* except /api/auth/*, /api/health, /api/deploy, /api/metrics
// JWT middleware in server/middleware/auth.js

// RBAC roles: super_admin, company_owner, admin, project_manager, field_worker
```

### State & Real-time
- **Zustand** stores in `src/lib/store/` — `useAuthStore` (JWT + user), `useAppStore` (UI)
- **WebSocket** at `/ws` via `server/lib/websocket.js`

---

## Architecture Patterns

### Frontend Structure
```
src/
├── App.tsx              # Main router (50+ lazy modules)
├── main.tsx             # Entry point
├── components/
│   ├── modules/         # 50+ construction modules
│   ├── ui/              # Reusable UI components
│   └── shared/          # Layout components
├── hooks/useData.ts     # makeHooks factory for CRUD
├── lib/
│   ├── store/           # Zustand stores
│   ├── validateNotification.ts  # Zod validation
│   └── validations.ts   # Zod schemas
└── types/               # TypeScript types
```

### Backend Route Structure
```
server/
├── index.js             # Express app + route registration
├── db.js                # PostgreSQL pool
├── routes/
│   ├── auth.js          # JWT login/register (bcrypt)
│   ├── generic.js       # CRUD factory
│   ├── oauth.js         # Google/Microsoft OAuth
│   ├── ai.js            # Ollama AI streaming
│   ├── files.js         # File operations
│   ├── upload.js        # Multer uploads
│   ├── email.js         # Nodemailer + SendGrid
│   ├── search.js        # Cross-table search
│   ├── metrics.js       # Health metrics
│   └── deploy.js        # Deployment endpoint
├── middleware/
│   ├── auth.js          # JWT middleware
│   └── uploadRateLimiter.js
└── lib/
    ├── websocket.js     # WebSocket server
    └── ws-broadcast.js
```

### API Response Format
```typescript
// Success
res.json({ data: result })

// Error
res.status(500).json({ error: 'message' })
```

---

## Security Notes

- **File uploads**: Path traversal prevention via `path.normalize()` + `startsWith()`; magic number validation
- **SQL injection**: All generic CRUD routes use column whitelists (`ALLOWED_COLUMNS`)
- **Multi-tenancy**: `organization_id` filtering on all CRUD operations
- **OAuth**: CSRF state parameter with 10-min expiry; rate limiting on callback

---

## Common Pitfalls

1. **Server ESM/CJS**: Root is ESM, server is CommonJS — use `require()`/`module.exports` in server
2. **Multi-tenancy**: NEVER query without `organization_id` filter
3. **Backend startup**: `server/index.js` refuses to start if `DB_PASSWORD` not set in `server/.env`
4. **Zod v4**: API is compatible with v3 but some imports may differ

---

## Key Files
| Path | Purpose |
|------|---------|
| `src/App.tsx` | Main router (50+ lazy modules) |
| `src/hooks/useData.ts` | `makeHooks` factory for CRUD hooks |
| `src/lib/validateNotification.ts` | Zod runtime validation |
| `src/lib/validations.ts` | Zod schemas |
| `server/routes/generic.js` | CRUD factory + column whitelist |
| `server/db.js` | PostgreSQL pool |
| `server/index.js` | Express app entry + route registration |
| `server/middleware/auth.js` | JWT middleware |
