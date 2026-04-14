#!/bin/bash
set -euo pipefail
echo "=== CortexBuild Frontend Deploy ==="
PROJECT_DIR="/var/www/cortexbuild-ultimate"
cd "$PROJECT_DIR"
git pull origin main
npm ci --ignore-scripts
npm run build
chown -R www-data:www-data "$PROJECT_DIR/dist"
echo "=== Frontend Deploy Complete ==="
