#!/usr/bin/env bash

# ==============================================================================
# VPS Deploy Bot - Production Installer
# Supported OS: Ubuntu 22.04+ / Debian
# Log File: /var/log/vpsdeploybot-install.log
# ==============================================================================

# Strict error handling
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Constants and Configurations
# ------------------------------------------------------------------------------
INSTALL_DIR="/opt/vpsdeploybot"
REPO_URL="https://github.com/hishadow1/vpsdeploybot.git"
LOG_FILE="/var/log/vpsdeploybot-install.log"
MIN_DISK_SPACE_KB=1048576 # 1 GB in KB

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Logging Setup
# ------------------------------------------------------------------------------
# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Redirect stdout and stderr to both console and log file
# Interactive prompts will explicitly read from /dev/tty to bypass tee redirection
exec > >(tee -i -a "$LOG_FILE") 2>&1

# ------------------------------------------------------------------------------
# Signal Traps & Error Handling
# ------------------------------------------------------------------------------
failure_handler() {
    local line_no=$1
    local exit_code=$2
    echo -e "\n${RED}[✗] Installation failed at line $line_no with exit code $exit_code.${NC}"
    echo -e "${YELLOW}Review the full installer logs at: $LOG_FILE${NC}"
    exit "$exit_code"
}
trap 'failure_handler ${LINENO} $?' ERR

