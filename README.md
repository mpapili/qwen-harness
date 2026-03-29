# qwen-harness

A 4-agent agentic workflow harness that uses [Qwen Code](https://github.com/QwenLM/qwen-code) CLI to autonomously process tasks in a loop. Drop a task file in `tasks/`, and the agents will plan it, implement it, review the code, and QA it — automatically.

## How it works

Four agents run concurrently (optionally), each polling their input directory every 5 seconds:

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
    │             writes ONE handoff .md to ready-for-code-review/ and ready-for-qa/
    │             harness moves action item → action-items/finished/ or action-items/failed/
    ├──────────────────────────────────────────┐
    ▼                                          ▼
ready-for-code-review/task_*.md        ready-for-qa/task_*.md
    │                                          │
    ▼                                          ▼
[Agent4: PR Review] — code review + unit     [Agent3: QA] — UI/functional tests +
    │                 tests + static analysis,    │        Playwright tests,
    │                 writes review report        │        writes QA report
    │                 to ready-for-code-review/   │        to ready-for-qa/
    │                 pr-review-report/, creates  │        qa-final-report/,
    │                 fix tasks if needed         │        creates fix tasks if needed
    │                 harness moves task →        │        harness moves task →
    │                 ready-for-code-review/      │        ready-for-qa/
    │                 finished/ or failed/        │        finished/ or failed/
    └──────────────────┬───────────────────────────┘
                       ▼
                 [Loop back to Agent1]
               (if any fix tasks created)
```

### Agent responsibilities

| Agent | Script | Reads from | Writes to | On exit 0 | On exit ≠ 0 |
|-------|--------|-----------|-----------|-----------|-------------|
| Listener | `agent1_listener.sh` | `tasks/*.md` | `action-items/<name>.md` | `tasks/finished/` | `tasks/failed/` |
| Doer | `agent2_doer.sh` | `action-items/*.md` | `outputs/`, `ready-for-code-review/<name>.md`, `ready-for-qa/<name>.md` | `action-items/finished/` | `action-items/failed/` |
| PR Review | `agent4_pr_review.sh` | `ready-for-code-review/*.md` | `ready-for-code-review/pr-review-report/`, `tasks/fix_*.md` | `ready-for-code-review/finished/` | `ready-for-code-review/failed/` |
| QA | `agent3_qa.sh` | `ready-for-qa/task_*.md` | `ready-for-qa/qa-final-report/`, `tasks/fix_*.md` | `ready-for-qa/finished/` | `ready-for-qa/failed/` |

**File routing is always done by the harness script**, not by qwen. qwen's exit code (propagated via `script -e`) determines finished vs failed.

### Agent roles (strict)

- **Agent1 (Listener):** Planning only. Writes a single action item markdown file. Must NOT write any code.
- **Agent2 (Doer):** Implementation only. Writes code to `outputs/` and handoff files to `ready-for-code-review/` and `ready-for-qa/`. Must NOT run tests or Playwright.
- **Agent4 (PR Review):** Code review + static analysis. Runs TypeScript checking, ESLint, HTML validation, CSS linting, broken link detection, and unit tests. Writes a detailed review report. If issues found, writes task files to `tasks/` for Agent1 to pick up.
- **Agent3 (QA):** UI/functional testing only. Runs Playwright + functional tests, writes a final report. If bugs are found, writes task files to `tasks/` for Agent1 to pick up next cycle.

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

### Using with Open Router

Create a `.env` file in the harness directory:

```bash
cat > .env << 'EOF'
OPENAI_API_KEY=sk-or-v1-...
OPENAI_BASE_URL=https://openrouter.io/api/v1
OPENAI_MODEL=qwen/qwen-coder-32b-vision
EOF
```

Then run:
```bash
./run-qwen-code-openrouter.sh
```

The script will load the `.env` file automatically (the `.env` file is git-ignored for security).

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
├── agent_controller.sh          # Starts all agents (1s stagger, configurable concurrency)
├── agent1_listener.sh           # Task → action item
├── agent2_doer.sh               # Action item → implementation + code review + QA handoffs
├── agent3_qa.sh                 # QA handoff → report + fix tasks (UI/functional tests)
├── agent4_pr_review.sh          # Code review handoff → review report + fix tasks
├── config.sh                    # Global config: agent toggles, LLM server, bounce settings
├── system-prompts/
│   ├── agent1-listener.md       # System prompt for Agent1
│   ├── agent2-doer.md           # System prompt for Agent2
│   ├── agent3-qa.md             # System prompt for Agent3
│   └── agent4-pr-review.md      # System prompt for Agent4
├── tasks/                       # Drop .md task files here to start a run
│   ├── finished/                # Tasks completed successfully
│   └── failed/                  # Tasks where qwen exited non-zero
├── action-items/                # Agent1 output (action plan .md files)
│   ├── finished/                # Processed successfully
│   └── failed/                  # qwen exited non-zero
├── outputs/                     # Agent2 implementations (actual code)
├── ready-for-code-review/       # Agent2 → Agent4 handoff .md files
│   ├── finished/                # Code reviewed successfully
│   ├── failed/                  # Code review failed
│   └── pr-review-report/        # PR review reports written by Agent4
├── ready-for-qa/                # Agent2 → Agent3 handoff .md files
│   ├── finished/                # QA'd successfully
│   ├── failed/                  # QA failed
│   └── qa-final-report/         # QA reports written by Agent3
├── agent-logs/                  # Per-agent log files
│   ├── sessions/                # LLM call transcripts (auto-generated)
│   └── llm-calls/               # Raw OpenAI logging JSONs
├── agent-utils/                 # Helper scripts (playwright-tool.sh, etc.)
├── Dockerfile                   # qwen-code-cli image
├── run-qwen-code.sh             # Build + run the container
└── rebuild-base-image.sh        # Rebuild the base Docker image
```

## Agent Control & Configuration

### Agent enable/disable toggles

All agents can be toggled on/off via environment variables in `config.sh`:

```bash
AGENT1_LISTENER_ENABLED=true          # Default: on
AGENT2_DOER_ENABLED=true              # Default: on
AGENT3_QA_ENABLED=false               # Default: off (UI tests require Playwright)
AGENT4_PR_REVIEW_ENABLED=true         # Default: on
```

Override at startup:
```bash
AGENT3_QA_ENABLED=true ./agent_controller.sh
```

### Concurrent agents & LLM slot management

Run multiple agent instances for higher throughput:

```bash
./agent_controller.sh --num-agents 4
```

This spawns 4 concurrent agents with automatic LLM slot management — each agent waits for an available slot before calling qwen, preventing LLM server overload. The queue is FIFO and fair.

### Real-time status monitoring

The controller prints agent status every 30 seconds, showing:
- Agent name and process ID
- Current task being processed (or "idle")
- Whether the agent is RUNNING or STOPPED

Example:
```
=== Pipeline Status [14:23:45] ===
  Agent1 Listener    (PID 1234  )  RUNNING   Processing: my_task.md
  Agent2 Doer        (PID 1235  )  RUNNING   idle
  Agent3 QA          (PID 1236  )  RUNNING   idle
  Agent4 PR Review   (PID 1237  )  STOPPED
```

## LLM Logging & Session Transcripts

All LLM calls are automatically logged with OpenAI-format JSON in `agent-logs/llm-calls/`.

After each agent session, the raw logs are summarized into a human-readable transcript:
```
agent-logs/sessions/session_agent1_listener_20250323_143512.md
```

These transcripts show:
- Full conversation history (system prompt + user message → assistant response)
- Tokens used (prompt + completion)
- Timing information
- Any errors or warnings

### Server Bounce

The harness can bounce (restart) the llama.cpp server between sessions to free memory:

```bash
LLAMA_CPP_BOUNCE_PORT=9090  # POST /bounce to restart server
BOUNCE_SLEEP_SECONDS=60     # Sleep after bounce to let server stabilize
```

### Automatic LLM retry

If qwen exits with code 143 (SIGTERM from server crash/disconnect), it automatically retries up to 3 times:

```bash
MAX_QWEN_RETRIES=3  # Configurable retry count
```

## Static Analysis & Code Review (Agent4)

Agent4 (PR Review) runs five static analysis tools against code submitted by Agent2:

1. **TypeScript/JavaScript** — `npx tsc --checkJs` for type errors
2. **ESLint** — Detects undefined variables, unreachable code, unused vars
3. **HTML Validation** — Checks HTML structure and validity
4. **CSS Linting** — Detects invalid colors, duplicate properties, etc.
5. **Broken Link Checker** — Validates all local/relative hrefs in HTML

All tools run non-interactively (`npx --yes ... < /dev/null`) to prevent hanging. Any findings are reported with severity (HIGH/MEDIUM/LOW), and fix tasks are written to `tasks/` if issues are found.

## Loop behavior

- **Pipeline completes cleanly** when both code review and QA pass — no new files appear in `tasks/` or `action-items/`, and all agents go idle.
- **Issues found by Agent4 (code review)** cause `fix_<name>_pr_N.md` files to appear in `tasks/`, which Agent1 picks up to plan fixes, restarting the cycle.
- **Bugs found by Agent3 (QA)** cause `fix_<name>_qa_N.md` files to appear in `tasks/`, which Agent1 picks up to plan fixes.
- **Failed runs** (non-zero exit) land in the appropriate `failed/` subdirectory and do not re-trigger agents automatically. Inspect the logs in `agent-logs/` to diagnose.
