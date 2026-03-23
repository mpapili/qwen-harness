#!/bin/bash
# Agent Controller Script
# Manages multiple qwen agents with configurable concurrency

# Default number of agents
export NUM_AGENTS="${NUM_AGENTS:-1}"

# Load global config for agent toggles
# shellcheck source=config.sh
source /workspace/config.sh

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --num-agents)
            NUM_AGENTS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--num-agents N]"
            echo "  --num-agents  Number of concurrent qwen agents to run (default: 1)"
            echo ""
            echo "The controller will spawn multiple instances of the agent harness scripts."
            echo "Each agent will run independently and monitor their respective directories."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate NUM_AGENTS is a positive integer
if ! [[ "$NUM_AGENTS" =~ ^[0-9]+$ ]] || [[ "$NUM_AGENTS" -lt 1 ]]; then
    echo "Error: --num-agents must be a positive integer"
    exit 1
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd /workspace

# Ensure all directories exist
mkdir -p tasks action-items ready-for-qa ready-for-code-review outputs agent-logs

echo "========================================"
echo "   AGENTIC WORKFLOW CONTROLLER"
echo "========================================"
echo ""
echo "Configuration:"
echo "  - Number of concurrent agents: $NUM_AGENTS"
echo "  - Tasks directory: ./tasks (work items for Agent1)"
echo "  - Action items directory: ./action-items (Agent1 output)"
echo "  - Ready for QA directory: ./ready-for-qa (handoffs for Agent3)"
echo "  - Ready for code review directory: ./ready-for-code-review (handoffs for Agent4)"
echo "  - Outputs directory: ./outputs (actual code/implementation)"
echo ""
echo "Agent Scripts:"
printf "  - agent1_listener.sh:  Reads tasks, creates action items       [%s]\n" "$( [[ "$AGENT1_LISTENER_ENABLED" == "true" ]] && echo "ON" || echo "OFF" )"
printf "  - agent2_doer.sh:      Reads action items, creates impls        [%s]\n" "$( [[ "$AGENT2_DOER_ENABLED" == "true" ]] && echo "ON" || echo "OFF" )"
printf "  - agent3_qa.sh:        UI/functional tests, QA reports          [%s]\n" "$( [[ "$AGENT3_QA_ENABLED" == "true" ]] && echo "ON" || echo "OFF" )"
printf "  - agent4_pr_review.sh: Code review + unit tests, review reports [%s]\n" "$( [[ "$AGENT4_PR_REVIEW_ENABLED" == "true" ]] && echo "ON" || echo "OFF" )"
echo ""
echo "Starting agents..."
echo "Press Ctrl+C to stop all agents"
echo ""

# Array to store agent PIDs and metadata
declare -a AGENT_PIDS
declare -a AGENT_NAMES
declare -a AGENT_STATUS_FILES

STATUS_INTERVAL=30
LOGS_DIR="./agent-logs"

print_status() {
    echo "=== Pipeline Status [$(date '+%H:%M:%S')] ==="
    for i in "${!AGENT_PIDS[@]}"; do
        local pid="${AGENT_PIDS[$i]}"
        local name="${AGENT_NAMES[$i]}"
        local status_file="${AGENT_STATUS_FILES[$i]}"
        if kill -0 "$pid" 2>/dev/null; then
            local current_task
            current_task=$(cat "$status_file" 2>/dev/null || echo "idle")
            printf "  %-18s (PID %-6s)  RUNNING   %s\n" "$name" "$pid" "$current_task"
        else
            printf "  %-18s (PID %-6s)  STOPPED\n" "$name" "$pid"
        fi
    done
}

# Function to start an agent
start_agent() {
    local agent_type="$1"
    local agent_script="$2"
    local agent_name="$3"
    
    local agent_status_file="$4"

    echo "[Agent] Starting $agent_name..."

    # Start the agent in background
    bash "$agent_script" &
    local pid=$!
    AGENT_PIDS+=("$pid")
    AGENT_NAMES+=("$agent_name")
    AGENT_STATUS_FILES+=("$agent_status_file")

    echo "[Agent] $agent_name started with PID: $pid"
}

# Function to stop all agents
stop_all_agents() {
    echo ""
    echo "[Controller] Stopping all agents..."
    
    for pid in "${AGENT_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "[Controller] Stopping agent with PID: $pid"
            kill "$pid" 2>/dev/null
        fi
    done
    
    echo "[Controller] All agents stopped."
    exit 0
}

# Set up signal handler for clean shutdown
trap stop_all_agents SIGINT SIGTERM

# Start the agents with a 1-second delay between each to avoid race conditions
# Each agent script can spawn qwen commands, so we're managing the agent processes
_maybe_start() {
    local enabled="$1"; shift
    if [[ "$enabled" == "true" ]]; then
        start_agent "$@"
        sleep 1
    else
        echo "[Agent] Skipping $3 (disabled in config)"
    fi
}

_maybe_start "$AGENT1_LISTENER_ENABLED"  "listener"   "/workspace/agent1_listener.sh"  "Agent1 Listener"   "$LOGS_DIR/agent1-listener.status"
_maybe_start "$AGENT2_DOER_ENABLED"      "doer"       "/workspace/agent2_doer.sh"       "Agent2 Doer"       "$LOGS_DIR/agent2-doer.status"
_maybe_start "$AGENT3_QA_ENABLED"        "qa"         "/workspace/agent3_qa.sh"         "Agent3 QA"         "$LOGS_DIR/agent3-qa.status"
_maybe_start "$AGENT4_PR_REVIEW_ENABLED" "pr-review"  "/workspace/agent4_pr_review.sh"  "Agent4 PR Review"  "$LOGS_DIR/agent4-pr-review.status"

echo ""
echo "========================================"
echo "All agents started successfully!"
echo "========================================"
echo ""
echo "Agent Status:"
for i in "${!AGENT_PIDS[@]}"; do
    pid="${AGENT_PIDS[$i]}"
    name="${AGENT_NAMES[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
        echo "  [Running] $name (PID: $pid)"
    else
        echo "  [Stopped] $name (PID: $pid)"
    fi
done
echo ""
echo "Waiting for agents to work..."
echo "Press Ctrl+C to stop all agents"
echo ""

# Keep the controller running and monitor agents
last_status_time=0
while true; do
    now=$(date +%s)

    # Print status on startup and every STATUS_INTERVAL seconds
    if (( now - last_status_time >= STATUS_INTERVAL )); then
        print_status
        last_status_time=$now
    fi

    # Check if any agents have crashed
    for i in "${!AGENT_PIDS[@]}"; do
        pid="${AGENT_PIDS[$i]}"
        name="${AGENT_NAMES[$i]}"
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "[Warning] $name (PID: $pid) has crashed!"
        fi
    done

    sleep 5
done
