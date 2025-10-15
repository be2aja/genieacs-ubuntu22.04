#!/bin/bash

# =============================================
# GenieACS Database Restore Script
# Fixed Version - No set -e
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

# =============================================
# Detection Functions
# =============================================

detect_mongodb() {
    # Check if Docker is available and MongoDB container is running
    if command -v docker >/dev/null 2>&1; then
        # Check if MongoDB is running in Docker
        if docker ps --format 'table {{.Names}}' | grep -q -E '(mongodb|mongo)'; then
            CONTAINER_NAME=$(docker ps --format 'table {{.Names}}' | grep -E '(mongodb|mongo)' | head -1)
            echo "docker:$CONTAINER_NAME"
            return 0
        fi
        
        # Check if MongoDB container exists but not running
        if docker ps -a --format 'table {{.Names}}' | grep -q -E '(mongodb|mongo)'; then
            CONTAINER_NAME=$(docker ps -a --format 'table {{.Names}}' | grep -E '(mongodb|mongo)' | head -1)
            echo "docker_stopped:$CONTAINER_NAME"
            return 0
        fi
    fi
    
    # Check if native MongoDB is running
    if systemctl is-active --quiet mongod 2>/dev/null; then
        echo "native"
        return 0
    fi
    
    # Check if mongod process is running
    if pgrep mongod >/dev/null 2>&1; then
        echo "native"
        return 0
    fi
    
    # Check if MongoDB commands are available
    if command -v mongo >/dev/null 2>&1 && command -v mongorestore >/dev/null 2>&1; then
        echo "installed"
        return 0
    fi
    
    echo "none"
    return 1
}

test_mongodb_connection() {
    local type=$1
    local container_name=$2
    
    case $type in
        "docker")
            log_info "Testing Docker container: $container_name"
            if docker exec "$container_name" mongo --eval "db.adminCommand('ismaster')" --quiet >/dev/null 2>&1; then
                log_info "✅ MongoDB connection successful (Docker)"
                return 0
            else
                log_error "❌ MongoDB connection failed (Docker)"
                return 1
            fi
            ;;
        "native"|"installed")
            log_info "Testing native MongoDB connection..."
            if mongo --eval "db.adminCommand('ismaster')" --quiet >/dev/null 2>&1; then
                log_info "✅ MongoDB connection successful (Native)"
                return 0
            elif mongo --eval "db.version()" --quiet >/dev/null 2>&1; then
                log_info "✅ MongoDB connection successful (Native - alternative)"
                return 0
            else
                log_error "❌ MongoDB connection failed (Native)"
                return 1
            fi
            ;;
        *)
            log_error "Unknown MongoDB type: $type"
            return 1
            ;;
    esac
}

start_mongodb() {
    local type=$1
    local container_name=$2
    
    case $type in
        "docker_stopped")
            log_info "Starting Docker container: $container_name"
            if docker start "$container_name"; then
                sleep 5
                if docker ps | grep -q "$container_name"; then
                    log_info "✅ Docker container started successfully"
                    return 0
                fi
            fi
            return 1
            ;;
        "installed")
            log_info "Attempting to start MongoDB service..."
            
            # Try systemd first
            if systemctl start mongod 2>/dev/null; then
                sleep 3
                if systemctl is-active --quiet mongod; then
                    log_info "✅ MongoDB started successfully via systemd"
                    return 0
                fi
            fi
            
            log_error "❌ Failed to start MongoDB"
            return 1
            ;;
    esac
}

# =============================================
# Main Script
# =============================================

log_info "Starting GenieACS database restore..."

# =============================================
# STEP 1: Detect MongoDB Type
# =============================================
log_info "Step 1: Detecting MongoDB installation..."
MONGODB_DETECTION=$(detect_mongodb)
MONGODB_TYPE=$(echo "$MONGODB_DETECTION" | cut -d: -f1)
CONTAINER_NAME=$(echo "$MONGODB_DETECTION" | cut -d: -f2-)

