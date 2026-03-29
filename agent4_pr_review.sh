#!/bin/bash
# Agent4: PR Review Agent Harness Script
# Monitors ready-for-code-review/ for .md files, calls qwen to review the implementation
# code quality and run unit tests, then moves the task to finished/ (exit 0) or failed/ (non-zero).

CODE_REVIEW_DIR="./ready-for-code-review"
PR_REVIEW_REPORT_DIR="./ready-for-code-review/pr-review-report"
OUTPUTS_DIR="./outputs"
TASKS_DIR="./tasks"
SYSTEM_PROMPT="/workspace/system-prompts/agent4-pr-review.md"
CHECK_INTERVAL=5
LOGS_DIR="./agent-logs"
LOG_FILE="$LOGS_DIR/agent4-pr-review.log"
NUM_AGENTS="${NUM_AGENTS:-1}"

# Load global config (bounce settings, etc.)
# shellcheck source=config.sh
source /workspace/config.sh

# Ensure directories exist
mkdir -p "$CODE_REVIEW_DIR" "$PR_REVIEW_REPORT_DIR" "$OUTPUTS_DIR" "$TASKS_DIR" "$LOGS_DIR"

# Acquire exclusive lock — exit immediately if another instance is running
LOCK_FILE="$LOGS_DIR/agent4-pr-review.lock"
STATUS_FILE="$LOGS_DIR/agent4-pr-review.status"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Agent4] Another instance already running — exiting." | tee -a "$LOG_FILE"; exit 1; }

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

