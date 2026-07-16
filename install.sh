#!/bin/bash

set -e

BOT_DIR="$(pwd)"
SERVICE_NAME="vpsdeploybot"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

echo "=================================="
echo " VPS Deploy Bot Installer"
echo "=================================="

apt update

apt install -y \
python3 \
python3-pip \
python3-venv \
docker.io \
git \
curl \
build-essential

systemctl enable docker
systemctl start docker

echo
read -p "Enter your Discord Bot Token: " BOT_TOKEN

echo
echo "Updating bot.py..."

sed -i "s|TOKEN = \".*\"|TOKEN = \"$BOT_TOKEN\"|g" "$BOT_DIR/bot.py"

echo
echo "Creating virtual environment..."

python3 -m venv venv

source venv/bin/activate

pip install --upgrade pip

pip install -r requirements.txt

deactivate

echo
echo "Building Docker image..."

if [ ! -f Dockerfile ]; then
    touch Dockerfile

cat > Dockerfile <<EOF
FROM ubuntu:22.04

RUN apt update && apt install -y curl wget tmate openssh-client

CMD ["/bin/bash"]
EOF

fi

docker build -t ubuntu-22.04-with-tmate .

echo
echo "Creating systemd service..."

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=VPS Deploy Discord Bot
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/venv/bin/python3 $BOT_DIR/bot.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable ${SERVICE_NAME}

systemctl restart ${SERVICE_NAME}

echo
echo "=================================="
echo " Installation Complete!"
echo "=================================="
echo
echo "Service Status:"
systemctl --no-pager status ${SERVICE_NAME}
echo
echo "Useful Commands:"
echo "systemctl restart ${SERVICE_NAME}"
echo "systemctl stop ${SERVICE_NAME}"
echo "systemctl status ${SERVICE_NAME}"
echo "journalctl -u ${SERVICE_NAME} -f"
echo
echo "Docker image built:"
echo "ubuntu-22.04-with-tmate"
