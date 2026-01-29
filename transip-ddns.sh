#!/usr/bin/env bash
#
# TransIP Dynamic DNS Updater
# Wraps tipctl to update DNS records with current external IP addresses
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# Default values
DRY_RUN=false
VERBOSE=false
SUMMARY=false
CONFIG_FILE=""

# Runtime variables
IPV4_ADDRESS=""
IPV6_ADDRESS=""
declare -a CHANGES_MADE=()
declare -a ERRORS=()

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
TransIP Dynamic DNS Updater v${VERSION}

Usage: $(basename "$0") [OPTIONS] -c <config_file>

Options:
    -c, --config <file>     Path to YAML configuration file (required)
    -n, --dry-run           Show what would be done without making changes
    -v, --verbose           Show detailed output of operations
    -s, --summary           Show summary of changes at the end
    -h, --help              Show this help message
    --version               Show version information

Example:
    $(basename "$0") -c /etc/transip-ddns/config.yaml -v -s
    $(basename "$0") --config config.yaml --dry-run

EOF
}

#######################################
# Log message with timestamp
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, DEBUG)
#   $2 - Message
#######################################
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local color=""
    case "$level" in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        DEBUG) color="$BLUE" ;;
    esac

    if [[ "$level" == "DEBUG" && "$VERBOSE" != "true" ]]; then
        return
    fi

    echo -e "${color}[${timestamp}] [${level}]${NC} ${message}"

    # Also write to logfile if configured
    if [[ -n "${LOGFILE:-}" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "$LOGFILE"
    fi
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--summary)
                SUMMARY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --version)
                echo "TransIP Dynamic DNS Updater v${VERSION}"
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file is required (-c/--config)" >&2
        usage
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file not found: $CONFIG_FILE" >&2
        exit 1
    fi
}

#######################################
# Check if required tools are installed
#######################################
check_dependencies() {
    local missing=()

    if ! command -v tipctl &> /dev/null; then
        missing+=("tipctl")
    fi

    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing[*]}" >&2
        echo "Please install them before running this script." >&2
        exit 1
    fi
}

#######################################
# Load configuration from YAML file
#######################################
load_config() {
    log "INFO" "Loading configuration from $CONFIG_FILE"

    # Required fields
    ACCOUNT_NAME=$(yq -r '.accountname // ""' "$CONFIG_FILE")
    PRIVATE_KEY_PATH=$(yq -r '.privatekeypath // ""' "$CONFIG_FILE")

    if [[ -z "$ACCOUNT_NAME" ]]; then
        log "ERROR" "accountname is required in configuration"
        exit 1
    fi

    if [[ -z "$PRIVATE_KEY_PATH" ]]; then
        log "ERROR" "privatekeypath is required in configuration"
        exit 1
    fi

    if [[ ! -f "$PRIVATE_KEY_PATH" ]]; then
        log "ERROR" "Private key file not found: $PRIVATE_KEY_PATH"
        exit 1
    fi

    # Optional fields with defaults
    LOGFILE=$(yq -r '.logfile // ""' "$CONFIG_FILE")
    TTL=$(yq -r '.timetolive // "300"' "$CONFIG_FILE")

    # Arrays
    readarray -t IPV4_PROVIDERS < <(yq -r '.iplookupproviders[].ipv4[]?' "$CONFIG_FILE" 2>/dev/null | grep -v '^null$' || true)
    readarray -t IPV6_PROVIDERS < <(yq -r '.iplookupproviders[].ipv6[]?' "$CONFIG_FILE" 2>/dev/null | grep -v '^null$' || true)
    readarray -t DOMAINS < <(yq -r '.domains[]' "$CONFIG_FILE")
    readarray -t SUBDOMAINS < <(yq -r '.subdomains[]' "$CONFIG_FILE")
    readarray -t RECORD_TYPES < <(yq -r '.recordtypes[]' "$CONFIG_FILE")

    log "DEBUG" "Account: $ACCOUNT_NAME"
    log "DEBUG" "Private key: $PRIVATE_KEY_PATH"
    log "DEBUG" "TTL: $TTL"
    log "DEBUG" "Domains: ${DOMAINS[*]}"
    log "DEBUG" "Subdomains: ${SUBDOMAINS[*]}"
    log "DEBUG" "Record types: ${RECORD_TYPES[*]}"
    log "DEBUG" "IPv4 providers: ${IPV4_PROVIDERS[*]:-none}"
    log "DEBUG" "IPv6 providers: ${IPV6_PROVIDERS[*]:-none}"
}

#######################################
# Validate an IPv4 address
# Arguments:
#   $1 - IP address to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
is_valid_ipv4() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! $ip =~ $regex ]]; then
        return 1
    fi

    # Check each octet is <= 255
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done

    return 0
}

