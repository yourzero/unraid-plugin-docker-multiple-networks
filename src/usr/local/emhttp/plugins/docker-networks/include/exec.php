<?php
/*
 * Docker Multi-Network Manager - AJAX Endpoint
 * Handles all backend operations from the web UI
 */

// Start session if not already started
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

$plugin = "docker-networks";
$configFile = "/boot/config/plugins/{$plugin}/networks.json";
$logFile = "/var/log/{$plugin}/{$plugin}.log";
$scriptPath = "/usr/local/emhttp/plugins/{$plugin}/scripts/docker-networks.sh";

// Include helper functions
require_once(__DIR__ . '/helpers.php');

// Set JSON content type for responses
header('Content-Type: application/json');

/**
 * Send JSON response
 */
function jsonResponse($success, $data = null, $message = null) {
    echo json_encode([
        'success' => $success,
        'data' => $data,
        'message' => $message
    ]);
    exit;
}

/**
 * Verify CSRF token
 */
function verifyCsrf($token) {
    if (!isset($_SESSION['csrf_token']) || $token !== $_SESSION['csrf_token']) {
        jsonResponse(false, null, 'Invalid CSRF token');
    }
}

// Handle export as file download (GET request)
if (isset($_GET['action']) && $_GET['action'] === 'export') {
    verifyCsrf($_GET['csrf_token'] ?? '');

    $config = loadConfig($configFile);

    header('Content-Type: application/json');
    header('Content-Disposition: attachment; filename="docker-networks-config.json"');
    echo json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    exit;
}

// All other requests are POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(false, null, 'Method not allowed');
}

// Get action and verify CSRF
$action = $_POST['action'] ?? '';
$csrfToken = $_POST['csrf_token'] ?? '';

verifyCsrf($csrfToken);

// Route action to handler
switch ($action) {
    case 'daemon':
        handleDaemon();
        break;

    case 'apply':
        handleApply();
        break;

    case 'saveContainer':
        handleSaveContainer();
        break;

    case 'removeContainer':
        handleRemoveContainer();
        break;

    case 'getContainer':
        handleGetContainer();
        break;

    case 'toggleEnabled':
        handleToggleEnabled();
        break;

    case 'saveSettings':
        handleSaveSettings();
        break;

    case 'getConfig':
        handleGetConfig();
        break;

    case 'import':
        handleImport();
        break;

    case 'getLogs':
        handleGetLogs();
        break;

    case 'clearLogs':
        handleClearLogs();
        break;

    default:
        jsonResponse(false, null, 'Unknown action');
}

/**
 * Handle daemon control commands
 */
function handleDaemon() {
    global $scriptPath;

    $command = $_POST['command'] ?? '';
    $allowedCommands = ['start', 'stop', 'restart', 'status'];

    if (!in_array($command, $allowedCommands)) {
        jsonResponse(false, null, 'Invalid daemon command');
    }

    $output = shell_exec(escapeshellcmd($scriptPath) . ' ' . escapeshellarg($command) . ' 2>&1');

    jsonResponse(true, null, trim($output));
}

/**
 * Handle apply configuration
 */
function handleApply() {
    global $scriptPath;

    $container = $_POST['container'] ?? null;

    if ($container) {
        $container = sanitizeContainerName($container);
        $output = shell_exec(escapeshellcmd($scriptPath) . ' apply ' . escapeshellarg($container) . ' 2>&1');
    } else {
        $output = shell_exec(escapeshellcmd($scriptPath) . ' apply 2>&1');
    }

    jsonResponse(true, null, trim($output));
}

/**
 * Handle save container configuration
 */
function handleSaveContainer() {
    global $configFile;

    $container = sanitizeContainerName($_POST['container'] ?? '');
    $networksJson = $_POST['networks'] ?? '[]';
    $networks = json_decode($networksJson, true);
    $enabled = filter_var($_POST['enabled'] ?? 'true', FILTER_VALIDATE_BOOLEAN);

    if (empty($container)) {
        jsonResponse(false, null, 'Container name is required');
    }

    if (!is_array($networks) || empty($networks)) {
        jsonResponse(false, null, 'At least one network is required');
    }

    // Sanitize network names
    $networks = array_map('sanitizeNetworkName', $networks);
    $networks = array_filter($networks);

    // Load current config
    $config = loadConfig($configFile);

    // Update container configuration
    $config['containers'][$container] = [
        'networks' => array_values($networks),
        'enabled' => $enabled
    ];

    // Save config
    if (saveConfig($configFile, $config)) {
        jsonResponse(true, null, 'Container configuration saved');
    } else {
        jsonResponse(false, null, 'Failed to save configuration');
    }
}

/**
 * Handle remove container from configuration
 */
function handleRemoveContainer() {
    global $configFile;

    $container = sanitizeContainerName($_POST['container'] ?? '');

    if (empty($container)) {
        jsonResponse(false, null, 'Container name is required');
    }

    $config = loadConfig($configFile);

    if (!isset($config['containers'][$container])) {
        jsonResponse(false, null, 'Container not found in configuration');
    }

    unset($config['containers'][$container]);

    if (saveConfig($configFile, $config)) {
        jsonResponse(true, null, 'Container removed from configuration');
    } else {
        jsonResponse(false, null, 'Failed to save configuration');
    }
}

