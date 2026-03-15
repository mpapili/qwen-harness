#!/bin/bash
# rebuild-base-image.sh - Remove old qwen-code-cli image, clear cache, and rebuild

set -euo pipefail

echo "=== Cleaning up old qwen-code-cli image ==="
docker rmi qwen-code-cli:latest 2>/dev/null || echo "  (no existing image to remove)"

echo "=== Clearing builder cache ==="
docker builder prune -a -f

echo "=== Rebuilding qwen-code-cli image ==="
docker build -t qwen-code-cli:latest .

echo "=== Done ==="
echo "Image qwen-code-cli:latest is ready"