log_info "Detection result - Type: $MONGODB_TYPE, Container: $CONTAINER_NAME"

case $MONGODB_TYPE in
    "docker")
        log_info "Using running Docker container: $CONTAINER_NAME"
        ;;
    "docker_stopped")
        log_info "Starting stopped Docker container: $CONTAINER_NAME"
        if ! start_mongodb "$MONGODB_TYPE" "$CONTAINER_NAME"; then
            log_error "Failed to start Docker container"
            exit 1
        fi
        MONGODB_TYPE="docker"
        ;;
    "native")
        log_info "Using native MongoDB installation"
        ;;
    "installed")
        log_info "MongoDB is installed but not running - attempting to start"
        if ! start_mongodb "$MONGODB_TYPE" "$CONTAINER_NAME"; then
            log_error "Failed to start MongoDB service"
            log_info "Please start MongoDB manually and run the script again"
            log_info "Command: sudo systemctl start mongod"
            exit 1
        fi
        MONGODB_TYPE="native"
        ;;
    "none")
        log_error "MongoDB is not installed. Please install MongoDB first."
        log_info "For Ubuntu/Debian: sudo apt-get install -y mongodb"
        log_info "For CentOS/RHEL: sudo yum install -y mongodb"
        log_info "Or use Docker: docker run -d --name mongodb -p 27017:27017 mongo:4.4"
        exit 1
        ;;
    *)
        log_error "Unknown MongoDB type: $MONGODB_TYPE"
        exit 1
        ;;
esac

# Test connection
if ! test_mongodb_connection "$MONGODB_TYPE" "$CONTAINER_NAME"; then
    log_error "❌ MongoDB connection test failed"
    log_info "Please ensure MongoDB is running and accessible"
    log_info "You can try: sudo systemctl start mongod"
    exit 1
fi

# =============================================
# STEP 2: Create Data Directory
# =============================================
log_info "Step 2: Preparing data directory..."
BACKUP_DIR="/root/genieacs_restore_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR" || {
    log_error "Failed to enter backup directory: $BACKUP_DIR"
    exit 1
}

# =============================================
# STEP 3: Download Data Files
# =============================================
log_info "Step 3: Downloading data files..."

download_file() {
    local file=$1
    local url="https://raw.githubusercontent.com/beryindo/genieacs/main/$file"
    log_info "Downloading: $file"
    
    # Try with wget first, then curl as fallback
    if command -v wget >/dev/null 2>&1; then
        if wget --timeout=30 --tries=3 -q "$url"; then
            log_info "✅ Downloaded: $file"
            return 0
        else
            log_warn "❌ wget failed for: $file"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if curl --connect-timeout 30 --retry 3 -s -o "$file" "$url"; then
            log_info "✅ Downloaded: $file"
            return 0
        else
            log_warn "❌ curl failed for: $file"
            return 1
        fi
    else
        log_error "Neither wget nor curl is available"
        return 1
    fi
}

files=(
    "config.bson"
    "config.metadata.json" 
    "presets.bson"
    "presets.metadata.json"
    "provisions.bson"
    "provisions.metadata.json"
    "virtualParameters.bson"
    "virtualParameters.metadata.json"
)

successful_downloads=0
failed_downloads=0

log_info "Starting download of ${#files[@]} files..."

for file in "${files[@]}"; do
    if download_file "$file"; then
        ((successful_downloads++))
    else
        ((failed_downloads++))
    fi
done

log_info "Download completed: $successful_downloads successful, $failed_downloads failed"

# Check if we have at least one BSON file
if ! ls *.bson >/dev/null 2>&1; then
    log_error "No BSON files downloaded. Cannot proceed with restore."
    log_info "Available files in $BACKUP_DIR:"
    ls -la "$BACKUP_DIR" 2>/dev/null || log_info "Directory is empty"
    exit 1
fi

