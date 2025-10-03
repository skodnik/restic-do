# Restic DO Script

A Bash script wrapper for `restic` to simplify and automate common backup operations. This script provides a convenient way to manage your `restic` repositories with easy-to-use commands and a clear configuration file.

## Features

-   **Simplified Commands**: Short and intuitive commands for common `restic` actions.
-   **Configuration via `.env`**: All settings are managed in a single `.env` file.
-   **Automated Backup Flow**: A `backup-flow` action that runs a full backup cycle, including checks and pruning.
-   **Flexible Backup Sources**: Supports backing up both directories and data from `stdin` (e.g., database dumps).
-   **Colored Output**: Enhanced readability with colored and timestamped log messages.

## Prerequisites

-   [restic](https://restic.net/) must be installed and available in your system's `PATH`.
-   `bash` (Bourne-Again SHell).

## Installation

1.  Clone this repository or download the `restic-do.sh` script.
2.  Make the script executable:
    ```bash
    chmod +x restic-do.sh
    ```
3.  Create a `.env` file for your configuration. You can copy the existing `.env.distr` file if you have one, or create it from scratch based on the section below.

## Configuration

All configuration is done through the `.env` file. It's a good practice to create a `.env.example` file (with dummy values) in your repository to show what variables are needed.

### `.env` file variables

| Variable                  | Description                                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------------- |
| `RESTIC_REPO`             | The path to your restic repository. Can be a local path or a remote one (e.g., `s3:bucket-name/repo`).     |
| `RESTIC_PASSWORD`         | The password for your restic repository.                                                                |
| `RESTIC_REPO_KEEP_LAST`   | Number of latest snapshots to keep.                                                                     |
| `RESTIC_REPO_KEEP_DAILY`  | Number of daily snapshots to keep.                                                                      |
| `RESTIC_REPO_KEEP_WEEKLY` | Number of weekly snapshots to keep.                                                                     |
| `RESTIC_REPO_KEEP_MONTHLY`| Number of monthly snapshots to keep.                                                                    |
| `RESTIC_REPO_KEEP_YEARLY` | Number of yearly snapshots to keep.                                                                     |
| `BACKUP_SOURCE_VALUE`     | Default directory to back up. Can be overridden by the `--source-value` argument.                         |
| `BACKUP_SOURCE_TYPE`      | Default backup source type (`dir` or `stdin`). Can be overridden by the `--source-type` argument.         |

## Usage

The script is executed with the following structure:

```bash
./restic-do.sh --action <action> --env-file /path/to/.env [options]
```

### Global Options

-   `--env-file <path>`: Path to the `.env` file. Defaults to `./.env` in the script's directory.
-   `--help`: Display the help message.

## Making the Script Globally Accessible

To use the `restic-do.sh` script from any directory on your system, you can move it to a directory within your system's `PATH`.

1.  **Move the script**

    Choose a directory from your `PATH` (like `/usr/local/bin`) and move the script there. You can rename it for easier typing.

    ```bash
    sudo mv /path/to/your/restic-do.sh /usr/local/bin/restic-do
    ```

2.  **Make it executable**

    Ensure the script has execution permissions.

    ```bash
    sudo chmod +x /usr/local/bin/restic-do
    ```

3.  **Usage**

    Now you can call the script from anywhere using `restic-do`.

    **Important:** Since the script is no longer in the same directory as your configuration file, the default mechanism for finding the `.env` file will not work. You **must** always provide the absolute path to your `.env` file using the `--env-file` option.

    ```bash
    # Example: running a backup from any directory
    restic-do --action backup --env-file /path/to/your/config/.env --source-value /path/to/your/data
    ```

## Actions

Here are the available actions:

-   `init`: Initializes a new `restic` repository.
-   `unlock`: Unlocks the repository if it's locked.
-   `snapshots`: Lists all snapshots in the repository.
-   `backup`: Performs a backup.
    -   `--source-type <dir|stdin>`: The type of source.
    -   `--source-value <path>`: The path to the directory to back up (for `dir` type).
    -   `--stdin-filename <name>`: The filename for the backup when using `stdin`.
-   `backup-flow`: Performs a full backup cycle: `check` -> `backup` -> `check` -> `forget` -> `cache.cleanup` -> `check` -> `snapshots` -> `stats`.
-   `check`: Checks the repository for errors.
-   `stats`: Shows repository statistics.
-   `stats.latest`: Shows statistics for the latest snapshot.
-   `cache.cleanup`: Cleans up the local cache.
-   `forget`: Forgets and prunes old snapshots according to the policy in `.env`.
-   `restore`: Restores a snapshot.
    -   `--snapshot-id <id>`: The ID of the snapshot to restore.
    -   `--target-dir <path>`: The directory where to restore the snapshot.
-   `restore.latest`: Restores the latest snapshot.
    -   `--target-dir <path>`: The directory where to restore the snapshot.
-   `ls`: Lists files in a snapshot.
    -   `--snapshot-id <id>`: The ID of the snapshot.
-   `find`: Finds files in all snapshots.
    -   `--pattern <pattern>`: The pattern to search for.
-   `mount`: Mounts the repository using FUSE.
    -   `--mount-dir <path>`: The directory where to mount the repository.
-   `diff`: Shows the difference between two snapshots.
    -   `--snapshot-id1 <id>`: The first snapshot ID.
    -   `--snapshot-id2 <id>`: The second snapshot ID.

## Examples

**List all snapshots:**
```bash
./restic-do.sh --action snapshots --env-file ./repo-test/.env
```

**Backup a directory:**
```bash
./restic-do.sh --action backup --env-file ./configs/.env --source-type dir --source-value /path/to/data
```

**Backup a PostgreSQL database dump:**
```bash
pg_dump my_db | ./restic-do.sh --action backup --env-file ./configs/.env --source-type stdin --stdin-filename my_db.sql
```

**Restore the latest snapshot:**
```bash
./restic-do.sh --action restore.latest --env-file ./configs/.env --target-dir /tmp/restore
```

**Run the full backup cycle:**
```bash
./restic-do.sh --action backup-flow --env-file ./configs/.env --source-value /path/to/data
```

## Disclaimer

**This script is provided "as is", without warranty of any kind, express or implied.** The author assumes no responsibility for any data loss or other damages that may occur as a result of using this script.

**You use this script at your own risk.** It is highly recommended to test the script and your backup/restore process thoroughly in a non-production environment before relying on it for critical data.

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
