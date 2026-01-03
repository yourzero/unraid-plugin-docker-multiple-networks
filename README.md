# Docker Multi-Network Manager for Unraid

Automatically connect Docker containers to multiple networks when they start. This plugin solves the limitation where Unraid's native Docker UI only allows assigning a single network per container.

## Features

- **Automatic Network Connection**: Containers are automatically connected to configured networks when they start
- **Persistent Configuration**: Network assignments survive reboots and array restarts
- **Web UI**: Easy-to-use interface integrated into Unraid's Docker menu
- **Import/Export**: JSON-based configuration for easy backup, restore, and migration
- **Event-Driven**: Uses Docker events (no polling) for efficient operation
- **Non-Destructive**: Works alongside Unraid's native Docker management

## Installation

### From Community Applications (Recommended)
1. Open the **Apps** tab in Unraid
2. Search for "Docker Multi-Network Manager"
3. Click **Install**

### Install from GitHub

1. In Unraid, navigate to **Plugins** > **Install Plugin**
2. Paste the raw URL to the `.plg` file:
   ```
   https://raw.githubusercontent.com/YOUR_USERNAME/unraid-docker-networks/main/docker-networks.plg
   ```
3. Click **Install**

**Note**: Before installing from GitHub, you must:
1. Update the `gitURL` entity in `docker-networks.plg` to point to your repository
2. Build and upload the `.txz` archive to your repository (see [Building the Plugin](#building-the-plugin))

### Install from Local File

1. **Build the plugin** (on any Linux machine):
   ```bash
   ./build.sh 2024.01.15
   ```
   This creates `archive/docker-networks-2024.01.15.txz`

2. **Copy files to your Unraid flash drive**:
   ```bash
   # Copy the plugin archive
   cp archive/docker-networks-*.txz /boot/config/plugins/docker-networks/

   # Copy the plg file
   cp docker-networks.plg /boot/config/plugins/docker-networks.plg
   ```

3. **Edit the `.plg` file** to use local paths instead of URLs:

   Change the FILE entries from URL-based to local:
   ```xml
   <!-- Change this: -->
   <FILE Name="&plugin;/&name;-&version;.txz">
   <URL>&gitURL;/archive/&name;-&version;.txz</URL>
   </FILE>

   <!-- To this (remove URL, file is already in place): -->
   <FILE Name="&plugin;/&name;-&version;.txz">
   <LOCAL>/boot/config/plugins/docker-networks/docker-networks-2024.01.15.txz</LOCAL>
   </FILE>
   ```

4. **Install the plugin**:
   - Navigate to **Plugins** > **Install Plugin**
   - Enter the local path: `/boot/config/plugins/docker-networks.plg`
   - Click **Install**

### Install via Command Line (SSH)

```bash
# From GitHub
plugin install https://raw.githubusercontent.com/YOUR_USERNAME/unraid-docker-networks/main/docker-networks.plg

# From local file
plugin install /boot/config/plugins/docker-networks.plg
```

## Usage

### Web Interface

Access the plugin at: **Settings** > **Docker** > **Multi-Network Manager**

The interface provides:

1. **Service Status Panel**
   - View daemon status (running/stopped)
   - Start/Stop/Restart daemon
   - Apply configuration immediately

2. **Container Network Assignments**
   - Add containers and select additional networks
   - Enable/disable automatic connection per container
   - Apply configuration to individual containers

3. **Import/Export**
   - Export configuration as JSON for backup
   - Import configuration from JSON file
   - Edit raw JSON configuration

4. **Settings**
   - Log level (debug, info, warn, error)
   - Retry attempts for failed connections
   - Retry delay between attempts

5. **Logs**
   - View recent log entries
   - Clear logs

### Command Line

```bash
# Start the monitoring daemon
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh start

# Stop the daemon
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh stop

# Restart the daemon
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh restart

# Check daemon status
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh status

# Apply configuration to all running containers
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh apply

# Apply configuration to a specific container
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh apply plex

# Validate configuration file
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh validate

# List current configuration
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh list

# View recent logs
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh logs
/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh logs 100
```

## Configuration

Configuration is stored at: `/boot/config/plugins/docker-networks/networks.json`

### Configuration Schema

```json
{
  "version": "1.0",
  "containers": {
    "container_name": {
      "networks": ["network1", "network2"],
      "enabled": true
    },
    "another_container": {
      "networks": ["network3"],
      "enabled": true
    }
  },
  "settings": {
    "log_level": "info",
    "retry_attempts": 3,
    "retry_delay_seconds": 2
  }
}
```

### Settings

| Setting | Description | Default | Range |
|---------|-------------|---------|-------|
| `log_level` | Logging verbosity | `info` | debug, info, warn, error |
| `retry_attempts` | Connection retry count | `3` | 1-10 |
| `retry_delay_seconds` | Delay between retries | `2` | 1-30 |

## How It Works

1. The plugin runs a daemon that monitors Docker events
2. When a container starts, the daemon checks if it has configured additional networks
3. For each configured network, the daemon:
   - Verifies the network exists
   - Checks if the container is already connected
   - Connects the container to the network (with retry logic)
4. All actions are logged for troubleshooting

## File Locations

| Path | Description |
|------|-------------|
| `/boot/config/plugins/docker-networks/` | Persistent config (on flash drive) |
| `/boot/config/plugins/docker-networks/networks.json` | Network assignments |
| `/usr/local/emhttp/plugins/docker-networks/` | Plugin files |
| `/var/log/docker-networks/docker-networks.log` | Runtime logs |
| `/var/run/docker-networks.pid` | Daemon PID file |

## Troubleshooting

### Daemon Not Starting

1. Check if Docker is running: `docker info`
2. Check the logs: `tail -f /var/log/docker-networks/docker-networks.log`
3. Try starting manually: `/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh start`

### Networks Not Connecting

1. Verify the network exists: `docker network ls`
2. Check container configuration in the web UI
3. Ensure the container entry is enabled
4. Review logs for error messages
5. Try applying manually: `/usr/local/emhttp/plugins/docker-networks/scripts/docker-networks.sh apply container_name`

### Common Log Messages

| Message | Meaning |
|---------|---------|
| `Container 'X' started - processing network assignments` | Container detected, checking configuration |
| `Connected 'X' to 'Y'` | Successfully connected container to network |
| `Container 'X' already connected to 'Y' - skipping` | No action needed, already connected |
| `Network 'Y' does not exist - skipping for 'X'` | Referenced network not found |
| `Failed to connect 'X' to 'Y'` | Connection failed after all retries |

## Compatibility

- **Unraid Version**: 6.12.0 or newer
- **Docker Network Types**: bridge, macvlan, ipvlan, custom
- **Dependencies**: bash, PHP (included with Unraid), jq (recommended but optional)

## Uninstallation

1. Navigate to **Plugins** > **Installed Plugins**
2. Click the **X** next to "Docker Multi-Network Manager"
3. Confirm removal

**Note**: Configuration files in `/boot/config/plugins/docker-networks/` are preserved for future reinstallation. Delete this directory manually if you want to completely remove all data.

## Development

### Building the Plugin

Use the included build script:

```bash
# Build with automatic date-based version
./build.sh

# Build with specific version
./build.sh 2024.01.15
```

This will:
1. Create `archive/docker-networks-VERSION.txz` containing the plugin files
2. Generate the MD5 hash
3. Create an updated `archive/docker-networks.plg` with the correct version and hash

**Manual build** (if needed):

```bash
# Create the txz archive
cd src
tar -cJf ../archive/docker-networks-2024.01.15.txz usr/
cd ..

# Generate MD5 hash for plg file
md5sum archive/docker-networks-2024.01.15.txz
```

### Publishing to GitHub

1. **Update `docker-networks.plg`** with your GitHub details:
   ```xml
   <!ENTITY gitURL "https://raw.githubusercontent.com/YOUR_USERNAME/unraid-docker-networks/main">
   ```

2. **Build the plugin**:
   ```bash
   ./build.sh 2024.01.15
   ```

3. **Commit and push**:
   ```bash
   git add archive/docker-networks-*.txz docker-networks.plg
   git commit -m "Release version 2024.01.15"
   git push
   ```

4. **Create a GitHub Release** (optional but recommended):
   - Go to your repository's Releases page
   - Create a new release with the version tag
   - Attach the `.txz` file

Users can then install via:
```
https://raw.githubusercontent.com/YOUR_USERNAME/unraid-docker-networks/main/docker-networks.plg
```

### Directory Structure

```
/boot/config/plugins/docker-networks/
├── docker-networks.plg              # Plugin installation file
├── networks.json                     # User configuration
└── docker-networks.cfg               # Plugin settings

/usr/local/emhttp/plugins/docker-networks/
├── DockerNetworks.page              # Main UI page
├── include/
│   ├── helpers.php                  # PHP helper functions
│   └── exec.php                     # AJAX endpoint
├── scripts/
│   ├── docker-networks.sh           # Main daemon/CLI script
│   ├── start.sh                     # Startup script
│   └── stop.sh                      # Shutdown script
├── images/
│   └── docker-networks.svg          # Plugin icon
└── event/
    ├── starting_svcs                # Array start hook
    └── stopping_svcs                # Array stop hook

/var/log/docker-networks/
└── docker-networks.log              # Runtime logs
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is open source. See the LICENSE file for details.

## Credits

- Inspired by the Unraid community's need for multi-network container support
- Thanks to the Unraid plugin development community for documentation and examples
