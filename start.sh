#!/bin/bash
set -e

echo "Starting Flask backend..."
cd /app/backend
python3 app.py &

echo "Starting Shiny app..."
R -q -e "options(shiny.port=5098, shiny.host='0.0.0.0'); library(RAGR); RAGR::run_app()"