# Check file sizes to ensure they're not empty
log_info "Checking downloaded files..."
for file in *.bson *.json; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        if [ "$size" -lt 10 ]; then
            log_warn "⚠️  File $file seems empty or too small ($size bytes)"
        else
            log_info "✅ $file: $size bytes"
        fi
    fi
done

# =============================================
# STEP 4: Restore Database
# =============================================
log_info "Step 4: Restoring database..."

case $MONGODB_TYPE in
    "docker")
        log_info "Using Docker method with container: $CONTAINER_NAME"
        # Copy files to container
        if ! docker cp "$BACKUP_DIR/." "$CONTAINER_NAME:/tmp/backup/"; then
            log_error "❌ Failed to copy files to container"
            exit 1
        fi
        
        # Verify files copied
        if docker exec "$CONTAINER_NAME" ls /tmp/backup/ | grep -q ".bson"; then
            log_info "✅ Files successfully copied to container"
        else
            log_error "❌ No BSON files found in container after copy"
            exit 1
        fi
        
        # Restore using mongorestore inside container
        log_info "Running mongorestore inside container..."
        if ! docker exec "$CONTAINER_NAME" mongorestore --db genieacs --drop /tmp/backup/; then
            log_error "❌ mongorestore failed in container"
            exit 1
        fi
        
        # Cleanup inside container
        docker exec "$CONTAINER_NAME" rm -rf /tmp/backup
        ;;
    
    "native")
        log_info "Using native MongoDB method..."
        # Restore directly using local mongorestore
        if command -v mongorestore >/dev/null 2>&1; then
            log_info "Executing: mongorestore --db genieacs --drop $BACKUP_DIR/"
            if ! mongorestore --db genieacs --drop "$BACKUP_DIR/"; then
                log_error "❌ mongorestore failed"
                exit 1
            fi
        else
            log_error "mongorestore command not found"
            exit 1
        fi
        ;;
esac

log_info "✅ Database restore completed"

# =============================================
# STEP 5: Verify Restore
# =============================================
log_info "Step 5: Verifying restore..."

case $MONGODB_TYPE in
    "docker")
        log_info "Collections in database:"
        docker exec "$CONTAINER_NAME" mongo genieacs --eval "db.getCollectionNames()" --quiet
        ;;
    "native")
        log_info "Collections in database:"
        mongo genieacs --eval "db.getCollectionNames()" --quiet
        ;;
esac

# =============================================
# STEP 6: Restart GenieACS Services
# =============================================
log_info "Step 6: Restarting GenieACS services..."

# Check which GenieACS services are available
services=("genieacs-cwmp" "genieacs-nbi" "genieacs-fs" "genieacs-ui")

for service in "${services[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        log_info "Restarting $service..."
        if systemctl restart "$service" 2>/dev/null; then
            log_info "✅ $service restarted"
        else
            log_warn "❌ Could not restart $service"
        fi
    else
        log_info "ℹ️  $service is not enabled, skipping"
    fi
done

sleep 3

# =============================================
# STEP 7: Cleanup and Final Status
# =============================================
log_info "Step 7: Cleaning up..."
rm -rf "$BACKUP_DIR"

# =============================================
# FINAL: Status Check
# =============================================
log_info "=== Final Status ==="
log_info "📦 MongoDB Type: $MONGODB_TYPE"
if [ "$MONGODB_TYPE" = "docker" ]; then
    log_info "🐳 Container: $CONTAINER_NAME"
fi
log_info "🌐 GenieACS Web UI: http://$(hostname -I | awk '{print $1}'):3000"
log_info "📊 Database: genieacs (restored from backup)"

# Check service status
log_info "=== Service Status ==="
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_info "✅ $service: RUNNING"
    else
        log_warn "❌ $service: NOT RUNNING"
    fi
done

echo ""
log_info "✅ Database restore completed successfully!"
log_info "You can now access GenieACS and login with the existing credentials"
