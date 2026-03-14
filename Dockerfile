FROM node:20-slim

# Required by Qwen Code (needs Node 20+)
WORKDIR /workspace

# Install Qwen Code CLI globally
RUN npm install -g @qwen-code/qwen-code@latest

# tools qwen-code wants to use
RUN apt-get update -y
RUN apt-get install -y procps vim curl

# Install Docker CLI so the container can run docker commands via host socket
RUN curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update -y \
    && apt-get install -y docker-ce-cli

# Default working directory will be your mounted project
WORKDIR /workspace

# Testing Python+Pygame demos
RUN apt-get install -y python3 python3-pip
RUN python3 -m pip install pygame --break-system-packages

