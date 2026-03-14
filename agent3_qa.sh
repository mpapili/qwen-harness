#!/bin/bash
# Agent3: QA Agent Harness Script
# Monitors ready-for-qa directory and creates work items

READY_FOR_QA_DIR="./ready-for-qa"
OUTPUTS_DIR="./outputs"
TASKS_DIR="./tasks"
SYSTEM_PROMPT="./system-prompts/agent3-qa.md"
CHECK_INTERVAL=5

# Ensure directories exist
mkdir -p "$READY_FOR_QA_DIR" "$OUTPUTS_DIR" "$TASKS_DIR"

# Generate unique timestamp
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Read the QA task file
read_qa_task() {
    local task_file="$1"
    if [[ -f "$task_file" ]]; then
        cat "$task_file"
    fi
}

# Read the actual implementation from outputs directory
read_implementation() {
    local content=""
    # Read all implementation files from outputs/
    for f in "$OUTPUTS_DIR"/implementation_*.md; do
        if [[ -f "$f" ]]; then
            content+="=== $(basename "$f") ===\n"
            content+=$(cat "$f")
            content+=$'\n\n'
        fi
    done
    echo "$content"
}

# Parse work items from QA output and create task files
parse_and_create_work_items() {
    local qwen_output="$1"
    local impl_name="$2"
    local work_item_count=0

    # Ensure tasks directory exists
    mkdir -p "$TASKS_DIR"

    # Check if output contains work items section
    if echo "$qwen_output" | grep -q "## Work Items"; then
        # Extract work items from the output
        local in_work_items=false
        local current_work_item=""
        local work_item_number=1

        while IFS= read -r line; do
            if [[ "$line" =~ ^##\ Work\ Items ]]; then
                in_work_items=true
                continue
            fi

            if $in_work_items; then
                # Check for new work item marker
                if [[ "$line" =~ ^-\ \*\*Work\ Item\*\*: ]]; then
                    # Save previous work item if exists
                    if [[ -n "$current_work_item" ]]; then
                        create_work_item_file "$current_work_item" "$impl_name" "$work_item_count"
                        ((work_item_count++))
                        work_item_number=1
                    fi
                    current_work_item="$line"$'\n'
                elif [[ "$line" =~ ^##\ [A-Z] ]]; then
                    # New section started, save last work item
                    if [[ -n "$current_work_item" ]]; then
                        create_work_item_file "$current_work_item" "$impl_name" "$work_item_count"
                        ((work_item_count++))
                    fi
                    in_work_items=false
                    current_work_item=""
                else
                    current_work_item+="$line"$'\n'
                fi
            fi
        done <<< "$qwen_output"

        # Save last work item if exists
        if [[ -n "$current_work_item" ]]; then
            create_work_item_file "$current_work_item" "$impl_name" "$work_item_count"
            ((work_item_count++))
        fi
    fi

    echo "Created $work_item_count work item(s) from QA output"
}

# Create a work item file from extracted content
create_work_item_file() {
    local work_item_content="$1"
    local impl_name="$2"
    local item_index="$3"
    local work_item_number=$((item_index + 1))
    local work_item_file="$TASKS_DIR/work_item_${work_item_number}_${impl_name}.md"

    # Extract values using sed (more portable than grep -P)
    local priority=$(echo "$work_item_content" | grep "Priority" | sed 's/.*Priority.*:.*//' | sed 's/^[[:space:]]*//' | tr -d '\n')
    local work_item_summary=$(echo "$work_item_content" | grep "Work Item" | sed 's/.*Work Item.*:.*//' | sed 's/^[[:space:]]*//' | tr -d '\n')
    local issue_desc=$(echo "$work_item_content" | grep "Issue" | sed 's/.*Issue.*:.*//' | sed 's/^[[:space:]]*//' | tr -d '\n')
    local expected=$(echo "$work_item_content" | grep "Expected Behavior" | sed 's/.*Expected Behavior.*:.*//' | sed 's/^[[:space:]]*//' | tr -d '\n')
    local actual=$(echo "$work_item_content" | grep "Actual Behavior" | sed 's/.*Actual Behavior.*:.*//' | sed 's/^[[:space:]]*//' | tr -d '\n')

    # Set defaults if empty
    [[ -z "$priority" ]] && priority="MEDIUM"
    [[ -z "$work_item_summary" ]] && work_item_summary="Multiple issues found"
    [[ -z "$issue_desc" ]] && issue_desc="See detailed description below"
    [[ -z "$expected" ]] && expected="Implementation should work correctly"
    [[ -z "$actual" ]] && actual="Implementation has bugs"

    # Build the work item markdown
    cat > "$work_item_file" << EOF
# Work Item: Fix issues in $impl_name

## Priority
$priority

## Issue Summary
$work_item_summary

## Problem Description
$issue_desc

## Expected Behavior
$expected

## Actual Behavior
$actual

## Action Required
Review the implementation, fix the identified issues, and retest.
EOF

    echo "  Created work item: $work_item_file"
}

# Create QA test report for an implementation
create_qa_report() {
    local task_file="$1"
    local impl_name
    impl_name=$(basename "$task_file" .md)

    # Read the QA task description
    local task_content
    task_content=$(read_qa_task "$task_file")

    # Read the system prompt
    local system_prompt_content
    system_prompt_content=$(cat "$SYSTEM_PROMPT")

    # Read the actual implementation content from outputs
    local impl_content
    impl_content=$(read_implementation)

    # Create the prompt for qwen
    local qwen_prompt="You are a QA Agent. Your job is to test and try to break this implementation.

SYSTEM PROMPT:
$system_prompt_content

QA TASK DESCRIPTION:
$task_content

ACTUAL IMPLEMENTATION TO TEST (from outputs directory):
$impl_content

Please create a comprehensive QA test report that includes:
1. Functional tests - does it work as expected?
2. Edge case tests - empty input, boundary values, unexpected data
3. Stress tests - large inputs, repeated operations
4. Security tests - injection attempts, unauthorized access
5. All test results with PASS/FAIL status
6. Any bugs or issues found
7. Recommendations for improvement

IMPORTANT: If the implementation fails any critical tests or has bugs, you MUST create work items in the '## Work Items' section below, with each work item containing:
- **Work Item**: Brief description of what needs to be fixed
- **Priority**: HIGH/MEDIUM/LOW
- **Issue**: Detailed description of the problem
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens

Output only the markdown content for the QA report."

    # Call qwen to generate the QA report
    echo "Running QA on: $impl_name"
    qwen_output=$(qwen --yolo --prompt "$qwen_prompt" 2>&1)

    # Parse and create work items if QA is dissatisfied
    echo "$qwen_output" | parse_and_create_work_items "$impl_name"

    # Move the task file to finished directory
    QA_FINISHED_DIR="$READY_FOR_QA_DIR/finished"
    mkdir -p "$QA_FINISHED_DIR"
    mv "$task_file" "$QA_FINISHED_DIR/"
    echo "Moved QA task to: $QA_FINISHED_DIR/"
}

# Main loop
echo "=== Agent3: QA Agent Started ==="
echo "Monitoring: $READY_FOR_QA_DIR (task descriptions)"
echo "Reads implementations from: $OUTPUTS_DIR (actual code)"
echo "Work items: $TASKS_DIR"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Find all task files in ready-for-qa directory
    task_files=("$READY_FOR_QA_DIR"/task_*.md)

    # Check if any task files exist
    if [[ -e "${task_files[0]}" ]]; then
        for task_file in "${task_files[@]}"; do
            if [[ -f "$task_file" ]]; then
                create_qa_report "$task_file"
            fi
        done
    fi

    # Wait before next check
    sleep $CHECK_INTERVAL
done
