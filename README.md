# qwen-harness

A 3-agent agentic workflow harness that uses [Qwen Code](https://github.com/QwenLM/qwen-code) CLI to autonomously process tasks in a loop. Drop a task file in `tasks/`, and the agents will plan it, implement it, and QA it — automatically.

## How it works

Three agents run concurrently, each polling their input directory every 5 seconds:

```
tasks/ --> [Agent1: Listener] --> action-items/ --> [Agent2: Doer] --> outputs/ + ready-for-qa/
                                                                                       |
tasks/ <-- (new work items if bugs found) <-- [Agent3: QA] <--------------------------+
```

| Agent | Script | Input | Output |
|-------|--------|-------|--------|
| Listener | `agent1_listener.sh` | `tasks/*.md` | `action-items/action_N.md` |
| Doer | `agent2_doer.sh` | `action-items/*.md` | `outputs/implementation_*.md` + `ready-for-qa/` |
| QA | `agent3_qa.sh` | `ready-for-qa/task_*.md` | QA report; creates new `tasks/` items if bugs found |

Each agent calls `qwen --yolo --prompt "..."` with its system prompt and the file contents.

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

## Sample task

`tasks/create_site.md` is an included example prompt that asks Qwen to build a full lawn-mower e-commerce single-page site — useful for a quick sanity-check of the pipeline.

## Directory structure

```
qwen-harness/
├── agent_controller.sh        # Starts all three agents
├── agent1_listener.sh         # Task → action item
├── agent2_doer.sh             # Action item → implementation
├── agent3_qa.sh               # Implementation → QA report / new work items
├── system-prompts/
│   ├── agent1-listener.md     # System prompt for Agent1
│   ├── agent2-doer.md         # System prompt for Agent2
│   └── agent3-qa.md           # System prompt for Agent3
├── tasks/                     # Drop .md task files here
├── action-items/              # Agent1 output
├── outputs/                   # Agent2 implementations
├── ready-for-qa/              # Agent2 → Agent3 handoff
├── Dockerfile                 # qwen-code-cli image
└── run-qwen-code.sh           # Build + run the container
