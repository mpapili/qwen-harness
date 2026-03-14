#!/bin/bash
# GreenLine Mowers - Simple HTTP Server Script
# Serves the website on port 8000

# Check if Python 3 is available
if command -v python3 &> /dev/null; then
    echo "Starting GreenLine Mowers server on http://localhost:8000"
    echo "Press Ctrl+C to stop the server"
    python3 -m http.server 8000
elif command -v python &> /dev/null; then
    echo "Starting GreenLine Mowers server on http://localhost:8000"
    echo "Press Ctrl+C to stop the server"
    python -m SimpleHTTPServer 8000
else
    echo "Error: Python 3 is required but not installed."
    echo "Please install Python 3 and try again."
    exit 1
fi
