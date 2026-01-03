#!/bin/bash
#
# Docker Multi-Network Manager - Shutdown Script
# Called when Docker service stops or array is stopped
#

PLUGIN_NAME="docker-networks"
SCRIPT_DIR="/usr/local/emhttp/plugins/${PLUGIN_NAME}/scripts"
LOG_FILE="/var/log/${PLUGIN_NAME}/${PLUGIN_NAME}.log"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [INFO] $*" >> "$LOG_FILE"
}

# Main shutdown
main() {
    log "Docker Multi-Network Manager shutdown initiated"

    # Stop the daemon
    "${SCRIPT_DIR}/docker-networks.sh" stop

    log "Docker Multi-Network Manager stopped"
}

main "$@"
