#!/bin/bash

# Restic DO Script - Bash Wrapper for Restic Backup Tool
# Version: 1.1.2
# License: MIT
# Author: Evgeny Vlasov

set -euo pipefail

# Script constants
readonly SCRIPT_VERSION="1.1.2"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENV_FILE="${SCRIPT_DIR}/.env"
ACTION=""
SNAPSHOT_ID=""
TARGET_DIR=""
PATTERN=""
MOUNT_DIR=""
SNAPSHOT_ID1=""
SNAPSHOT_ID2=""
BACKUP_SOURCE_TYPE=""
BACKUP_SOURCE_VALUE=""
STDIN_FILENAME=""
declare -a CLI_EXCLUDES=() # Array to hold --exclude patterns from CLI

# Color variables for output
readonly DELIMITER_COLOR="\e[01;38;05;214m"
readonly COLOR_RESET="\033[0m"
readonly ERROR_COLOR="\033[0;31m"
readonly SUCCESS_COLOR="\033[0;32m"
readonly WARNING_COLOR="\033[0;33m"
readonly INFO_COLOR="\033[0;36m"

# Logging configuration
LOG_FILE=""
ENABLE_FILE_LOGGING="false"

# Dependency check results
DEPENDENCIES_CHECKED="false"
RESTIC_AVAILABLE="false"
CURL_AVAILABLE="false"

# Function to log messages with timestamp and level
log() {
    local level="$1"
    local message="$2"
    local color=""
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

    case "$level" in
        "ERROR")   color="$ERROR_COLOR" ;;
        "SUCCESS") color="$SUCCESS_COLOR" ;;
        "WARNING") color="$WARNING_COLOR" ;;
        "INFO")    color="$INFO_COLOR" ;;
        *)         color="" ;;
    esac

    # Print to stdout/stderr with color
    if [[ "$level" == "ERROR" ]]; then
        printf "${color}[%s] [%s] %s${COLOR_RESET}\n" "$timestamp" "$level" "$message" >&2
    else
        printf "${color}[%s] [%s] %s${COLOR_RESET}\n" "$timestamp" "$level" "$message"
    fi

    # Log to file if enabled
    if [[ "$ENABLE_FILE_LOGGING" == "true" && -n "$LOG_FILE" ]]; then
        printf "[%s] [%s] %s\n" "$timestamp" "$level" "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Function to display version information
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
    echo "A Bash wrapper for restic backup tool"
    echo "License: MIT"
    echo "Author: Evgeny Vlasov"
}

