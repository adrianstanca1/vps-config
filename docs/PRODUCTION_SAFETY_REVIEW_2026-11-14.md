# VPS production safety review — 2026-11-14

## Confirmed findings

- This repository is public. The tracked `CLAUDE.md` previously included a plaintext CortexBuild application login and database password. Those values have been removed from the current default-branch file in commit `45ba62f34b9999654b2bb9aa06966fb96c42430b`. Rotation is still mandatory because Git history, clones and caches may retain the old values.
- The prior `update-vps.sh` performed broad cleanup: dangling Docker volume removal, Docker image/build-cache pruning, PM2 log flushing, journal/log truncation, deletion of older backups, npm dependency updates, and `docker compose up -d`. That is too destructive for a routine maintenance command and conflicts with the repository's own warning not to recreate the production compose stack.
- The prior `configure-local-llm.sh` printed a public Ollama endpoint on port 11435. The public endpoint hint has been removed; Ollama should be private/loopback-only unless protected by an authenticated gateway.
- The existing `deploy-api.sh` removes the existing API container before the new container's health check has succeeded. Its final health check can report a warning without making the script fail. It does not provide a tested rollback path.
- Existing docs refer to an older host and application path. They do not prove the new one.com host has the same services, databases, backups, ports, or repository checkout.

## Changes in this branch

- Replaced `update-vps.sh` with a read-only default status check and explicit `--apply-os-updates` mode.
- Removed any routine Docker prune, volume deletion, backup deletion, log truncation, npm updates, container recreation, or production service restart from that script.
- Removed the public Ollama endpoint hint.
- Updated `CLAUDE.md` with the current command semantics and explicit warnings about deployment rollback and old-host assumptions.

## Validation and limits

- Bash syntax was validated locally for the replacement maintenance script.
- No VPS connection is available in this session; no server state was read or changed.
- No live application deploy, DB migration, backup deletion, Docker cleanup, or service restart was attempted.
