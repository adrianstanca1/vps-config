#!/bin/bash
cd /var/www/cortexbuild-ultimate
set -a
source .env
set +a

echo "Restarting Docker containers with updated images..."
docker compose up -d --remove-orphans 2>&1 | tail -10

echo ""
echo "===== FINAL STATUS ====="
echo ""
echo "Docker containers:"
docker ps --format "  {{.Names}}: {{.Status}}"

echo ""
echo "Disk after cleanup:"
df -h / | tail -1

echo ""
echo "PM2:"
pm2 list

echo ""
echo "Ollama models:"
curl -s --max-time 3 http://127.0.0.1:11434/api/tags | python3 -c "import json,sys; [print('  ' + m['name']) for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null

echo ""
echo "SSL certs:"
certbot certificates 2>/dev/null | grep -E "Domains|Expiry"

echo ""
echo "Node deps updated:"
cd /var/www/cortexbuild-ultimate && npm outdated 2>/dev/null | wc -l
echo "outdated packages remaining"
