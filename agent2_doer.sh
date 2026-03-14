#!/bin/bash
# Agent2: Doer Harness Script
# Monitors action-items directory and creates implementations

ACTION_ITEMS_DIR="./action-items"
OUTPUTS_DIR="./outputs"
READY_FOR_QA_DIR="./ready-for-qa"
SYSTEM_PROMPT="./system-prompts/agent2-doer.md"
CHECK_INTERVAL=5

# Ensure directories exist
mkdir -p "$ACTION_ITEMS_DIR" "$OUTPUTS_DIR" "$READY_FOR_QA_DIR"

# Generate unique timestamp for output
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Read an action item file
read_action_item() {
    local action_file="$1"
    cat "$action_file"
}

# Process an action item and create implementation
process_action_item() {
    local action_file="$1"
    local action_name
    action_name=$(basename "$action_file" .md)
    local timestamp
    timestamp=$(get_timestamp)
    local output_file="$OUTPUTS_DIR/implementation_${timestamp}.md"
    local qa_task_file="$READY_FOR_QA_DIR/task_${timestamp}.md"

    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")

    # Read the action item content
    local action_content
    action_content=$(read_action_item "$action_file")

    # Create the prompt for qwen
    local qwen_prompt="You are a Doer Agent. Your job is to implement this action item.

SYSTEM PROMPT:
$system_prompt_content

ACTION ITEM TO IMPLEMENT:
$action_content

Your task is to:
1. Create the implementation as described in the action item
2. Write code/files as needed
3. Ensure it works and handles edge cases
4. Include a README with instructions on how to run/use the implementation

Please provide the complete implementation with all necessary files and a README."

    # Call qwen to generate the implementation
    echo "Processing action item: $action_name"
    qwen_output=$(qwen --yolo --prompt "$qwen_prompt" 2>&1)

    # Write the implementation output directly to outputs/
    echo "$qwen_output" > "$output_file"

    # Create a summary file
    cat > "$OUTPUTS_DIR/summary_${timestamp}.txt" << EOF
Implementation Summary
======================
Action Item: $action_name
Timestamp: $timestamp
Status: Completed

The implementation has been generated in: $output_file
EOF

    # Create QA task description file
    cat > "$qa_task_file" << EOF
# QA Task: Review $action_name

## Description
This is a QA task to review the implementation created for the action item: $action_name

## Implementation Location
The actual implementation files are located in: $OUTPUTS_DIR

## Files to Review
- $output_file - The generated implementation

## Testing Criteria
Please review the implementation in the outputs directory and verify it meets the requirements.

## Notes
Timestamp: $timestamp
EOF

    echo "Created implementation: $output_file"
    echo "Created QA task: $qa_task_file"

    # Move the action item to finished directory
    ACTION_FINISHED_DIR="$ACTION_ITEMS_DIR/finished"
    mkdir -p "$ACTION_FINISHED_DIR"
    mv "$action_file" "$ACTION_FINISHED_DIR/"
    echo "Moved action item to: $ACTION_FINISHED_DIR/"
}

# Main loop
echo "=== Agent2: Doer Started ==="
echo "Monitoring: $ACTION_ITEMS_DIR"
echo "Output: $OUTPUTS_DIR"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Find all .md files in action-items directory
    action_files=("$ACTION_ITEMS_DIR"/*.md)
    
    # Check if any action item files exist
    if [[ -e "${action_files[0]}" ]]; then
        for action_file in "${action_files[@]}"; do
            if [[ -f "$action_file" ]]; then
                process_action_item "$action_file"
            fi
        done
    fi
    
    # Wait before next check
    sleep $CHECK_INTERVAL
done
