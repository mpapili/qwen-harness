#!/bin/bash
# Agent1: Task Listener Harness Script
# Monitors tasks directory and creates action items

TASKS_DIR="./tasks"
ACTION_ITEMS_DIR="./action-items"
SYSTEM_PROMPT="./system-prompts/agent1-listener.md"
CHECK_INTERVAL=5

# Ensure directories exist
mkdir -p "$TASKS_DIR" "$ACTION_ITEMS_DIR"

# Generate unique timestamp for action item files
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Get next available action item number
get_next_action_number() {
    local max=0
    for f in "$ACTION_ITEMS_DIR"/action_*.md; do
        if [[ -f "$f" ]]; then
            num=$(basename "$f" | sed 's/action_\([0-9]*\)\.md/\1/')
            if [[ "$num" -gt "$max" ]]; then
                max=$num
            fi
        fi
    done
    echo $((max + 1))
}

# Read a task file and get its name
read_task() {
    local task_file="$1"
    local task_name
    task_name=$(basename "$task_file" .md)
    echo "$task_name"
}

# Create action item for a task
create_action_item() {
    local task_file="$1"
    local task_name="$2"
    local action_number
    action_number=$(get_next_action_number)
    local action_file="$ACTION_ITEMS_DIR/action_${action_number}.md"
    local timestamp
    timestamp=$(get_timestamp)
    
    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")
    
    # Read the task file content
    local task_content
    task_content=$(cat "$task_file")
    
    # Create the prompt for qwen
    local qwen_prompt="You are a Task Listener Agent. Your job is to analyze this task and create a detailed action item.

TASK FILE CONTENT:
$task_content

SYSTEM PROMPT:
$system_prompt_content

Please create a detailed action item markdown file that includes:
1. A clear description of what needs to be done
2. Implementation steps
3. Tools needed
4. Testing criteria
5. Any notes or warnings

Output only the markdown content for the action item file."

    # Call qwen to generate the action item
    echo "Processing task: $task_name"
    qwen_output=$(qwen --yolo --prompt "$qwen_prompt" 2>&1)
    
    # Write the action item
    echo "$qwen_output" > "$action_file"
    
    echo "Created action item: $action_file"
    
    # Move the task file to finished directory
    TASK_FINISHED_DIR="$TASKS_DIR/finished"
    mkdir -p "$TASK_FINISHED_DIR"
    mv "$task_file" "$TASK_FINISHED_DIR/"
    echo "Moved task to: $TASK_FINISHED_DIR/"
}

# Main loop
echo "=== Agent1: Task Listener Started ==="
echo "Monitoring: $TASKS_DIR"
echo "Output: $ACTION_ITEMS_DIR"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Find all .md files in tasks directory
    task_files=("$TASKS_DIR"/*.md)
    
    # Check if any task files exist
    if [[ -e "${task_files[0]}" ]]; then
        for task_file in "${task_files[@]}"; do
            if [[ -f "$task_file" ]]; then
                task_name=$(read_task "$task_file")
                create_action_item "$task_file" "$task_name"
            fi
        done
    fi
    
    # Wait before next check
    sleep $CHECK_INTERVAL
done
