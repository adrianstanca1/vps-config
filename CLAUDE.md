# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a VPS configuration repo at `/root`. It tracks shell config, systemd services, and GitHub CLI config. The main application lives at `/var/www/cortexbuild-ultimate/` (separate git repo with its own `CLAUDE.md`).

Deploy scripts, utility scripts, and this file are gitignored — they exist on disk but aren't tracked.

## Critical Rules

- **Never run `docker-compose up`** — v1.29.2 is broken on this VPS and takes down DB/Redis/Ollama. Use `docker start <name>` or deploy scripts. Also avoid `docker compose up -d` in `restart-status.sh` and `update-vps.sh`.
- **Never edit files in `/var/www/cortexbuild-ultimate/`** — use deploy scripts instead.
- **`db.js`** exports the pool directly: `module.exports = pool`. Import with `const pool = require('./db')`, NOT `const { pool }` — destructuring yields `undefined`.
- **Server `.env`** loads from `server/` subdirectory, not project root. The deploy script (`deploy-api.sh`) sources both root `.env` and `server/.env`, passing all vars via `-e` flags to the container.
- **`organization_id = NULL`** for `company_owner` users — routes filtering `WHERE organization_id = $1` will crash. Use `COALESCE(organization_id, company_id)` or handle NULL explicitly.
- **Ollama models** are lost on container restart. Re-pull: `docker exec cortexbuild-ollama ollama pull qwen3.5:latest` and `docker exec cortexbuild-ollama ollama pull deepseek-r1:7b`. Other models: `gemma4:latest`, `qwen2.5:7b`, `nomic-embed-text:latest`.

## Production Infrastructure

| Container | Port | Notes |
|-----------|------|-------|
| `cortexbuild-api` | 127.0.0.1:3001 | Built from Dockerfile.api |
| `cortexbuild-db` | 127.0.0.1:5432 | PostgreSQL 16 + pgvector |
| `cortexbuild-redis` | 127.0.0.1:6379 | Redis 7 Alpine |
| `cortexbuild-ollama` | 127.0.0.1:11434 | 5 models pulled |
| `cortexbuild-prometheus` | 127.0.0.1:9090 | |
| `cortexbuild-grafana` | 127.0.0.1:3002 | |

All containers on `cortexbuild-ultimate_cortexbuild` network. Docker hostnames: `cortexbuild-db`, `cortexbuild-redis`, `http://cortexbuild-ollama:11434`. Nginx runs on the host on ports 80/443.

## Commands (Reference)

Most commands here run on the VPS at `/var/www/cortexbuild-ultimate/` (see its own CLAUDE.md for frontend/backend). These are documented for reference when working on VPS config files.

