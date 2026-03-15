# qwen-harness

A 3-agent agentic workflow harness that uses [Qwen Code](https://github.com/QwenLM/qwen-code) CLI to autonomously process tasks in a loop. Drop a task file in `tasks/`, and the agents will plan it, implement it, and QA it — automatically.

## How it works

Three agents run concurrently, each polling their input directory every 5 seconds:

```
tasks/*.md
    │
    ▼
[Agent1: Listener] — analyzes the task, writes ONE action item .md to action-items/
    │                 harness moves task → tasks/finished/ (success) or tasks/failed/ (error)
    ▼
action-items/*.md
    │
    ▼
[Agent2: Doer] — implements the action item, writes code to outputs/,
    │             writes ONE handoff .md to ready-for-qa/
    │             harness moves action item → action-items/finished/ or action-items/failed/
    ▼
ready-for-qa/task_*.md
    │
    ▼
[Agent3: QA] — actively tests the implementation with Playwright + functional tests,
    │           writes QA report to ready-for-qa/qa-final-report/
    │           if bugs found: writes fix task .md files to tasks/ → loop continues
    │           if all pass: no new tasks → pipeline goes quiet
    │           harness moves task → ready-for-qa/finished/ or ready-for-qa/failed/
```

### Agent responsibilities

| Agent | Script | Reads from | Writes to | On exit 0 | On exit ≠ 0 |
|-------|--------|-----------|-----------|-----------|-------------|
| Listener | `agent1_listener.sh` | `tasks/*.md` | `action-items/<name>.md` | `tasks/finished/` | `tasks/failed/` |
| Doer | `agent2_doer.sh` | `action-items/*.md` | `outputs/`, `ready-for-qa/<name>.md` | `action-items/finished/` | `action-items/failed/` |
| QA | `agent3_qa.sh` | `ready-for-qa/task_*.md` | `ready-for-qa/qa-final-report/`, `tasks/fix_*.md` | `ready-for-qa/finished/` | `ready-for-qa/failed/` |

**File routing is always done by the harness script**, not by qwen. qwen's exit code (propagated via `script -e`) determines finished vs failed.

### Agent roles (strict)

- **Agent1 (Listener):** Planning only. Writes a single action item markdown file. Must NOT write any code.
- **Agent2 (Doer):** Implementation only. Writes code to `outputs/` and a QA handoff file to `ready-for-qa/`. Must NOT run tests or Playwright.
- **Agent3 (QA):** Testing only. Runs Playwright + functional tests, writes a final report. If bugs are found, writes task files to `tasks/` for Agent1 to pick up next cycle.

## Prerequisites

- Docker (or Podman)
- A running **llama-cpp** (or any OpenAI-compatible) server — defaults to `http://host.docker.internal:8080`

## Setup

Build and enter the container:

```bash
chmod +x run-qwen-code.sh
./run-qwen-code.sh
```

This builds a `qwen-code-cli` Docker image (Node 20 + Qwen Code CLI) and drops you into a shell with your current directory mounted at `/workspace`.

The container connects to your host's llama-cpp server at:
```
http://host.docker.internal:8080
```
Change `OPENAI_BASE_URL` in `run-qwen-code.sh` if your server runs elsewhere.

## Usage

Inside the container, start all three agents:

```bash
./agent_controller.sh
```

Agents start with a 1-second stagger (1 → 2 → 3) to avoid startup race conditions.

Then drop a task file into `tasks/`:

```bash
cat > tasks/my_task.md << 'EOF'
Create a simple Python CLI tool that converts Celsius to Fahrenheit.
EOF
```

The agents will pick it up within 5 seconds and begin processing. Watch the terminal for progress. Press `Ctrl+C` to stop all agents.

### Run agents individually

```bash
./agent1_listener.sh   # listener only
./agent2_doer.sh       # doer only
./agent3_qa.sh         # QA only
```

## Directory structure

```
qwen-harness/
├── agent_controller.sh        # Starts all three agents (1s stagger)
├── agent1_listener.sh         # Task → action item
├── agent2_doer.sh             # Action item → implementation + QA handoff
├── agent3_qa.sh               # QA handoff → report + fix tasks
├── system-prompts/
│   ├── agent1-listener.md     # System prompt for Agent1
│   ├── agent2-doer.md         # System prompt for Agent2
│   └── agent3-qa.md           # System prompt for Agent3
├── tasks/                     # Drop .md task files here to start a run
│   ├── finished/              # Tasks completed successfully
│   └── failed/                # Tasks where qwen exited non-zero
├── action-items/              # Agent1 output (action plan .md files)
│   ├── finished/              # Processed successfully
│   └── failed/                # qwen exited non-zero
├── outputs/                   # Agent2 implementations (actual code)
├── ready-for-qa/              # Agent2 → Agent3 handoff .md files
│   ├── finished/              # QA'd successfully
│   ├── failed/                # qwen exited non-zero during QA
│   └── qa-final-report/       # QA reports written by Agent3
├── agent-logs/                # Per-agent log files
├── agent-utils/               # Helper scripts (playwright-tool.sh, etc.)
├── Dockerfile                 # qwen-code-cli image
└── run-qwen-code.sh           # Build + run the container
```

## Loop behavior

- **Pipeline completes cleanly** when QA passes — no new files appear in `tasks/` or `action-items/`, and all agents go idle.
- **Bugs found by QA** cause `fix_<name>_N.md` files to appear in `tasks/`, which Agent1 picks up to plan fixes, restarting the cycle.
- **Failed runs** (non-zero exit) land in the appropriate `failed/` subdirectory and do not re-trigger agents automatically. Inspect the logs in `agent-logs/` to diagnose.
