#!/bin/bash

# CrystalShards API Documentation Server
# Serves the interactive API documentation locally

set -e

PORT=${PORT:-8080}
HOST=${HOST:-localhost}

echo "🚀 Starting CrystalShards API Documentation Server..."
echo "📚 Documentation will be available at: http://$HOST:$PORT"
echo "📄 OpenAPI spec: http://$HOST:$PORT/openapi.yml"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Check if we have Python 3
if command -v python3 &> /dev/null; then
    echo "Using Python 3 HTTP server..."
    python3 -m http.server $PORT --bind $HOST
elif command -v python &> /dev/null; then
    echo "Using Python 2 HTTP server..."
    python -m SimpleHTTPServer $PORT
elif command -v node &> /dev/null; then
    echo "Using Node.js http-server..."
    if ! command -v http-server &> /dev/null; then
        echo "Installing http-server..."
        npm install -g http-server
    fi
    http-server -p $PORT -a $HOST
else
    echo "❌ Error: No suitable HTTP server found!"
    echo "Please install one of the following:"
    echo "  - Python 3: python3 -m pip install --user http.server"
    echo "  - Node.js: npm install -g http-server"
    echo "  - Or use any other static file server"
    exit 1
fi