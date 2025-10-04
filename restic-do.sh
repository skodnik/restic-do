#!/bin/bash

set -euo pipefail

# Default values
ENV_FILE="$(dirname "$0")/.env" # Default to .env in the script's directory
ACTION=""
SNAPSHOT_ID=""
TARGET_DIR=""
PATTERN=""
MOUNT_DIR=""
SNAPSHOT_ID1=""
SNAPSHOT_ID2=""
BACKUP_SOURCE_TYPE="" # Will be set from .env or CLI, with a default later
BACKUP_SOURCE_VALUE=""
STDIN_FILENAME=""
declare -a CLI_EXCLUDES # Array to hold --exclude patterns from CLI

# Color variables for output
DELIMITER_COLOR="\e[01;38;05;214m"
COLOR_RESET="\033[0m"
ERROR_COLOR="\033[0;31m" # Red color

# Function to print a colored banner message
banner() {
    local message="$1"
    local current_time_log=$(date +"%F %H:%M:%S")
    printf "\n${DELIMITER_COLOR}[${current_time_log}] ${message}${COLOR_RESET}\n\n"
}

# Function to print an error message in red and exit
error_message() {
    local message="$1"
    printf "\n${ERROR_COLOR}Error: ${message}${COLOR_RESET}\n" >&2 # Print to stderr
    exit 1
}

