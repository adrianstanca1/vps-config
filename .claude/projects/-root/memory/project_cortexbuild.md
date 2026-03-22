---
name: CortexBuild Project Context
description: Key decisions and state for the CortexBuild Ultimate VPS project
type: project
---

CortexBuild Ultimate is a UK construction management platform at /var/www/cortexbuild-ultimate. React/TypeScript frontend, Express + PostgreSQL backend.

**Why:** Full-featured SaaS-style app for UK contractors (company: CortexBuild Ltd, owner: Adrian Stanca).

**How to apply:** When working on this project, the backend is fully live and the frontend should be connecting to it.

## Backend Status (as of 2026-03-22)
- PostgreSQL running locally, database: `cortexbuild`, user: `cortexbuild`, password: `CortexBuild2024!`
- API server running via PM2 on port 3001 (`pm2 list` to check, `pm2 restart cortexbuild-api --update-env` to restart)
- 22 tables, seed data loaded
- Login: adrian@cortexbuild.co.uk / CortexBuild2024! ✅ CONFIRMED WORKING

## Key Decisions
- AI features (AIAssistant module, ai_score on tenders) use LOCAL agents, NOT the Claude API
- Supabase fully removed — custom Express + JWT + bcrypt stack
- pg_hba.conf set to md5 auth (not scram-sha-256) for node-postgres compatibility
- DB connects via 127.0.0.1 (not localhost) to force TCP not Unix socket
- Column-name injection fixed in generic.js via per-table ALLOWED_COLUMNS whitelist
- User management: GET/POST/DELETE /api/auth/users (admin+ only)

## pg_hba.conf / Password Rules (IMPORTANT)
- File must be owned `postgres:postgres` — always `chown postgres:postgres /etc/postgresql/16/main/pg_hba.conf` after editing
- Password must be stored as md5: run as `sudo -u postgres psql` with `SET password_encryption='md5'; ALTER USER cortexbuild WITH PASSWORD '...';` in ONE session
- PostgreSQL md5 = md5(password + username) — verify with: `echo -n 'PASSWORD_USERNAME' | md5sum` matches `pg_authid.rolpassword`
