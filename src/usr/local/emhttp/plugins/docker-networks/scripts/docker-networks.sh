#!/bin/bash
#
# Docker Multi-Network Manager Daemon
# Monitors Docker container start events and connects containers to additional networks
#

# Configuration paths
PLUGIN_NAME="docker-networks"
CONFIG_FILE="/boot/config/plugins/${PLUGIN_NAME}/networks.json"
SETTINGS_FILE="/boot/config/plugins/${PLUGIN_NAME}/${PLUGIN_NAME}.cfg"
LOG_DIR="/var/log/${PLUGIN_NAME}"
LOG_FILE="${LOG_DIR}/${PLUGIN_NAME}.log"
PID_FILE="/var/run/${PLUGIN_NAME}.pid"
PLUGIN_DIR="/usr/local/emhttp/plugins/${PLUGIN_NAME}"

# Default settings
LOG_LEVEL="info"
RETRY_ATTEMPTS=3
RETRY_DELAY_SECONDS=2
MAX_LOG_SIZE=1048576  # 1MB
MAX_LOG_FILES=5

# Log levels
declare -A LOG_LEVELS=([debug]=0 [info]=1 [warn]=2 [error]=3 [success]=1)

# Load settings from config file
load_settings() {
    if [[ -f "$SETTINGS_FILE" ]]; then
        source "$SETTINGS_FILE"
    fi

    # Also load settings from JSON config if present
    if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
        local json_log_level json_retry_attempts json_retry_delay
        json_log_level=$(jq -r '.settings.log_level // empty' "$CONFIG_FILE" 2>/dev/null)
        json_retry_attempts=$(jq -r '.settings.retry_attempts // empty' "$CONFIG_FILE" 2>/dev/null)
        json_retry_delay=$(jq -r '.settings.retry_delay_seconds // empty' "$CONFIG_FILE" 2>/dev/null)

        [[ -n "$json_log_level" ]] && LOG_LEVEL="$json_log_level"
        [[ -n "$json_retry_attempts" ]] && RETRY_ATTEMPTS="$json_retry_attempts"
        [[ -n "$json_retry_delay" ]] && RETRY_DELAY_SECONDS="$json_retry_delay"
    fi
}

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
}

# Rotate log files if needed
rotate_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt $MAX_LOG_SIZE ]]; then
            for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
                [[ -f "${LOG_FILE}.${i}" ]] && mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
            done
            mv "$LOG_FILE" "${LOG_FILE}.1"
            touch "$LOG_FILE"
        fi
    fi
}

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local current_level=${LOG_LEVELS[$LOG_LEVEL]:-1}
    local msg_level=${LOG_LEVELS[$level]:-1}

    if [[ $msg_level -ge $current_level ]]; then
        local formatted_level
        formatted_level=$(echo "$level" | tr '[:lower:]' '[:upper:]')
        echo "${timestamp} [${formatted_level}] ${message}" >> "$LOG_FILE"
    fi

    rotate_logs
}

# Check if jq is available, provide fallback JSON parsing
has_jq() {
    command -v jq &>/dev/null
}

