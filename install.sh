#!/usr/bin/env bash

# ==============================================================================
# VPS Deploy Bot - Essential Installer
# Supported OS: Ubuntu 22.04+ / Debian
# Log File: /var/log/vpsdeploybot-install.log
# ==============================================================================

set -Eeuo pipefail

INSTALL_DIR="/opt/vpsdeploybot"
REPO_URL="https://github.com/hishadow1/vpsdeploybot.git"
LOG_FILE="/var/log/vpsdeploybot-install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -i -a "$LOG_FILE") 2>&1

failure_handler() {
    echo -e "\n${RED}[✗] Installation failed at line $1 with exit code $2.${NC}"
    exit "$2"
}
trap 'failure_handler ${LINENO} $?' ERR

echo -e "${BLUE}========================================"
echo "      VPS Deploy Bot Essential Setup    "
echo -e "========================================${NC}\n"

# 1. Essential Pre-flight Checks
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[✗] This installer must be run as root.${NC}"
    exit 1
fi

# 2. Package Installation
echo -e "${BLUE}[*] Installing essential system packages...${NC}"
apt-get update -y
apt-get install -y git curl python3 python3-pip python3-venv docker.io build-essential tmate screen jq unzip

echo -e "${GREEN}[✓] Installing Python${NC}"
echo -e "${GREEN}[✓] Installing Docker${NC}"

systemctl enable --now docker

# 3. Repository Sync
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "${BLUE}[*] Updating existing repository...${NC}"
    cd "$INSTALL_DIR"
    git fetch --all && git reset --hard origin/$(git rev-parse --abbrev-ref HEAD) && git pull --rebase
else
    echo -e "${BLUE}[*] Cloning repository...${NC}"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi
echo -e "${GREEN}[✓] Cloning Repository${NC}"

# 4. Token Configuration
echo -e "${BLUE}[*] Configuring Bot Token...${NC}"
bot_file="$INSTALL_DIR/bot.py"
token=""
while [[ -z "$token" ]]; do
    read -r -p "Enter Discord Bot Token: " token < /dev/tty
done
sed -i 's|TOKEN = ""|TOKEN = "'"$token"'"|g' "$bot_file"
sed -i 's|TOKEN = '\'\''|TOKEN = "'"$token"'"|g' "$bot_file"
echo -e "${GREEN}[✓] Configuring Bot${NC}"

# 5. Python Environment Setup
echo -e "${BLUE}[*] Setting up Python virtual environment...${NC}"
cd "$INSTALL_DIR"
python3 -m venv venv
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
if [[ -f "requirements.txt" ]]; then
    "$INSTALL_DIR/venv/bin/pip" install -r requirements.txt
fi

# 6. Docker Build
echo -e "${BLUE}[*] Preparing Docker environment...${NC}"
if [[ ! -f "Dockerfile" ]]; then
    cat << 'EOF' > Dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y tmate openssh-client curl ca-certificates git sudo && rm -rf /var/lib/apt/lists/*
CMD ["/bin/bash"]
EOF
fi
echo -e "${BLUE}[*] Building runtime Docker image...${NC}"
docker build -t ubuntu-22.04-with-tmate .
echo -e "${GREEN}[✓] Building Docker Image${NC}"

# 7. Systemd Service Deployment
echo -e "${BLUE}[*] Deploying Systemd service...${NC}"
cat << EOF > /etc/systemd/system/vpsdeploybot.service
[Unit]
Description=VPS Deploy Bot Service
After=network.target docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vpsdeploybot.service
echo -e "${GREEN}[✓] Creating Service${NC}"

# Final Status Output
echo -e "${GREEN}"
echo "========================================"
echo " VPS Deploy Bot Installed Successfully  "
echo "========================================"
echo -e "${NC}"
echo -e "Repository:   ${BLUE}$INSTALL_DIR${NC}"
echo -e "Docker Image: ${BLUE}ubuntu-22.04-with-tmate${NC}"
echo -e "Service:      ${BLUE}vpsdeploybot${NC}"
echo -e "\n${YELLOW}Management Commands:${NC}"
echo -e "  - Status: ${BLUE}systemctl status vpsdeploybot${NC}"
echo -e "  - Logs:   ${BLUE}journalctl -u vpsdeploybot -f${NC}"
echo ""
