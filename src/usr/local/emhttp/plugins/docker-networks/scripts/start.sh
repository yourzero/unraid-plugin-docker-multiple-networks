#!/bin/bash
#
# Docker Multi-Network Manager - Startup Script
# Called when Docker service starts or array is started
#

PLUGIN_NAME="docker-networks"
SCRIPT_DIR="/usr/local/emhttp/plugins/${PLUGIN_NAME}/scripts"
LOG_FILE="/var/log/${PLUGIN_NAME}/${PLUGIN_NAME}.log"

# Create log directory if needed
mkdir -p "/var/log/${PLUGIN_NAME}"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [INFO] $*" >> "$LOG_FILE"
}

# Wait for Docker to be ready
wait_for_docker() {
    local timeout=60
    local interval=2

    log "Waiting for Docker to be ready..."

    while ! docker info &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep $interval
        ((timeout -= interval))
    done

    if docker info &>/dev/null; then
        log "Docker is ready"
        return 0
    else
        log "Timeout waiting for Docker"
        return 1
    fi
}

# Main startup
main() {
    log "Docker Multi-Network Manager startup initiated"

    if wait_for_docker; then
        # Start the daemon
        "${SCRIPT_DIR}/docker-networks.sh" start

        # Optional: Apply configuration to any already-running containers
        sleep 2
        "${SCRIPT_DIR}/docker-networks.sh" apply
    else
        log "Failed to start - Docker not available"
        exit 1
    fi
}

main "$@"