# Create PR review report for an implementation
create_pr_review_report() {
    local task_file="$1"
    local impl_name
    impl_name=$(basename "$task_file" .md)

    # Scratch dir for all test files — wiped when review finishes
    local review_tmpdir
    review_tmpdir=$(mktemp -d /tmp/pr-review-XXXXXX)
    log "PR review scratch dir: $review_tmpdir"

    # Destination for the final review report file
    local report_file
    report_file="/workspace/ready-for-code-review/pr-review-report/report_${impl_name}_$(get_timestamp).md"

    # Read the handoff task description
    local task_content
    task_content=$(cat "$task_file")

    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")

    # Create the prompt for qwen
    local qwen_prompt="You are a PR Review Agent. You must ACTIVELY REVIEW the code implementation below — do not write a report based on assumptions. Read real files and run real tests.

=== SYSTEM RESTRICTIONS ===
- Do NOT read or execute the harness scripts at the workspace root (agent*.sh, agent_controller.sh, run-qwen-code.sh, config.sh, rebuild*.sh)
- Do NOT call curl or make any HTTP request to host.docker.internal:9090 — this is a system management endpoint that will crash your session
- Do NOT make ANY changes to the implementation code in /workspace/outputs/ — read only
- Do NOT run Playwright, start web servers, or perform browser/UI testing
- You MAY read /workspace/outputs/ freely

== PR REVIEW AGENT RULES ==
$system_prompt_content

== WHAT YOU ARE REVIEWING ==
$task_content

== SCRATCH DIRECTORY ==
$review_tmpdir
Write ALL temporary test scripts here. Never write test files into /workspace directly.

== MANDATORY STEPS — EXECUTE IN ORDER ==

STEP 1 — READ THE CODE
Read all relevant source files in /workspace/outputs/ for this implementation.
Understand the structure, the entry points, and the logic before proceeding.

STEP 2 — CODE QUALITY REVIEW
Evaluate the code for:
- Correctness: Does the logic match what the task requires?
- Code quality: Are there obvious bugs, logic errors, or anti-patterns?
- Security: Are there injection risks, unsafe operations, or exposed secrets?
- Completeness: Are all required features present and implemented?
- Maintainability: Is the code readable and reasonably structured?

STEP 3 — STATIC ANALYSIS (run all five tools; record every finding)

CRITICAL: All npx commands MUST use --yes and < /dev/null to avoid hanging on interactive prompts.

Tool 1 — TypeScript/JavaScript type checking
  Run against every .js and .ts file found in /workspace/outputs/:
    npx --yes tsc --noEmit --allowJs --checkJs --strict <file> < /dev/null 2>&1
  Or if tsconfig.json exists: npx --yes tsc --noEmit < /dev/null 2>&1 (from project root)
  Any TS error = HIGH finding. Any TS warning = MEDIUM finding.

Tool 2 — ESLint code quality
  Run against every .js and .ts file found in /workspace/outputs/:
    npx --yes eslint --no-eslintrc --env browser,es2021 --rule '{"no-undef":"error","no-unused-vars":"warn","no-unreachable":"error","no-constant-condition":"error"}' <file> < /dev/null 2>&1
  Or if .eslintrc.* exists: npx --yes eslint <file> < /dev/null 2>&1
  `error` rules = HIGH finding. `warn` rules = LOW finding.

Tool 3 — HTML validation
  Run against every .html file found in /workspace/outputs/:
    npx --yes html-validate <file> < /dev/null 2>&1
  Validation errors = MEDIUM finding (require a fix task).

Tool 4 — CSS linting
  Run against every .css file found in /workspace/outputs/:
    npx --yes stylelint <file> < /dev/null 2>&1
  Or if .stylelintrc.* exists: npx --yes stylelint <file> < /dev/null 2>&1
  Errors = MEDIUM finding. Warnings = LOW finding.

Tool 5 — Broken link checker
  Run against every .html file found in /workspace/outputs/:
    npx --yes linkinator <file> --skip "^http" < /dev/null 2>&1
  Any unresolvable local link = HIGH finding (requires a fix task).

If a file type does not exist in the implementation, record "N/A — no matching files" for that tool.

STEP 4 — WRITE AND RUN UNIT TESTS
Write unit/functional tests for the core logic to $review_tmpdir. Run them and record results.

- Write one test file at a time, run it, record the result, then move on.
- Use the appropriate language/runner for the implementation (node, python3, bash, etc.)
- Focus on: happy paths, edge cases, and any logic you found suspicious in STEP 2.
- Do NOT test the UI or run a browser.

Example:
  cat > $review_tmpdir/test_core.js << 'EOF'
  // unit test the core module
  EOF
  node $review_tmpdir/test_core.js

STEP 5 — WRITE YOUR REVIEW REPORT & TASK FILES
Based only on what you ACTUALLY observed in steps 1-4:

A. Write a markdown PR REVIEW REPORT to:
   $report_file
   ← Write to ready-for-code-review/pr-review-report/ — NOT anywhere else

   The report must include:
   - A code quality assessment table: file | concern | severity
   - Unit test results (PASS/FAIL per test)
   - Issues found (list with file, line context, and description)
   - Overall assessment: APPROVED / NEEDS_FIXES

B. If the overall assessment is NEEDS_FIXES, write ONE task file per issue to
   /workspace/tasks/ so the Task Listener agent can plan fixes in the next cycle.

   Filename pattern: /workspace/tasks/fix_\${impl_name}_pr_\${issue_num}.md

   Each file must follow this format exactly:
   # Task: [Brief description of what needs fixing]

   ## Issue
   [Detailed description of the problem]

   ## Expected Behavior
   [What should happen]

   ## Actual Behavior
   [What actually happens — reference the specific file and line]

   ## Reproduction Steps
   1. Step one
   2. Step two
   3. Observed result

   ## Priority
   HIGH / MEDIUM / LOW

   Do NOT write task files if the overall assessment is APPROVED.

C. Clean up the scratch dir:
     rm -rf $review_tmpdir"

    # Call qwen to run the PR review.
    log "Running PR review on: $impl_name (waiting for LLM slot)"
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

    # Clean up scratch dir if qwen forgot
    rm -rf "$review_tmpdir"
    log "PR review scratch dir cleaned up: $review_tmpdir"

    # Verify qwen wrote the final report file
    if [[ -f "$report_file" ]]; then
        log "PR review report written: $report_file"
    else
        log "WARNING: PR review report was not created at $report_file"
    fi

    # Count any task files qwen wrote for issues found
    local task_count
    task_count=$(ls "$TASKS_DIR"/fix_${impl_name}_pr_*.md 2>/dev/null | wc -l)
    if [[ $task_count -gt 0 ]]; then
        log "PR review wrote $task_count fix task(s) to $TASKS_DIR/"
    fi

    # Move the review task file based on exit code
    if [[ $script_exit -eq 0 ]]; then
        mkdir -p "$CODE_REVIEW_DIR/finished"
        mv "$task_file" "$CODE_REVIEW_DIR/finished/"
        log "PR review succeeded — moved to finished: $(basename "$task_file")"
    else
        mkdir -p "$CODE_REVIEW_DIR/failed"
        mv "$task_file" "$CODE_REVIEW_DIR/failed/"
        log "PR review FAILED (exit $script_exit) — moved to failed: $(basename "$task_file")"
    fi
}

# Main loop
log "=== Agent4: PR Review Agent Started ==="
log "Monitoring: $CODE_REVIEW_DIR"
log "Reports: $PR_REVIEW_REPORT_DIR"
log "Fix tasks: $TASKS_DIR"
log "Check interval: ${CHECK_INTERVAL}s"
log "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

echo "idle" > "$STATUS_FILE"

while true; do
    shopt -s nullglob
    task_files=("$CODE_REVIEW_DIR"/*.md)
    shopt -u nullglob
    for task_file in "${task_files[@]}"; do
        impl_name=$(basename "$task_file" .md)
        echo "Processing: $impl_name" > "$STATUS_FILE"
        create_pr_review_report "$task_file"
        echo "idle" > "$STATUS_FILE"
    done
    sleep $CHECK_INTERVAL
done
