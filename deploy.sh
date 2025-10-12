
## 2. Buat deploy.sh (One-command installer)

Klik "Add file" → "Create new file" → Namai `deploy.sh`

```bash
#!/bin/bash

# =============================================
# GenieACS Auto Installer for Ubuntu 22.04
# One-command installation from GitHub
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
    log_error "Please run as root or use sudo"
    exit 1
fi

log_info "🚀 GenieACS Auto Installer from GitHub"
log_info "Repository: be2aja/genieacs-ubuntu22.04"

# =============================================
# DOWNLOAD SCRIPTS
# =============================================
log_info "📥 Downloading installation scripts..."

SCRIPTS=(
    "install-genieacs.sh"
    "restore-genieacs-data.sh"
)

for script in "${SCRIPTS[@]}"; do
    log_info "Downloading: $script"
    wget -q "https://raw.githubusercontent.com/be2aja/genieacs-ubuntu22.04/main/$script" -O "$script"
    if [ $? -eq 0 ]; then
        log_info "✅ Downloaded: $script"
    else
        log_error "❌ Failed to download: $script"
        exit 1
    fi
done

# Make scripts executable
chmod +x *.sh

# =============================================
# RUN INSTALLATION
# =============================================
log_info "📦 Starting GenieACS installation..."
sudo ./install-genieacs.sh

# =============================================
# RUN DATABASE RESTORE
# =============================================
log_info "🔄 Restoring database..."
sudo ./restore-genieacs-data.sh

# =============================================
# CLEANUP
# =============================================
log_info "🧹 Cleaning up..."
rm -f install-genieacs.sh restore-genieacs-data.sh

# =============================================
# FINAL MESSAGE
# =============================================
log_info "=== 🎉 INSTALLATION COMPLETE ==="
log_info "🌐 GenieACS Web UI: http://$(hostname -I | awk '{print $1}'):3000"
log_info "🔧 CWMP URL: http://$(hostname -I | awk '{print $1}'):7547"
log_info "📡 NBI API: http://$(hostname -I | awk '{print $1}'):7557"
log_info ""
log_info "📋 Management commands:"
log_info "  sudo systemctl status genieacs-ui"
log_info "  sudo journalctl -u genieacs-ui -f"
log_info "  sudo docker ps"
log_info ""
log_info "Thank you for using GenieACS!"