### Deploy (on VPS, at /var/www/cortexbuild-ultimate/)
```bash
bash /root/deploy-api.sh          # Full Docker rebuild + health check
bash /root/deploy-frontend.sh     # git pull + npm ci + build + chown
bash /root/audit-vps.sh          # Disk, logs, Docker, nginx, SSL audit
bash /root/update-vps.sh         # System updates, Docker cleanup, log rotation
bash /root/configure-local-llm.sh  # Configure all AI tools to use local Ollama
docker start cortexbuild-api      # Start stopped container
docker restart cortexbuild-api    # Quick restart (no rebuild)
docker logs cortexbuild-api --tail 50
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Frontend (in /var/www/cortexbuild-ultimate/)
```bash
npm install && npm run dev        # Dev server on :5173 (proxies /api → :3001)
npm run build                     # tsc -b && vite build → dist/
npm run check                     # tsc --noEmit + lint + test
npm test                          # Vitest (happy-dom)
npx vitest run src/test/hooks.test.ts  # Single test file
npm run verify:all                # route verify + tsc + test + lint + build
```

### Backend (in /var/www/cortexbuild-ultimate/server/)
```bash
npm install && npm run dev        # nodemon on :3001
npm start                         # Production mode
```

### Database
```bash
docker exec cortexbuild-db psql -U cortexbuild -d cortexbuild -c "\dt"
docker exec cortexbuild-db psql -U cortexbuild -d cortexbuild -c "\d <table>"
```

### Debugging
```bash
curl -s http://127.0.0.1:3001/api/health   # API health (postgres + redis)
docker exec cortexbuild-redis redis-cli ping  # Redis check
docker exec cortexbuild-api node -e "console.log(process.env.FEATURE_AI_AGENTS)"  # Env var check
```

## Key Directories

| Path | Purpose |
|------|---------|
| `/var/www/cortexbuild-ultimate/` | Main application repo (own git, own CLAUDE.md) |
| `/root/deploy-api.sh` | API deploy script (gitignored) |
| `/root/deploy-frontend.sh` | Frontend deploy script (gitignored) |
| `/root/audit-vps.sh` | VPS health audit (gitignored) |
| `/root/update-vps.sh` | System update script (gitignored) |
| `/root/configure-local-llm.sh` | Local LLM config for all AI tools (gitignored) |

## Git Repositories

| Repo | Path | Remote | Notes |
|------|------|--------|-------|
| Root config | `/root/.git` | None (local only) | Tracks VPS config files |
| Main app | `/var/www/cortexbuild-ultimate/` | `origin/main` on GitHub | Has its own CLAUDE.md |

## Background Services

No long-running systemd services beyond Docker containers. Additional processes:
| Service | Purpose | Notes |
|---------|---------|-------|
| `hysteria-server.service` | VPN/Proxy service | Running |
| `ollama.service` | (disabled — Ollama runs as Docker container `cortexbuild-ollama`) | Inactive |

## Hooks

Claude Code hooks in `~/.claude/settings.json`:
- **PreToolUse (Bash)**: Blocks `docker-compose up`; blocks `rm -rf /var/www`; warns on destructive SQL; warns on `localStorage.getItem('token')`; warns on secrets in .env
- **PreToolUse (Write/Edit)**: Blocks direct edits to `/var/www/cortexbuild-ultimate/`; warns on bare `organization_id = $N` without COALESCE; warns on `company_owner` in isSuper checks
- **PostToolUse (Bash)**: Auto-checks API container health after docker commands
- **PostToolUse (Write/Edit)**: ESLint auto-fix + TypeScript type-check on frontend file writes

## Custom Agents & Skills

Agents in `~/.claude/agents/`:
- **security-reviewer**: Auth, tenant isolation, SQL injection, input validation
- **test-writer**: Vitest unit tests and Playwright E2E scaffolds
- **docker-compose-reviewer**: Docker networking misconfigs, broken service refs
- **api-route-reviewer**: Response shape mismatches, tenant isolation, route ordering, auth gaps
- **frontend-reviewer**: Wrong API module usage, token access anti-patterns, DaisyUI patterns

Skills in `~/.claude/skills/`:
- **api-test**: Smoke test API health, auth, and CRUD endpoints
- **db-migration**: Create timestamped SQL migrations
- **deploy-check**: Validate Docker deployment (DB, health, log scan)
- **new-module**: Scaffold full module (frontend + backend + migration)
- **pr-check**: Pre-commit checklist (tenant filtering, route correctness, Docker safety)
- **container-restart**: Safe container restart with health verification and Ollama model recovery
- **api-debug**: Systematic API debugging (container, logs, DB/Redis, endpoints, env)
- **quick-status**: Instant system health overview
- **db-inspect**: Database inspection (tables, schema, indexes, migrations)

## MCP Servers

Configured in `~/.claude/.mcp.json`:
- **ollama**: Local LLM access via Python MCP server (4 tools: list models, generate code, reasoning, chat)
- **postgres**: Direct database access via `mcp-postgres`

## Login Credentials

- **App**: `superadmin@cortexbuild.com` / `CortexBuild2024!`
- **DB**: `cortexbuild` / `CortexBuild2024!` (PostgreSQL)