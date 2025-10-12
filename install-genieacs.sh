#!/bin/bash

# =============================================
# GenieACS Installer for Ubuntu 22.04
# Official Method with Systemd Services
# =============================================

set -e

# Colors for output
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

log_info "Starting GenieACS installation (Official Method)..."

# =============================================
# STEP 1: System Update & Dependencies
# =============================================
log_info "Step 1: Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install -y curl wget gnupg software-properties-common

# =============================================
# STEP 2: Install Node.js 20.x
# =============================================
log_info "Step 2: Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

log_info "Node.js version: $(node --version)"
log_info "NPM version: $(npm --version)"

# =============================================
# STEP 3: Install Docker dan MongoDB
# =============================================
log_info "Step 3: Installing Docker and MongoDB..."

# Install Docker
apt install -y docker.io
systemctl enable docker
systemctl start docker

# Stop and remove existing MongoDB container if exists
log_info "Stopping existing MongoDB containers..."
docker stop mongodb 2>/dev/null || true
docker rm mongodb 2>/dev/null || true

# Remove existing volume if any
docker volume rm mongodb_data 2>/dev/null || true

# Run MongoDB 4.4 (lebih stabil untuk QEMU)
log_info "Starting MongoDB 4.4 container..."
docker run -d \
    --name mongodb \
    --restart unless-stopped \
    -p 27017:27017 \
    -v mongodb_data:/data/db \
    mongo:4.4 --quiet --logpath /dev/null

# Wait longer for MongoDB to start
log_info "Waiting for MongoDB to start (30 seconds)..."
for i in {1..30}; do
    if docker ps | grep -q mongodb && docker exec mongodb mongo --eval "db.adminCommand('ismaster')" 2>/dev/null | grep -q "ismaster"; then
        log_info "✅ MongoDB is running successfully"
        break
    fi
    echo -n "."
    sleep 1
    if [ $i -eq 30 ]; then
        log_error "❌ MongoDB failed to start within 30 seconds"
        log_info "Checking container logs..."
        docker logs mongodb || true
        log_warn "Trying to continue anyway..."
    fi
done

# =============================================
# STEP 4: Install GenieACS
# =============================================
log_info "Step 4: Installing GenieACS 1.2.13..."
npm install -g genieacs@1.2.13

# =============================================
# STEP 5: Create System User and Directories
# =============================================
log_info "Step 5: Creating system user and directories..."
useradd --system --no-create-home --user-group genieacs 2>/dev/null || log_info "User genieacs already exists"

mkdir -p /opt/genieacs/ext
mkdir -p /var/log/genieacs
chown genieacs:genieacs /opt/genieacs/ext
chown genieacs:genieacs /var/log/genieacs

# =============================================
# STEP 6: Create Environment File
# =============================================
log_info "Step 6: Creating environment configuration..."

# Generate JWT secret first
JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(64).toString('hex'))")

cat > /opt/genieacs/genieacs.env << EOF
GENIEACS_CWMP_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-cwmp-access.log
GENIEACS_NBI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-nbi-access.log
GENIEACS_FS_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-fs-access.log
GENIEACS_UI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-ui-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
NODE_OPTIONS=--enable-source-maps
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_UI_JWT_SECRET=$JWT_SECRET
GENIEACS_MONGODB_CONNECTION_URL=mongodb://localhost:27017/genieacs
EOF

chown genieacs:genieacs /opt/genieacs/genieacs.env
chmod 600 /opt/genieacs/genieacs.env

# =============================================
# STEP 7: Create Systemd Services
# =============================================
log_info "Step 7: Creating systemd services..."

# Service: genieacs-cwmp
cat > /etc/systemd/system/genieacs-cwmp.service << 'EOF'
[Unit]
Description=GenieACS CWMP
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-cwmp
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Service: genieacs-nbi
cat > /etc/systemd/system/genieacs-nbi.service << 'EOF'
[Unit]
Description=GenieACS NBI
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-nbi
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Service: genieacs-fs
cat > /etc/systemd/system/genieacs-fs.service << 'EOF'
[Unit]
Description=GenieACS FS
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-fs
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Service: genieacs-ui
cat > /etc/systemd/system/genieacs-ui.service << 'EOF'
[Unit]
Description=GenieACS UI
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-ui
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# =============================================
# STEP 8: Configure Logrotate
# =============================================
log_info "Step 8: Configuring log rotation..."
cat > /etc/logrotate.d/genieacs << 'EOF'
/var/log/genieacs/*.log /var/log/genieacs/*.yaml {
    daily
    rotate 30
    compress
    delaycompress
    dateext
}
EOF

# =============================================
# STEP 9: Enable and Start Services
# =============================================
log_info "Step 9: Starting GenieACS services..."
systemctl daemon-reload

for service in genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui; do
    systemctl enable $service
    systemctl start $service
    sleep 3
done

# Wait for services to start
sleep 10

# =============================================
# STEP 10: Configure Firewall
# =============================================
log_info "Step 10: Configuring firewall..."
apt install -y ufw
ufw --force enable || true
ufw allow ssh
ufw allow 3000/tcp comment "GenieACS Web UI"
ufw allow 7547/tcp comment "GenieACS CWMP"
ufw allow 7557/tcp comment "GenieACS NBI"
ufw allow 7567/tcp comment "GenieACS File Server"

# =============================================
# STEP 11: Verification
# =============================================
log_info "Step 11: Verifying installation..."
echo ""
log_info "=== Service Status ==="
for service in genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui; do
    if systemctl is-active --quiet $service; then
        log_info "✅ $service: RUNNING"
    else
        log_error "❌ $service: FAILED"
        systemctl status $service --no-pager -l
    fi
done

echo ""
log_info "=== Docker Container ==="
if docker ps | grep -q mongodb; then
    log_info "✅ MongoDB Container: RUNNING"
else
    log_error "❌ MongoDB Container: STOPPED"
    docker ps -a | grep mongodb || true
fi

echo ""
log_info "=== Port Check ==="
for port in 3000 7547 7557 7567; do
    if ss -tln 2>/dev/null | grep -q ":$port "; then
        log_info "✅ Port $port: OPEN"
    else
        if command -v netstat &>/dev/null && netstat -tln 2>/dev/null | grep -q ":$port "; then
            log_info "✅ Port $port: OPEN"
        else
            log_warn "⚠️ Port $port: CLOSED"
        fi
    fi
done

echo ""
log_info "=== Installation Complete ==="
log_info "GenieACS Web UI: http://$(hostname -I | awk '{print $1}'):3000"
log_info "Run the database restore script next:"
log_info "sudo /root/restore-genieacs-data.sh"
log_info ""
log_info "To check logs: journalctl -u genieacs-ui -f"
log_info "To check MongoDB: docker logs mongodb"
