# TransIP Dynamic DNS Updater

A bash script that automatically updates DNS records at TransIP with your current external IP addresses. Wraps the official [tipctl](https://github.com/transip/tipctl) CLI tool.

## Features

- Updates A (IPv4) and AAAA (IPv6) DNS records
- Supports multiple domains and subdomains
- Multiple IP lookup providers with fallback
- Dry-run mode for testing
- Verbose logging
- Execution summary

## Requirements

- [tipctl](https://github.com/transip/tipctl) - TransIP CLI tool
- [yq](https://github.com/mikefarah/yq) - YAML processor
- curl

### Installing Dependencies

**macOS (Homebrew):**
```bash
brew install yq curl
# For tipctl, download from GitHub releases or install via composer
composer global require transip/tipctl
```

**Debian/Ubuntu:**
```bash
sudo apt install curl
# Install yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
# For tipctl, download PHAR from GitHub releases
```

## Configuration

1. Copy the example configuration:
   ```bash
   cp config.example.yaml config.yaml
   ```

2. Edit `config.yaml` with your settings:

```yaml
# TransIP account name (required)
accountname: your-transip-username

# Path to your TransIP private key file (required)
privatekeypath: /path/to/transip.key

# Log file path (optional)
logfile: /var/log/transip-ddns.log

# IP lookup providers
iplookupproviders:
  - ipv4:
      - 'https://ipv4.icanhazip.com/'
  - ipv6:
      - 'https://ipv6.icanhazip.com/'

# Domains to update
domains:
  - example.com

# Subdomains to update ('/' or '@' for root)
subdomains:
  - '/'
  - www

# TTL in seconds
timetolive: 300

# Record types
recordtypes:
  - A
  - AAAA
```

### Getting Your TransIP API Key

1. Log in to the [TransIP Control Panel](https://www.transip.nl/cp/)
2. Go to Account Settings > API
3. Generate a new key pair
4. Save the private key to a secure location
5. Set `privatekeypath` in your config to point to this file

## Usage

```bash
# Show help
./transip-ddns.sh --help

# Dry run (preview changes)
./transip-ddns.sh -c config.yaml --dry-run --verbose

# Live run with summary
./transip-ddns.sh -c config.yaml --summary

# Full verbose output
./transip-ddns.sh -c config.yaml -v -s
```

### Options

| Option | Description |
|--------|-------------|
| `-c, --config <file>` | Path to YAML configuration file (required) |
| `-n, --dry-run` | Show what would be done without making changes |
| `-v, --verbose` | Show detailed output |
| `-s, --summary` | Show summary of changes at the end |
| `-h, --help` | Show help message |
| `--version` | Show version |

## Scheduling

### Cron

Run every 5 minutes:
```bash
*/5 * * * * /path/to/transip-ddns.sh -c /path/to/config.yaml -s >> /var/log/transip-ddns-cron.log 2>&1
```

### Systemd Timer

Create `/etc/systemd/system/transip-ddns.service`:
```ini
[Unit]
Description=TransIP Dynamic DNS Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/path/to/transip-ddns.sh -c /path/to/config.yaml -s
```

Create `/etc/systemd/system/transip-ddns.timer`:
```ini
[Unit]
Description=Run TransIP DDNS every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

Enable and start:
```bash
sudo systemctl enable --now transip-ddns.timer
```

## License

MIT
