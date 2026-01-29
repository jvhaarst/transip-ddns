#!/usr/bin/env bash
#
# Docker entrypoint for TransIP DDNS
#
# Supports two modes:
# 1. Run once: execute the script and exit
# 2. Scheduled: run on an interval (set SCHEDULE_INTERVAL in seconds)
#

set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/config/config.yaml}"
SCHEDULE_INTERVAL="${SCHEDULE_INTERVAL:-0}"
SCRIPT_ARGS="${SCRIPT_ARGS:--s}"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Mount your config file to /config/config.yaml or set CONFIG_FILE environment variable"
    exit 1
fi

# Function to run the DDNS script
run_ddns() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running TransIP DDNS update..."
    /app/transip-ddns.sh -c "$CONFIG_FILE" $SCRIPT_ARGS
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Update complete"
}

# Main execution
if [[ "$SCHEDULE_INTERVAL" -gt 0 ]]; then
    echo "Running in scheduled mode (interval: ${SCHEDULE_INTERVAL}s)"
    while true; do
        run_ddns || true  # Don't exit on error in scheduled mode
        echo "Sleeping for ${SCHEDULE_INTERVAL} seconds..."
        sleep "$SCHEDULE_INTERVAL"
    done
else
    echo "Running in single-run mode"
    run_ddns
fi