# Function to display usage
usage() {
    cat << 'EOF'

Usage: restic-do.sh --action <action> [options]

ACTIONS:
  snapshots     List all snapshots in the repository
  backup        Perform a backup operation
  backup-flow   Execute full backup cycle (check → backup → prune → check)
  check         Check repository integrity
  stats         Show repository statistics (raw data mode)
  stats.latest  Show statistics for the latest snapshot
  cache.cleanup Clean up local cache
  forget        Forget and prune old snapshots
  init          Initialize a new repository
  unlock        Unlock a locked repository
  restore       Restore a specific snapshot
  restore.latest Restore the latest snapshot
  ls            List files in a snapshot
  find          Find files matching pattern across snapshots
  mount         Mount repository using FUSE
  diff          Show differences between two snapshots

GLOBAL OPTIONS:
  --env-file <path>         Path to .env configuration file
                           (default: ./.env in script directory)
  --log-file <path>         Enable file logging to specified path
  --version                 Show version information
  --help                    Display this help message

BACKUP OPTIONS:
  --source-type <type>      Backup source type: 'dir' or 'stdin'
  --source-value <path>     Directory path (required for 'dir' type)
  --stdin-filename <name>   Filename for stdin backup (required for 'stdin' type)
  --exclude <pattern>       Exclude pattern (can be used multiple times)

RESTORE OPTIONS:
  --snapshot-id <id>        Snapshot ID for restore/ls operations
  --target-dir <path>       Target directory for restore operations

SEARCH OPTIONS:
  --pattern <pattern>       Search pattern for find operation

MOUNT OPTIONS:
  --mount-dir <path>        Directory to mount repository

DIFF OPTIONS:
  --snapshot-id1 <id>       First snapshot ID for comparison
  --snapshot-id2 <id>       Second snapshot ID for comparison

EXAMPLES:
  # Initialize a new repository
  restic-do.sh --action init --env-file ./config/.env

  # Backup a directory with exclusions
  restic-do.sh --action backup \
    --env-file ./config/.env \
    --source-type dir \
    --source-value /home/user/documents \
    --exclude "*.tmp" \
    --exclude "cache/"

  # Backup database dump from stdin
  pg_dump mydb | restic-do.sh --action backup \
    --env-file ./config/.env \
    --source-type stdin \
    --stdin-filename "mydb_$(date +%Y%m%d).sql"

  # Full backup cycle with logging
  restic-do.sh --action backup-flow \
    --env-file ./config/.env \
    --source-value /data \
    --log-file ./backup.log

  # Restore latest snapshot
  restic-do.sh --action restore.latest \
    --env-file ./config/.env \
    --target-dir /tmp/restore

  # Mount repository for browsing
  restic-do.sh --action mount \
    --env-file ./config/.env \
    --mount-dir /mnt/backup

CONFIGURATION:
  All configuration is managed through .env files. See .env.distr for template.

EOF
    exit 0
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate path exists and is readable/writable
validate_path() {
    local path="$1"
    local operation="$2" # "read", "write", "create"

    case "$operation" in
        "read")
            if [[ ! -r "$path" ]]; then
                return 1
            fi
            ;;
        "write")
            if [[ ! -w "$path" ]]; then
                return 1
            fi
            ;;
        "create")
            local parent_dir
            parent_dir="$(dirname "$path")"
            if [[ ! -d "$parent_dir" || ! -w "$parent_dir" ]]; then
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to safely escape JSON strings
json_escape() {
    local input="$1"
    # Handle backslashes first, then other special characters
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    input="${input//	/\\t}"
    # Handle actual newlines (convert to \n)
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"
    printf '%s' "$input"
}

# Function to check dependencies
check_dependencies() {
    if [[ "$DEPENDENCIES_CHECKED" == "true" ]]; then
        return 0
    fi

    log "INFO" "Checking system dependencies..."

    # Check restic
    if command_exists "restic"; then
        RESTIC_AVAILABLE="true"
        local restic_version
        restic_version="$(restic version 2>/dev/null | head -1 || echo "unknown")"
        log "SUCCESS" "Found restic: $restic_version"
    else
        RESTIC_AVAILABLE="false"
        log "ERROR" "restic command not found. Please install restic and ensure it's in your PATH."
        log "INFO" "Installation guide: https://restic.readthedocs.io/en/latest/020_installation.html"
        exit 1
    fi

    # Check curl (for Slack notifications)
    if command_exists "curl"; then
        CURL_AVAILABLE="true"
        log "SUCCESS" "Found curl (required for Slack notifications)"
    else
        CURL_AVAILABLE="false"
        log "WARNING" "curl not found. Slack notifications will be disabled."
    fi

    DEPENDENCIES_CHECKED="true"
}

