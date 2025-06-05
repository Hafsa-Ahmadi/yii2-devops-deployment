#!/bin/bash

# Yii2 Application Rollback Script
# This script handles rolling back to a previous deployment version

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
LOG_FILE="${PROJECT_ROOT}/logs/rollback.log"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.prod.yml"
SERVICE_NAME="yii2-app"
NGINX_SERVICE="nginx"
DB_SERVICE="mysql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    case $level in
        "ERROR")
            echo -e "${RED}[$level] $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$level] $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[$level] $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}[$level] $message${NC}"
            ;;
    esac
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rollback Yii2 application to a previous version

OPTIONS:
    -v, --version VERSION    Rollback to specific version/tag (required)
    -t, --type TYPE         Rollback type: app|db|full (default: app)
    -f, --force             Force rollback without confirmation
    -s, --skip-health       Skip health checks after rollback
    -h, --help              Show this help message

EXAMPLES:
    $0 -v v1.2.3                    # Rollback application to version v1.2.3
    $0 -v v1.2.3 -t full           # Full rollback (app + database)
    $0 -v v1.2.3 -f                # Force rollback without confirmation
    $0 -v latest-stable -t db       # Rollback only database

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        log "ERROR" "Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose > /dev/null 2>&1; then
        log "ERROR" "docker-compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        log "ERROR" "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    # Check if compose file exists
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        log "ERROR" "Docker compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check passed"
}

# Function to validate version exists
validate_version() {
    local version=$1
    local backup_path="${BACKUP_DIR}/${version}"
    
    if [ ! -d "$backup_path" ]; then
        log "ERROR" "Backup for version '$version' not found in $backup_path"
        log "INFO" "Available versions:"
        ls -la "$BACKUP_DIR" | grep "^d" | awk '{print $9}' | grep -v "^\.$\|^\.\.$" || log "WARN" "No backups found"
        exit 1
    fi
    
    log "INFO" "Version '$version' backup found at: $backup_path"
}

# Function to create current state backup before rollback
create_rollback_backup() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local rollback_backup_dir="${BACKUP_DIR}/pre_rollback_${timestamp}"
    
    log "INFO" "Creating pre-rollback backup..."
    mkdir -p "$rollback_backup_dir"
    
    # Backup current application files
    if [ -d "${PROJECT_ROOT}/yii2-app" ]; then
        cp -r "${PROJECT_ROOT}/yii2-app" "${rollback_backup_dir}/"
        log "INFO" "Application files backed up"
    fi
    
    # Backup database if running
    if docker-compose -f "$DOCKER_COMPOSE_FILE" ps "$DB_SERVICE" | grep -q "Up"; then
        log "INFO" "Creating database backup..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_SERVICE" \
            mysqldump -u root -p"${MYSQL_ROOT_PASSWORD:-root}" --all-databases \
            > "${rollback_backup_dir}/database_backup.sql" 2>/dev/null || \
            log "WARN" "Database backup failed or database not accessible"
    fi
    
    log "SUCCESS" "Pre-rollback backup created at: $rollback_backup_dir"
}

# Function to stop services
stop_services() {
    log "INFO" "Stopping services..."
    
    cd "$PROJECT_ROOT"
    
    # Stop services gracefully
    docker-compose -f "$DOCKER_COMPOSE_FILE" stop "$SERVICE_NAME" "$NGINX_SERVICE" || {
        log "WARN" "Graceful stop failed, forcing stop..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" kill "$SERVICE_NAME" "$NGINX_SERVICE"
    }
    
    log "SUCCESS" "Services stopped"
}

# Function to rollback application
rollback_application() {
    local version=$1
    local backup_path="${BACKUP_DIR}/${version}"
    
    log "INFO" "Rolling back application to version: $version"
    
    # Remove current application
    if [ -d "${PROJECT_ROOT}/yii2-app" ]; then
        rm -rf "${PROJECT_ROOT}/yii2-app"
        log "INFO" "Current application removed"
    fi
    
    # Restore application from backup
    if [ -d "${backup_path}/yii2-app" ]; then
        cp -r "${backup_path}/yii2-app" "${PROJECT_ROOT}/"
        log "SUCCESS" "Application files restored from backup"
    else
        log "ERROR" "Application backup not found in ${backup_path}/yii2-app"
        exit 1
    fi
    
    # Restore configuration if exists
    if [ -f "${backup_path}/docker-compose.prod.yml" ]; then
        cp "${backup_path}/docker-compose.prod.yml" "$PROJECT_ROOT/"
        log "INFO" "Docker compose configuration restored"
    fi
}

# Function to rollback database
rollback_database() {
    local version=$1
    local backup_path="${BACKUP_DIR}/${version}"
    local db_backup="${backup_path}/database_backup.sql"
    
    if [ "$ROLLBACK_TYPE" != "db" ] && [ "$ROLLBACK_TYPE" != "full" ]; then
        return 0
    fi
    
    log "INFO" "Rolling back database to version: $version"
    
    if [ ! -f "$db_backup" ]; then
        log "WARN" "Database backup not found: $db_backup"
        return 0
    fi
    
    # Start database service if not running
    if ! docker-compose -f "$DOCKER_COMPOSE_FILE" ps "$DB_SERVICE" | grep -q "Up"; then
        log "INFO" "Starting database service..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d "$DB_SERVICE"
        sleep 10
    fi
    
    # Restore database
    log "INFO" "Restoring database from backup..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_SERVICE" \
        mysql -u root -p"${MYSQL_ROOT_PASSWORD:-root}" < "$db_backup" || {
        log "ERROR" "Database restore failed"
        exit 1
    }
    
    log "SUCCESS" "Database restored successfully"
}

