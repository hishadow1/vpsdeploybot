#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

clear
echo -e "${BLUE}"
cat <<'EOF'
╔══════════════════════════════════════╗
║     🚀 VPS Deploy Bot Installer      ║
╚══════════════════════════════════════╝
EOF
echo -e "${NC}"

[ "$EUID" -eq 0 ] || { echo -e "${RED}Run as root.${NC}"; exit 1; }

apt update
apt install -y git curl docker.io python3 python3-pip python3-venv build-essential

systemctl enable --now docker

INSTALL_DIR=/opt/vpsdeploybot
rm -rf "$INSTALL_DIR"
git clone https://github.com/hishadow1/vpsdeploybot.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

read -rsp "Enter Discord Bot Token: " TOKEN
echo

if [ -f bot.py ]; then
  sed -i "s|TOKEN *= *\".*\"|TOKEN = \"$TOKEN\"|g" bot.py || true
fi

python3 -m venv venv
. venv/bin/activate
pip install --upgrade pip
[ -f requirements.txt ] && pip install -r requirements.txt

if [ ! -f Dockerfile ]; then
cat > Dockerfile <<'EOF'
FROM ubuntu:22.04
RUN apt update && apt install -y tmate curl wget openssh-client
CMD ["/bin/bash"]
EOF
fi

docker build -t ubuntu-22.04-with-tmate .

cat >/etc/systemd/system/vpsdeploybot.service <<EOF
[Unit]
Description=VPS Deploy Bot
After=network.target docker.service

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/bot.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vpsdeploybot

echo -e "${GREEN}Installation complete!${NC}"
echo "Status: systemctl status vpsdeploybot"
echo "Logs: journalctl -u vpsdeploybot -f"