#######################################
# Validate an IPv6 address
# Arguments:
#   $1 - IP address to validate
# Returns:
#   0 if valid, 1 if invalid
#######################################
is_valid_ipv6() {
    local ip="$1"
    # Simple regex for IPv6 - accepts most common formats
    local regex='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'

    if [[ $ip =~ $regex ]]; then
        return 0
    fi

    return 1
}

#######################################
# Lookup external IPv4 address
# Returns:
#   Sets IPV4_ADDRESS variable
#######################################
lookup_ipv4() {
    if [[ ${#IPV4_PROVIDERS[@]} -eq 0 ]]; then
        log "DEBUG" "No IPv4 providers configured, skipping IPv4 lookup"
        return 0
    fi

    for provider in "${IPV4_PROVIDERS[@]}"; do
        log "DEBUG" "Trying IPv4 provider: $provider"

        local ip
        ip=$(curl -4 -s --max-time 10 "$provider" | tr -d '[:space:]') || continue

        if is_valid_ipv4 "$ip"; then
            IPV4_ADDRESS="$ip"
            log "INFO" "IPv4 address: $IPV4_ADDRESS"
            return 0
        else
            log "WARN" "Invalid IPv4 response from $provider: $ip"
        fi
    done

    log "ERROR" "Failed to obtain valid IPv4 address from any provider"
    return 1
}

#######################################
# Lookup external IPv6 address
# Returns:
#   Sets IPV6_ADDRESS variable
#######################################
lookup_ipv6() {
    if [[ ${#IPV6_PROVIDERS[@]} -eq 0 ]]; then
        log "DEBUG" "No IPv6 providers configured, skipping IPv6 lookup"
        return 0
    fi

    for provider in "${IPV6_PROVIDERS[@]}"; do
        log "DEBUG" "Trying IPv6 provider: $provider"

        local ip
        ip=$(curl -6 -s --max-time 10 "$provider" | tr -d '[:space:]') || continue

        if is_valid_ipv6 "$ip"; then
            IPV6_ADDRESS="$ip"
            log "INFO" "IPv6 address: $IPV6_ADDRESS"
            return 0
        else
            log "WARN" "Invalid IPv6 response from $provider: $ip"
        fi
    done

    log "ERROR" "Failed to obtain valid IPv6 address from any provider"
    return 1
}

# Variable to cache DNS records for current domain
CACHED_DNS_DOMAIN=""
CACHED_DNS_RECORDS=""

#######################################
# Fetch all DNS records for a domain (single API call)
# Arguments:
#   $1 - Domain
# Sets:
#   CACHED_DNS_DOMAIN - The domain that was fetched
#   CACHED_DNS_RECORDS - All DNS records for the domain
#######################################
fetch_domain_dns() {
    local domain="$1"

    log "DEBUG" "Fetching DNS records for $domain"
    CACHED_DNS_DOMAIN="$domain"
    CACHED_DNS_RECORDS=$(tipctl domain:dns:getall "$domain" 2>/dev/null) || CACHED_DNS_RECORDS=""

    if [[ -z "$CACHED_DNS_RECORDS" ]]; then
        log "WARN" "No DNS records found for $domain (or failed to fetch)"
    else
        local record_count
        record_count=$(echo "$CACHED_DNS_RECORDS" | wc -l | tr -d ' ')
        log "DEBUG" "Fetched $record_count DNS records for $domain"
    fi
}

#######################################
# Get current DNS record value from cached data
# Arguments:
#   $1 - Domain
#   $2 - Subdomain (use @ for root)
#   $3 - Record type (A or AAAA)
# Returns:
#   Prints current value or empty string
#######################################
get_dns_record() {
    local domain="$1"
    local subdomain="$2"
    local record_type="$3"

    # Normalize subdomain for lookup
    local lookup_subdomain="$subdomain"
    if [[ "$subdomain" == "/" || "$subdomain" == "@" ]]; then
        lookup_subdomain="@"
    fi

    # Ensure we have cached data for this domain
    if [[ "$CACHED_DNS_DOMAIN" != "$domain" ]]; then
        fetch_domain_dns "$domain"
    fi

    # Filter cached records for the specific subdomain and type
    local result
    result=$(echo "$CACHED_DNS_RECORDS" | grep -E "^${lookup_subdomain}\s+[0-9]+\s+${record_type}\s+" | awk '{print $4}') || true

    echo "$result"
}

#######################################
# Update DNS record using tipctl
# Arguments:
#   $1 - Domain
#   $2 - Subdomain
#   $3 - Record type
#   $4 - New value
#   $5 - Old value (optional, for display)
#######################################
update_dns_record() {
    local domain="$1"
    local subdomain="$2"
    local record_type="$3"
    local new_value="$4"
    local old_value="${5:-}"

    # Normalize subdomain for tipctl
    local tipctl_subdomain="$subdomain"
    if [[ "$subdomain" == "/" ]]; then
        tipctl_subdomain="@"
    fi

    # Build change description with old -> new transition
    local change_desc
    if [[ -n "$old_value" ]]; then
        change_desc="${subdomain}.${domain} ${record_type}: ${old_value} -> ${new_value}"
    else
        change_desc="${subdomain}.${domain} ${record_type}: (new) -> ${new_value}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would update: $change_desc"
        CHANGES_MADE+=("[DRY-RUN] $change_desc")
    else
        log "INFO" "Updating: $change_desc"

        if tipctl domain:dns:updatednsentry "$domain" "$tipctl_subdomain" "$TTL" "$record_type" "$new_value" 2>&1; then
            CHANGES_MADE+=("$change_desc")
            log "DEBUG" "Successfully updated $change_desc"
        else
            local error_msg="Failed to update $change_desc"
            ERRORS+=("$error_msg")
            log "ERROR" "$error_msg"
        fi
    fi
}

#######################################
# Process a single domain
# Arguments:
#   $1 - Domain name
#######################################
process_domain() {
    local domain="$1"

    log "INFO" "Processing domain: $domain"

    # Fetch all DNS records for this domain once (optimization)
    fetch_domain_dns "$domain"

    for subdomain in "${SUBDOMAINS[@]}"; do
        log "DEBUG" "Processing subdomain: $subdomain"

        for record_type in "${RECORD_TYPES[@]}"; do
            local new_ip=""

            case "$record_type" in
                A)
                    if [[ -n "$IPV4_ADDRESS" ]]; then
                        new_ip="$IPV4_ADDRESS"
                    else
                        log "DEBUG" "Skipping A record for $subdomain.$domain - no IPv4 address"
                        continue
                    fi
                    ;;
                AAAA)
                    if [[ -n "$IPV6_ADDRESS" ]]; then
                        new_ip="$IPV6_ADDRESS"
                    else
                        log "DEBUG" "Skipping AAAA record for $subdomain.$domain - no IPv6 address"
                        continue
                    fi
                    ;;
                *)
                    log "WARN" "Unsupported record type: $record_type"
                    continue
                    ;;
            esac

            # Get current record from cached data
            local current_ip
            current_ip=$(get_dns_record "$domain" "$subdomain" "$record_type")

            if [[ -z "$current_ip" ]]; then
                log "DEBUG" "No existing $record_type record for $subdomain.$domain"
                # Create new record
                update_dns_record "$domain" "$subdomain" "$record_type" "$new_ip" ""
            elif [[ "$current_ip" != "$new_ip" ]]; then
                log "DEBUG" "IP changed for $subdomain.$domain $record_type: $current_ip -> $new_ip"
                update_dns_record "$domain" "$subdomain" "$record_type" "$new_ip" "$current_ip"
            else
                log "DEBUG" "No change for $subdomain.$domain $record_type (current: $current_ip)"
            fi
        done
    done
}

#######################################
# Print summary of changes
#######################################
print_summary() {
    echo ""
    echo "=========================================="
    echo "           EXECUTION SUMMARY"
    echo "=========================================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY-RUN (no changes were made)"
    else
        echo "Mode: LIVE"
    fi
    echo ""

    echo "IP Addresses:"
    echo "  IPv4: ${IPV4_ADDRESS:-not configured}"
    echo "  IPv6: ${IPV6_ADDRESS:-not configured}"
    echo ""

    echo "Changes made: ${#CHANGES_MADE[@]}"
    if [[ ${#CHANGES_MADE[@]} -gt 0 ]]; then
        for change in "${CHANGES_MADE[@]}"; do
            echo "  - $change"
        done
    fi
    echo ""

    echo "Errors: ${#ERRORS[@]}"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        for error in "${ERRORS[@]}"; do
            echo "  - $error"
        done
    fi
    echo ""
    echo "=========================================="
}

#######################################
# Main function
#######################################
main() {
    parse_args "$@"
    check_dependencies
    load_config

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY-RUN mode - no changes will be made"
    fi

    # Lookup IP addresses
    local ipv4_ok=true
    local ipv6_ok=true

    # Check if A records are requested
    if printf '%s\n' "${RECORD_TYPES[@]}" | grep -q '^A$'; then
        if ! lookup_ipv4; then
            ipv4_ok=false
        fi
    fi

    # Check if AAAA records are requested
    if printf '%s\n' "${RECORD_TYPES[@]}" | grep -q '^AAAA$'; then
        if ! lookup_ipv6; then
            ipv6_ok=false
        fi
    fi

    # Stop if required IP lookups failed
    if [[ "$ipv4_ok" == "false" && "$ipv6_ok" == "false" ]]; then
        log "ERROR" "Both IPv4 and IPv6 lookups failed, stopping"
        exit 1
    fi

    # Process each domain
    for domain in "${DOMAINS[@]}"; do
        process_domain "$domain"
    done

    # Print summary if requested
    if [[ "$SUMMARY" == "true" ]]; then
        print_summary
    fi

    # Exit with error if there were any errors
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        exit 1
    fi
}

# Run main function
main "$@"