# Function to print a colored banner message
banner() {
    local message="$1"
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

    # Calculate the full text length including timestamp and brackets
    local full_text="[$timestamp] $message"
    local text_length=${#full_text}

    # Set minimum width and add padding
    local min_width=50
    local padding=4  # 2 spaces on each side
    local banner_width=$((text_length + padding))

    # Use minimum width if calculated width is too small
    if [[ $banner_width -lt $min_width ]]; then
        banner_width=$min_width
    fi

    # Create top border
    local border=""
    local i
    for ((i=0; i<banner_width-2; i++)); do
        border+="─"
    done

    # Calculate spaces for centering text
    local content_width=$((banner_width - 4))  # Account for │ and spaces
    local text_padding=$((content_width - text_length))
    local left_padding=$((text_padding / 2))
    local right_padding=$((text_padding - left_padding))

    # Build padding strings
    local left_spaces=""
    local right_spaces=""
    for ((i=0; i<left_padding; i++)); do
        left_spaces+=" "
    done
    for ((i=0; i<right_padding; i++)); do
        right_spaces+=" "
    done

    # Print the banner
    printf "\n${DELIMITER_COLOR}╭${border}╮${COLOR_RESET}\n"
    printf "${DELIMITER_COLOR}│ ${left_spaces}%s${right_spaces} │${COLOR_RESET}\n" "$full_text"
    printf "${DELIMITER_COLOR}╰${border}╯${COLOR_RESET}\n\n"
}

# Function to print an error message and exit
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    log "ERROR" "$message"

    # Send Slack notification in background if available and configured
    if should_send_slack_notification "error" && [[ -n "${SLACK_HOOK:-}" ]]; then
        send_slack_notification "❌ Error: $message" ":x:" "error"
    fi

    exit "$exit_code"
}