/**
 * Handle get container configuration
 */
function handleGetContainer() {
    global $configFile;

    $container = sanitizeContainerName($_POST['container'] ?? '');

    if (empty($container)) {
        jsonResponse(false, null, 'Container name is required');
    }

    $config = loadConfig($configFile);

    if (!isset($config['containers'][$container])) {
        jsonResponse(false, null, 'Container not found in configuration');
    }

    jsonResponse(true, $config['containers'][$container]);
}

/**
 * Handle toggle container enabled state
 */
function handleToggleEnabled() {
    global $configFile;

    $container = sanitizeContainerName($_POST['container'] ?? '');
    $enabled = filter_var($_POST['enabled'] ?? 'true', FILTER_VALIDATE_BOOLEAN);

    if (empty($container)) {
        jsonResponse(false, null, 'Container name is required');
    }

    $config = loadConfig($configFile);

    if (!isset($config['containers'][$container])) {
        jsonResponse(false, null, 'Container not found in configuration');
    }

    $config['containers'][$container]['enabled'] = $enabled;

    if (saveConfig($configFile, $config)) {
        jsonResponse(true, null, 'Container ' . ($enabled ? 'enabled' : 'disabled'));
    } else {
        jsonResponse(false, null, 'Failed to save configuration');
    }
}

/**
 * Handle save settings
 */
function handleSaveSettings() {
    global $configFile;

    $logLevel = $_POST['log_level'] ?? 'info';
    $retryAttempts = intval($_POST['retry_attempts'] ?? 3);
    $retryDelay = intval($_POST['retry_delay_seconds'] ?? 2);

    // Validate log level
    $allowedLogLevels = ['debug', 'info', 'warn', 'error'];
    if (!in_array($logLevel, $allowedLogLevels)) {
        $logLevel = 'info';
    }

    // Validate numeric values
    $retryAttempts = max(1, min(10, $retryAttempts));
    $retryDelay = max(1, min(30, $retryDelay));

    $config = loadConfig($configFile);

    $config['settings'] = [
        'log_level' => $logLevel,
        'retry_attempts' => $retryAttempts,
        'retry_delay_seconds' => $retryDelay
    ];

    if (saveConfig($configFile, $config)) {
        jsonResponse(true, null, 'Settings saved');
    } else {
        jsonResponse(false, null, 'Failed to save settings');
    }
}

/**
 * Handle get full configuration
 */
function handleGetConfig() {
    global $configFile;

    $config = loadConfig($configFile);
    jsonResponse(true, $config);
}

/**
 * Handle import configuration
 */
function handleImport() {
    global $configFile;

    $configJson = $_POST['config'] ?? '';

    if (empty($configJson)) {
        jsonResponse(false, null, 'No configuration provided');
    }

    // Validate JSON
    $config = json_decode($configJson, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        jsonResponse(false, null, 'Invalid JSON: ' . json_last_error_msg());
    }

    // Validate structure
    $validation = validateConfig($configJson);
    if (!$validation['success']) {
        jsonResponse(false, null, implode(', ', $validation['errors']));
    }

    // Ensure required fields exist
    if (!isset($config['version'])) {
        $config['version'] = '1.0';
    }
    if (!isset($config['containers'])) {
        $config['containers'] = [];
    }
    if (!isset($config['settings'])) {
        $config['settings'] = [
            'log_level' => 'info',
            'retry_attempts' => 3,
            'retry_delay_seconds' => 2
        ];
    }

    // Sanitize container and network names
    $sanitizedContainers = [];
    foreach ($config['containers'] as $containerName => $containerConfig) {
        $sanitizedName = sanitizeContainerName($containerName);
        if (!empty($sanitizedName)) {
            $sanitizedNetworks = [];
            if (isset($containerConfig['networks']) && is_array($containerConfig['networks'])) {
                foreach ($containerConfig['networks'] as $network) {
                    $sanitizedNetwork = sanitizeNetworkName($network);
                    if (!empty($sanitizedNetwork)) {
                        $sanitizedNetworks[] = $sanitizedNetwork;
                    }
                }
            }
            $sanitizedContainers[$sanitizedName] = [
                'networks' => $sanitizedNetworks,
                'enabled' => $containerConfig['enabled'] ?? true
            ];
        }
    }
    $config['containers'] = $sanitizedContainers;

    if (saveConfig($configFile, $config)) {
        $warnings = [];
        if (!empty($validation['warnings'])) {
            $warnings = $validation['warnings'];
        }
        jsonResponse(true, ['warnings' => $warnings], 'Configuration imported successfully');
    } else {
        jsonResponse(false, null, 'Failed to save configuration');
    }
}

/**
 * Handle get recent logs
 */
function handleGetLogs() {
    global $logFile;

    $lines = intval($_POST['lines'] ?? 50);
    $lines = max(10, min(500, $lines));

    $logs = getRecentLogs($logFile, $lines);
    jsonResponse(true, $logs);
}

/**
 * Handle clear logs
 */
function handleClearLogs() {
    global $logFile;

    if (clearLogs($logFile)) {
        jsonResponse(true, null, 'Logs cleared');
    } else {
        jsonResponse(false, null, 'Failed to clear logs');
    }
}