# Function to start services
start_services() {
    log "INFO" "Starting services..."
    
    cd "$PROJECT_ROOT"
    
    # Start services
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d "$SERVICE_NAME" "$NGINX_SERVICE"
    
    # Wait for services to be ready
    log "INFO" "Waiting for services to start..."
    sleep 15
    
    log "SUCCESS" "Services started"
}

# Function to perform health checks
health_check() {
    if [ "$SKIP_HEALTH_CHECK" = true ]; then
        log "INFO" "Skipping health checks as requested"
        return 0
    fi
    
    log "INFO" "Performing health checks..."
    
    # Check if containers are running
    local app_status=$(docker-compose -f "$DOCKER_COMPOSE_FILE" ps -q "$SERVICE_NAME" | xargs docker inspect -f '{{.State.Status}}' 2>/dev/null || echo "not found")
    local nginx_status=$(docker-compose -f "$DOCKER_COMPOSE_FILE" ps -q "$NGINX_SERVICE" | xargs docker inspect -f '{{.State.Status}}' 2>/dev/null || echo "not found")
    
    if [ "$app_status" != "running" ]; then
        log "ERROR" "Application container is not running (status: $app_status)"
        return 1
    fi
    
    if [ "$nginx_status" != "running" ]; then
        log "ERROR" "Nginx container is not running (status: $nginx_status)"
        return 1
    fi
    
    # Test HTTP response
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s -o /dev/null http://localhost:80/health 2>/dev/null; then
            log "SUCCESS" "Health check passed - Application is responding"
            return 0
        fi
        
        log "INFO" "Health check attempt $attempt/$max_attempts failed, retrying in 5 seconds..."
        sleep 5
        ((attempt++))
    done
    
    log "ERROR" "Health check failed after $max_attempts attempts"
    return 1
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "INFO" "Cleaning up old backups (keeping last 5 pre-rollback backups)..."
    
    # Remove old pre-rollback backups (keep last 5)
    ls -dt "${BACKUP_DIR}"/pre_rollback_* 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true
    
    log "INFO" "Backup cleanup completed"
}

# Function to display rollback summary
rollback_summary() {
    local version=$1
    
    log "SUCCESS" "=== ROLLBACK COMPLETED ==="
    log "INFO" "Rolled back to version: $version"
    log "INFO" "Rollback type: $ROLLBACK_TYPE"
    log "INFO" "Timestamp: $(date)"
    log "INFO" "Log file: $LOG_FILE"
    
    if [ "$ROLLBACK_TYPE" = "full" ] || [ "$ROLLBACK_TYPE" = "app" ]; then
        log "INFO" "Application rollback: ✓"
    fi
    
    if [ "$ROLLBACK_TYPE" = "full" ] || [ "$ROLLBACK_TYPE" = "db" ]; then
        log "INFO" "Database rollback: ✓"
    fi
    
    log "INFO" "=========================="
}

# Main rollback function
main() {
    # Default values
    VERSION=""
    ROLLBACK_TYPE="app"
    FORCE=false
    SKIP_HEALTH_CHECK=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -t|--type)
                ROLLBACK_TYPE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -s|--skip-health)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$VERSION" ]; then
        log "ERROR" "Version is required. Use -v or --version to specify."
        usage
        exit 1
    fi
    
    # Validate rollback type
    if [[ ! "$ROLLBACK_TYPE" =~ ^(app|db|full)$ ]]; then
        log "ERROR" "Invalid rollback type. Must be: app, db, or full"
        exit 1
    fi
    
    log "INFO" "Starting rollback process..."
    log "INFO" "Version: $VERSION"
    log "INFO" "Type: $ROLLBACK_TYPE"
    log "INFO" "Force: $FORCE"
    
    # Confirmation prompt
    if [ "$FORCE" != true ]; then
        echo -e "${YELLOW}Are you sure you want to rollback to version '$VERSION'? (y/N)${NC}"
        read -r confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log "INFO" "Rollback cancelled by user"
            exit 0
        fi
    fi
    
    # Execute rollback steps
    check_prerequisites
    validate_version "$VERSION"
    create_rollback_backup
    stop_services
    
    if [ "$ROLLBACK_TYPE" = "app" ] || [ "$ROLLBACK_TYPE" = "full" ]; then
        rollback_application "$VERSION"
    fi
    
    rollback_database "$VERSION"
    start_services
    
    if ! health_check; then
        log "ERROR" "Health checks failed after rollback"
        log "WARN" "You may need to investigate the issue manually"
        exit 1
    fi
    
    cleanup_old_backups
    rollback_summary "$VERSION"
    
    log "SUCCESS" "Rollback completed successfully!"
}

# Error handling
trap 'log "ERROR" "Rollback script failed at line $LINENO. Check logs for details."' ERR

# Run main function
main "$@"