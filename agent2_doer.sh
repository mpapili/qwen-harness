#!/bin/bash
# Agent2: Doer Harness Script
# Monitors action-items/ for .md files, calls qwen to implement the action item,
# then moves it to action-items/finished/ (exit 0) or action-items/failed/ (non-zero).

ACTION_ITEMS_DIR="./action-items"
OUTPUTS_DIR="./outputs"
READY_FOR_QA_DIR="./ready-for-qa"
CODE_REVIEW_DIR="./ready-for-code-review"
SYSTEM_PROMPT="/workspace/system-prompts/agent2-doer.md"
CHECK_INTERVAL=5
LOGS_DIR="./agent-logs"
LOG_FILE="$LOGS_DIR/agent2-doer.log"
NUM_AGENTS="${NUM_AGENTS:-1}"

# Load global config (bounce settings, etc.)
# shellcheck source=config.sh
source /workspace/config.sh

# Ensure directories exist
mkdir -p "$ACTION_ITEMS_DIR" "$OUTPUTS_DIR" "$READY_FOR_QA_DIR" "$CODE_REVIEW_DIR" "$LOGS_DIR"

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

    # Read SITE_INDEX.md and README.md from outputs if they exist (project context)
    local outputs_context=""
    if [[ -f "$OUTPUTS_DIR/SITE_INDEX.md" ]]; then
        outputs_context="${outputs_context}

=== outputs/SITE_INDEX.md ===
$(cat "$OUTPUTS_DIR/SITE_INDEX.md")"
    fi
    if [[ -f "$OUTPUTS_DIR/README.md" ]]; then
        outputs_context="${outputs_context}

=== outputs/README.md ===
$(cat "$OUTPUTS_DIR/README.md")"
    fi

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
   If a relevant project exists, ADD TO IT — do not create a new separate directory.${outputs_context:+

=== EXISTING PROJECT CONTEXT ===
$outputs_context}
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

    # Snapshot ready-for-qa before qwen runs so we can detect new handoff files
    local qa_before
    qa_before=$(ls -1 "$READY_FOR_QA_DIR"/*.md 2>/dev/null | sort || true)

    log "Processing action item: $action_name (waiting for LLM slot)"
    local run_log
    run_log=$(mktemp /tmp/qwen-run-XXXXXX.log)
    export QWEN_PROMPT="$qwen_prompt"
    _acquire_llm_slot
    _wait_for_server
    log "--- qwen output start ---"
    _run_qwen "$run_log"
    local script_exit=$QWEN_EXIT
    _bounce_server
    _release_llm_slot
    unset QWEN_PROMPT
    rm -f "$run_log"
    log "--- qwen output end ---"
    log "qwen exit code: $script_exit"

    # On success, fan out any new handoff files to the enabled downstream agents
    if [[ $script_exit -eq 0 ]]; then
        local qa_after
        qa_after=$(ls -1 "$READY_FOR_QA_DIR"/*.md 2>/dev/null | sort || true)
        local new_handoffs
        new_handoffs=$(comm -13 <(echo "$qa_before") <(echo "$qa_after") | grep -v '^$' || true)

        if [[ -n "$new_handoffs" ]]; then
            # Copy to code-review queue if agent4 is enabled
            if [[ "${AGENT4_PR_REVIEW_ENABLED:-true}" == "true" ]]; then
                mkdir -p "$CODE_REVIEW_DIR"
                while IFS= read -r hf; do
                    cp "$hf" "$CODE_REVIEW_DIR/"
                    log "Routed handoff to code review: $(basename "$hf")"
                done <<< "$new_handoffs"
            fi
            # Remove from QA queue if agent3 is disabled
            if [[ "${AGENT3_QA_ENABLED:-true}" != "true" ]]; then
                while IFS= read -r hf; do
                    rm -f "$hf"
                    log "Agent3 disabled — removed from QA queue: $(basename "$hf")"
                done <<< "$new_handoffs"
            fi
        fi

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