# Get container configuration from JSON
get_container_config() {
    local container_name="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    if has_jq; then
        local enabled networks
        enabled=$(jq -r ".containers[\"${container_name}\"].enabled // false" "$CONFIG_FILE" 2>/dev/null)
        networks=$(jq -r ".containers[\"${container_name}\"].networks // [] | .[]" "$CONFIG_FILE" 2>/dev/null)

        if [[ "$enabled" == "true" ]] && [[ -n "$networks" ]]; then
            echo "$networks"
            return 0
        fi
    else
        # Fallback: basic grep/sed parsing for simple cases
        if grep -q "\"${container_name}\"" "$CONFIG_FILE" 2>/dev/null; then
            # This is a simplified fallback - jq is strongly recommended
            log warn "jq not available - using basic JSON parsing (limited functionality)"
            local in_container=false
            local in_networks=false
            local enabled=false

            while IFS= read -r line; do
                if [[ "$line" =~ \"${container_name}\" ]]; then
                    in_container=true
                fi
                if $in_container; then
                    if [[ "$line" =~ \"enabled\"[[:space:]]*:[[:space:]]*true ]]; then
                        enabled=true
                    fi
                    if [[ "$line" =~ \"networks\" ]]; then
                        in_networks=true
                    fi
                    if $in_networks && [[ "$line" =~ \"([^\"]+)\" ]] && [[ ! "$line" =~ networks ]]; then
                        local network
                        network=$(echo "$line" | sed -n 's/.*"\([^"]*\)".*/\1/p')
                        [[ -n "$network" ]] && echo "$network"
                    fi
                    if [[ "$line" =~ \] ]] && $in_networks; then
                        in_networks=false
                    fi
                    if [[ "$line" =~ \} ]] && ! $in_networks; then
                        break
                    fi
                fi
            done < "$CONFIG_FILE"

            if $enabled; then
                return 0
            fi
        fi
    fi

    return 1
}

# Check if network exists
network_exists() {
    local network="$1"
    docker network inspect "$network" &>/dev/null
}

# Check if container is connected to network
is_connected() {
    local container="$1"
    local network="$2"
    docker inspect --format='{{range $net, $config := .NetworkSettings.Networks}}{{$net}} {{end}}' "$container" 2>/dev/null | grep -qw "$network"
}

# Connect container to network with retry logic
connect_to_network() {
    local container="$1"
    local network="$2"
    local attempt=1

    while [[ $attempt -le $RETRY_ATTEMPTS ]]; do
        if docker network connect "$network" "$container" 2>&1; then
            log success "Connected '${container}' to '${network}'"
            return 0
        else
            if [[ $attempt -lt $RETRY_ATTEMPTS ]]; then
                log warn "Failed to connect '${container}' to '${network}' (attempt ${attempt}/${RETRY_ATTEMPTS}), retrying in ${RETRY_DELAY_SECONDS}s..."
                sleep "$RETRY_DELAY_SECONDS"
            else
                log error "Failed to connect '${container}' to '${network}' after ${RETRY_ATTEMPTS} attempts"
            fi
        fi
        ((attempt++))
    done

    return 1
}

# Process container start event
process_container() {
    local container="$1"

    log info "Container '${container}' started - checking network assignments"

    local networks
    networks=$(get_container_config "$container")

    if [[ -z "$networks" ]]; then
        log debug "No network configuration found for '${container}'"
        return 0
    fi

    log info "Processing network assignments for '${container}'"

    echo "$networks" | while IFS= read -r network; do
        [[ -z "$network" ]] && continue

        if ! network_exists "$network"; then
            log warn "Network '${network}' does not exist - skipping for '${container}'"
            continue
        fi

        if is_connected "$container" "$network"; then
            log info "Container '${container}' already connected to '${network}' - skipping"
            continue
        fi

        log info "Connecting '${container}' to network '${network}'"
        connect_to_network "$container" "$network"
    done
}

# Apply configuration to all running containers
apply_all() {
    log info "Applying network configuration to all running containers"

    local containers
    containers=$(docker ps --format '{{.Names}}' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        log info "No running containers found"
        return 0
    fi

    echo "$containers" | while IFS= read -r container; do
        process_container "$container"
    done

    log info "Finished applying network configuration"
}

# Apply configuration to specific container
apply_container() {
    local container="$1"

    if ! docker inspect "$container" &>/dev/null; then
        log error "Container '${container}' not found"
        echo "Error: Container '${container}' not found"
        return 1
    fi

    if ! docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
        log warn "Container '${container}' is not running"
        echo "Warning: Container '${container}' is not running"
    fi

    process_container "$container"
}

# Validate configuration file
validate_config() {
    echo "Validating configuration file: ${CONFIG_FILE}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file not found"
        return 1
    fi

    if has_jq; then
        if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
            echo "Error: Invalid JSON syntax"
            return 1
        fi

        local version
        version=$(jq -r '.version // empty' "$CONFIG_FILE" 2>/dev/null)
        if [[ -z "$version" ]]; then
            echo "Warning: No version field in configuration"
        else
            echo "Configuration version: ${version}"
        fi

        local container_count
        container_count=$(jq -r '.containers | keys | length' "$CONFIG_FILE" 2>/dev/null)
        echo "Configured containers: ${container_count:-0}"

        # Check each container and network
        local containers
        containers=$(jq -r '.containers | keys[]' "$CONFIG_FILE" 2>/dev/null)

        echo "$containers" | while IFS= read -r container; do
            [[ -z "$container" ]] && continue

            local enabled
            enabled=$(jq -r ".containers[\"${container}\"].enabled" "$CONFIG_FILE" 2>/dev/null)
            local networks
            networks=$(jq -r ".containers[\"${container}\"].networks[]" "$CONFIG_FILE" 2>/dev/null)

            echo ""
            echo "Container: ${container}"
            echo "  Enabled: ${enabled}"
            echo "  Networks:"

            echo "$networks" | while IFS= read -r network; do
                [[ -z "$network" ]] && continue
                if network_exists "$network"; then
                    echo "    - ${network} (exists)"
                else
                    echo "    - ${network} (WARNING: does not exist)"
                fi
            done

            if docker inspect "$container" &>/dev/null; then
                echo "  Container status: exists"
            else
                echo "  Container status: WARNING - not found"
            fi
        done

        echo ""
        echo "Configuration validation complete"
        return 0
    else
        echo "Warning: jq not available - basic validation only"
        if grep -q '"version"' "$CONFIG_FILE" && grep -q '"containers"' "$CONFIG_FILE"; then
            echo "Configuration appears valid (basic check)"
            return 0
        else
            echo "Error: Configuration missing required fields"
            return 1
        fi
    fi
}

# List current configuration
list_config() {
    echo "Current configuration:"
    echo "====================="
    echo ""

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No configuration file found at: ${CONFIG_FILE}"
        return 1
    fi

    if has_jq; then
        jq '.' "$CONFIG_FILE"
    else
        cat "$CONFIG_FILE"
    fi
}

# Start the monitoring daemon
start_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon already running (PID: ${pid})"
            return 1
        else
            rm -f "$PID_FILE"
        fi
    fi

    # Check if Docker is available
    if ! docker info &>/dev/null; then
        echo "Error: Docker is not available"
        log error "Cannot start daemon - Docker is not available"
        return 1
    fi

    init_logging
    load_settings

    log info "Starting Docker Multi-Network daemon"
    echo "Starting Docker Multi-Network daemon..."

    # Start daemon in background
    (
        echo $$ > "$PID_FILE"

        # Trap signals for graceful shutdown
        trap 'log info "Daemon stopped"; rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT

        log info "Daemon started (PID: $$)"
        log info "Monitoring Docker container start events..."

        # Monitor Docker events
        docker events --filter 'event=start' --filter 'type=container' --format '{{.Actor.Attributes.name}}' 2>/dev/null | while IFS= read -r container; do
            # Reload settings on each event (allows config changes without restart)
            load_settings
            process_container "$container"
        done

        log error "Docker event stream ended unexpectedly"
        rm -f "$PID_FILE"
    ) &

    local daemon_pid=$!
    sleep 1

    if kill -0 "$daemon_pid" 2>/dev/null; then
        echo "Daemon started successfully (PID: ${daemon_pid})"
        return 0
    else
        echo "Error: Daemon failed to start"
        return 1
    fi
}

# Stop the monitoring daemon
stop_daemon() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "Daemon is not running (no PID file)"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping daemon (PID: ${pid})..."
        kill "$pid"

        # Wait for process to terminate
        local timeout=10
        while kill -0 "$pid" 2>/dev/null && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo "Force killing daemon..."
            kill -9 "$pid" 2>/dev/null
        fi

        rm -f "$PID_FILE"
        log info "Daemon stopped"
        echo "Daemon stopped"
    else
        echo "Daemon not running (stale PID file)"
        rm -f "$PID_FILE"
    fi
}

# Restart the daemon
restart_daemon() {
    stop_daemon
    sleep 1
    start_daemon
}

# Show daemon status
show_status() {
    echo "Docker Multi-Network Manager Status"
    echo "===================================="
    echo ""

    # Daemon status
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon: Running (PID: ${pid})"
        else
            echo "Daemon: Not running (stale PID file)"
        fi
    else
        echo "Daemon: Not running"
    fi

    # Docker status
    if docker info &>/dev/null; then
        echo "Docker: Available"
    else
        echo "Docker: Not available"
    fi

    # Configuration status
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config: ${CONFIG_FILE} (exists)"
        if has_jq; then
            local container_count
            container_count=$(jq -r '.containers | keys | length' "$CONFIG_FILE" 2>/dev/null)
            echo "Configured containers: ${container_count:-0}"
        fi
    else
        echo "Config: Not found"
    fi

    # Log file status
    if [[ -f "$LOG_FILE" ]]; then
        local log_size
        log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "unknown")
        echo "Log file: ${LOG_FILE} (${log_size} bytes)"
    else
        echo "Log file: Not created yet"
    fi

    echo ""
    echo "Settings:"
    load_settings
    echo "  Log level: ${LOG_LEVEL}"
    echo "  Retry attempts: ${RETRY_ATTEMPTS}"
    echo "  Retry delay: ${RETRY_DELAY_SECONDS}s"
}

# Show recent logs
show_logs() {
    local lines="${1:-50}"

    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "No log file found"
    fi
}

# Print usage information
usage() {
    cat << EOF
Docker Multi-Network Manager

Usage: $(basename "$0") <command> [arguments]

Commands:
  start           Start the monitoring daemon
  stop            Stop the monitoring daemon
  restart         Restart the monitoring daemon
  status          Show daemon and configuration status
  apply           Apply network config to all running containers
  apply <name>    Apply network config to specific container
  validate        Validate configuration file
  list            List current configuration
  logs [lines]    Show recent log entries (default: 50 lines)
  help            Show this help message

Configuration:
  ${CONFIG_FILE}

Logs:
  ${LOG_FILE}

EOF
}

# Main entry point
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        restart)
            restart_daemon
            ;;
        status)
            show_status
            ;;
        apply)
            init_logging
            load_settings
            if [[ -n "${1:-}" ]]; then
                apply_container "$1"
            else
                apply_all
            fi
            ;;
        validate)
            validate_config
            ;;
        list)
            list_config
            ;;
        logs)
            show_logs "${1:-50}"
            ;;
        help|--help|-h)
            usage
            ;;
        "")
            usage
            exit 1
            ;;
        *)
            echo "Unknown command: ${command}"
            echo "Run '$(basename "$0") help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
