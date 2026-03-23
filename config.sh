#!/bin/bash
# Global harness configuration — source this file in each agent script.
# All variables can be overridden by setting them in the environment before launching.

# llama.cpp management server
LLAMA_CPP_HOST="${LLAMA_CPP_HOST:-host.docker.internal}"
LLAMA_CPP_BOUNCE_PORT="${LLAMA_CPP_BOUNCE_PORT:-9090}"

# How long to sleep after a successful server bounce (seconds)
BOUNCE_SLEEP_SECONDS="60"
