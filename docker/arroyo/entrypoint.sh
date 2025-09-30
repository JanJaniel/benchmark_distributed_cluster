#!/bin/bash

# Arroyo entrypoint script
set -e

# Function to wait for controller
wait_for_controller() {
    echo "Waiting for controller at $ARROYO__CONTROLLER_ENDPOINT..."
    while ! curl -s "${ARROYO__CONTROLLER_ENDPOINT}/health" > /dev/null 2>&1; do
        echo "Controller not ready, retrying in 5 seconds..."
        sleep 5
    done
    echo "Controller is ready!"
}

# Main logic based on the command
case "$1" in
    "controller")
        echo "Starting Arroyo controller..."
        exec /usr/local/bin/arroyo cluster
        ;;
    "worker")
        echo "Starting Arroyo worker node: ${ARROYO__NODE_ID}"
        wait_for_controller
        exec /usr/local/bin/arroyo worker
        ;;
    *)
        echo "Usage: $0 {controller|worker}"
        exit 1
        ;;
esac