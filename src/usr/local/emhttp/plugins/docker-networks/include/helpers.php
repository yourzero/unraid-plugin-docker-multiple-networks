<?php
/*
 * Docker Multi-Network Manager - Helper Functions
 */

/**
 * Load configuration from JSON file
 *
 * @param string $configFile Path to configuration file
 * @return array Configuration array
 */
function loadConfig($configFile) {
    $defaultConfig = [
        'version' => '1.0',
        'containers' => [],
        'settings' => [
            'log_level' => 'info',
            'retry_attempts' => 3,
            'retry_delay_seconds' => 2
        ]
    ];

    if (!file_exists($configFile)) {
        return $defaultConfig;
    }

    $content = file_get_contents($configFile);
    $config = json_decode($content, true);

    if (json_last_error() !== JSON_ERROR_NONE) {
        error_log("Docker Networks: Failed to parse config file: " . json_last_error_msg());
        return $defaultConfig;
    }

    // Merge with defaults to ensure all keys exist
    return array_replace_recursive($defaultConfig, $config);
}

/**
 * Save configuration to JSON file
 *
 * @param string $configFile Path to configuration file
 * @param array $config Configuration array
 * @return bool Success status
 */
function saveConfig($configFile, $config) {
    // Ensure directory exists
    $dir = dirname($configFile);
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }

    $json = json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        error_log("Docker Networks: Failed to encode config: " . json_last_error_msg());
        return false;
    }

    $result = file_put_contents($configFile, $json);
    if ($result === false) {
        error_log("Docker Networks: Failed to write config file");
        return false;
    }

    // Set proper permissions
    chmod($configFile, 0600);

    return true;
}

/**
 * Get list of Docker containers with their status
 *
 * @return array Container information
 */
function getDockerContainers() {
    $containers = [];

    // Get all containers
    $output = shell_exec('docker ps -a --format "{{.Names}}|{{.State}}" 2>/dev/null');
    if ($output === null) {
        return $containers;
    }

    $lines = explode("\n", trim($output));
    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line)) continue;

        $parts = explode('|', $line);
        if (count($parts) >= 2) {
            $name = $parts[0];
            $state = $parts[1];

            // Get networks for this container
            $networks = getContainerNetworks($name);

            $containers[$name] = [
                'running' => $state === 'running',
                'state' => $state,
                'networks' => $networks
            ];
        }
    }

    return $containers;
}

/**
 * Get networks a container is connected to
 *
 * @param string $containerName Container name
 * @return array List of network names
 */
function getContainerNetworks($containerName) {
    $networks = [];

    $output = shell_exec("docker inspect --format='{{range \$net, \$config := .NetworkSettings.Networks}}{{\$net}} {{end}}' " . escapeshellarg($containerName) . " 2>/dev/null");
    if ($output !== null) {
        $networks = array_filter(array_map('trim', explode(' ', trim($output))));
    }

    return array_values($networks);
}

/**
 * Get list of Docker networks
 *
 * @return array List of network names
 */
function getDockerNetworks() {
    $networks = [];

    $output = shell_exec('docker network ls --format "{{.Name}}" 2>/dev/null');
    if ($output !== null) {
        $networks = array_filter(array_map('trim', explode("\n", trim($output))));
    }

    return $networks;
}

/**
 * Get daemon status
 *
 * @return array Status information
 */
function getDaemonStatus() {
    $pidFile = '/var/run/docker-networks.pid';
    $status = [
        'running' => false,
        'pid' => null,
        'docker' => false
    ];

    // Check if Docker is available
    $dockerCheck = shell_exec('docker info 2>&1');
    $status['docker'] = strpos($dockerCheck, 'Server:') !== false;

    // Check daemon PID
    if (file_exists($pidFile)) {
        $pid = trim(file_get_contents($pidFile));
        if ($pid && file_exists("/proc/{$pid}")) {
            $status['running'] = true;
            $status['pid'] = $pid;
        }
    }

    return $status;
}

/**
 * Execute daemon command
 *
 * @param string $command Command to execute (start, stop, restart, status)
 * @return array Result with success status and message
 */
