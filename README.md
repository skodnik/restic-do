# Restic DO Script

A Bash wrapper for [restic](https://restic.net/) that simplifies and automates backup operations with enterprise-level features including comprehensive logging, error handling, and Slack integration.

## 🚀 Features

- **🎯 Simplified Commands**: Intuitive commands for all restic operations
- **⚙️ Environment Configuration**: Centralized configuration via `.env` files
- **🔄 Automated Backup Flow**: Complete backup cycle with integrity checks and pruning
- **📊 Flexible Source Types**: Support for directory and stdin backups (databases, etc.)
- **🎨 Enhanced Output**: Colored logs with timestamps and formatting
- **📱 Slack Integration**: Real-time notifications with detailed metadata
- **📝 File Logging**: Optional persistent logging to files
- **🛡️ Robust Error Handling**: Comprehensive validation and graceful error recovery
- **🔍 Dependency Validation**: Automatic system dependency checking
- **⚡ Signal Handling**: Graceful cleanup on interruption
- **📋 Parameter Validation**: Extensive input validation and sanitization

## 📋 Prerequisites

- **[restic](https://restic.net/)** - Must be installed and available in your system's PATH
- **bash** - Version 4.0 or higher recommended
- **curl** - Required for Slack notifications (optional)

## 🔧 Installation

1. **Clone or download** the repository:
   ```bash
   git clone <repository-url>
   cd restic-do
   ```

2. **Make executable**:
   ```bash
   chmod +x restic-do.sh
   ```

3. **Create configuration**:
   ```bash
   cp .env.distr .env
   # Edit .env with your settings
   ```

## ⚙️ Configuration

All configuration is managed through `.env` files. **Never commit real credentials to version control!**

### Required Variables

| Variable | Description |
|----------|-------------|
| `RESTIC_REPO` | Repository path (local or remote, e.g., `/backup` or `s3:bucket/repo`) |
| `RESTIC_PASSWORD` | Repository encryption password |

### Retention Policy

| Variable | Description | Default |
|----------|-------------|---------|
| `RESTIC_REPO_KEEP_LAST` | Number of latest snapshots to keep | 20 |
| `RESTIC_REPO_KEEP_DAILY` | Number of daily snapshots to keep | 14 |
| `RESTIC_REPO_KEEP_WEEKLY` | Number of weekly snapshots to keep | 8 |
| `RESTIC_REPO_KEEP_MONTHLY` | Number of monthly snapshots to keep | 12 |
| `RESTIC_REPO_KEEP_YEARLY` | Number of yearly snapshots to keep | 3 |

### Backup Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `BACKUP_SOURCE_TYPE` | Default source type (`dir` or `stdin`) | `dir` |
| `BACKUP_SOURCE_VALUE` | Default directory to backup | |
| `BACKUP_EXCLUDE` | Comma-separated exclude patterns | |

### Slack Integration

| Variable | Description | Default |
|----------|-------------|---------|
| `SLACK_SEND_NOTIFICATIONS_ON_SUCCESS` | Enable Slack notifications for successful operations (`true`/`false`) | `false` |
| `SLACK_SEND_NOTIFICATIONS_ON_ERROR` | Enable Slack notifications for errors and failures (`true`/`false`) | `false` |
| `SLACK_HOOK` | Slack incoming webhook URL | |
| `SLACK_CHANNEL` | Target Slack channel | |
| `SLACK_USERNAME` | Bot username | `Restic Backup` |
| `SLACK_LOG_EMOJI_DEFAULT` | Default emoji | `:bell:` |

### S3 Configuration

| Variable | Description |
|----------|-------------|
| `S3_URL` | S3 endpoint URL |
| `S3_BUCKET_NAME` | S3 bucket name |
| `AWS_ACCESS_KEY_ID` | S3 access key |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key |
| `AWS_DEFAULT_REGION` | S3 region |

> **Note**: Construct `RESTIC_REPO` from S3 variables: `RESTIC_REPO="s3:${S3_URL}/${S3_BUCKET_NAME}"`

## 🚀 Usage

### Basic Syntax

```bash
./restic-do.sh --action <action> [options]
```

### Global Options

```bash
--env-file <path>     # Configuration file path (default: ./.env)
--log-file <path>     # Enable file logging
--version             # Show version information
--help                # Display help message
```

## 📚 Actions

### Repository Management

```bash
# Initialize new repository
./restic-do.sh --action init --env-file ./config/.env

# Check repository integrity
./restic-do.sh --action check --env-file ./config/.env

# Unlock locked repository
./restic-do.sh --action unlock --env-file ./config/.env

# Clean cache
./restic-do.sh --action cache.cleanup --env-file ./config/.env
```

### Backup Operations

```bash
# Backup directory
./restic-do.sh --action backup \
  --env-file ./config/.env \
  --source-type dir \
  --source-value /home/user/documents \
  --exclude "*.tmp" \
  --exclude "cache/"

# Backup database from stdin
pg_dump mydb | ./restic-do.sh --action backup \
  --env-file ./config/.env \
  --source-type stdin \
  --stdin-filename "mydb_$(date +%Y%m%d).sql"

# Complete backup flow (recommended)
./restic-do.sh --action backup-flow \
  --env-file ./config/.env \
  --source-value /data \
  --log-file ./backup.log
```

### Snapshot Management

```bash
# List snapshots
./restic-do.sh --action snapshots --env-file ./config/.env

# Forget old snapshots
./restic-do.sh --action forget --env-file ./config/.env

# Repository statistics
./restic-do.sh --action stats --env-file ./config/.env

# Latest snapshot statistics
./restic-do.sh --action stats.latest --env-file ./config/.env
```

### Restore Operations

```bash
# Restore specific snapshot
./restic-do.sh --action restore \
  --env-file ./config/.env \
  --snapshot-id abc123def \
  --target-dir /tmp/restore

# Restore latest snapshot
./restic-do.sh --action restore.latest \
  --env-file ./config/.env \
  --target-dir /tmp/restore
```

### Browse and Search

```bash
# List files in snapshot
./restic-do.sh --action ls \
  --env-file ./config/.env \
  --snapshot-id abc123def

# Find files across snapshots
./restic-do.sh --action find \
  --env-file ./config/.env \
  --pattern "*.pdf"

# Mount repository (requires FUSE)
./restic-do.sh --action mount \
  --env-file ./config/.env \
  --mount-dir /mnt/backup

# Compare snapshots
./restic-do.sh --action diff \
  --env-file ./config/.env \
  --snapshot-id1 abc123def \
  --snapshot-id2 def456ghi
```

## 🔄 Backup Flow

The `backup-flow` action performs a comprehensive 8-step backup process:

1. **Pre-backup integrity check** - Verify repository health
2. **Perform backup** - Execute the actual backup
3. **Post-backup integrity check** - Verify backup success
4. **Forget old snapshots** - Apply retention policy
5. **Cache cleanup** - Remove unused cache data
6. **Final integrity check** - Ensure repository consistency
7. **List snapshots** - Show current repository state
8. **Repository statistics** - Display storage usage

## 🌍 Global Installation

To use the script from any directory:

```bash
# Move to system PATH
sudo mv restic-do.sh /usr/local/bin/restic-do
sudo chmod +x /usr/local/bin/restic-do

# Use with absolute paths to config files
restic-do --action backup-flow --env-file /path/to/your/.env --source-value /data
```

## 🔐 Security Best Practices

1. **Never commit credentials** to version control
2. **Use appropriate file permissions** for `.env` files:
   ```bash
   chmod 600 .env
   ```
3. **Regularly rotate** backup passwords and access keys
4. **Test restore procedures** regularly
5. **Monitor backup notifications** for failures
6. **Use strong, unique passwords** for repositories

## 📊 Example Configurations

### Local Backup

```bash
# .env for local backup
RESTIC_REPO="/backup/restic-repo"
RESTIC_PASSWORD="your-secure-password"
BACKUP_SOURCE_VALUE="/home/user"
BACKUP_EXCLUDE="*.log,*.tmp,cache/,node_modules/"
SLACK_SEND_NOTIFICATIONS_ON_SUCCESS="true"
SLACK_SEND_NOTIFICATIONS_ON_ERROR="true"
SLACK_HOOK="https://hooks.slack.com/services/..."
SLACK_CHANNEL="#backup-alerts"
```

### S3 Backup

```bash
# .env for S3 backup
RESTIC_REPO="s3:s3.amazonaws.com/my-backup-bucket"
RESTIC_PASSWORD="your-secure-password"
AWS_ACCESS_KEY_ID="AKIA..."
AWS_SECRET_ACCESS_KEY="..."
AWS_DEFAULT_REGION="us-west-2"
BACKUP_SOURCE_VALUE="/data"
SLACK_SEND_NOTIFICATIONS_ON_SUCCESS="true"
SLACK_SEND_NOTIFICATIONS_ON_ERROR="true"
```

### Database Backup Script

```bash
#!/bin/bash
# Daily database backup script

# Set environment
export RESTIC_CONFIG="/etc/restic/.env"
export LOG_DIR="/var/log/backup"

# Create log directory
mkdir -p "$LOG_DIR"

# Backup PostgreSQL
pg_dump -h localhost -U postgres mydb | \
  /usr/local/bin/restic-do \
    --action backup \
    --env-file "$RESTIC_CONFIG" \
    --source-type stdin \
    --stdin-filename "mydb_$(date +%Y%m%d_%H%M%S).sql" \
    --log-file "$LOG_DIR/postgres-backup.log"

# Backup MySQL
mysqldump -u root -p mydb | \
  /usr/local/bin/restic-do \
    --action backup \
    --env-file "$RESTIC_CONFIG" \
    --source-type stdin \
    --stdin-filename "mysql_$(date +%Y%m%d_%H%M%S).sql" \
    --log-file "$LOG_DIR/mysql-backup.log"
```

## 🐛 Troubleshooting

### Common Issues

1. **Permission denied**: Ensure script is executable and paths are accessible
2. **Environment file not found**: Check file path and permissions
3. **Restic not found**: Install restic and ensure it's in PATH
4. **Repository locked**: Use `--action unlock`
5. **S3 authentication**: Verify AWS credentials and permissions

### Debug Mode

For detailed troubleshooting, you can modify the script to enable bash debugging:

```bash
# Add to top of script temporarily
set -x  # Enable debug output
```

### Log Analysis

```bash
# Monitor real-time logs
tail -f /path/to/backup.log

# Search for errors
grep -i error /path/to/backup.log

# Check Slack notifications
grep "Slack notification" /path/to/backup.log
```

## 🔄 Version History

- **v1.1.1** - Small fixes
- **v1.1.0** - Enhanced Slack notifications: separate controls for success and error notifications
- **v1.0.3** - Small fixes
- **v1.0.2** - Small fixes
- **v1.0.1** - Added support for reading version and help without arguments
- **v1.0.0** - Complete rewrite with features
- **v0.0.2** - Added Slack notifications
- **v0.0.1** - Initial release

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow the existing code style
4. Add tests for new features
5. Submit a pull request

## ⚠️ Disclaimer

**This software is provided "as is" without warranty of any kind.** Always test your backup and restore procedures in a non-production environment before relying on them for critical data.

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**💡 Pro Tip**: Set up automated daily backups using cron with the `backup-flow` action for a complete, hands-off backup solution!
