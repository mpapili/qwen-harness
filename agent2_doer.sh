#!/bin/bash
# Agent2: Doer Harness Script
# Monitors action-items/ for .md files, calls qwen to implement the action item,
# then moves it to action-items/finished/ (exit 0) or action-items/failed/ (non-zero).

ACTION_ITEMS_DIR="./action-items"
OUTPUTS_DIR="./outputs"
READY_FOR_QA_DIR="./ready-for-qa"
SYSTEM_PROMPT="/workspace/system-prompts/agent2-doer.md"
CHECK_INTERVAL=5
LOGS_DIR="./agent-logs"
LOG_FILE="$LOGS_DIR/agent2-doer.log"
NUM_AGENTS="${NUM_AGENTS:-1}"

# Load global config (bounce settings, etc.)
# shellcheck source=config.sh
source /workspace/config.sh

# Ensure directories exist
mkdir -p "$ACTION_ITEMS_DIR" "$OUTPUTS_DIR" "$READY_FOR_QA_DIR" "$LOGS_DIR"

# Acquire exclusive lock — exit immediately if another instance is running
LOCK_FILE="$LOGS_DIR/agent2-doer.lock"
STATUS_FILE="$LOGS_DIR/agent2-doer.status"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Agent2] Another instance already running — exiting." | tee -a "$LOG_FILE"; exit 1; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# LLM semaphore helpers - acquire/release slots based on NUM_AGENTS
_acquire_llm_slot() {
    local n="${NUM_AGENTS:-1}"
    while true; do
        for i in $(seq 1 "$n"); do
            exec 10>"$LOGS_DIR/llm-slot-$i.lock"
            if flock -n 10; then
                return
            fi
            exec 10>&-
        done
        sleep 1
    done
}

_release_llm_slot() {
    exec 10>&-
}

# Bounce the llama.cpp server between sessions; sleep if successful
_bounce_server() {
    local url="http://${LLAMA_CPP_HOST}:${LLAMA_CPP_BOUNCE_PORT}/bounce"
    log "Bouncing llama.cpp server at $url ..."
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url" --max-time 10)
    if [[ "$http_code" == "200" ]]; then
        log "Bounce successful (HTTP $http_code) — sleeping ${BOUNCE_SLEEP_SECONDS}s"
        sleep "$BOUNCE_SLEEP_SECONDS"
    else
        log "WARNING: Bounce returned HTTP $http_code — continuing without sleep"
    fi
}

# Process an action item and create implementation
process_action_item() {
    local action_file="$1"
    local action_name
    action_name=$(basename "$action_file" .md)

    # List existing outputs so qwen extends an existing project rather than creating a new one
    local existing_outputs
    existing_outputs=$(ls -1 "$OUTPUTS_DIR" 2>/dev/null | tr '\n' ' ')

    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")

    # Read the action item content
    local action_content
    action_content=$(cat "$action_file")

    # Create the prompt for qwen
    local qwen_prompt="You are a Doer Agent. Your job is to implement the action item below.

=== SYSTEM RESTRICTIONS ===
- Do NOT read or execute the harness scripts at the workspace root (agent*.sh, agent_controller.sh, run-qwen-code.sh, config.sh, rebuild*.sh)
- Do NOT call curl or make any HTTP request to host.docker.internal:9090

SYSTEM PROMPT:
$system_prompt_content

ACTION ITEM TO IMPLEMENT:
$action_content

=== IMPLEMENTATION RULES ===
1. Implement exactly what the action item describes. Write all code and files needed.
2. Check the outputs directory FIRST: /workspace/outputs/
   Existing project(s) already there: $existing_outputs
   If a relevant project exists, ADD TO IT — do not create a new separate directory.
3. Include a README with instructions on how to run/use the implementation.

=== READY-FOR-QA HANDOFF (REQUIRED) ===
When your implementation is complete, write EXACTLY ONE handoff file to /workspace/ready-for-qa/
Use a descriptive filename (e.g. greenline_mowers_homepage.md).

The file MUST contain:
- A summary of what was built or changed
- A '## How to Run' section with the EXACT shell commands to start the app, e.g.:
    cd /workspace/outputs/my-app
    python3 -m http.server 8080
  Then open: http://localhost:8080
- Any setup steps needed before running

DO NOT perform QA yourself. DO NOT run Playwright or browser tests. Just implement and write the handoff file, then stop."

    log "Processing action item: $action_name"
    log "--- qwen output start ---"
    local run_log
    run_log=$(mktemp /tmp/qwen-run-XXXXXX.log)
    export QWEN_PROMPT="$qwen_prompt"
    _acquire_llm_slot
    script -q -e -c 'qwen --yolo --prompt "$QWEN_PROMPT"' "$run_log" \
        | sed --unbuffered 's/\x1b\[[0-9;]*[mGKHFJP]//g; s/\r//g' \
        | tee -a "$LOG_FILE"
    local script_exit=${PIPESTATUS[0]}
    _bounce_server
    _release_llm_slot
    unset QWEN_PROMPT
    rm -f "$run_log"
    log "--- qwen output end ---"
    log "qwen exit code: $script_exit"

    # Move the action item based on exit code
    if [[ $script_exit -eq 0 ]]; then
        mkdir -p "$ACTION_ITEMS_DIR/finished"
        mv "$action_file" "$ACTION_ITEMS_DIR/finished/"
        log "Action item succeeded — moved to finished: $(basename "$action_file")"
    else
        mkdir -p "$ACTION_ITEMS_DIR/failed"
        mv "$action_file" "$ACTION_ITEMS_DIR/failed/"
        log "Action item FAILED (exit $script_exit) — moved to failed: $(basename "$action_file")"
    fi
}

# Main loop
log "=== Agent2: Doer Started ==="
log "Monitoring: $ACTION_ITEMS_DIR"
log "Output: $OUTPUTS_DIR"
log "Check interval: ${CHECK_INTERVAL}s"
log "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

echo "idle" > "$STATUS_FILE"

while true; do
    shopt -s nullglob
    action_files=("$ACTION_ITEMS_DIR"/*.md)
    shopt -u nullglob
    for action_file in "${action_files[@]}"; do
        action_name=$(basename "$action_file" .md)
        echo "Processing: $action_name" > "$STATUS_FILE"
        process_action_item "$action_file"
        echo "idle" > "$STATUS_FILE"
    done
    sleep $CHECK_INTERVAL
done
