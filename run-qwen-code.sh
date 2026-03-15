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

docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -v "$(pwd)":/workspace:Z \
  --add-host=host.docker.internal:host-gateway \
  -w /workspace \
  -e HOME=/tmp \
  -e OPENAI_API_KEY="dummy-key" \
  -e OPENAI_BASE_URL="http://host.docker.internal:8080" \
  -e OPENAI_MODEL="qwen-code" \
  $DOCKER_SOCK_ARGS \
  "$IMAGE_NAME" /bin/bash