function executeDaemonCommand($command) {
    $scriptPath = '/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh';
    $allowedCommands = ['start', 'stop', 'restart', 'status', 'apply'];

    if (!in_array($command, $allowedCommands)) {
        return ['success' => false, 'message' => 'Invalid command'];
    }

    $output = shell_exec(escapeshellcmd($scriptPath) . ' ' . escapeshellarg($command) . ' 2>&1');

    return [
        'success' => true,
        'message' => trim($output)
    ];
}

/**
 * Apply configuration to container(s)
 *
 * @param string|null $container Container name or null for all
 * @return array Result with success status and message
 */
function applyConfiguration($container = null) {
    $scriptPath = '/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh';

    if ($container) {
        $output = shell_exec(escapeshellcmd($scriptPath) . ' apply ' . escapeshellarg($container) . ' 2>&1');
    } else {
        $output = shell_exec(escapeshellcmd($scriptPath) . ' apply 2>&1');
    }

    return [
        'success' => true,
        'message' => trim($output)
    ];
}

/**
 * Get recent log entries
 *
 * @param string $logFile Path to log file
 * @param int $lines Number of lines to return
 * @return string Log content
 */
function getRecentLogs($logFile, $lines = 50) {
    if (!file_exists($logFile)) {
        return "No log entries yet.";
    }

    $output = shell_exec("tail -n " . intval($lines) . " " . escapeshellarg($logFile) . " 2>/dev/null");
    return $output ?: "Unable to read log file.";
}

/**
 * Clear log file
 *
 * @param string $logFile Path to log file
 * @return bool Success status
 */
function clearLogs($logFile) {
    if (file_exists($logFile)) {
        return file_put_contents($logFile, '') !== false;
    }
    return true;
}

/**
 * Validate JSON configuration
 *
 * @param string $json JSON string to validate
 * @return array Validation result with success status and errors/warnings
 */
function validateConfig($json) {
    $result = [
        'success' => true,
        'errors' => [],
        'warnings' => []
    ];

    $config = json_decode($json, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        $result['success'] = false;
        $result['errors'][] = 'Invalid JSON: ' . json_last_error_msg();
        return $result;
    }

    // Check required fields
    if (!isset($config['version'])) {
        $result['warnings'][] = 'No version field specified';
    }

    if (!isset($config['containers'])) {
        $result['errors'][] = 'Missing containers field';
        $result['success'] = false;
    }

    if (!isset($config['settings'])) {
        $result['warnings'][] = 'No settings field, defaults will be used';
    }

    // Validate container entries
    if (isset($config['containers']) && is_array($config['containers'])) {
        $networks = getDockerNetworks();
        $containers = getDockerContainers();

        foreach ($config['containers'] as $containerName => $containerConfig) {
            if (!isset($containers[$containerName])) {
                $result['warnings'][] = "Container '{$containerName}' not found";
            }

            if (isset($containerConfig['networks'])) {
                foreach ($containerConfig['networks'] as $network) {
                    if (!in_array($network, $networks)) {
                        $result['warnings'][] = "Network '{$network}' for container '{$containerName}' not found";
                    }
                }
            } else {
                $result['warnings'][] = "Container '{$containerName}' has no networks defined";
            }
        }
    }

    return $result;
}

/**
 * Sanitize container name
 *
 * @param string $name Container name
 * @return string Sanitized name
 */
function sanitizeContainerName($name) {
    // Docker container names can contain: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    return preg_replace('/[^a-zA-Z0-9_.-]/', '', $name);
}

/**
 * Sanitize network name
 *
 * @param string $name Network name
 * @return string Sanitized name
 */
function sanitizeNetworkName($name) {
    // Docker network names can contain: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    return preg_replace('/[^a-zA-Z0-9_.-]/', '', $name);
}

/**
 * Get plugin version from plg file
 *
 * @return string Version string
 */
function getPluginVersion() {
    $plgFile = '/boot/config/plugins/docker-networks/docker-networks.plg';
    if (file_exists($plgFile)) {
        $content = file_get_contents($plgFile);
        if (preg_match('/version="([^"]+)"/', $content, $matches)) {
            return $matches[1];
        }
    }
    return 'unknown';
}