# Function to perform a backup
perform_backup() {
    # Prepare exclude parameters
    local BACKUP_EXCLUDE_PARAMS=()
    # From .env file (comma-separated)
    if [ -n "${BACKUP_EXCLUDE-}" ]; then
        IFS=',' read -ra patterns <<< "$BACKUP_EXCLUDE"
        for pattern in "${patterns[@]}"; do
            # Trim whitespace
            pattern=$(echo "$pattern" | xargs)
            if [ -n "$pattern" ]; then
                BACKUP_EXCLUDE_PARAMS+=(--exclude "$pattern")
            fi
        done
    fi
    # From command line
    if [ ${#CLI_EXCLUDES[@]} -gt 0 ]; then
        for pattern in "${CLI_EXCLUDES[@]}"; do
            BACKUP_EXCLUDE_PARAMS+=(--exclude "$pattern")
        done
    fi

    if [ "$BACKUP_SOURCE_TYPE" == "dir" ]; then
        if [ -z "$BACKUP_SOURCE_VALUE" ]; then
            error_message "--source-value is required for dir source-type."
        fi
        banner "Performing backup of ${BACKUP_SOURCE_VALUE}..."
        if [ ${#BACKUP_EXCLUDE_PARAMS[@]} -gt 0 ]; then
            ${RESTIC_BASE_COMMAND} backup "${BACKUP_EXCLUDE_PARAMS[@]}" "${BACKUP_SOURCE_VALUE}"
        else
            ${RESTIC_BASE_COMMAND} backup "${BACKUP_SOURCE_VALUE}"
        fi
    elif [ "$BACKUP_SOURCE_TYPE" == "stdin" ]; then
        if [ -z "$STDIN_FILENAME" ]; then
            error_message "--stdin-filename is required for stdin source-type."
        fi
        banner "Performing backup from stdin (filename: ${STDIN_FILENAME})..."
        # Excludes are not typically used with stdin, but restic allows them, so we pass them.
        if [ ${#BACKUP_EXCLUDE_PARAMS[@]} -gt 0 ]; then
            cat - | ${RESTIC_BASE_COMMAND} backup "${BACKUP_EXCLUDE_PARAMS[@]}" --stdin --stdin-filename "${STDIN_FILENAME}"
        else
            cat - | ${RESTIC_BASE_COMMAND} backup --stdin --stdin-filename "${STDIN_FILENAME}"
        fi
    else
        error_message "Invalid backup source type: ${BACKUP_SOURCE_TYPE}"
    fi
}

# Function to display usage
usage() {
    echo ""
    echo "Usage: $0 --action <action> [options]"
    echo ""
    echo "Actions: snapshots, backup, check, stats, stats.latest, cache.cleanup, forget, init, unlock, restore, ls, find, mount, diff, backup-flow"
    echo ""
    echo "Options:"
    echo "  --env-file <path>         : Path to the .env file (default: ./.env in script's directory)"
    echo "  --snapshot-id <id>        : Snapshot ID for restore, ls, diff"
    echo "  --target-dir <path>       : Target directory for restore"
    echo "  --pattern <pattern>       : Pattern for find"
    echo "  --mount-dir <path>        : Mount directory for mount"
    echo "  --snapshot-id1 <id>       : First snapshot ID for diff"
    echo "  --snapshot-id2 <id>       : Second snapshot ID for diff"
    echo "  --source-type <type>      : Type of backup source (dir, stdin) for backup action"
    echo "  --source-value <value>    : Value for backup source (path for dir). Not used for stdin."
    echo "  --stdin-filename <name>   : Filename for stdin backup (required for stdin source-type)"
    echo "  --exclude <pattern>       : Exclude a file or directory matching pattern. Can be specified multiple times."
    echo "  --help                    : Display this help message"
    echo ""
    echo "Examples:"
    echo "  # List all snapshots in the repository"
    echo "  $0 --action snapshots --env-file ./repo-test/.env"
    echo ""
    echo "  # Backup a directory"
    echo "  $0 --action backup --env-file ./path/to/configs/.env --source-type dir --source-value /path/to/backup/data"
    echo ""
    echo "  # Backup data from stdin (e.g., pg_dump output)"
    echo "  pg_dump my_db | $0 --action backup --env-file ./path/to/configs/.env --source-type stdin --stdin-filename my_db.sql"
    echo ""
    echo "  # Restore the latest snapshot to a directory"
    echo "  $0 --action restore.latest --env-file ./path/to/configs/.env --target-dir /tmp/restore"
    echo ""
    echo "  # Restore a specific snapshot by ID"
    echo "  $0 --action restore --env-file ./path/to/configs/.env --snapshot-id <snapshot_id> --target-dir /tmp/restore"
    echo ""
    echo "  # Mount the repository (requires FUSE)"
    echo "  $0 --action mount --env-file ./path/to/configs/.env --mount-dir /mnt/restic_repo"
    echo ""
    echo "  # Perform a full backup cycle with checks and pruning"
    echo "  $0 --action backup-flow --env-file ./path/to/configs/.env --source-value /path/to/backup/data"
    exit 1
}

# Pre-parse arguments to find --env-file
_ENV_FILE_PATH_FROM_ARGS=""
_PREV_ARG=""
for arg in "$@"; do
  if [[ "$_PREV_ARG" == "--env-file" ]]; then
    _ENV_FILE_PATH_FROM_ARGS="$arg"
    break
  fi
  _PREV_ARG="$arg"
done

# If --env-file was passed, use it. Otherwise, use the default.
if [[ -n "$_ENV_FILE_PATH_FROM_ARGS" ]]; then
  ENV_FILE="$_ENV_FILE_PATH_FROM_ARGS"
fi

# Source environment variables from the determined .env file path
if [ -f "${ENV_FILE}" ]; then
    set -a
    source "${ENV_FILE}"
    set +a
fi

# Set default for BACKUP_SOURCE_TYPE if not set by .env
BACKUP_SOURCE_TYPE="${BACKUP_SOURCE_TYPE:-dir}"

# Parse all arguments. CLI args will override any .env values.
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --action) ACTION="$2"; shift ;;
        --env-file) ENV_FILE="$2"; shift ;; # This updates ENV_FILE again, which is fine.
        --snapshot-id) SNAPSHOT_ID="$2"; shift ;;
        --target-dir) TARGET_DIR="$2"; shift ;;
        --pattern) PATTERN="$2"; shift ;;
        --mount-dir) MOUNT_DIR="$2"; shift ;;
        --snapshot-id1) SNAPSHOT_ID1="$2"; shift ;;
        --snapshot-id2) SNAPSHOT_ID2="$2"; shift ;;
        --source-type) BACKUP_SOURCE_TYPE="$2"; shift ;;
        --source-value) BACKUP_SOURCE_VALUE="$2"; shift ;;
        --stdin-filename) STDIN_FILENAME="$2"; shift ;;
        --exclude) CLI_EXCLUDES+=("$2"); shift ;;
        --help) usage; exit 0 ;;
        *) usage ;;
    esac
    shift
