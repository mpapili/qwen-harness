#!/bin/bash
# Agent1: Task Listener Harness Script
# Monitors tasks/ for .md files, calls qwen to produce an action item,
# then moves the task to tasks/finished/ (exit 0) or tasks/failed/ (non-zero).

TASKS_DIR="./tasks"
ACTION_ITEMS_DIR="./action-items"
SYSTEM_PROMPT="/workspace/system-prompts/agent1-listener.md"
CHECK_INTERVAL=5
LOGS_DIR="./agent-logs"
LOG_FILE="$LOGS_DIR/agent1-listener.log"
NUM_AGENTS="${NUM_AGENTS:-1}"

# Load global config (bounce settings, etc.)
# shellcheck source=config.sh
source /workspace/config.sh

# Ensure directories exist
mkdir -p "$TASKS_DIR" "$ACTION_ITEMS_DIR" "$LOGS_DIR"

# Acquire exclusive lock — exit immediately if another instance is running
LOCK_FILE="$LOGS_DIR/agent1-listener.lock"
STATUS_FILE="$LOGS_DIR/agent1-listener.status"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Agent1] Another instance already running — exiting." | tee -a "$LOG_FILE"; exit 1; }

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

# Read a task file and get its name
read_task() {
    local task_file="$1"
    basename "$task_file" .md
}

# Create action item for a task
create_action_item() {
    local task_file="$1"
    local task_name="$2"

    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")

    # Read the task file content
    local task_content
    task_content=$(cat "$task_file")

    # Create the prompt for qwen
    local qwen_prompt="You are a Task Listener Agent. Your job is to analyze the task below and produce ONE detailed action item markdown file.

SYSTEM PROMPT:
$system_prompt_content

TASK FILE CONTENT:
$task_content

=== CRITICAL CONSTRAINTS ===
- DO NOT write any code. DO NOT create any implementation files or directories.
- Your ONLY output is a SINGLE action item markdown file written to /workspace/action-items/
- Use a descriptive filename based on the task (e.g. build_contact_form.md).
- Do NOT use numbered filenames like action_1.md.
- The file must follow the action item format from the system prompt above.
- Once you have written the file, you are done. Stop immediately."

    log "Processing task: $task_name"
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

    # Move the task file based on exit code
    if [[ $script_exit -eq 0 ]]; then
        mkdir -p "$TASKS_DIR/finished"
        mv "$task_file" "$TASKS_DIR/finished/"
        log "Task succeeded — moved to finished: $(basename "$task_file")"
    else
        mkdir -p "$TASKS_DIR/failed"
        mv "$task_file" "$TASKS_DIR/failed/"
        log "Task FAILED (exit $script_exit) — moved to failed: $(basename "$task_file")"
    fi
}

# Main loop
log "=== Agent1: Task Listener Started ==="
log "Monitoring: $TASKS_DIR"
log "Output: $ACTION_ITEMS_DIR"
log "Check interval: ${CHECK_INTERVAL}s"
log "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

echo "idle" > "$STATUS_FILE"

while true; do
    shopt -s nullglob
    task_files=("$TASKS_DIR"/*.md)
    shopt -u nullglob
    for task_file in "${task_files[@]}"; do
        task_name=$(read_task "$task_file")
        echo "Processing: $task_name" > "$STATUS_FILE"
        create_action_item "$task_file" "$task_name"
        echo "idle" > "$STATUS_FILE"
    done
    sleep $CHECK_INTERVAL
done
