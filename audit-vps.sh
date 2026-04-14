#!/bin/bash
echo "===== DISK USAGE ====="
df -h /

echo ""
echo "===== TOP CONSUMERS ====="
du -sh /var/www/cortexbuild-ultimate 2>/dev/null
du -sh /var/lib/docker 2>/dev/null
du -sh /var/log 2>/dev/null
du -sh /var/backups 2>/dev/null
du -sh /root/models 2>/dev/null
du -sh /root/llama-cpp 2>/dev/null
du -sh /root/.hermes 2>/dev/null
du -sh /root/.ollama 2>/dev/null
du -sh /root/cortexbuild-work 2>/dev/null

echo ""
echo "===== BACKUPS ====="
ls -lh /var/backups/ 2>/dev/null

echo ""
echo "===== LOG SIZES ====="
du -sh /var/log/journal 2>/dev/null
du -sh /var/log/nginx 2>/dev/null
journalctl --disk-usage 2>/dev/null

echo ""
echo "===== PM2 LOGS ====="
du -sh /root/.pm2/logs/ 2>/dev/null
ls -lh /root/.pm2/logs/ 2>/dev/null

echo ""
echo "===== HERMES LOGS ====="
du -sh /root/.hermes/logs/ 2>/dev/null

echo ""
echo "===== UNUSED DOCKER VOLUMES ====="
docker volume ls -f dangling=true 2>/dev/null

echo ""
echo "===== NGINX CONFIG TEST ====="
nginx -t 2>&1

echo ""
echo "===== GIT STATUS (cortexbuild-work) ====="
cd /root/cortexbuild-work && git status --short 2>/dev/null | head -10
echo "Branch: $(git branch --show-current 2>/dev/null)"
echo "Behind/ahead: $(git rev-list --left-right --count origin/main...HEAD 2>/dev/null)"

echo ""
echo "===== GIT STATUS (production) ====="
cd /var/www/cortexbuild-ultimate && git status --short 2>/dev/null | head -10
echo "Branch: $(git branch --show-current 2>/dev/null)"
echo "Behind/ahead: $(git rev-list --left-right --count origin/main...HEAD 2>/dev/null)"

echo ""
echo "===== CORTEXBUILD UPLOADS DIR ====="
du -sh /var/www/cortexbuild-ultimate/uploads/ 2>/dev/null
ls /var/www/cortexbuild-ultimate/uploads/ 2>/dev/null | wc -l

echo ""
echo "===== CRONTABS ====="
crontab -l 2>/dev/null || echo "No crontab"

echo ""
echo "===== OPEN PORTS (external) ====="
ss -tlnp | grep -v 127.0.0 | grep LISTEN
