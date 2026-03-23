#!/bin/bash
# Global harness configuration — source this file in each agent script.
# All variables can be overridden by setting them in the environment before launching.

# Agent enable/disable toggles (default: all ON)
AGENT1_LISTENER_ENABLED="${AGENT1_LISTENER_ENABLED:-true}"
AGENT2_DOER_ENABLED="${AGENT2_DOER_ENABLED:-true}"
AGENT3_QA_ENABLED="${AGENT3_QA_ENABLED:-false}"
AGENT4_PR_REVIEW_ENABLED="${AGENT4_PR_REVIEW_ENABLED:-true}"

# llama.cpp management server
LLAMA_CPP_HOST="${LLAMA_CPP_HOST:-host.docker.internal}"
LLAMA_CPP_BOUNCE_PORT="${LLAMA_CPP_BOUNCE_PORT:-9090}"
LLAMA_CPP_INFERENCE_PORT="${LLAMA_CPP_INFERENCE_PORT:-8080}"

# How long to sleep after a successful server bounce (seconds)
BOUNCE_SLEEP_SECONDS="60"

# Wait for the inference server to be ready before starting qwen.
# Polls /health until HTTP 200 or gives up after ~60s.
_wait_for_server() {
    local url="http://${LLAMA_CPP_HOST}:${LLAMA_CPP_INFERENCE_PORT}/health"
    local attempts=30
    for i in $(seq 1 "$attempts"); do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null)
        if [[ "$http_code" == "200" ]]; then
            return 0
        fi
        sleep 2
    done
    echo "[_wait_for_server] WARNING: server not ready after ${attempts} attempts — proceeding anyway"
}

# Run qwen with retry logic for server crashes (exit 143 = SIGTERM from lost connection).
# Usage: _run_qwen <log_file>   (QWEN_PROMPT must be exported before calling)
# Sets global QWEN_EXIT with the final exit code.
MAX_QWEN_RETRIES="${MAX_QWEN_RETRIES:-3}"
_run_qwen() {
    local run_log="$1"
    local llm_log_dir="${LOGS_DIR}/llm-calls"
    mkdir -p "$llm_log_dir"
    local attempt
    for attempt in $(seq 1 "$MAX_QWEN_RETRIES"); do
        if [[ $attempt -gt 1 ]]; then
            echo "[_run_qwen] Retry attempt $attempt of $MAX_QWEN_RETRIES — waiting for server..."
            _wait_for_server
        fi
        script -q -e -c "qwen --yolo --prompt \"\$QWEN_PROMPT\" --openai-logging --openai-logging-dir \"$llm_log_dir\"" "$run_log" \
            | sed --unbuffered 's/\x1b\[[0-9;]*[mGKHFJP]//g; s/\r//g' \
            | tee -a "$LOG_FILE"
        QWEN_EXIT=${PIPESTATUS[0]}
        if [[ $QWEN_EXIT -ne 143 ]]; then
            _summarize_llm_session "$llm_log_dir"
            return
        fi
        echo "[_run_qwen] qwen exited with 143 (server crash/disconnect) — will retry"
    done
    _summarize_llm_session "$llm_log_dir"
}

# Summarize raw openai-*.json call logs into a readable transcript, then delete them.
_summarize_llm_session() {
    local llm_log_dir="$1"
    local agent_label
    agent_label=$(basename "${LOG_FILE%.log}")
    local ts
    ts=$(date +"%Y%m%d_%H%M%S")
    local out="${LOGS_DIR}/sessions/session_${agent_label}_${ts}.md"
    python3 /workspace/agent-utils/summarize-llm-session.py \
        "$llm_log_dir" "$out" "$agent_label" 2>/dev/null \
        && echo "[session] Transcript: $out" \
        || true
}
