# TransIP Dynamic DNS Updater

A bash script that automatically updates DNS records at TransIP with your current external IP addresses. Wraps the official [tipctl](https://github.com/transip/tipctl) CLI tool.

## Features

- Updates A (IPv4) and AAAA (IPv6) DNS records
- Supports multiple domains and subdomains
- Multiple IP lookup providers with fallback
- Dry-run mode for testing
- Verbose logging
- Execution summary
- Docker support with scheduled mode
- Helm chart for Kubernetes deployment

## Requirements

- [tipctl](https://github.com/transip/tipctl) - TransIP CLI tool
- [yq](https://github.com/mikefarah/yq) - YAML processor
- [jq](https://jqlang.github.io/jq/) - JSON processor
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

## Docker

### Pre-built Images

Multi-arch images (amd64, arm64) are available from GitHub Container Registry:

```bash
docker pull ghcr.io/jvhaarst/transip-ddns:main
```

### Building the Image Locally

```bash
docker build -t transip-ddns .
```

### Running the Container

The container supports two modes: single-run and scheduled.

**Single-run mode** (runs once and exits):
```bash
docker run --rm \
    -v $(pwd)/config.yaml:/config/config.yaml:ro \
    -v $(pwd)/transip.key:/keys/transip.key:ro \
    transip-ddns
```

**Scheduled mode** (runs continuously at an interval):
```bash
docker run -d \
    --name transip-ddns \
    --restart unless-stopped \
    -e SCHEDULE_INTERVAL=300 \
    -v $(pwd)/config.yaml:/config/config.yaml:ro \
    -v $(pwd)/transip.key:/keys/transip.key:ro \
    transip-ddns
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONFIG_FILE` | `/config/config.yaml` | Path to configuration file inside container |
| `SCHEDULE_INTERVAL` | `0` | Interval in seconds between runs (0 = single-run mode) |
| `SCRIPT_ARGS` | `-s` | Arguments passed to the script |

### Volume Mounts

| Container Path | Description |
|----------------|-------------|
| `/config/config.yaml` | Configuration file (required) |
| `/keys/` | Directory for private key file |

### Docker Compose

```yaml
version: '3.8'
services:
  transip-ddns:
    build: .
    # Or use a pre-built image:
    # image: your-registry/transip-ddns:latest
    restart: unless-stopped
    environment:
      - SCHEDULE_INTERVAL=300
      - SCRIPT_ARGS=-v -s
    volumes:
      - ./config.yaml:/config/config.yaml:ro
      - ./transip.key:/keys/transip.key:ro
```

### Configuration for Docker

When using Docker, set `privatekeypath` in your config to `/keys/transip.key`:

```yaml
accountname: your-transip-username
privatekeypath: /keys/transip.key
# ... rest of config
```

## Kubernetes (Helm)

### Prerequisites

- Kubernetes cluster
- Helm 3.x
- Container image available (built and pushed to a registry)

### Installation

1. Create a secret with your TransIP private key:
   ```bash
   kubectl create secret generic transip-key --from-file=transip.key=/path/to/your/transip.key
   ```

2. Install the chart:
   ```bash
   helm install transip-ddns ./charts/transip-ddns \
     --set transip.accountName=your-username \
     --set transip.privateKey.existingSecret=transip-key \
     --set config.domains[0]=example.com \
     --set config.subdomains[0]=@ \
     --set config.subdomains[1]=www
   ```

### Using a values file

Create a `my-values.yaml`:

```yaml
image:
  repository: ghcr.io/jvhaarst/transip-ddns
  tag: main

schedule: "*/5 * * * *"

transip:
  accountName: your-transip-username
  privateKey:
    existingSecret: transip-key

config:
  domains:
    - example.com
    - example.org
  subdomains:
    - "@"
    - www
    - mail
  recordTypes:
    - A
    - AAAA
```

Install with:
```bash
helm install transip-ddns ./charts/transip-ddns -f my-values.yaml
```

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `transip-ddns` |
| `image.tag` | Container image tag | `latest` |
| `schedule` | Cron schedule | `*/5 * * * *` |
| `transip.accountName` | TransIP account name | `""` |
| `transip.privateKey.existingSecret` | Existing secret name | `""` |
| `config.domains` | List of domains to update | `[]` |
| `config.subdomains` | List of subdomains | `["@"]` |
| `config.recordTypes` | Record types to update | `["A", "AAAA"]` |

### Manual Trigger

To manually trigger a DNS update:
```bash
kubectl create job --from=cronjob/transip-ddns transip-ddns-manual
```

### Viewing Logs

```bash
kubectl logs -l app.kubernetes.io/name=transip-ddns --tail=50
```

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
