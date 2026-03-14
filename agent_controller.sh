#!/bin/bash
# Agent Controller Script
# Manages multiple qwen agents with configurable concurrency

# Default number of agents
NUM_AGENTS="${NUM_AGENTS:-1}"

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
cd "$SCRIPT_DIR"

# Ensure all directories exist
mkdir -p tasks action-items ready-for-qa system-prompts outputs

echo "========================================"
echo "   AGENTIC WORKFLOW CONTROLLER"
echo "========================================"
echo ""
echo "Configuration:"
echo "  - Number of concurrent agents: $NUM_AGENTS"
echo "  - Tasks directory: ./tasks (work items for Agent1)"
echo "  - Action items directory: ./action-items (Agent1 output)"
echo "  - Ready for QA directory: ./ready-for-qa (task descriptions for Agent3)"
echo "  - Outputs directory: ./outputs (actual code/implementation)"
echo ""
echo "Agent Scripts:"
echo "  - agent1_listener.sh: Reads tasks, creates action items"
echo "  - agent2_doer.sh: Reads action items, creates implementations"
echo "  - agent3_qa.sh: Tests implementations, creates QA reports"
echo ""
echo "Starting agents..."
echo "Press Ctrl+C to stop all agents"
echo ""

# Array to store agent PIDs
declare -a AGENT_PIDS

# Function to start an agent
start_agent() {
    local agent_type="$1"
    local agent_script="$2"
    local agent_name="$3"
    
    echo "[Agent] Starting $agent_name..."
    
    # Make script executable if needed
    chmod +x "$agent_script"
    
    # Start the agent in background
    bash "$agent_script" &
    local pid=$!
    AGENT_PIDS+=("$pid")
    
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

# Start the agents
# We'll start all three agent types, but limit total concurrent qwen calls
# Each agent script can spawn qwen commands, so we're managing the agent processes
start_agent "listener" "./agent1_listener.sh" "Listener (Agent1)"
start_agent "doer" "./agent2_doer.sh" "Doer (Agent2)"
start_agent "qa" "./agent3_qa.sh" "QA (Agent3)"

echo ""
echo "========================================"
echo "All agents started successfully!"
echo "========================================"
echo ""
echo "Agent Status:"
for i in "${!AGENT_PIDS[@]}"; do
    pid="${AGENT_PIDS[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
        echo "  [Running] Agent $((i+1)) (PID: $pid)"
    else
        echo "  [Stopped] Agent $((i+1)) (PID: $pid)"
    fi
done
echo ""
echo "Waiting for agents to work..."
echo "Press Ctrl+C to stop all agents"
echo ""

# Keep the controller running and monitor agents
while true; do
    # Check if any agents have crashed
    for i in "${!AGENT_PIDS[@]}"; do
        pid="${AGENT_PIDS[$i]}"
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "[Warning] Agent $((i+1)) (PID: $pid) has crashed!"
            # Optionally restart the agent
            # agent_type=($(echo "$i" | awk '{if($1==0)print "listener"; if($1==1)print "doer"; if($1==2)print "qa"}'))
            # start_agent "agent_type" "./agent${i+1}_agent.sh" "Agent $((i+1))"
        fi
    done
    
    # Sleep before checking again
    sleep 5
done