# Function to get meta information for Slack notifications
get_meta_info() {
    local meta=""

    # Add each line separately with actual newlines for Slack
    meta+="
> *Repository*: \`${RESTIC_REPO:-"Not set"}\`"
    meta+="
> *Action*: \`${ACTION:-"Not set"}\`"

    if [[ -n "${BACKUP_SOURCE_TYPE:-}" ]]; then
        meta+="
> *Source Type*: \`${BACKUP_SOURCE_TYPE}\`"
    fi

    if [[ -n "${BACKUP_SOURCE_VALUE:-}" ]]; then
        meta+="
> *Source Value*: \`${BACKUP_SOURCE_VALUE}\`"
    fi

    if [[ -n "${STDIN_FILENAME:-}" ]]; then
        meta+="
> *Stdin Filename*: \`${STDIN_FILENAME}\`"
    fi

    if [[ -n "${BACKUP_EXCLUDE:-}" ]]; then
        meta+="
> *Excludes (.env)*: \`${BACKUP_EXCLUDE}\`"
    fi

    if [[ ${#CLI_EXCLUDES[@]} -gt 0 ]]; then
        local excludes_str=""
        local i
        for ((i=0; i<${#CLI_EXCLUDES[@]}; i++)); do
            if [[ $i -gt 0 ]]; then
                excludes_str+=", "
            fi
            excludes_str+="${CLI_EXCLUDES[$i]}"
        done
        meta+="
> *Excludes (CLI)*: \`${excludes_str}\`"
    fi

    printf '%s' "$meta"
}

# Function to check if Slack notifications should be sent
should_send_slack_notification() {
    local notification_type="${1:-success}" # success or error

    case "$notification_type" in
        "success")
            [[ "${SLACK_SEND_NOTIFICATIONS_ON_SUCCESS:-false}" == "true" ]]
            ;;
        "error")
            [[ "${SLACK_SEND_NOTIFICATIONS_ON_ERROR:-false}" == "true" ]]
            ;;
        *)
            # For backward compatibility, check both flags
            [[ "${SLACK_SEND_NOTIFICATIONS_ON_SUCCESS:-false}" == "true" ]] || \
            [[ "${SLACK_SEND_NOTIFICATIONS_ON_ERROR:-false}" == "true" ]]
            ;;
    esac
}

# Function to send Slack notification
send_slack_notification() {
    local message="$1"
    local emoji="${2:-${SLACK_LOG_EMOJI_DEFAULT:-:bell:}}"
    local notification_type="${3:-success}" # success or error

    # Early return if notifications disabled or dependencies missing
    if ! should_send_slack_notification "$notification_type"; then
        return 0
    fi

    if [[ "$CURL_AVAILABLE" != "true" ]]; then
        log "WARNING" "Cannot send Slack notification: curl not available"
        return 0
    fi

    if [[ -z "${SLACK_HOOK:-}" ]]; then
        log "WARNING" "Cannot send Slack notification: SLACK_HOOK not configured"
        return 0
    fi

    local message="$1"
    local emoji="${2:-${SLACK_LOG_EMOJI_DEFAULT:-:bell:}}"
    local channel="${SLACK_CHANNEL:-#general}"
    local username="${SLACK_USERNAME:-Restic Backup}"

    # Add meta information
    local meta_info
    meta_info="$(get_meta_info)"
    message+="$meta_info"

    # Escape message for JSON
    local escaped_message
    escaped_message="$(json_escape "$message")"

    # Construct JSON payload
    local json_payload
    json_payload="$(printf '{"channel": "%s", "username": "%s", "text": "%s", "icon_emoji": "%s"}' \
        "$channel" "$username" "$escaped_message" "$emoji")"

    # Send notification in background to avoid blocking script completion
    log "INFO" "Sending Slack notification..."

    # Execute curl in background and capture result
    (
        if timeout 10 curl -s -X POST \
            -H 'Content-type: application/json' \
            --data "$json_payload" \
            "$SLACK_HOOK" >/dev/null 2>&1; then
            # Success - but don't log as it might appear after script ends
            :
        else
            # Failure - but don't log as it might appear after script ends
            :
        fi
    ) &

    # Log immediately without waiting for curl to complete
    log "SUCCESS" "Slack notification initiated"
}

# Function to validate backup parameters
validate_backup_params() {
    if [[ -z "$BACKUP_SOURCE_TYPE" ]]; then
        error_exit "Backup source type is required. Use --source-type dir|stdin"
    fi

    case "$BACKUP_SOURCE_TYPE" in
        "dir")
            if [[ -z "$BACKUP_SOURCE_VALUE" ]]; then
                error_exit "Directory path is required for 'dir' source type. Use --source-value <path>"
            fi
            if [[ ! -d "$BACKUP_SOURCE_VALUE" ]]; then
                error_exit "Source directory does not exist: $BACKUP_SOURCE_VALUE"
            fi
            if ! validate_path "$BACKUP_SOURCE_VALUE" "read"; then
                error_exit "Source directory is not readable: $BACKUP_SOURCE_VALUE"
            fi
            ;;
        "stdin")
            if [[ -z "$STDIN_FILENAME" ]]; then
                error_exit "Filename is required for 'stdin' source type. Use --stdin-filename <name>"
            fi
            # Validate filename doesn't contain dangerous characters
            if [[ "$STDIN_FILENAME" =~ [[:space:]/\\] ]]; then
                error_exit "Invalid filename for stdin backup: $STDIN_FILENAME"
            fi
            ;;
        *)
            error_exit "Invalid backup source type: $BACKUP_SOURCE_TYPE (must be 'dir' or 'stdin')"
            ;;
    esac
}

# Function to build exclude parameters
build_exclude_params() {
    local -a exclude_params=()

    # Add excludes from .env file
    if [[ -n "${BACKUP_EXCLUDE:-}" ]]; then
        IFS=',' read -ra patterns <<< "$BACKUP_EXCLUDE"
        for pattern in "${patterns[@]}"; do
            # Trim whitespace
            pattern="$(echo "$pattern" | xargs)"
            if [[ -n "$pattern" ]]; then
                exclude_params+=("--exclude" "$pattern")
            fi
        done
    fi

    # Add excludes from command line (check if array exists first)
    if [[ ${#CLI_EXCLUDES[@]} -gt 0 ]]; then
        local i
        for ((i=0; i<${#CLI_EXCLUDES[@]}; i++)); do
            exclude_params+=("--exclude" "${CLI_EXCLUDES[$i]}")
        done
    fi

    # Output parameters one per line
    if [[ ${#exclude_params[@]} -gt 0 ]]; then
        local param
        for param in "${exclude_params[@]}"; do
            printf '%s\n' "$param"
        done
    fi
}

# Function to perform backup
perform_backup() {
    validate_backup_params

    # Build exclude parameters using a more compatible method
    local -a exclude_params=()
    while IFS= read -r param; do
        [[ -n "$param" ]] && exclude_params+=("$param")
    done < <(build_exclude_params)

    case "$BACKUP_SOURCE_TYPE" in
        "dir")
            banner "Backing up directory: $BACKUP_SOURCE_VALUE"
            log "INFO" "Starting directory backup with ${#exclude_params[@]} exclude rules"

            # Execute backup with proper quoting and error handling
            if [[ ${#exclude_params[@]} -gt 0 ]]; then
                restic --repo "$RESTIC_REPO" backup "${exclude_params[@]}" "$BACKUP_SOURCE_VALUE"
            else
                restic --repo "$RESTIC_REPO" backup "$BACKUP_SOURCE_VALUE"
            fi
            ;;
        "stdin")
            banner "Backing up from stdin: $STDIN_FILENAME"
            log "INFO" "Starting stdin backup"

            # Read from stdin and backup
            if [[ ${#exclude_params[@]} -gt 0 ]]; then
                restic --repo "$RESTIC_REPO" backup "${exclude_params[@]}" --stdin --stdin-filename "$STDIN_FILENAME"
            else
                restic --repo "$RESTIC_REPO" backup --stdin --stdin-filename "$STDIN_FILENAME"
            fi
            ;;
    esac

    log "SUCCESS" "Backup completed successfully"
    send_slack_notification "Backup completed successfully!" ":white_check_mark:" "success"
}

# Function to safely parse arguments looking for --env-file
pre_parse_env_file() {
    local prev_arg=""

    for arg in "$@"; do
        if [[ "$prev_arg" == "--env-file" ]]; then
            if [[ -n "$arg" && "$arg" != --* ]]; then
                ENV_FILE="$arg"
                return 0
            else
                error_exit "Invalid or missing value for --env-file argument"
            fi
        fi
        prev_arg="$arg"
    done
}

# Function to load and validate environment variables
load_environment() {
    if [[ ! -f "$ENV_FILE" ]]; then
        error_exit "Environment file not found: $ENV_FILE"
    fi

    if ! validate_path "$ENV_FILE" "read"; then
        error_exit "Cannot read environment file: $ENV_FILE"
    fi

    log "INFO" "Loading environment from: $ENV_FILE"

    # Source the environment file safely
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    # Set defaults for optional variables
    BACKUP_SOURCE_TYPE="${BACKUP_SOURCE_TYPE:-dir}"
    SLACK_SEND_NOTIFICATIONS_ON_SUCCESS="${SLACK_SEND_NOTIFICATIONS_ON_SUCCESS:-false}"
    SLACK_SEND_NOTIFICATIONS_ON_ERROR="${SLACK_SEND_NOTIFICATIONS_ON_ERROR:-false}"
    SLACK_LOG_EMOJI_DEFAULT="${SLACK_LOG_EMOJI_DEFAULT:-:bell:}"
    SLACK_USERNAME="${SLACK_USERNAME:-Restic Backup}"

    # Validate required variables
    local required_vars=("RESTIC_REPO" "RESTIC_PASSWORD")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable not set: $var"
        fi
    done

    # Validate retention policy variables
    local retention_vars=(
        "RESTIC_REPO_KEEP_LAST"
        "RESTIC_REPO_KEEP_DAILY"
        "RESTIC_REPO_KEEP_WEEKLY"
        "RESTIC_REPO_KEEP_MONTHLY"
        "RESTIC_REPO_KEEP_YEARLY"
    )

    for var in "${retention_vars[@]}"; do
        local value="${!var:-}"
        if [[ -n "$value" ]] && ! [[ "$value" =~ ^[0-9]+$ ]]; then
            error_exit "Invalid retention policy value for $var: must be a positive integer"
        fi
    done

    log "SUCCESS" "Environment loaded successfully"
}

# Function to parse early arguments (version and help) before environment loading
early_parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                show_version
                exit 0
                ;;
            --help)
                usage
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --action"
                ACTION="$2"
                shift 2
                ;;
            --env-file)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --env-file"
                ENV_FILE="$2"
                shift 2
                ;;
            --log-file)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --log-file"
                LOG_FILE="$2"
                ENABLE_FILE_LOGGING="true"
                shift 2
                ;;
            --snapshot-id)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --snapshot-id"
                SNAPSHOT_ID="$2"
                shift 2
                ;;
            --target-dir)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --target-dir"
                TARGET_DIR="$2"
                shift 2
                ;;
            --pattern)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --pattern"
                PATTERN="$2"
                shift 2
                ;;
            --mount-dir)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --mount-dir"
                MOUNT_DIR="$2"
                shift 2
                ;;
            --snapshot-id1)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --snapshot-id1"
                SNAPSHOT_ID1="$2"
                shift 2
                ;;
            --snapshot-id2)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --snapshot-id2"
                SNAPSHOT_ID2="$2"
                shift 2
                ;;
            --source-type)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --source-type"
                BACKUP_SOURCE_TYPE="$2"
                shift 2
                ;;
            --source-value)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --source-value"
                BACKUP_SOURCE_VALUE="$2"
                shift 2
                ;;
            --stdin-filename)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --stdin-filename"
                STDIN_FILENAME="$2"
                shift 2
                ;;
            --exclude)
                [[ -n "${2:-}" ]] || error_exit "Missing value for --exclude"
                CLI_EXCLUDES+=("$2")
                shift 2
                ;;
            *)
                error_exit "Unknown argument: $1"
                ;;
        esac
    done
}

# Function to validate action-specific parameters
validate_action_params() {
    case "$ACTION" in
        "restore")
            [[ -n "$SNAPSHOT_ID" ]] || error_exit "--snapshot-id is required for restore action"
            [[ -n "$TARGET_DIR" ]] || error_exit "--target-dir is required for restore action"
            ;;
        "restore.latest")
            [[ -n "$TARGET_DIR" ]] || error_exit "--target-dir is required for restore.latest action"
            ;;
        "ls")
            [[ -n "$SNAPSHOT_ID" ]] || error_exit "--snapshot-id is required for ls action"
            ;;
        "find")
            [[ -n "$PATTERN" ]] || error_exit "--pattern is required for find action"
            ;;
        "mount")
            [[ -n "$MOUNT_DIR" ]] || error_exit "--mount-dir is required for mount action"
            ;;
        "diff")
            [[ -n "$SNAPSHOT_ID1" ]] || error_exit "--snapshot-id1 is required for diff action"
            [[ -n "$SNAPSHOT_ID2" ]] || error_exit "--snapshot-id2 is required for diff action"
            ;;
        "backup"|"backup-flow")
            # Validation handled in perform_backup function
            ;;
    esac

    # Validate target directory for restore operations
    if [[ -n "$TARGET_DIR" ]]; then
        local target_parent
        target_parent="$(dirname "$TARGET_DIR")"
        if [[ ! -d "$target_parent" ]]; then
            error_exit "Parent directory for target does not exist: $target_parent"
        fi
        if ! validate_path "$target_parent" "write"; then
            error_exit "Cannot write to target parent directory: $target_parent"
        fi
    fi

    # Validate mount directory
    if [[ -n "$MOUNT_DIR" ]]; then
        if [[ ! -d "$MOUNT_DIR" ]]; then
            error_exit "Mount directory does not exist: $MOUNT_DIR"
        fi
        if ! validate_path "$MOUNT_DIR" "write"; then
            error_exit "Cannot write to mount directory: $MOUNT_DIR"
        fi
    fi
}

# Main execution function
execute_action() {
    case "$ACTION" in
        "snapshots")
            banner "Listing repository snapshots"
            restic --repo "$RESTIC_REPO" snapshots
            ;;
        "backup")
            perform_backup
            ;;
        "check")
            banner "Checking repository integrity"
            restic --repo "$RESTIC_REPO" check --read-data
            log "SUCCESS" "Repository check completed successfully"
            ;;
        "stats")
            banner "Repository statistics (raw data mode)"
            restic --repo "$RESTIC_REPO" stats --mode raw-data
            ;;
        "stats.latest")
            banner "Latest snapshot statistics"
            restic --repo "$RESTIC_REPO" stats latest --mode restore-size
            ;;
        "cache.cleanup")
            banner "Cleaning repository cache"
            restic --repo "$RESTIC_REPO" cache --cleanup
            log "SUCCESS" "Cache cleanup completed successfully"
            ;;
        "forget")
            banner "Forgetting and pruning old snapshots"
            restic --repo "$RESTIC_REPO" forget \
                --keep-last "${RESTIC_REPO_KEEP_LAST}" \
                --keep-daily "${RESTIC_REPO_KEEP_DAILY}" \
                --keep-weekly "${RESTIC_REPO_KEEP_WEEKLY}" \
                --keep-monthly "${RESTIC_REPO_KEEP_MONTHLY}" \
                --keep-yearly "${RESTIC_REPO_KEEP_YEARLY}" \
                --prune
            log "SUCCESS" "Forget and prune completed successfully"
            ;;
        "init")
            banner "Initializing repository"
            restic --repo "$RESTIC_REPO" init
            log "SUCCESS" "Repository initialized successfully"
            ;;
        "unlock")
            banner "Unlocking repository"
            restic --repo "$RESTIC_REPO" unlock
            log "SUCCESS" "Repository unlocked successfully"
            ;;
        "restore")
            banner "Restoring snapshot $SNAPSHOT_ID to $TARGET_DIR"
            restic --repo "$RESTIC_REPO" restore "$SNAPSHOT_ID" --target "$TARGET_DIR"
            log "SUCCESS" "Snapshot restored successfully"
            ;;
        "restore.latest")
            banner "Restoring latest snapshot to $TARGET_DIR"
            restic --repo "$RESTIC_REPO" restore latest --target "$TARGET_DIR"
            log "SUCCESS" "Latest snapshot restored successfully"
            ;;
        "ls")
            banner "Listing files in snapshot $SNAPSHOT_ID"
            restic --repo "$RESTIC_REPO" ls "$SNAPSHOT_ID"
            ;;
        "find")
            banner "Finding files matching pattern: $PATTERN"
            restic --repo "$RESTIC_REPO" find "$PATTERN"
            ;;
        "mount")
            banner "Mounting repository to $MOUNT_DIR"
            log "INFO" "Note: This command requires FUSE to be installed on your system"
            log "INFO" "Press Ctrl+C to unmount"
            restic --repo "$RESTIC_REPO" mount "$MOUNT_DIR"
            ;;
        "diff")
            banner "Comparing snapshots $SNAPSHOT_ID1 and $SNAPSHOT_ID2"
            restic --repo "$RESTIC_REPO" diff "$SNAPSHOT_ID1" "$SNAPSHOT_ID2"
            ;;
        "backup-flow")
            execute_backup_flow
            ;;
        *)
            error_exit "Invalid action: $ACTION"
            ;;
    esac
}

# Function to execute full backup flow
execute_backup_flow() {
    banner "Starting comprehensive backup flow (8 steps)"

    # Display configuration summary
    log "INFO" "Configuration Summary:"
    log "INFO" "  Repository: $RESTIC_REPO"
    log "INFO" "  Source Type: $BACKUP_SOURCE_TYPE"
    log "INFO" "  Source Value: ${BACKUP_SOURCE_VALUE:-"Not set"}"
    log "INFO" "  Stdin Filename: ${STDIN_FILENAME:-"Not set"}"
    echo
    log "INFO" "Retention Policy:"
    log "INFO" "  Keep Last: $RESTIC_REPO_KEEP_LAST"
    log "INFO" "  Keep Daily: $RESTIC_REPO_KEEP_DAILY"
    log "INFO" "  Keep Weekly: $RESTIC_REPO_KEEP_WEEKLY"
    log "INFO" "  Keep Monthly: $RESTIC_REPO_KEEP_MONTHLY"
    log "INFO" "  Keep Yearly: $RESTIC_REPO_KEEP_YEARLY"
    echo

    # Step 1: Pre-backup repository check
    banner "Step 1/8: Pre-backup repository integrity check"
    restic --repo "$RESTIC_REPO" check --read-data
    log "SUCCESS" "Pre-backup check completed"

    # Step 2: Perform backup
    banner "Step 2/8: Performing backup"
    perform_backup

    # Step 3: Post-backup repository check
    banner "Step 3/8: Post-backup repository integrity check"
    restic --repo "$RESTIC_REPO" check --read-data
    log "SUCCESS" "Post-backup check completed"

    # Step 4: Forget and prune old snapshots
    banner "Step 4/8: Forgetting and pruning old snapshots"
    restic --repo "$RESTIC_REPO" forget \
        --keep-last "$RESTIC_REPO_KEEP_LAST" \
        --keep-daily "$RESTIC_REPO_KEEP_DAILY" \
        --keep-weekly "$RESTIC_REPO_KEEP_WEEKLY" \
        --keep-monthly "$RESTIC_REPO_KEEP_MONTHLY" \
        --keep-yearly "$RESTIC_REPO_KEEP_YEARLY" \
        --prune
    log "SUCCESS" "Forget and prune completed"

    # Step 5: Cache cleanup
    banner "Step 5/8: Cleaning repository cache"
    restic --repo "$RESTIC_REPO" cache --cleanup
    log "SUCCESS" "Cache cleanup completed"

    # Step 6: Final repository check
    banner "Step 6/8: Final repository integrity check"
    restic --repo "$RESTIC_REPO" check --read-data
    log "SUCCESS" "Final repository check completed"

    # Step 7: List current snapshots
    banner "Step 7/8: Listing current snapshots"
    restic --repo "$RESTIC_REPO" snapshots

    # Step 8: Show repository statistics
    banner "Step 8/8: Repository statistics"
    restic --repo "$RESTIC_REPO" stats --mode raw-data

    banner "Complete backup flow finished successfully!"
    log "SUCCESS" "All backup flow steps completed successfully"
}

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script exited with error code: $exit_code"
        if should_send_slack_notification "error" && [[ -n "${SLACK_HOOK:-}" ]]; then
            # Send notification using the enhanced function with meta info
            send_slack_notification "💥 Script failed with exit code: $exit_code" ":x:" "error"
        fi
    fi

    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM

# Main execution starts here
main() {
    # Early parse for --version and --help (before loading environment)
    early_parse_arguments "$@"

    # Pre-parse to find --env-file before loading environment
    pre_parse_env_file "$@"

    # Load environment configuration
    load_environment

    # Set up file logging if specified
    if [[ "$ENABLE_FILE_LOGGING" == "true" && -n "$LOG_FILE" ]]; then
        if ! validate_path "$(dirname "$LOG_FILE")" "write"; then
            error_exit "Cannot write to log file directory: $(dirname "$LOG_FILE")"
        fi
        log "INFO" "File logging enabled: $LOG_FILE"
    fi

    # Parse all command line arguments
    parse_arguments "$@"

    # Validate that action was specified
    if [[ -z "$ACTION" ]]; then
        usage
    fi

    # Check system dependencies
    check_dependencies

    # Validate action-specific parameters
    validate_action_params

    # Log startup information
    log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log "INFO" "Action: $ACTION"
    log "INFO" "Environment: $ENV_FILE"

    # Execute the requested action
    execute_action

    log "SUCCESS" "Action '$ACTION' completed successfully"
}

# Execute main function with all arguments
main "$@"