done

# Validate action
if [ -z "$ACTION" ]; then
    usage
fi

# Final check that the .env file exists and is readable
if [ ! -f "${ENV_FILE}" ]; then
    error_message ".env file not found at ${ENV_FILE}"
fi

# Check required restic variables
REQUIRED_VARS="RESTIC_REPO RESTIC_PASSWORD"
for v in $REQUIRED_VARS; do
    if [ -z "${!v}" ]; then
        error_message "$v is not set in .env file."
    fi
done

# Check for restic command and print version
if ! command -v restic &> /dev/null; then
    error_message "restic command not found. Please install restic and make sure it's in your PATH."
else
    banner "Found restic version"
    restic version
fi

# Construct RESTIC_BASE_COMMAND
RESTIC_BASE_COMMAND="restic --repo ${RESTIC_REPO}"

# Execute action
case "$ACTION" in
    snapshots)
        banner "Listing repository snapshots..."
        ${RESTIC_BASE_COMMAND} snapshots
        ;;
    backup)
        if [ -z "$BACKUP_SOURCE_TYPE" ]; then # Only source-type is mandatory now
            error_message "--source-type is required for backup action."
        fi
        perform_backup
        ;;
    check)
        banner "Checking repository..."
        ${RESTIC_BASE_COMMAND} check --read-data
        ;;
    stats)
        banner "Showing repository statistics (raw data mode)..."
        ${RESTIC_BASE_COMMAND} stats --mode raw-data
        ;;
    stats.latest)
        banner "Showing statistics for the latest snapshot..."
        ${RESTIC_BASE_COMMAND} stats latest --mode restore-size
        ;;
    cache.cleanup)
        banner "Cleaning up cache..."
        ${RESTIC_BASE_COMMAND} cache --cleanup
        ;;
    forget)
        banner "Forgetting and pruning old snapshots..."
        ${RESTIC_BASE_COMMAND} forget --keep-last ${RESTIC_REPO_KEEP_LAST} --keep-daily ${RESTIC_REPO_KEEP_DAILY} --keep-weekly ${RESTIC_REPO_KEEP_WEEKLY} --keep-monthly ${RESTIC_REPO_KEEP_MONTHLY} --keep-yearly ${RESTIC_REPO_KEEP_YEARLY} --prune
        ;;
    init)
        banner "Initializing repository..."
        ${RESTIC_BASE_COMMAND} init
        ;;
    unlock)
        banner "Unlocking repository..."
        ${RESTIC_BASE_COMMAND} unlock
        ;;
    restore)
        if [ -z "$SNAPSHOT_ID" ] || [ -z "$TARGET_DIR" ]; then
            error_message "--snapshot-id and --target-dir are required for restore action."
        fi
        banner "Restoring snapshot ${SNAPSHOT_ID} to ${TARGET_DIR}..."
        ${RESTIC_BASE_COMMAND} restore "${SNAPSHOT_ID}" --target "${TARGET_DIR}"
        ;;
    restore.latest)
        if [ -z "$TARGET_DIR" ]; then
            error_message "--target-dir is required for restore.latest action."
        fi
        banner "Restoring latest snapshot to ${TARGET_DIR}..."
        ${RESTIC_BASE_COMMAND} restore latest --target "${TARGET_DIR}"
        ;;
    ls)
        if [ -z "$SNAPSHOT_ID" ]; then
            error_message "--snapshot-id is required for ls action."
        fi
        banner "Listing files in snapshot ${SNAPSHOT_ID}..."
        ${RESTIC_BASE_COMMAND} ls "${SNAPSHOT_ID}"
        ;;
    find)
        if [ -z "$PATTERN" ]; then
            error_message "--pattern is required for find action."
        fi
        banner "Finding files matching pattern ${PATTERN}..."
        ${RESTIC_BASE_COMMAND} find "${PATTERN}"
        ;;
    mount)
        if [ -z "$MOUNT_DIR" ]; then
            error_message "--mount-dir is required for mount action."
        fi
        banner "Mounting repository to ${MOUNT_DIR}..."
        echo "Note: This command requires FUSE to be installed on your system." # This echo remains as it's a specific note
        ${RESTIC_BASE_COMMAND} mount "${MOUNT_DIR}"
        ;;
    diff)
        if [ -z "$SNAPSHOT_ID1" ] || [ -z "$SNAPSHOT_ID2" ]; then
            error_message "--snapshot-id1 and --snapshot-id2 are required for diff action."
        fi
        banner "Showing diff between ${SNAPSHOT_ID1} and ${SNAPSHOT_ID2}..."
        ${RESTIC_BASE_COMMAND} diff "${SNAPSHOT_ID1}" "${SNAPSHOT_ID2}"
        ;;
    backup-flow)
        banner "Starting full backup cycle (8 steps)"

        echo "RESTIC_REPO: ${RESTIC_REPO}"
        echo "RESTIC_PASSWORD: *****"
        echo "BACKUP_SOURCE_TYPE: ${BACKUP_SOURCE_TYPE}"
        echo "BACKUP_SOURCE_VALUE: ${BACKUP_SOURCE_VALUE:-Not set}"
        echo "STDIN_FILENAME: ${STDIN_FILENAME:-Not set}"
        echo ""
        echo "Forget/Prune Policy:"
        echo "  Keep Last: ${RESTIC_REPO_KEEP_LAST}"
        echo "  Keep Daily: ${RESTIC_REPO_KEEP_DAILY}"
        echo "  Keep Weekly: ${RESTIC_REPO_KEEP_WEEKLY}"
        echo "  Keep Monthly: ${RESTIC_REPO_KEEP_MONTHLY}"
        echo "  Keep Yearly: ${RESTIC_REPO_KEEP_YEARLY}"

        # 1. Check repository for errors before backup
        banner "Step 1/8: Checking repository for errors before backup"
        ${RESTIC_BASE_COMMAND} check --read-data

        # 2. Perform backup
        banner "Step 2/8: Performing backup"
        if [ -z "$BACKUP_SOURCE_TYPE" ]; then
            error_message "--source-type is required for backup action within backup-flow."
        fi
        perform_backup

        # 3. Check repository for errors after backup
        banner "Step 3/8: Checking repository for errors after backup"
        ${RESTIC_BASE_COMMAND} check --read-data

        # 4. Forget/Prune old snapshots
        banner "Step 4/8: Forgetting and pruning old snapshots..."
        ${RESTIC_BASE_COMMAND} forget --keep-last ${RESTIC_REPO_KEEP_LAST} --keep-daily ${RESTIC_REPO_KEEP_DAILY} --keep-weekly ${RESTIC_REPO_KEEP_WEEKLY} --keep-monthly ${RESTIC_REPO_KEEP_MONTHLY} --keep-yearly ${RESTIC_REPO_KEEP_YEARLY} --prune

        # 5. Clear repository cache
        banner "Step 5/8: Clearing repository cache"
        ${RESTIC_BASE_COMMAND} cache --cleanup

        # 6. Check repository for errors after forget/prune and cache cleanup
        banner "Step 6/8: Checking repository for errors after forget/prune and cache cleanup"
        ${RESTIC_BASE_COMMAND} check --read-data

        # 7. List snapshots
        banner "Step 7/8: Listing repository snapshots"
        ${RESTIC_BASE_COMMAND} snapshots

        # 8. Show repository statistics
        banner "Step 8/8: Showing repository statistics (raw data mode)"
        ${RESTIC_BASE_COMMAND} stats --mode raw-data

        banner "Full backup cycle completed successfully"
        ;;
    *)
        error_message "Invalid action: $ACTION"
        ;;
esac
