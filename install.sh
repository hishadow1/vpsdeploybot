#!/usr/bin/env bash
set -e

INSTALL_DIR="/opt/vpsdeploybot"
REPO_URL="https://github.com/hishadow1/vpsdeploybot.git"

# 1. System Packages & Repository Setup
echo "[*] Installing core dependencies..."
apt-get update -y && apt-get install -y git python3 python3-pip python3-venv

echo "[*] Cloning codebase..."
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 2. Virtual Environment & Requirements
echo "[*] Configuring Python virtual environment..."
python3 -m venv venv
./venv/bin/pip install --upgrade pip
if [ -f "requirements.txt" ]; then
    ./venv/bin/pip install -r requirements.txt
fi

# 3. Secure Token Prompt & Configuration Replacement
token=""
while [ -z "$token" ]; do
    read -r -p "Enter Discord Bot Token: " token < /dev/tty
done
sed -i 's|TOKEN = ""|TOKEN = "'"$token"'"|g' bot.py
sed -i 's|TOKEN = '\'\''|TOKEN = "'"$token"'"|g' bot.py
echo "[✓] Token successfully configured in bot.py"

# 4. Runtime Mode Selector Switch
echo ""
echo "How do you want to launch the bot?"
echo "1) Systemd Service (Runs continuously in background)"
echo "2) Python Only (Launches interactively right now)"
read -r -p "Select choice [1-2]: " mode < /dev/tty

if [ "$mode" == "1" ]; then
    echo "[*] Deploying Systemd background service..."
    cat << EOF > /etc/systemd/system/vpsdeploybot.service
[Unit]
Description=VPS Deploy Bot Service
After=network.target

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
    echo "[✓] Bot is running via systemd! Check status with: systemctl status vpsdeploybot"
else
    echo "[*] Starting bot directly via Python..."
    ./venv/bin/python3 bot.py
fi
