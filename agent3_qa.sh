#!/bin/bash
# Agent3: QA Agent Harness Script
# Monitors ready-for-qa/ for .md files, calls qwen to actively test the implementation,
# then moves the task to ready-for-qa/finished/ (exit 0) or ready-for-qa/failed/ (non-zero).

READY_FOR_QA_DIR="./ready-for-qa"
QA_FINAL_REPORT_DIR="./ready-for-qa/qa-final-report"
OUTPUTS_DIR="./outputs"
TASKS_DIR="./tasks"
SYSTEM_PROMPT="/workspace/system-prompts/agent3-qa.md"
CHECK_INTERVAL=5
LOGS_DIR="./agent-logs"
LOG_FILE="$LOGS_DIR/agent3-qa.log"
NUM_AGENTS="${NUM_AGENTS:-1}"

# Load global config (bounce settings, etc.)
# shellcheck source=config.sh
source /workspace/config.sh

# Ensure directories exist
mkdir -p "$READY_FOR_QA_DIR" "$QA_FINAL_REPORT_DIR" "$OUTPUTS_DIR" "$TASKS_DIR" "$LOGS_DIR"

# Acquire exclusive lock — exit immediately if another instance is running
LOCK_FILE="$LOGS_DIR/agent3-qa.lock"
STATUS_FILE="$LOGS_DIR/agent3-qa.status"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Agent3] Another instance already running — exiting." | tee -a "$LOG_FILE"; exit 1; }

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

