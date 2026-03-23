#!/bin/bash
# playwright-tool.sh — Visual QA tool for the agent harness
#
# Runs a headless Chromium browser embedded directly in this container
# (no Docker socket required — Playwright + Chromium are baked into the image).
# Takes screenshots saved to screenshots/ and manages session state.
#
# USAGE (call from inside the qwen container):
#   playwright-tool.sh start-browser                  Launch persistent Chromium via CDP (call once per QA session)
#   playwright-tool.sh goto       <url>               Navigate to URL, screenshot
#   playwright-tool.sh screenshot                     Screenshot current page
#   playwright-tool.sh inspect                        List all interactive elements (NO screenshot produced)
#   playwright-tool.sh click      <selector>          Click element by CSS selector, screenshot
#   playwright-tool.sh clickxy    <x> <y>             Click at pixel coordinates, screenshot
#   playwright-tool.sh fill       <selector> <value>  Fill input field, screenshot
#   playwright-tool.sh type       <selector> <value>  Type into input, screenshot
#   playwright-tool.sh hover      <selector>          Hover over element, screenshot
#   playwright-tool.sh scroll     [x] [y]             Scroll page by (x,y) pixels
#   playwright-tool.sh eval       <js-expression>     Evaluate JS in browser
#   playwright-tool.sh stop                           Kill browser + clear session state
#   playwright-tool.sh session                        Show current session state
#
# VIEWING SCREENSHOTS:
#   After each command the relative screenshot path is printed as:
#     SCREENSHOT_SAVED: screenshots/screenshot_001.png
#   Pass that to qwen with the @ prefix to visually inspect it:
#     qwen --yolo --prompt "@screenshots/screenshot_001.png What do you see?"
#
# NETWORKING:
#   Playwright runs inside this container so localhost:<port> reaches any server
#   you started here directly (e.g. python3 -m http.server 8080).

set -euo pipefail

# Playwright is installed inside the image — no Docker needed.
PLAYWRIGHT_NODE_MODULES="/opt/playwright-agent/node_modules"
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/playwright-browsers}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
SCREENSHOTS_DIR="$WORKSPACE_DIR/screenshots"
STATE_FILE="$WORKSPACE_DIR/.playwright-session.json"
RUNNER_SCRIPT="/workspace/agent-utils/playwright-runner.js"

ACTION="${1:-}"

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 1
}

ensure_screenshots_dir() {
  mkdir -p "$SCREENSHOTS_DIR"
  # Ensure the directory is world-writable so the playwright container
  # (which may run as a different UID) can write screenshots into it.
  chmod 777 "$SCREENSHOTS_DIR"
}

run_playwright() {
  ensure_screenshots_dir

  # Run playwright-runner.js directly in this container — no Docker socket needed.
  NODE_PATH="$PLAYWRIGHT_NODE_MODULES" \
  PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH" \
    node "$RUNNER_SCRIPT" "$@"
}

# ── commands ─────────────────────────────────────────────────────────────────

case "$ACTION" in
  stop)
    if [[ -f "$STATE_FILE" ]]; then
      cdp_pid=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('cdpPid',''), end='')" 2>/dev/null || true)
      if [[ -n "$cdp_pid" ]]; then
        kill "$cdp_pid" 2>/dev/null || true
        echo "Killed browser process (pid $cdp_pid)."
      fi
    fi
    rm -f "$STATE_FILE"
    echo "Playwright session cleared."
    exit 0
    ;;

  session)
    if [[ -f "$STATE_FILE" ]]; then
      echo "Current session state:"
      cat "$STATE_FILE"
    else
      echo "No active session."
    fi
    exit 0
    ;;

  start-browser)
    # Kill any stale Chrome already holding port 9222 before launching a new one
    fuser -k 9222/tcp 2>/dev/null || true
    sleep 0.5
    rm -rf /tmp/pw-profile          # Wipe stale HTTP cache + localStorage
    run_playwright "$@"
    ;;

  goto|screenshot|inspect|click|clickxy|fill|type|hover|scroll|eval)
    run_playwright "$@"
    ;;

  ""|--help|-h)
    usage
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Run playwright-tool.sh --help for usage." >&2
    exit 1
    ;;
esac