# ------------------------------------------------------------------------------
# UI Helper Functions
# ------------------------------------------------------------------------------
print_logo() {
    clear
    echo -e "${BLUE}"
    echo " __     ______  ____    ____             _             ____        _   "
    echo " \ \   / /  _ \/ ___|  |  _ \  ___ _ __ | | ___  _   _| __ )  ___ | |_ "
    echo "  \ \ / /| |_) \___ \  | | | |/ _ \ '_ \| |/ _ \| | | |  _ \ / _ \| __|"
    echo "   \ V / |  __/ ___) | | |_| |  __/ |_) | | (_) | |_| | |_) | (_) | |_ "
    echo "    \_/  |_|   |____/  |____/ \___| .__/|_|\___/ \__, |____/ \___/ \__|"
    echo "                                  |_|            |___/                 "
    echo -e "${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "${CYAN}            VPS Deploy Bot Installer - Debian & Ubuntu${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[*] $1...${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

# ------------------------------------------------------------------------------
# Startup Verification Checks
# ------------------------------------------------------------------------------
run_startup_checks() {
    print_step "Running startup system verifications"

    # 1. Root privilege check
    if [[ "$EUID" -ne 0 ]]; then
        print_error "This installer must be run as root. Please run using sudo or root account."
        exit 1
    fi

    # 2. OS Compatibility verification (Ubuntu 22.04+ or Debian)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=${VERSION_ID:-0}
    else
        print_error "Unsupported operating system (cannot find /etc/os-release)."
        exit 1
    fi

    if [[ "$OS_NAME" != "ubuntu" && "$OS_NAME" != "debian" ]]; then
        print_error "This installer only supports Ubuntu and Debian systems."
        exit 1
    fi

    if [[ "$OS_NAME" == "ubuntu" ]]; then
        # Check if version is 22.04 or newer
        major_version=$(echo "$OS_VERSION" | cut -d. -f1)
        if (( major_version < 22 )); then
            print_error "Ubuntu version $OS_VERSION is not supported. Ubuntu 22.04+ is required."
            exit 1
        fi
    fi

    # 3. Internet Connectivity Check
    if ! curl -s --connect-timeout 8 https://github.com > /dev/null; then
        print_error "Unable to reach GitHub. Please check your internet connection."
        exit 1
    fi

    # 4. APT Lock Verification
    if fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        print_error "APT package manager is currently locked by another process. Please wait and run again."
        exit 1
    fi

    # 5. Disk Space Check
    local free_space
    free_space=$(df "$PWD" | awk 'NR==2 {print $4}')
    if [[ "$free_space" -lt "$MIN_DISK_SPACE_KB" ]]; then
        print_error "Insufficient disk space. Free up at least 1GB of disk space to proceed."
        exit 1
    fi

    print_success "All pre-flight checks passed successfully"
}

# ------------------------------------------------------------------------------
# Repository Actions (Clone or Pull)
# ------------------------------------------------------------------------------
clone_or_update_repo() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        print_step "Existing repository detected. Updating files"
        cd "$INSTALL_DIR"
        git fetch --all
        git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)
        git pull --rebase
        print_success "Cloning Repository"
    else
        print_step "Cloning repository"
        mkdir -p "$INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR"
        print_success "Cloning Repository"
    fi
}

# ------------------------------------------------------------------------------
# Dependency Package Installation
# ------------------------------------------------------------------------------
install_dependencies() {
    print_step "Updating package lists"
    apt-get update -y

    print_step "Installing dependencies"
    apt-get install -y \
        git \
        curl \
        wget \
        python3 \
        python3-pip \
        python3-venv \
        docker.io \
        build-essential \
        tmate \
        screen \
        jq \
        unzip

    print_success "Installing Python"
    print_success "Installing Docker"

    # Start and Enable Docker Service
    print_step "Configuring Docker service"
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
    print_success "Docker Service Enabled & Started"
}

# ------------------------------------------------------------------------------
# Python Virtual Environment Setup
# ------------------------------------------------------------------------------
setup_python_env() {
    print_step "Configuring Python virtual environment"
    cd "$INSTALL_DIR"

    # Create & activate venv
    python3 -m venv venv
    # We execute python modules directly from the venv binary path to ensure correctness inside non-interactive shells
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
    
    if [[ -f "requirements.txt" ]]; then
        print_step "Installing pip dependencies"
        "$INSTALL_DIR/venv/bin/pip" install -r requirements.txt
    else
        print_warning "requirements.txt not found. Skipping dependency resolution."
    fi
    print_success "Python virtual environment configured"
}

# ------------------------------------------------------------------------------
# Docker Image Builder
# ------------------------------------------------------------------------------
build_docker_image() {
    print_step "Verifying Docker environment"
    cd "$INSTALL_DIR"

    if [[ ! -f "Dockerfile" ]]; then
        print_warning "Dockerfile not found. Writing default environment build definitions."
        cat << 'EOF' > Dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    tmate \
    openssh-client \
    curl \
    ca-certificates \
    git \
    sudo \
    && rm -rf /var/lib/apt/lists/*
CMD ["/bin/bash"]
EOF
    fi

    print_step "Building Docker Image: ubuntu-22.04-with-tmate"
    docker build -t ubuntu-22.04-with-tmate .
    print_success "Building Docker Image"
}

# ------------------------------------------------------------------------------
# Interactive Configuration Tasks
# ------------------------------------------------------------------------------
configure_bot() {
    print_step "Configuring Bot Environment"
    local token=""
    local bot_file="$INSTALL_DIR/bot.py"

    if [[ ! -f "$bot_file" ]]; then
        print_error "Target $bot_file was not found. Please check repository state."
        exit 1
    fi

    # Read config input safely from /dev/tty
    while [[ -z "$token" ]]; do
        read -r -p "Enter Discord Bot Token: " token < /dev/tty
        if [[ -z "$token" ]]; then
            print_warning "Token cannot be blank."
        fi
    done

    # Replace token securely using sed with arbitrary safe delimiters
    sed -i 's|TOKEN = ""|TOKEN = "'"$token"'"|g' "$bot_file"
    sed -i 's|TOKEN = '\'\''|TOKEN = "'"$token"'"|g' "$bot_file" # Handles single quote matches

    print_success "Configuring Bot"
}

# ------------------------------------------------------------------------------
# Running Modes Configuration (Systemd or Direct Manual Launch)
# ------------------------------------------------------------------------------
configure_service_menu() {
    echo ""
    echo -e "${YELLOW}Choose how you want to run the bot:${NC}"
    echo "1) Systemd Service (Recommended - runs in background, starts on boot)"
    echo "2) Python Only (Manual execution)"
    
    local choice=""
    while [[ "$choice" != "1" && "$choice" != "2" ]]; do
        read -r -p "Select option [1-2]: " choice < /dev/tty
    done

    if [[ "$choice" == "1" ]]; then
        print_step "Writing Systemd Service configuration"
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
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

        print_step "Enabling and Starting Systemd Service"
        systemctl daemon-reload
        systemctl enable vpsdeploybot.service
        systemctl start vpsdeploybot.service
        print_success "Creating Service"
        
        # Show status block
        echo -e "\n${CYAN}Systemd Service Status Monitoring:${NC}"
        systemctl status vpsdeploybot.service --no-pager || true
        
        show_final_banner "systemd"
    else
        print_warning "Skipping Service configuration. Manual Python launch requested."
        show_final_banner "python"
    fi
}

# ------------------------------------------------------------------------------
# Final Banner Reporting
# ------------------------------------------------------------------------------
show_final_banner() {
    local run_mode=$1
    echo -e "${GREEN}"
    echo "========================================"
    echo " VPS Deploy Bot Installed Successfully  "
    echo "========================================"
    echo -e "${NC}"
    echo -e "Repository:   ${CYAN}$INSTALL_DIR${NC}"
    echo -e "Docker Image: ${CYAN}ubuntu-22.04-with-tmate${NC}"
    echo ""

    if [[ "$run_mode" == "systemd" ]]; then
        echo -e "Service:      ${CYAN}vpsdeploybot${NC}"
        echo -e "\n${YELLOW}Useful management commands:${NC}"
        echo -e "  - View service status:   ${CYAN}systemctl status vpsdeploybot${NC}"
        echo -e "  - Restart service:       ${CYAN}systemctl restart vpsdeploybot${NC}"
        echo -e "  - Stop service:          ${CYAN}systemctl stop vpsdeploybot${NC}"
        echo -e "  - Read logs real-time:   ${CYAN}journalctl -u vpsdeploybot -f${NC}"
    else
        echo -e "\n${YELLOW}To run the bot manually, execute:${NC}"
        echo -e "  cd $INSTALL_DIR"
        echo -e "  source venv/bin/activate"
        echo -e "  python3 bot.py"
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# Uninstallation Protocol
# ------------------------------------------------------------------------------
uninstall_bot() {
    print_warning "Initiating VPS Deploy Bot Uninstallation Procedure"

    # Stop and Disable Systemd service if it exists
    if systemctl list-unit-files | grep -q "vpsdeploybot.service"; then
        print_step "Stopping and removing systemd service"
        systemctl stop vpsdeploybot.service || true
        systemctl disable vpsdeploybot.service || true
        rm -f /etc/systemd/system/vpsdeploybot.service
        systemctl daemon-reload
        print_success "Service removed successfully"
    fi

    # Remove the docker image optionally
    if docker images -q ubuntu-22.04-with-tmate > /dev/null 2>&1; then
        print_step "Deleting docker container images created"
        docker rmi ubuntu-22.04-with-tmate || true
    fi

    # Remove root application directory
    if [[ -d "$INSTALL_DIR" ]]; then
        print_step "Deleting codebase installation target path"
        rm -rf "$INSTALL_DIR"
        print_success "Directory clean completed"
    fi

    print_success "VPS Deploy Bot removed successfully from this server."
}

# ------------------------------------------------------------------------------
# High-Level Operations Orchestrator / Menu Manager
# ------------------------------------------------------------------------------
orchestrate_installation() {
    # Ensure system setup meets prerequisites
    run_startup_checks

    # Check for Existing installation state
    if [[ -d "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}An existing VPS Deploy Bot installation was detected at: $INSTALL_DIR${NC}"
        echo "1) Update existing installation"
        echo "2) Reinstall (Removes current installation and configs)"
        echo "3) Remove installation"
        echo "4) Exit"
        
        local m_choice=""
        while [[ "$m_choice" != "1" && "$m_choice" != "2" && "$m_choice" != "3" && "$m_choice" != "4" ]]; do
            read -r -p "Select option [1-4]: " m_choice < /dev/tty
        done

        case "$m_choice" in
            1)
                clone_or_update_repo
                install_dependencies
                setup_python_env
                build_docker_image
                configure_bot
                configure_service_menu
                ;;
            2)
                uninstall_bot
                clone_or_update_repo
                install_dependencies
                setup_python_env
                build_docker_image
                configure_bot
                configure_service_menu
                ;;
            3)
                uninstall_bot
                ;;
            4)
                print_warning "Exiting installer."
                exit 0
                ;;
        esac
    else
        # Brand new installation pipeline
        clone_or_update_repo
        install_dependencies
        setup_python_env
        build_docker_image
        configure_bot
        configure_service_menu
    fi
}

# ------------------------------------------------------------------------------
# Entry Point Execution Execution
# ------------------------------------------------------------------------------
print_logo
orchestrate_installation
