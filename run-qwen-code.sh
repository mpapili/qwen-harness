#! /bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="qwen-code-cli"

# Build the image if it doesn't exist
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "Image '$IMAGE_NAME' not found. Building..." >&2
  docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" >&2
  echo >&2   # ensure clean newline before interactive session
fi

# Mount Docker socket so the container can run docker/podman commands
DOCKER_SOCK_ARGS=""
if [ -S /var/run/docker.sock ]; then
  DOCKER_SOCK_ARGS="-v /var/run/docker.sock:/var/run/docker.sock"
elif [ -S /run/podman/podman.sock ]; then
  DOCKER_SOCK_ARGS="-v /run/podman/podman.sock:/var/run/docker.sock"
fi

# Pre-create all runtime dirs so the bind mounts have targets on the host
mkdir -p "$SCRIPT_DIR/tasks" "$SCRIPT_DIR/action-items" "$SCRIPT_DIR/outputs" \
         "$SCRIPT_DIR/ready-for-qa" "$SCRIPT_DIR/agent-logs" "$SCRIPT_DIR/screenshots"
# .playwright-session.json must exist as a file before it can be bind-mounted
touch "$SCRIPT_DIR/.playwright-session.json"

docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -v "$SCRIPT_DIR:/workspace:ro,Z" \
  -v "$SCRIPT_DIR/tasks:/workspace/tasks:Z" \
  -v "$SCRIPT_DIR/action-items:/workspace/action-items:Z" \
  -v "$SCRIPT_DIR/outputs:/workspace/outputs:Z" \
  -v "$SCRIPT_DIR/ready-for-qa:/workspace/ready-for-qa:Z" \
  -v "$SCRIPT_DIR/agent-logs:/workspace/agent-logs:Z" \
  -v "$SCRIPT_DIR/screenshots:/workspace/screenshots:Z" \
  -v "$SCRIPT_DIR/.playwright-session.json:/workspace/.playwright-session.json:Z" \
  --add-host=host.docker.internal:host-gateway \
  -w /workspace \
  -e HOME=/tmp \
  -e OPENAI_API_KEY="dummy-key" \
  -e OPENAI_BASE_URL="http://host.docker.internal:8080" \
  -e OPENAI_MODEL="qwen-code" \
  $DOCKER_SOCK_ARGS \
  "$IMAGE_NAME" /workspace/agent_controller.sh "$@"
