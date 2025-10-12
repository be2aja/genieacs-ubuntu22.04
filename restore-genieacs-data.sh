#!/bin/bash

# =============================================
# GenieACS Database Restore Script
# Docker Only Version
# =============================================

set -e

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

log_info "Starting GenieACS database restore (Docker only)..."

# =============================================
# STEP 1: Check MongoDB Container
# =============================================
log_info "Step 1: Checking MongoDB container..."
if ! docker ps | grep -q mongodb; then
    log_error "MongoDB container is not running"
    exit 1
fi

# Test MongoDB connection
if docker exec mongodb mongo --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; then
    log_info "✅ MongoDB is running"
else
    log_error "❌ MongoDB connection failed"
    exit 1
fi

# =============================================
# STEP 2: Create Data Directory
# =============================================
log_info "Step 2: Preparing data directory..."
mkdir -p /root/db
cd /root/db

# =============================================
# STEP 3: Download Data Files
# =============================================
log_info "Step 3: Downloading data files..."

download_file() {
    local file=$1
    local url="https://github.com/beryindo/genieacs/raw/main/$file"
    log_info "Downloading: $file"
    if wget -q "$url"; then
        log_info "✅ Downloaded: $file"
        return 0
    else
        log_warn "❌ Failed to download: $file"
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

for file in "${files[@]}"; do
    download_file "$file"
done

# =============================================
# STEP 4: Copy Files to Container
# =============================================
log_info "Step 4: Copying files to MongoDB container..."
docker cp /root/db/. mongodb:/tmp/backup/

# Verify files copied
if docker exec mongodb ls /tmp/backup/ | grep -q ".bson"; then
    log_info "✅ Files successfully copied to container"
else
    log_error "❌ Failed to copy files to container"
    exit 1
fi

# =============================================
# STEP 5: Restore Database using Docker
# =============================================
log_info "Step 5: Restoring database from inside container..."
docker exec mongodb mongorestore --db genieacs --drop /tmp/backup/

log_info "✅ Database restore completed"

# =============================================
# STEP 6: Cleanup Temporary Files
# =============================================
log_info "Step 6: Cleaning up..."
docker exec mongodb rm -rf /tmp/backup

# =============================================
# STEP 7: Verify Restore
# =============================================
log_info "Step 7: Verifying restore..."
docker exec mongodb mongo genieacs --eval "db.getCollectionNames()"

log_info "✅ Database restore verification complete"

# =============================================
# STEP 8: Restart GenieACS Services
# =============================================
log_info "Step 8: Restarting GenieACS services..."
systemctl restart genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui

sleep 3

# =============================================
# FINAL: Status Check
# =============================================
log_info "=== Final Status ==="
log_info "🌐 GenieACS Web UI: http://$(hostname -I | awk '{print $1}'):3000"
log_info "📊 Database: genieacs (restored from backup)"
log_info "🐳 MongoDB: Running in Docker container"

echo ""
log_info "✅ Database restore completed successfully!"
log_info "You can now access GenieACS and login with the existing credentials"
