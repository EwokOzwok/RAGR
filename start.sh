#!/bin/bash
set -e

echo "Starting Flask backend..."
cd /app/backend
python3 app.py &

echo "Starting Shiny app (internal port 5100)..."
R -q -e "options(shiny.port=5100, shiny.host='0.0.0.0'); library(RAGR); RAGR::run_app()" &

echo "Starting nginx (public port 5098)..."
nginx -g "daemon off;"