# Generate unique timestamp
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Create QA test report for an implementation
create_qa_report() {
    local task_file="$1"
    local impl_name
    impl_name=$(basename "$task_file" .md)

    # Kill any lingering web server from a crashed previous session
    fuser -k 8080/tcp 2>/dev/null || true

    # Clear stale screenshots from any previous QA run
    rm -f /workspace/screenshots/screenshot_*.png 2>/dev/null || true
    # Reset the playwright session screenshot counter to 0
    if [[ -f /workspace/.playwright-session.json ]]; then
        python3 -c "
import json, sys
with open('/workspace/.playwright-session.json') as f: d = json.load(f)
d['count'] = 0
with open('/workspace/.playwright-session.json', 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || true
    fi

    # Scratch dir for all test files — wiped when QA finishes
    local qa_tmpdir
    qa_tmpdir=$(mktemp -d /tmp/qa-XXXXXX)
    log "QA scratch dir: $qa_tmpdir"

    # Destination for the final QA report file
    local report_file
    report_file="/workspace/ready-for-qa/qa-final-report/report_${impl_name}_$(get_timestamp).md"

    # Read the QA task description
    local task_content
    task_content=$(cat "$task_file")

    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")

    # Running findings log — one line per screenshot, reviewed at STEP 5 and then deleted
    local qa_findings_log="$qa_tmpdir/findings.log"
    touch "$qa_findings_log"

    # Create the prompt for qwen
    local qwen_prompt="You are a QA Agent. You must ACTIVELY TEST the implementation below — do not write a report based on assumptions. Run real commands and report what you actually observe.

=== SYSTEM RESTRICTIONS ===
- Do NOT read or execute the harness scripts at the workspace root (agent*.sh, agent_controller.sh, run-qwen-code.sh, config.sh, rebuild*.sh)
- Do NOT call curl or make any HTTP request to host.docker.internal:9090 — this is a system management endpoint that will crash your session
- You MAY read /workspace/outputs/ and use /workspace/agent-utils/playwright-tool.sh

== QA AGENT RULES ==
$system_prompt_content

== WHAT YOU ARE TESTING ==
$task_content

== SCRATCH DIRECTORY ==
$qa_tmpdir
Write ALL temporary test scripts here. Never write test files into /workspace directly.

== MANDATORY STEPS — EXECUTE IN ORDER ==

STEP 1 — START THE SERVER
Read the '## How to Run' section in the task above and run those exact commands in the background, e.g.:
  cd /workspace/outputs/<app-dir> && python3 -m http.server 8000 &
  sleep 2   # wait for server to be ready

STEP 2 — VISUAL BROWSER TESTING WITH PLAYWRIGHT (REQUIRED — DO NOT SKIP)
You MUST run playwright-tool.sh for every web app. These are real commands you must execute:

FINDINGS LOG: After EVERY screenshot review, you MUST append exactly one line to:
  $qa_findings_log
Format: screenshot_NNN.png | STATUS | one-sentence finding
Example: echo \"screenshot_001.png | PASS | Homepage loads correctly with hero image and nav\" >> $qa_findings_log
This log is your running record — you will use it in STEP 5 to write the final report.

HARD LIMIT: Stop visual testing after 20 screenshots maximum. Once the findings log has
20 lines, call playwright-tool.sh stop and proceed to STEP 3 immediately.
Check the count with: wc -l < $qa_findings_log

  # Start persistent browser — keeps ALL page state (scroll, modals, forms) across every subsequent call
  /workspace/agent-utils/playwright-tool.sh start-browser

  # Take initial screenshot of the homepage
  /workspace/agent-utils/playwright-tool.sh goto http://localhost:8000
  # → prints: SCREENSHOT_SAVED: screenshots/screenshot_001.png

  # Visually inspect it — open the screenshot file directly using your image viewing tool (do NOT
  # spawn a nested qwen subprocess; you can read image files yourself with your built-in Read tool).
  # Read the file at the path printed in SCREENSHOT_SAVED above (e.g. screenshots/screenshot_001.png).
  # Classify its status using EXACTLY one of these labels:
  #   SCREENSHOT_STATUS: PASS          — everything looks correct
  #   SCREENSHOT_STATUS: BUGGY         — clear defect (broken layout, error message, wrong content)
  #   SCREENSHOT_STATUS: APPEARS_BUGGY — something looks off (unexpected spacing, missing elements, wrong colours)
  #   SCREENSHOT_STATUS: NOT_WORKING   — an interactive element had no visible effect after click/fill
  # Then immediately log your finding (replace STATUS and description with your actual observation):
  echo \"screenshot_001.png | STATUS | one-sentence finding\" >> $qa_findings_log

  # Check limit before continuing: if findings log has 20 lines, stop now
  if [[ \$(wc -l < $qa_findings_log) -ge 20 ]]; then /workspace/agent-utils/playwright-tool.sh stop; fi

  # IMPORTANT: call goto EXACTLY ONCE per URL. Never call goto again during the same session.
  # Use click, scroll, fill, hover for all subsequent interactions.

  # BEFORE clicking anything, get real selectors from the live DOM:
  /workspace/agent-utils/playwright-tool.sh inspect
  # → prints ELEMENTS: [...] and NO_SCREENSHOT (inspect is data-only, no screenshot is saved)
  # Read the ELEMENTS JSON output above and pick real selector values from it.
  # Example: if ELEMENTS contains {\"selector\":\"#nav-products\"}, then run:
  #   /workspace/agent-utils/playwright-tool.sh click \"#nav-products\"
  # Do NOT use angle-bracket placeholders — substitute actual selector strings from the JSON.

  # Test interactions — use the selector values returned by inspect above
  # Scroll before clicking elements that may be below the fold:
  /workspace/agent-utils/playwright-tool.sh scroll 0 800
  # Then click a real selector from the ELEMENTS JSON (e.g. \"a.nav-link\", \"#submit-btn\"):
  /workspace/agent-utils/playwright-tool.sh click \"SELECTOR_FROM_INSPECT_OUTPUT\"
  # Fill inputs using real selectors from ELEMENTS JSON:
  /workspace/agent-utils/playwright-tool.sh fill \"INPUT_SELECTOR_FROM_INSPECT\" \"test value\"

  # If a selector click fails, fall back to coordinate click (estimate coords from the 1920x1080 screenshot):
  /workspace/agent-utils/playwright-tool.sh clickxy 960 400

  # After EACH action, inspect the new screenshot directly — use your built-in Read/image tool on
  # the path printed in SCREENSHOT_SAVED (e.g. screenshots/screenshot_NNN.png).
  # DO NOT run a nested \`qwen --yolo --prompt\` subprocess — that spawns a new qwen process and
  # causes 15–30 second idle gaps where llama.cpp receives no requests at all.
  # You are already running inside qwen; just open the image file yourself.
  # Classify using one of: PASS | BUGGY | APPEARS_BUGGY | NOT_WORKING
  # Then immediately log your finding:
  echo \"screenshot_NNN.png | STATUS | one-sentence finding\" >> $qa_findings_log
  # Check limit: if findings log has 20 lines, stop visual testing now
  if [[ \$(wc -l < $qa_findings_log) -ge 20 ]]; then /workspace/agent-utils/playwright-tool.sh stop; fi

  # When done (or when 20-screenshot limit reached)
  /workspace/agent-utils/playwright-tool.sh stop

STEP 3 — FUNCTIONAL / EDGE CASE TESTS
Write one test script at a time to $qa_tmpdir, run it, record the result, delete it, then move to the next.
Example:
  cat > $qa_tmpdir/test_calc.js << 'EOF'
  // test the calculator logic
  EOF
  node $qa_tmpdir/test_calc.js
  rm $qa_tmpdir/test_calc.js

STEP 4 — KILL THE SERVER
  kill \$SERVER_PID 2>/dev/null || true

STEP 5 — WRITE YOUR QA REPORT & TASK FILES
Based only on what you ACTUALLY observed in steps 1-4:

First, read your running findings log to review all one-line screenshot findings:
  cat $qa_findings_log

A. Write a markdown QA REPORT summarizing your findings to:
   $report_file
   ← Write to ready-for-qa/qa-final-report/ — NOT to screenshots/ or any other directory

   The report must include:
   - A screenshot review table populated from your findings log: filename | status | one-line finding
   - Functional test results (PASS/FAIL per test)
   - Bugs and improvements found (list with reproduction steps)
   - Overall assessment: PASS / NEEDS_FIXES

B. If the overall assessment is NEEDS_FIXES, write ONE task file per bug/improvement to
   /workspace/tasks/ so the Task Listener agent can plan fixes in the next cycle.

   Filename pattern: /workspace/tasks/fix_\${impl_name}_\${issue_num}.md

   Each file must follow this format exactly:
   # Task: [Brief description of what needs fixing]

   ## Issue
   [Detailed description of the problem]

   ## Expected Behavior
   [What should happen]

   ## Actual Behavior
   [What actually happens]

   ## Reproduction Steps
   1. Step one
   2. Step two
   3. Observed result

   ## Priority
   HIGH / MEDIUM / LOW

   Do NOT write task files if the overall assessment is PASS.

C. Clean up the findings log now that the final report is written:
     rm -f $qa_findings_log"

    # Call qwen to run the QA.
    log "Running QA on: $impl_name"
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

    # Clean up scratch dir
    rm -rf "$qa_tmpdir"
    log "QA scratch dir cleaned up: $qa_tmpdir"

    # Verify qwen wrote the final report file
    if [[ -f "$report_file" ]]; then
        log "QA final report written: $report_file"
    else
        log "WARNING: QA report was not created at $report_file"
    fi

    # Count any task files qwen wrote for issues found
    local task_count
    task_count=$(ls "$TASKS_DIR"/fix_${impl_name}_*.md 2>/dev/null | wc -l)
    if [[ $task_count -gt 0 ]]; then
        log "QA wrote $task_count fix task(s) to $TASKS_DIR/"
    fi

    # Move the QA task file based on exit code
    if [[ $script_exit -eq 0 ]]; then
        mkdir -p "$READY_FOR_QA_DIR/finished"
        mv "$task_file" "$READY_FOR_QA_DIR/finished/"
        log "QA succeeded — moved to finished: $(basename "$task_file")"
    else
        mkdir -p "$READY_FOR_QA_DIR/failed"
        mv "$task_file" "$READY_FOR_QA_DIR/failed/"
        log "QA FAILED (exit $script_exit) — moved to failed: $(basename "$task_file")"
    fi
}

# Main loop
log "=== Agent3: QA Agent Started ==="
log "Monitoring: $READY_FOR_QA_DIR"
log "Reports: $QA_FINAL_REPORT_DIR"
log "Fix tasks: $TASKS_DIR"
log "Check interval: ${CHECK_INTERVAL}s"
log "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

echo "idle" > "$STATUS_FILE"

while true; do
    shopt -s nullglob
    task_files=("$READY_FOR_QA_DIR"/*.md)
    shopt -u nullglob
    for task_file in "${task_files[@]}"; do
        impl_name=$(basename "$task_file" .md)
        echo "Processing: $impl_name" > "$STATUS_FILE"
        create_qa_report "$task_file"
        echo "idle" > "$STATUS_FILE"
    done
    sleep $CHECK_INTERVAL
done
