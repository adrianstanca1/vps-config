#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  VPS Comprehensive Update & Cleanup"
echo "  $(date)"
echo "============================================"

# ─────────────────────────────────────────────────
# 1. SYSTEM PACKAGES
# ─────────────────────────────────────────────────
echo ""
echo "[1/8] Updating system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq 2>&1 | tail -5
apt-get autoremove -y -qq 2>&1 | tail -3
apt-get autoclean -qq 2>&1
echo "  ✓ System packages updated"

# ─────────────────────────────────────────────────
# 2. DOCKER IMAGES
# ─────────────────────────────────────────────────
echo ""
echo "[2/8] Pulling latest Docker images..."
cd /var/www/cortexbuild-ultimate

# Pull updated images
docker compose pull 2>&1 | tail -10
echo "  ✓ Docker images pulled"

# ─────────────────────────────────────────────────
# 3. DOCKER CLEANUP
# ─────────────────────────────────────────────────
echo ""
echo "[3/8] Docker cleanup..."

# Remove dangling volumes
DANGLING=$(docker volume ls -f dangling=true -q 2>/dev/null)
if [ -n "$DANGLING" ]; then
    echo "  Removing dangling volumes: $DANGLING"
    docker volume rm $DANGLING 2>/dev/null || true
fi

# Prune build cache
docker builder prune -f 2>&1 | tail -3

# Remove unused images (but keep ones in use)
docker image prune -f 2>&1 | tail -3

echo "  ✓ Docker cleaned up"

# ─────────────────────────────────────────────────
# 4. LOG CLEANUP
# ─────────────────────────────────────────────────
echo ""
echo "[4/8] Cleaning up logs..."

# PM2 logs (159MB error log is excessive)
pm2 flush 2>/dev/null || true
echo "  ✓ PM2 logs flushed"

# Journal logs — keep only 7 days
journalctl --vacuum-time=7d 2>&1 | tail -3

# Truncate old Docker container logs
for logfile in /var/lib/docker/containers/*/*-json.log; do
    if [ -f "$logfile" ]; then
        size=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
        if [ "$size" -gt 10485760 ]; then  # >10MB
            truncate -s 0 "$logfile"
            echo "  Truncated: $logfile"
        fi
    fi
done

# Truncate old nginx logs
for f in /var/log/nginx/*.log; do
    if [ -f "$f" ]; then
        truncate -s 0 "$f" 2>/dev/null
    fi
done
nginx -s reopen 2>/dev/null || true

echo "  ✓ Logs cleaned"

# ─────────────────────────────────────────────────
# 5. CLEAN STALE BACKUPS
# ─────────────────────────────────────────────────
echo ""
echo "[5/8] Cleaning stale backups..."

# Remove old cortexbuild backups (keep latest 2)
BACKUP_DIR="/var/backups"
cd "$BACKUP_DIR"
BACKUP_COUNT=$(ls -d cortexbuild-* 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 2 ]; then
    ls -dt cortexbuild-* 2>/dev/null | tail -n +3 | while read dir; do
        echo "  Removing old backup: $dir"
        rm -rf "$BACKUP_DIR/$dir"
    done
fi

# Clean old .env backup files in production
find /var/www/cortexbuild-ultimate -name ".env.bak.*" -mtime +7 -delete 2>/dev/null

echo "  ✓ Stale backups cleaned"

# ─────────────────────────────────────────────────
# 6. CLEAN TEMP & CACHE
# ─────────────────────────────────────────────────
echo ""
echo "[6/8] Cleaning temp files and caches..."

# Clean apt cache
apt-get clean -qq

# Clean npm cache
npm cache clean --force 2>/dev/null || true

# Remove the wget download if still running (it's a duplicate of what Ollama already has)
WGET_PID=$(pgrep -f "wget.*Meta-Llama" 2>/dev/null || true)
if [ -n "$WGET_PID" ]; then
    kill "$WGET_PID" 2>/dev/null || true
    echo "  Killed stale wget download"
fi

# Clean old llama.cpp tarball
rm -f /root/llama-cpp/llama-ubuntu-x64.tar.gz 2>/dev/null

echo "  ✓ Temp files cleaned"

# ─────────────────────────────────────────────────
# 7. UPDATE NODE DEPS (safe: wanted versions only)
# ─────────────────────────────────────────────────
echo ""
echo "[7/8] Updating Node dependencies (safe/wanted versions)..."
cd /var/www/cortexbuild-ultimate

# Only update to wanted versions (semver-compatible), not latest
npm update --save 2>&1 | tail -10
echo "  ✓ Node dependencies updated to wanted versions"

# ─────────────────────────────────────────────────
# 8. RESTART SERVICES
# ─────────────────────────────────────────────────
echo ""
echo "[8/8] Restarting services..."

# Recreate containers with updated images
cd /var/www/cortexbuild-ultimate
docker compose up -d 2>&1 | tail -10

# Restart PM2 app
pm2 restart cortex-api 2>/dev/null || true

# Reload nginx
nginx -t 2>&1 && nginx -s reload 2>&1

echo "  ✓ Services restarted"

# ─────────────────────────────────────────────────
# FINAL STATUS
# ─────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Update Complete! Final Status:"
echo "============================================"
echo ""
echo "Disk usage:"
df -h / | tail -1
echo ""
echo "Docker containers:"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null
echo ""
echo "PM2:"
pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'  {p[\"name\"]}: {p[\"pm2_env\"][\"status\"]}') for p in d]" 2>/dev/null || pm2 list 2>/dev/null
echo ""
echo "Ollama models:"
curl -s --max-time 3 http://127.0.0.1:11434/api/tags | python3 -c "import json,sys; [print(f'  {m[\"name\"]}') for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null
