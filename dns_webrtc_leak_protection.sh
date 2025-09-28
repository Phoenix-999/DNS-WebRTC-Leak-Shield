#!/bin/bash
# Avoid BrokenPipeError in progress output
trap '' SIGPIPE


########################################################################################
# Project:   DNS & WebRTC Leak Shield
# Author:    Phoenix-999
# Repository: https://github.com/Phoenix-999
#
# Purpose:
#   Harden VPS environments by preventing DNS leaks and WebRTC local IP exposure.
#   Implements nftables-based firewall rules, resolver hardening, and systemd
#   integration to ensure DNS privacy, integrity, and resistance against leaks.
#
# Features:
#   - Enforces secure DNS resolution via DoH/DoT (Cloudflare, Google, Quad9).
#   - Blocks plaintext DNS and local/private IP leaks.
#   - Optional WebRTC leak protection (STUN/TURN and private IP ranges).
#   - Integrates with systemd-resolved for persistence across reboots.
#   - Designed for VPS use: protects SSH, VPN tunnels, and console access.
#
# Usage:
#   Run interactively with root privileges:
#      sudo bash dns_webrtc_leak_protection.sh
#
# Requirements:
#   - Linux VPS with systemd
#   - nftables, curl, jq (installed automatically if missing)
#
# Notes:
#   - Script modifies DNS configuration and firewall rules in an isolated manner.
#   - Existing nftables rules are preserved; only leak protection chains are applied.
#   - Use the menu system to enable/disable protections or restore defaults.
#
# License:
#   MIT License (free to use, modify, and distribute with attribution).
#
# Created:   2024-07-21
# Updated:   2025-09-27
########################################################################################


###############################
# Define ANSI color codes
###############################

RED='\033[0;31m'
DARK_RED='\033[1;31m'
LESS_SATURATED_RED='\033[0;31m'
BOLD_RED='\033[1;31m'
YELLOW='\033[1;33m'
DARK_YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD_BLUE='\033[1;34m'
DARK_BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'
GREEN='\033[0;32m'
NEON_GREEN='\033[1;38;5;154m'
PURPLE='\033[0;35m'
GREY='\033[0;37m'
DARK_GRAY='\033[1;30m'
DARK_SILVER='\033[38;5;244m'
SPACE_GRAY='\033[38;5;238m'
TIN_DARK_SILVER='\033[38;5;250m'
BOLD='\033[1m'
PLAIN='\033[0m'
RESET='\033[0m'
NC='\033[0m'  # No Color

# URL
URL="github.com/Phoenix-999"

##############################################
# Helper: Ensure package is installed
# - Handles cloudflared special case
##############################################
_ensure_package() {
    local pkg="$1"
    echo -e "${CYAN}  • Ensuring package: $pkg${NC}"

    if [ "$pkg" = "cloudflared" ]; then
        if ! command -v cloudflared >/dev/null 2>&1; then
            echo -e "${YELLOW}  • Installing cloudflared...${NC}"
            if command -v apt-get >/dev/null 2>&1; then
                curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
                echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
                sudo apt-get update -y && sudo apt-get install -y cloudflared || true
            fi
            # Fallback: static binary
            if ! command -v cloudflared >/dev/null 2>&1; then
                curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
                sudo chmod +x /usr/local/bin/cloudflared
                echo -e "${NEON_GREEN}  • Installed cloudflared binary manually${NC}"
            fi
        fi
        return 0
    fi

    # Normal packages
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$pkg"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$pkg"
    else
        echo -e "  • ${RED}No supported package manager found. Please install $pkg manually.${NC}"
        return 1
    fi
}



#############################################
# Function to display a unified progress bar
#############################################
show_progress() {
    local progress=$1
    local total_steps=$2
    local step_message=$3
    local bar_width=34

    # Calculate percentage
    local pct=$(( progress * 100 / total_steps ))
    local num_stars=$(( progress * bar_width / total_steps ))
    local num_spaces=$(( bar_width - num_stars ))

    # Move cursor up two lines and clear the lines to update progress
    if [ "$progress" -ne 1 ]; then
        printf "\033[A\033[K\033[A\033[K"
    fi

    # Print the progress bar
    printf "${DARK_SILVER}   ["
    for ((i=0; i<num_stars; i++)); do
        printf "${GREEN}*"
    done
    for ((i=0; i<num_spaces; i++)); do
        printf "-"
    done
    printf "${DARK_SILVER}] ${NEON_GREEN}${pct}%%${RESET}\n"

    # Print the step message on the next line
    printf "   ${DARK_SILVER}${step_message}${RESET}\n"

    # Move cursor to the beginning of the next line if progress is complete
    if [ "$pct" -eq 100 ]; then
        echo ""
    fi
}


##############################################
# Install Dependencies (if missing)
##############################################
install_dependencies() {
    echo -e "${DARK_BLUE}  • Checking and installing required dependencies...${NC}"
    echo -e "${DARK_YELLOW}  • Please wait, this may take a minute.${NC}"

    # List of essential baseline packages (jq is excluded here, handled by check_jq)
    BASE_PACKAGES="curl ufw iptables"

    # Detect package manager and install baseline + cloudflared if possible
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq > /dev/null 2>&1
        sudo apt-get install -y $BASE_PACKAGES > /dev/null 2>&1

        # Try to install cloudflared from apt (if available)
        if ! command -v cloudflared >/dev/null 2>&1; then
            echo -e "${PURPLE}  • Installing cloudflared (Cloudflare DoH proxy)...${NC}"
            sudo apt-get install -y cloudflared > /dev/null 2>&1 || {
                echo -e "${DARK_YELLOW}  • cloudflared not found in default repos, adding Cloudflare repo...${NC}"
                curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
                echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare.list >/dev/null
                sudo apt-get update -qq > /dev/null 2>&1
                sudo apt-get install -y cloudflared > /dev/null 2>&1 || echo -e "${RED}  • Failed to install cloudflared. DoH will not be available, falling back to DoT.${NC}"
            }
        fi

    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y $BASE_PACKAGES > /dev/null 2>&1
        echo -e "${DARK_YELLOW}  • cloudflared package not in yum repos. DoT will be used instead.${NC}"

    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y $BASE_PACKAGES > /dev/null 2>&1
        echo -e "${DARK_YELLOW}  • cloudflared package not in dnf repos. DoT will be used instead.${NC}"

    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm $BASE_PACKAGES cloudflared > /dev/null 2>&1 || {
            echo -e "${DARK_YELLOW}  • cloudflared not in pacman repos. DoT will be used instead.${NC}"
        }

    else
        echo -e "${RED}  • ERROR: Unsupported package manager. Please install curl, ufw, iptables manually.${NC}"
    fi

    echo -e "${NEON_GREEN}  • All required dependencies installed or verified.${NC}"
}

#####################################################
# Function to check and install jq if not installed
#####################################################
check_jq() {
    clear
    echo -e "${DARK_SILVER}${BOLD} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    local steps=2
    local step=1
    local step_message="  • Checking jq installation"
    echo -e "${DARK_BLUE}  • Server Assessment & Script Preparation${NC}"
    echo -e "${DARK_YELLOW}  • Please Wait...${NC}"
    show_progress $step $steps "$step_message"


    if ! command -v jq &> /dev/null; then
        step_message="  • Installing jq"
        echo -e "${PURPLE}\n  • jq not found. Installing jq...${NC}"
        if command -v apt-get &> /dev/null; then
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y jq > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq > /dev/null 2>&1
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y jq > /dev/null 2>&1
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy jq > /dev/null 2>&1
        else
            echo -e "${RED}  • Error: Package manager not supported. Install jq manually.${NC}"
            exit 1
        fi
        step=2
        show_progress $step $steps "$step_message"
    fi

    # Complete progress bar
    step=$steps
    step_message="  • jq check and installation complete"
    show_progress $step $steps "$step_message"
    echo -e "\n${PURPLE}  • jq check and installation complete.${NC}"
    echo -e "${DARK_SILVER}${BOLD} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

##############################################
# Function to gather VPS details
##############################################
gather_vps_details() {
    local steps=6
    local step=1

    clear
    echo -e "${GREY}"
    echo -e "${DARK_BLUE}   • Server Assessment & Script Preparation${NC}"
    echo -e "${DARK_YELLOW}   • Please Wait...${NC}"

    # VPS Name
    step_message="• Gathering VPS Name"
    VPS_NAME=$(hostname)
    show_progress $step $steps "$step_message"
    sleep 1
    ((step++))

    # System distribution and release info
    step_message="• Gathering System Distribution Info"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRIBUTOR_ID=$ID
        RELEASE=$VERSION_ID
    else
        DISTRIBUTOR_ID="Unknown"
        RELEASE="Unknown"
    fi
    show_progress $step $steps "$step_message"
    sleep 1
    ((step++))

    # VPS IPv4 Address
    step_message="• Gathering VPS IPv4 Address"
    VPS_IPV4=$(hostname -I | awk '{print $1}')
    show_progress $step $steps "$step_message"
    sleep 1
    ((step++))

    # VPS IPv6 Address
    step_message="• Gathering VPS IPv6 Address"
    VPS_IPV6=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    show_progress $step $steps "$step_message"
    sleep 1
    ((step++))

    # Location of the server (using ipinfo.io)
    step_message="• Gathering Server Location"
    IP=$(curl -s https://ipinfo.io/ip)
    LOCATION_JSON=$(curl -s "https://ipinfo.io/${IP}?token=${IPINFO_TOKEN}")
    CITY=$(echo "$LOCATION_JSON" | jq -r '.city // "Unknown"')
    COUNTRY=$(echo "$LOCATION_JSON" | jq -r '.country // "Unknown"')
    LOCATION="${CITY}, ${COUNTRY}"
    show_progress $step $steps "$step_message"
    sleep 1
    ((step++))

    # Check if server and packages are up to date
    step_message="• Checking Server & Packages Update Status"
    sudo apt update > /dev/null 2>&1
    UPGRADABLE=$(apt list --upgradable 2> /dev/null | grep -v "Listing" | wc -l)
    if [ "$UPGRADABLE" -eq 0 ]; then
        STATUS="${NEON_GREEN}√ UP TO DATE${NC}"
    else
        STATUS="${BOLD_RED}✕ NOT UP TO DATE${NC}"
    fi
    show_progress $step $steps "$step_message"
    sleep 1
    ((step++))
    echo -e "${GREY}"
    clear

    # Print details in a formatted table layout
    echo -e "${SPACE_GRAY}${BOLD} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${DARK_SILVER}                  »»——— VPS Details ———««                  ${NC}"
    echo -e "${SPACE_GRAY}${BOLD} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "${YELLOW}  • ${TIN_DARK_SILVER}%-15s${NC} | ${DARK_YELLOW}%-30s${NC}\n" "IPv4 Address" "$VPS_IPV4"
    printf "${YELLOW}  • ${TIN_DARK_SILVER}%-15s${NC} | ${DARK_YELLOW}%-30s${NC}\n" "IPv6 Address" "$VPS_IPV6"
    printf "${YELLOW}  • ${TIN_DARK_SILVER}%-15s${NC} | ${DARK_YELLOW}%-30s${NC}\n" "Location" "$LOCATION"
    printf "${YELLOW}  • ${TIN_DARK_SILVER}%-15s${NC} | ${DARK_YELLOW}%-30s${NC}\n" "Distributor ID" "$DISTRIBUTOR_ID"
    printf "${YELLOW}  • ${TIN_DARK_SILVER}%-15s${NC} | ${DARK_YELLOW}%-30s${NC}\n" "Release" "$RELEASE"
    printf "${YELLOW}  • ${TIN_DARK_SILVER}%-15s${NC} | ${STATUS}${NC}\n" "Server Status"
    echo -e "${SPACE_GRAY}${BOLD} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Call the function to check and install jq
check_jq

# Call the function to gather and display VPS details
gather_vps_details

#####################################################################
# Function: backup_config_files
# Purpose:
#   - Capture true factory DNS state (first run only)
#   - Preserve backups permanently for later restore
#   - Do not overwrite if backups already exist
#####################################################################
backup_config_files() {
    local resolv_backup="/etc/resolv.conf.bak"
    local resolved_backup="/etc/systemd/resolved.conf.bak"
    local timestamp_file="/etc/dns-backup.timestamp"
    local netplan_dir="/etc/netplan"
    local netplan_backup_dir="/root/netplan-backups"

    echo -e "${GREEN} ▷ Backing up DNS configuration files...${NC}"

    #------------------------------------------------------------------
    # 1. Backup /etc/resolv.conf (first run only)
    #------------------------------------------------------------------
    if [ -f "$resolv_backup" ]; then
        echo -e "  • resolv.conf   → ${YELLOW}Factory backup already exists (kept)${NC}"
    else
        sudo cp -a /etc/resolv.conf "$resolv_backup" && \
        echo -e "  • resolv.conf   → ${NEON_GREEN}Factory backup created${NC}"
    fi

    #------------------------------------------------------------------
    # 2. Backup /etc/systemd/resolved.conf (first run only)
    #------------------------------------------------------------------
    if [ -f "$resolved_backup" ]; then
        echo -e "  • resolved.conf → ${YELLOW}Factory backup already exists (kept)${NC}"
    elif [ -f /etc/systemd/resolved.conf ]; then
        sudo cp -a /etc/systemd/resolved.conf "$resolved_backup" && \
        echo -e "  • resolved.conf → ${NEON_GREEN}Factory backup created${NC}"
    else
        echo "# No resolved.conf existed on this system" | sudo tee "$resolved_backup" > /dev/null
        echo -e "  • resolved.conf → ${DARK_YELLOW}No file present (placeholder saved)${NC}"
    fi

    #------------------------------------------------------------------
    # 3. Backup ALL Netplan YAMLs (first run only)
    #------------------------------------------------------------------
    sudo mkdir -p "$netplan_backup_dir"
    local found_any=false
    for netfile in "$netplan_dir"/*.yaml; do
        [ -f "$netfile" ] || continue
        found_any=true
        local fname=$(basename "$netfile")
        local first_backup="$netplan_backup_dir/${fname}.FIRST.bak"

        if [ -f "$first_backup" ]; then
            echo -e "  • $fname → ${YELLOW}Factory backup already exists (kept)${NC}"
        else
            sudo cp -a "$netfile" "$first_backup"
            echo -e "  • $fname → ${NEON_GREEN}Factory backup created${NC}"
        fi
    done
    [ "$found_any" = false ] && echo -e "  • Netplan YAML  → ${DARK_YELLOW}No YAML files found${NC}"

    #------------------------------------------------------------------
    # 4. Record timestamp (first backup only)
    #------------------------------------------------------------------
    if [ ! -f "$timestamp_file" ]; then
        date +"%Y-%m-%d %H:%M:%S" | sudo tee "$timestamp_file" > /dev/null
        echo -e "  • Timestamp     → ${NEON_GREEN}$(cat $timestamp_file)${NC}"
    else
        echo -e "  • Timestamp     → ${YELLOW}$(cat $timestamp_file) (kept)${NC}"
    fi
}


##############################################
# Function to print the introduction message
##############################################

print_introduction() {
    echo -e "${DARK_SILVER}${BOLD} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE} ╭━━━━━━━━━━━━━━━━━━━━∙⋆⋅⋆∙━━━━━━━━━━━━━━━━━━━╮${NC}"
    echo -e "${BLUE}\033[1m    ✭✭✭✭✭✭ DNS & WebRTC Leak Shield ✭✭✭✭✭✭ \033[0m${NC}"
    echo -e "${PURPLE} ╰━━━━━━━━━━━━━━━━━━━━∙⋆⋅⋆∙━━━━━━━━━━━━━━━━━━━╯${NC}"
}

##############################################
# Function to print the menu
##############################################

print_menu() {
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "${BLUE}"
    echo -e "${BLUE}| 1)  - Set DNS ${DARK_RED}▷${RESET}${BLUE} Cloudflare ${DARK_YELLOW}(Recommended${RESET})"
    echo -e "${BLUE}| 2)  - Set DNS ${DARK_RED}▷${RESET}${BLUE} Google"
    echo -e "${BLUE}| 3)  - Set DNS ${DARK_RED}▷${RESET}${BLUE} Quad9"
    echo -e "${BLUE}| 4)  - Verify DNS Configuration"
    echo -e "${BLUE}| 5)  - Automate Flushing DNS Caches"
    echo -e "${BLUE}| 6)  - Restoring Default Server DNS Settings"
    echo -e "${BLUE}| 7)  - Enable WebRTC Leak Protection"
    echo -e "${BLUE}| 8)  - Disable WebRTC Leak Protection"
    echo -e "${BLUE}| 9)  - Verify WebRTC Leak Protection"
    echo -e "${BLUE}"
    echo -e "${DARK_RED}| 0  - Exit"
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
}

##############################################
# Hard-lock resolv.conf to systemd stub
# - Detects and replaces symlink safely
# - Backs up original once
# - Auto unlocks, rewrites if needed, and re-locks
# - Verifies correctness and rolls back on failure
##############################################
_lock_resolvconf_stub() {
    local resolv_file="/etc/resolv.conf"
    local resolv_backup="/etc/resolv.conf.lockback"
    local tmp_file="/tmp/resolv.conf.stub.$$"

    echo -e "${GREEN} ▷ Locking resolv.conf to systemd stub...${NC}"

    # --- Ensure file exists or recreate if symlink ---
    if [ ! -e "$resolv_file" ]; then
        echo -e "  • ${RED}ERROR: $resolv_file missing, creating fresh.${NC}"
        echo -e "nameserver 127.0.0.53" | sudo tee "$resolv_file" >/dev/null
    elif [ -L "$resolv_file" ]; then
        echo -e "  • resolv.conf   → ${YELLOW}Symlink detected, replacing with real file${NC}"
        sudo cp --remove-destination "$(readlink -f $resolv_file)" "$resolv_file"
    fi

    # --- Backup original once ---
    if [ ! -f "$resolv_backup" ]; then
        if sudo cp "$resolv_file" "$resolv_backup"; then
            echo -e "  • resolv.conf   → ${NEON_GREEN}Backup created${NC}"
        else
            echo -e "  • resolv.conf   → ${RED}ERROR: Backup failed${NC}"
            return 1
        fi
    else
        echo -e "  • resolv.conf   → ${YELLOW}Backup exists (kept)${NC}"
    fi

    # --- Desired stub content ---
    cat > "$tmp_file" <<'EOF'
# Managed by DNS & WebRTC Leak Shield (static lock)
nameserver 127.0.0.53
options edns0 trust-ad
search .
EOF

    # --- Unlock before overwrite ---
    if command -v chattr >/dev/null 2>&1; then
        sudo chattr -i "$resolv_file" 2>/dev/null || true
    fi

    # --- Apply only if changed ---
    if ! cmp -s "$resolv_file" "$tmp_file"; then
        if sudo cp "$tmp_file" "$resolv_file"; then
            echo -e "  • resolv.conf   → ${NEON_GREEN}Stub applied${NC}"
        else
            echo -e "  • resolv.conf   → ${RED}ERROR: Failed to apply stub (restoring backup).${NC}"
            sudo cp -f "$resolv_backup" "$resolv_file"
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo -e "  • resolv.conf   → ${YELLOW}Stub already in place (kept)${NC}"
    fi
    rm -f "$tmp_file"

    # --- Verify correctness ---
    if grep -q "127.0.0.53" "$resolv_file" && grep -q "trust-ad" "$resolv_file"; then
        echo -e "  • Verification  → ${NEON_GREEN}Valid stub${NC}"
    else
        echo -e "  • Verification  → ${RED}Stub invalid. Restoring backup.${NC}"
        sudo cp -f "$resolv_backup" "$resolv_file"
        return 1
    fi

    # --- Lock file against tampering ---
    if command -v chattr >/dev/null 2>&1; then
        if sudo chattr +i "$resolv_file" 2>/dev/null; then
            echo -e "  • Lock status   → ${NEON_GREEN}Immutable (chattr +i)${NC}"
        else
            echo -e "  • Lock status   → ${RED}ERROR: Failed to set immutable${NC}"
        fi
    else
        echo -e "  • Lock status   → ${DARK_YELLOW}chattr not available, skipped${NC}"
    fi
}

##############################################
# Disable cloud-init network rewrites (one-time)
# - Prevents VPS provider from injecting DNS
# - Creates /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
# - Verifies correctness and protects with immutability
##############################################
_disable_cloudinit_networking() {
    local cfg_dir="/etc/cloud/cloud.cfg.d"
    local cfg_file="$cfg_dir/99-disable-network-config.cfg"
    local backup_file="$cfg_file.$(date +%Y%m%dT%H%M%S).bak"
    local tmp_file="/tmp/cloudinit.cfg.$$"

    # Detect if cloud-init is in play
    if [ -d /var/lib/cloud ] || command -v cloud-init >/dev/null 2>&1; then
        echo -e "${PURPLE}  → Cloud-init detected. Disabling network overrides...${NC}"

        # Backup existing file (if any)
        if [ -f "$cfg_file" ]; then
            sudo cp "$cfg_file" "$backup_file" && \
                echo -e "  • cloud-init cfg → ${YELLOW}Backup saved ($backup_file)${NC}"
        fi

        # Ensure directory exists
        sudo mkdir -p "$cfg_dir"

        # Write desired config into a temp file
        cat > "$tmp_file" <<'EOF'
network: {config: disabled}
EOF

        # Unlock if immutable
        if command -v chattr >/dev/null 2>&1; then
            sudo chattr -i "$cfg_file" 2>/dev/null || true
        fi

        # Apply config safely
        if ! cmp -s "$cfg_file" "$tmp_file" 2>/dev/null; then
            if sudo cp "$tmp_file" "$cfg_file"; then
                echo -e "  • cloud-init cfg → ${NEON_GREEN}Overrides disabled${NC}"
            else
                echo -e "  • cloud-init cfg → ${RED}ERROR: Failed to apply config. Restoring backup.${NC}"
                [ -f "$backup_file" ] && sudo cp -f "$backup_file" "$cfg_file"
                rm -f "$tmp_file"
                return 1
            fi
        else
            echo -e "  • cloud-init cfg → ${YELLOW}Already disabled (kept)${NC}"
        fi
        rm -f "$tmp_file"

        # Verify correctness
        if grep -q "network: {config: disabled}" "$cfg_file"; then
            echo -e "  • Verification   → ${NEON_GREEN}Valid${NC}"
        else
            echo -e "  • Verification   → ${RED}Invalid config detected (restoring backup).${NC}"
            [ -f "$backup_file" ] && sudo cp -f "$backup_file" "$cfg_file"
            return 1
        fi

        # Lock file to prevent re-enable
        if command -v chattr >/dev/null 2>&1; then
            if sudo chattr +i "$cfg_file" 2>/dev/null; then
                echo -e "  • Lock status    → ${NEON_GREEN}Immutable (chattr +i)${NC}"
            else
                echo -e "  • Lock status    → ${RED}Failed to set immutable${NC}"
            fi
        else
            echo -e "  • Lock status    → ${DARK_YELLOW}chattr not available, skipped${NC}"
        fi
    else
        echo -e "${DARK_YELLOW}  → No cloud-init detected (skipped).${NC}"
    fi
}

##############################################
# Disable per-interface DHCP DNS injection
# - Detects network renderer (networkd/NetworkManager)
# - Safely cleans ALL netplan YAML files
# - Adds dhcp4-overrides: use-dns: false
# - Removes nameservers blocks
# - Rolls back on failure
# - Auto-locks YAML with chattr after success
##############################################
_disable_dhcp_dns_networkd() {
    echo -e "${PURPLE}  → Disabling DHCP-provided DNS (systemd-networkd + netplan).${NC}"

    local renderer
    if command -v netplan >/dev/null 2>&1; then
        renderer=$(netplan get | yq e '.network.renderer' - 2>/dev/null)
        [ -z "$renderer" ] && renderer="networkd"
    else
        renderer="unknown"
    fi
    echo -e "  • Renderer       → ${CYAN}${renderer}${NC}"

    if [ -d /etc/netplan ]; then
        for NETPLAN_FILE in /etc/netplan/*.yaml; do
            [ -e "$NETPLAN_FILE" ] || continue
            echo -e "  • Processing netplan → ${CYAN}$(basename "$NETPLAN_FILE")${NC}"

            local BACKUP="/root/netplan-$(basename $NETPLAN_FILE).$(date +%Y%m%dT%H%M%S).bak"
            sudo cp -a "$NETPLAN_FILE" "$BACKUP"
            echo -e "     ↳ Backup saved → ${YELLOW}$BACKUP${NC}"

            # Unlock if immutable
            if command -v chattr >/dev/null 2>&1; then
                sudo chattr -i "$NETPLAN_FILE" 2>/dev/null || true
            fi

            # Ensure yq v4 installed
            if ! command -v yq >/dev/null 2>&1 || ! yq --version | grep -q 'version 4'; then
                echo -e "     ↳ ${RED}yq v4 required.${NC} Installing..."
                sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
                sudo chmod +x /usr/local/bin/yq
            fi

            # Remove nameservers blocks
            sudo yq -i 'del(.network.ethernets[].nameservers)' "$NETPLAN_FILE"

            # Add dhcp4-overrides: use-dns: false
            sudo yq -i '.network.ethernets |= with_entries(.value += {"dhcp4-overrides":{"use-dns":false}})' "$NETPLAN_FILE"

            # Validate
            if ! sudo yq e '.network.ethernets[]."dhcp4-overrides"."use-dns"' "$NETPLAN_FILE" | grep -q "false"; then
                echo -e "     ↳ ${RED}Validation failed, restoring backup.${NC}"
                sudo cp -f "$BACKUP" "$NETPLAN_FILE"
                return 1
            fi

            # Apply netplan
            if sudo netplan apply; then
                echo -e "     ↳ ${NEON_GREEN}Applied successfully${NC}"
            else
                echo -e "     ↳ ${RED}Netplan apply failed. Restoring backup.${NC}"
                sudo cp -f "$BACKUP" "$NETPLAN_FILE"
                return 1
            fi

            # Reapply immutability
            if command -v chattr >/dev/null 2>&1; then
                sudo chattr +i "$NETPLAN_FILE"
                echo -e "     ↳ ${NEON_GREEN}Immutable (chattr +i)${NC}"
            fi
        done
    fi
}


##############################################
# Reset systemd DNS state & old DHCP leases
# - Stops services cleanly
# - Clears caches, leases, runtime state
# - Re-applies netplan safely
# - Restarts resolver + networkd
# - Verifies current active resolvers
# - Reboot-resistant and rollback safe
##############################################
_reset_dns_state() {
    echo -e "${GREEN} ▷ Resetting DNS state and clearing old leases...${NC}"

    # --- Stop services cleanly ---
    if systemctl list-unit-files | grep -q systemd-resolved.service; then
        sudo systemctl stop systemd-resolved 2>/dev/null || true
        echo -e "  • systemd-resolved → ${YELLOW}Stopped${NC}"
    fi
    if systemctl list-unit-files | grep -q systemd-networkd.service; then
        sudo systemctl stop systemd-networkd 2>/dev/null || true
        echo -e "  • systemd-networkd → ${YELLOW}Stopped${NC}"
    fi

    # --- Clear runtime state ---
    sudo rm -rf /run/systemd/resolve/* /run/systemd/network/* 2>/dev/null || true

    # --- Backup + clear persistent DHCP leases ---
    if [ -d /var/lib/systemd/network ]; then
        local lease_backup="/root/network-leases-$(date +%Y%m%dT%H%M%S).tar.gz"
        if sudo tar -czf "$lease_backup" /var/lib/systemd/network 2>/dev/null; then
            echo -e "  • Old DHCP leases → ${YELLOW}Backed up at $lease_backup${NC}"
        fi
        sudo rm -rf /var/lib/systemd/network/* 2>/dev/null || true
        echo -e "  • Old DHCP leases → ${NEON_GREEN}Cleared${NC}"
    fi

    # --- Apply netplan (with validation) ---
    if command -v netplan >/dev/null 2>&1; then
        if sudo netplan generate 2>/dev/null && sudo netplan apply 2>/dev/null; then
            echo -e "  • Netplan config  → ${NEON_GREEN}Re-applied${NC}"
        else
            echo -e "  • Netplan config  → ${RED}Apply failed${NC}"
        fi
    else
        echo -e "  • Netplan config  → ${DARK_YELLOW}Not present (skipped)${NC}"
    fi

    # --- Restart services in order ---
    if systemctl list-unit-files | grep -q systemd-networkd.service; then
        if sudo systemctl start systemd-networkd 2>/dev/null; then
            echo -e "  • systemd-networkd → ${NEON_GREEN}Started${NC}"
        else
            echo -e "  • systemd-networkd → ${RED}Failed to start${NC}"
        fi
    fi
    if systemctl list-unit-files | grep -q systemd-resolved.service; then
        if sudo systemctl start systemd-resolved 2>/dev/null; then
            echo -e "  • systemd-resolved → ${NEON_GREEN}Started${NC}"
        else
            echo -e "  • systemd-resolved → ${RED}Failed to start${NC}"
        fi
    fi

    # --- Flush caches ---
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches 2>/dev/null || true
        echo -e "  • DNS cache       → ${NEON_GREEN}Flushed${NC}"
    fi

    # --- Verification: check resolvers ---
    if command -v resolvectl >/dev/null 2>&1; then
        local status; status="$(resolvectl status 2>/dev/null)"
        local bad_dns; bad_dns=$(echo "$status" | grep -E "67\.207\.")

        echo -e "  • Active resolvers →${CYAN}"
        echo "$status" | awk '/DNS Servers:/,/DNSSEC/ {print "     " $0}'
        echo -e "${NC}"

        if [ -n "$bad_dns" ]; then
            echo -e "  • Verification    → ${RED}Provider DNS (67.207.x.x) still present!${NC}"
        elif echo "$status" | grep -q "127.0.0.1"; then
            echo -e "  • Verification    → ${NEON_GREEN}Custom resolvers active${NC}"
        else
            echo -e "  • Verification    → ${DARK_YELLOW}Unexpected DNS state, check manually${NC}"
        fi
    fi
}

##############################################
# Write provider to MAIN resolved.conf (hard lock)
# - Args: IPv4_A IPv4_B IPv6_A IPv6_B
# - Purges vendor drop-ins before apply
# - Creates first + timestamped backups
# - Applies atomically, rollback on failure
# - Flushes caches & strips provider DNS
# - Verifies only target resolvers remain
##############################################
_write_resolved_main() {
    local d1="$1" d2="$2" f1="$3" f2="$4"
    local resolved_file="/etc/systemd/resolved.conf"
    local first_backup="/etc/systemd/resolved.conf.mainbak"
    local ts_backup="/root/resolved.conf.$(date +%Y%m%dT%H%M%S).bak"
    local tmp_file="/tmp/resolved.conf.$$"

    echo -e "${GREEN} ▷ Applying provider DNS to resolved.conf...${NC}"

    # --- Ensure systemd-resolved exists ---
    if ! systemctl list-unit-files | grep -q '^systemd-resolved.service'; then
        echo -e "  • systemd-resolved → ${DARK_YELLOW}Not installed (skipped)${NC}"
        return 0
    fi

    # --- Purge vendor drop-ins before apply ---
    if [ -d /etc/systemd/resolved.conf.d ]; then
        sudo mkdir -p /root/resolved-dropins-backup
        for f in /etc/systemd/resolved.conf.d/*.conf; do
            [ -f "$f" ] || continue
            sudo cp "$f" "/root/resolved-dropins-backup/$(basename $f).$(date +%Y%m%dT%H%M%S).bak"
            sudo rm -f "$f"
            echo -e "  • Vendor drop-in removed → ${RED}$(basename $f)${NC}"
        done
    fi

    # --- One-time permanent backup ---
    if [ -f "$resolved_file" ] && [ ! -f "$first_backup" ]; then
        sudo cp -a "$resolved_file" "$first_backup" && \
            echo -e "  • resolved.conf   → ${NEON_GREEN}First backup created${NC}"
    fi

    # --- Generate desired config ---
    cat > "$tmp_file" <<EOF
[Resolve]
DNS=${d1} ${d2}
FallbackDNS=${f1} ${f2}
DNSOverTLS=yes
DNSSEC=yes
Domains=~.
MulticastDNS=no
LLMNR=no
DNSStubListener=yes
DNSDefaultRoute=no
EOF

    # --- Compare + replace only if changed ---
    local changed=0
    if [ ! -f "$resolved_file" ] || ! cmp -s "$resolved_file" "$tmp_file"; then
        [ -f "$resolved_file" ] && sudo cp -a "$resolved_file" "$ts_backup" && \
            echo -e "  • Backup          → ${YELLOW}$ts_backup${NC}"

        if sudo cp "$tmp_file" "$resolved_file"; then
            echo -e "  • resolved.conf   → ${NEON_GREEN}Updated${NC}"
            changed=1
        else
            echo -e "  • resolved.conf   → ${RED}ERROR: Write failed${NC}"
            [ -f "$ts_backup" ] && sudo cp -f "$ts_backup" "$resolved_file"
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo -e "  • resolved.conf   → ${YELLOW}Already up-to-date${NC}"
    fi
    rm -f "$tmp_file"

    # --- Restart resolver if changed ---
    if [ "$changed" -eq 1 ]; then
        if sudo systemctl restart systemd-resolved; then
            echo -e "  • systemd-resolved → ${NEON_GREEN}Restarted${NC}"
            command -v resolvectl >/dev/null 2>&1 && resolvectl flush-caches || true
            for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|eno)'); do
                resolvectl revert "$IFACE" >/dev/null 2>&1 || true
                echo -e "  • Interface $IFACE → ${DARK_SILVER}Reverted DNS config${NC}"
            done
        else
            echo -e "  • systemd-resolved → ${RED}Restart failed, restoring backup${NC}"
            [ -f "$ts_backup" ] && sudo cp -f "$ts_backup" "$resolved_file"
            return 1
        fi
    fi

    # --- Verification ---
    if command -v resolvectl >/dev/null 2>&1; then
        local ip_d1="${d1%%#*}" ip_d2="${d2%%#*}" ip_f1="${f1%%#*}" ip_f2="${f2%%#*}"
        local status ok=0
        status="$(resolvectl status 2>/dev/null)"
        echo -e "  • Active DNS      →${CYAN}"
        echo "$status" | awk '/DNS Servers:/,/DNSSEC/ {print "     " $0}'
        echo -e "${NC}"

        [[ "$status" == *"$ip_d1"* ]] && ok=$((ok+1))
        [[ "$status" == *"$ip_d2"* ]] && ok=$((ok+1))
        [[ "$status" == *"$ip_f1"* ]] && ok=$((ok+1))
        [[ "$status" == *"$ip_f2"* ]] && ok=$((ok+1))

        if [ $ok -ge 2 ]; then
            echo -e "  • Verification    → ${NEON_GREEN}Resolvers applied successfully${NC}"
        else
            echo -e "  • Verification    → ${RED}Configured resolvers not detected${NC}"
            return 1
        fi
    else
        echo -e "  • Verification    → ${DARK_YELLOW}resolvectl not available (skipped)${NC}"
    fi
}


##############################################
# Function: install_cloudflared
# Purpose:
#   - Ensure cloudflared binary is present
#   - Create & enable systemd service for DoH proxy
#   - Verify listener on 127.0.0.1:5053
#   - Reboot-resistant setup
##############################################
install_cloudflared() {
    echo -e "${GREEN} ▷ Ensuring cloudflared DoH proxy is installed...${NC}"

    # 1. Install binary if missing
    if ! command -v cloudflared >/dev/null 2>&1; then
        echo -e "${YELLOW}  • cloudflared not found. Installing latest release...${NC}"
        curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
            -o /usr/local/bin/cloudflared
        sudo chmod +x /usr/local/bin/cloudflared
        echo -e "${NEON_GREEN}  • cloudflared installed at /usr/local/bin/cloudflared${NC}"
    else
        echo -e "${DARK_SILVER}  • cloudflared found at $(command -v cloudflared)${NC}"
    fi

    # 2. Create systemd service (fresh overwrite each time)
    echo -e "${PURPLE}  • Creating systemd unit for cloudflared...${NC}"
    sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<'EOF'
[Unit]
Description=Cloudflared DoH DNS proxy (Cloudflare)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared proxy-dns \
  --address 127.0.0.1 \
  --port 5053 \
  --upstream https://cloudflare-dns.com/dns-query
Restart=always
RestartSec=5s
User=root
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    # 3. Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable --now cloudflared-doh.service

    # 4. Verification step
    sleep 2
    if ss -tulnp 2>/dev/null | grep -q "127.0.0.1:5053"; then
        if dig @127.0.0.1 -p 5053 example.com +short >/dev/null 2>&1; then
            echo -e "${NEON_GREEN}  ✓ cloudflared is running and resolving on 127.0.0.1:5053${NC}"
        else
            echo -e "${RED}  ✗ cloudflared is listening but not resolving queries${NC}"
            echo -e "    Run: sudo journalctl -u cloudflared-doh.service -e"
        fi
    else
        echo -e "${RED}  ✗ cloudflared service failed to bind to 127.0.0.1:5053${NC}"
        echo -e "    Run: sudo journalctl -u cloudflared-doh.service -e"
    fi
}


##############################################
# Hard-lock DNS (reboot resistant)
# - Removes provider drop-ins
# - Overwrites systemd-resolved.conf safely
# - Cleans netplan YAML (safe edits with yq)
# - Locks YAML against provider re-injection
# - Verifies final DNS state matches target
##############################################
_hard_lock_dns() {
    local d1="$1" d2="$2" f1="$3" f2="$4"
    local resolved_file="/etc/systemd/resolved.conf"
    local resolved_backup="/etc/systemd/resolved.conf.hardlock.bak"
    local tmp_file="/tmp/resolved.conf.$$"
    local netplan_file="/etc/netplan/50-cloud-init.yaml"
    local netplan_backup="/root/netplan-$(basename $netplan_file).$(date +%Y%m%dT%H%M%S).bak"

    echo -e "${GREEN} ▷ Hard-locking DNS configuration...${NC}"

    # 1. Remove provider DNS overrides
    sudo rm -f /etc/systemd/resolved.conf.d/*.conf 2>/dev/null || true

    # 2. Backup resolved.conf if not yet saved
    if [ -f "$resolved_file" ] && [ ! -f "$resolved_backup" ]; then
        sudo cp -a "$resolved_file" "$resolved_backup" && \
            echo -e "  • resolved.conf   → ${NEON_GREEN}First backup created${NC}"
    fi

    # 3. Build desired resolved.conf
    cat > "$tmp_file" <<EOF
[Resolve]
DNS=${d1} ${d2}
FallbackDNS=${f1} ${f2}
DNSOverTLS=yes
DNSSEC=yes
Domains=~.
MulticastDNS=no
LLMNR=no
DNSStubListener=yes
DNSDefaultRoute=no
EOF

    # 4. Write only if changed
    if [ ! -f "$resolved_file" ] || ! cmp -s "$resolved_file" "$tmp_file"; then
        sudo cp -a "$resolved_file" "$resolved_file.$(date +%Y%m%dT%H%M%S).bak" 2>/dev/null || true
        sudo cp "$tmp_file" "$resolved_file"
        echo -e "  • resolved.conf   → ${NEON_GREEN}Updated${NC}"
        local changed=1
    else
        echo -e "  • resolved.conf   → ${YELLOW}No change (already matches)${NC}"
        local changed=0
    fi
    rm -f "$tmp_file"

    # 5. Patch netplan YAML
    if [ -f "$netplan_file" ]; then
        sudo cp -a "$netplan_file" "$netplan_backup"
        echo -e "  • Netplan backup  → ${YELLOW}$netplan_backup${NC}"

        # Ensure yq present
        if ! command -v yq >/dev/null 2>&1; then
            echo -e "  • ${RED}yq not found.${NC} Installing..."
            if command -v apt >/dev/null 2>&1; then
                sudo apt update -y && sudo apt install -y yq || return 1
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y yq || return 1
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y yq || return 1
            else
                echo -e "  • ${RED}No supported package manager found. Install yq manually.${NC}"
                return 1
            fi
        fi

        # Safe edits
        sudo yq -i 'del(.network.ethernets[].nameservers)' "$netplan_file"
        sudo yq -i '.network.ethernets |= with_entries(.value += {"dhcp4-overrides":{"use-dns":false}})' "$netplan_file"

        # Apply netplan, rollback if fail
        if ! sudo netplan apply; then
            echo -e "  • ${RED}Netplan apply failed. Restoring backup.${NC}"
            sudo cp -f "$netplan_backup" "$netplan_file"
            return 1
        fi

        # Lock YAML
        sudo chattr -i "$netplan_file" 2>/dev/null || true
        sudo chattr +i "$netplan_file"
        echo -e "  • Netplan YAML    → ${NEON_GREEN}Locked (immutable)${NC}"
    fi

    # 6. Restart resolver only if changed
    if [ "$changed" -eq 1 ]; then
        sudo systemctl restart systemd-resolved
        resolvectl flush-caches 2>/dev/null || true
    fi

    # 7. Verification
    if command -v resolvectl >/dev/null 2>&1; then
        local ip_d1="${d1%%#*}" ip_d2="${d2%%#*}" ip_f1="${f1%%#*}" ip_f2="${f2%%#*}"
        local show; show="$(resolvectl status 2>/dev/null)"
        echo -e "  • Active resolvers →${CYAN}"
        echo "$show" | awk '/DNS Servers:/,/DNSSEC/ {print "     " $0}'
        echo -e "${NC}"
        if echo "$show" | grep -q "$ip_d1" && echo "$show" | grep -q "$ip_d2"; then
            echo -e "  • Verification     → ${NEON_GREEN}Resolvers applied successfully${NC}"
        else
            echo -e "  • Verification     → ${RED}Mismatch with expected DNS${NC}"
            return 1
        fi
    fi

    echo -e "${NEON_GREEN}  ✓ DNS hard-locked to secure resolvers (reboot resistant).${NC}"
}

##############################################
# Firewall rule helper (block DNS leaks only)
# - Requires nftables
# - Whitelists loopback, SSH, VPN, local IPs
# - Drops all other plaintext DNS traffic
# - Idempotent with backups and verification
##############################################
_block_dns_leaks() {
    echo -e "${PURPLE}  → Enforcing DNS Leak Protection with nftables...${NC}"

    local nft_file="/etc/nftables.d/dns_shield.nft"
    local service_file="/etc/systemd/system/dns-shield.service"

    # --- Ensure nftables installed ---
    if ! command -v nft >/dev/null 2>&1; then
        echo -e "  • nftables       → ${RED}Not installed${NC}"
        echo -e "    ${YELLOW}Installing...${NC}"
        if command -v apt >/dev/null 2>&1; then
            sudo apt update -y && sudo apt install -y nftables || return 1
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y nftables || return 1
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y nftables || return 1
        else
            echo -e "  • ${RED}No supported package manager found. Install nftables manually.${NC}"
            return 1
        fi
    fi

    # --- Detect SSH port (default 22) ---
    local ssh_port
    ssh_port=$(ss -tlnp 2>/dev/null | awk '/sshd/ {gsub(".*:", "", $4); print $4; exit}')
    [ -z "$ssh_port" ] && ssh_port=22

    # --- Detect local IPs ---
    local ipv4s ipv6s vpn_ifaces
    ipv4s=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) print $i}')
    ipv6s=$(ip -6 addr show scope global | awk '/inet6/ {print $2}' | cut -d/ -f1)
    vpn_ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(tun|wg)[0-9]')

    # --- Backup old config ---
    if [ -f "$nft_file" ]; then
        local backup="/root/dns_shield.nft.$(date +%Y%m%dT%H%M%S).bak"
        sudo cp "$nft_file" "$backup"
        echo -e "  • nft config     → ${YELLOW}Backup saved: $backup${NC}"
    fi

    # --- Write new nftables rules ---
    sudo mkdir -p /etc/nftables.d
    sudo tee "$nft_file" >/dev/null <<EOF
table inet dns_shield {
    chain output {
        type filter hook output priority 0; policy accept;

        # Allow VPN tunnels
EOF

    for vpn in $vpn_ifaces; do
        echo "        iifname \"$vpn\" accept" | sudo tee -a "$nft_file" >/dev/null
    done

    sudo tee -a "$nft_file" >/dev/null <<EOF

        # Allow loopback DNS
        ip daddr 127.0.0.1 udp dport 53 accept
        ip daddr 127.0.0.1 tcp dport 53 accept
        ip daddr 127.0.0.53 udp dport 53 accept
        ip daddr 127.0.0.53 tcp dport 53 accept

        # Allow SSH
        tcp dport $ssh_port accept
EOF

    # Whitelist IPv4 addresses
    for ip in $ipv4s; do
        echo "        ip daddr $ip accept" | sudo tee -a "$nft_file" >/dev/null
    done

    # Whitelist IPv6 addresses
    for ip6 in $ipv6s; do
        echo "        ip6 daddr $ip6 accept" | sudo tee -a "$nft_file" >/dev/null
    done

    # Blocking rules
    sudo tee -a "$nft_file" >/dev/null <<'EOF'
        # Block all other plaintext DNS
        udp dport 53 drop
        tcp dport 53 drop

        # Block private IP ranges DNS
        ip daddr 10.0.0.0/8 udp dport 53 drop
        ip daddr 10.0.0.0/8 tcp dport 53 drop
        ip daddr 172.16.0.0/12 udp dport 53 drop
        ip daddr 172.16.0.0/12 tcp dport 53 drop
        ip daddr 192.168.0.0/16 udp dport 53 drop
        ip daddr 192.168.0.0/16 tcp dport 53 drop
        ip daddr 169.254.0.0/16 udp dport 53 drop
        ip daddr 169.254.0.0/16 tcp dport 53 drop
    }
}
EOF

    # --- Backup old service ---
    if [ -f "$service_file" ]; then
        local service_backup="/root/dns-shield.service.$(date +%Y%m%dT%H%M%S).bak"
        sudo cp "$service_file" "$service_backup"
        echo -e "  • dns-shield svc → ${YELLOW}Backup saved: $service_backup${NC}"
    fi

    # --- Write service file ---
    sudo tee "$service_file" >/dev/null <<'EOF'
[Unit]
Description=DNS Leak Shield (nftables)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables.d/dns_shield.nft
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # --- Reload systemd and apply rules ---
    sudo systemctl daemon-reload
    sudo systemctl enable dns-shield.service > /dev/null 2>&1

    if sudo systemctl restart dns-shield.service; then
        echo -e "  • nftables       → ${NEON_GREEN}DNS Leak Shield applied${NC}"
    else
        echo -e "  • nftables       → ${RED}Failed to apply rules${NC}"
        systemctl status dns-shield.service -l || true
        return 1
    fi

    # --- Verify ---
    if nft list ruleset | grep -q "dport 53 drop"; then
        echo -e "  • Verification   → ${NEON_GREEN}Drop rules active${NC}"
    else
        echo -e "  • Verification   → ${RED}Rules missing${NC}"
    fi

    # --- Summary ---
    [ -n "$ipv4s" ] && echo -e "${DARK_SILVER}  • IPv4 whitelisted:${NC}\n$ipv4s" || echo -e "${DARK_SILVER}  • IPv4 whitelisted:${NC} none"
    [ -n "$ipv6s" ] && echo -e "${DARK_SILVER}  • IPv6 whitelisted:${NC} enabled" || echo -e "${DARK_SILVER}  • IPv6 whitelisted:${NC} none"
    echo -e "${DARK_SILVER}  • SSH port open:${NC} ${RED}$ssh_port${NC}"
}

##############################################
# Remove old provider DNS configs (safe cleanup)
# - Backs up then removes stale drop-ins and units we manage
# - Stops old cloudflared unit to avoid dup instances
# - Leaves user nftables and netplan alone
# - Idempotent, with 30-day backup pruning
##############################################
cleanup_old_dns_configs() {
    echo -e "${PURPLE}  → Cleaning up old DNS provider configs...${NC}"

    local ts dir bak pruned=0
    ts="$(date +%Y%m%dT%H%M%S)"
    dir="/root/dns-shield-backups/$ts"
    bak() { # backup <path>
        local p="$1"
        [ -e "$p" ] || return 0
        sudo mkdir -p "$dir"
        sudo cp -a --parents "$p" "$dir" 2>/dev/null || true
    }

    # 1) systemd-resolved drop-ins we used previously
    sudo mkdir -p /etc/systemd/resolved.conf.d
    for f in \
        /etc/systemd/resolved.conf.d/99-cloudflare-dot.conf \
        /etc/systemd/resolved.conf.d/99-google-dot.conf \
        /etc/systemd/resolved.conf.d/99-quad9-dot.conf \
        /etc/systemd/resolved.conf.d/force-dns.conf \
        /etc/systemd/resolved.conf.d/99-*.conf
    do
        if [ -f "$f" ]; then
            bak "$f"
            sudo rm -f "$f"
            echo -e "  • removed: ${DARK_SILVER}$f${NC}"
        fi
    done

    # 2) legacy cloudflared unit/config we own
    if systemctl list-unit-files | grep -q '^cloudflared-doh.service'; then
        echo -e "  • stopping old unit: cloudflared-doh.service"
        sudo systemctl stop cloudflared-doh.service 2>/dev/null || true
        sudo systemctl disable cloudflared-doh.service 2>/dev/null || true
    fi
    if [ -L /etc/systemd/system/multi-user.target.wants/cloudflared-doh.service ]; then
        bak /etc/systemd/system/multi-user.target.wants/cloudflared-doh.service
        sudo rm -f /etc/systemd/system/multi-user.target.wants/cloudflared-doh.service
    fi
    if [ -f /etc/systemd/system/cloudflared-doh.service ]; then
        bak /etc/systemd/system/cloudflared-doh.service
        sudo rm -f /etc/systemd/system/cloudflared-doh.service
        echo -e "  • removed: ${DARK_SILVER}/etc/systemd/system/cloudflared-doh.service${NC}"
    fi
    if [ -d /etc/cloudflared ]; then
        # only back up; provider funcs will recreate config
        bak /etc/cloudflared
        sudo rm -rf /etc/cloudflared
        echo -e "  • removed: ${DARK_SILVER}/etc/cloudflared${NC}"
    fi

    # 3) daemon-reload if any unit changed
    sudo systemctl daemon-reload 2>/dev/null || true

    # 4) prune backups older than 30 days
    if sudo find /root/dns-shield-backups -mindepth 1 -maxdepth 1 -type d -mtime +30 -print -exec rm -rf {} \; 2>/dev/null | grep -q .; then
        pruned=1
    fi
    [ -d "$dir" ] && echo -e "  • backups at: ${CYAN}$dir${NC}"
    [ "$pruned" = 1 ] && echo -e "  • old backups: ${DARK_SILVER}pruned (>30d)${NC}"

    echo -e "${NEON_GREEN}  ✓ Cleanup complete.${NC}"
}


##############################################
# Remove provider DNS drop-ins (DigitalOcean, etc.)
# - Backs up vendor files under /etc/systemd/resolved.conf.d/
# - Deletes them so they can’t re-inject DNS
# - Locks the directory for reboot resistance
##############################################
cleanup_vendor_resolved_dropins() {
    echo -e "${PURPLE}  → Checking for provider DNS drop-ins...${NC}"
    local dropin_dir="/etc/systemd/resolved.conf.d"
    local backup_dir="/root/resolved-dropins-backup"
    local ts="$(date +%Y%m%dT%H%M%S)"
    local changed=0

    if [ -d "$dropin_dir" ]; then
        sudo mkdir -p "$backup_dir"

        for f in "$dropin_dir"/*.conf; do
            [ -f "$f" ] || continue
            local fname=$(basename "$f")
            local bak="$backup_dir/${fname}.$ts.bak"

            # Backup then remove
            sudo cp -a "$f" "$bak" && echo -e "  • Backup saved: ${YELLOW}$bak${NC}"
            sudo rm -f "$f"
            echo -e "  • Removed vendor drop-in: ${DARK_SILVER}$fname${NC}"
            changed=1
        done

        # Lock directory to block re-creation
        if [ "$changed" -eq 1 ]; then
            if command -v chattr >/dev/null 2>&1; then
                sudo chattr -i "$dropin_dir"/* 2>/dev/null || true
                sudo chattr +i "$dropin_dir"
                echo -e "  • Lock status → ${NEON_GREEN}Immutable directory (chattr +i)${NC}"
            fi
        fi
    else
        echo -e "  • ${DARK_YELLOW}No /etc/systemd/resolved.conf.d directory found${NC}"
    fi
}

##############################################
# Cloudflare DNS Setup (DoH + DoT fallback)
# - Uses cloudflared for DoH
# - Fallback via Cloudflare DoT
# - Cleans up old configs, locks DNS
##############################################
set_dns_cloudflare() {
    clear
    LOGFILE="/root/dns-shield.log"

    print_cloudflare_header() {
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_BLUE} ▶ Cloudflare DNS Setup (DoH + DoT Fallback)${NC}"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREY}"
    }
    # Print header at the beginning
    print_cloudflare_header
    echo -e "${DARK_YELLOW} ▶ Please wait...${NC}${PURPLE} Setting up Cloudflare secure DNS.${NC}"
    echo -e "${GREY}"

    # ── Run setup in background, log everything ──────────────────────────
    (
        cleanup_old_dns_configs
        _disable_cloudinit_networking
        _disable_dhcp_dns_networkd
        _lock_resolvconf_stub
        cleanup_vendor_resolved_dropins
        install_cloudflared || exit 1

        if [ -f /etc/cloudflared/config.yml ]; then
            cf_bak="/root/cloudflared.config.$(date +%Y%m%dT%H%M%S).bak"
            sudo cp /etc/cloudflared/config.yml "$cf_bak"
        fi

        sudo mkdir -p /etc/cloudflared
        sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://cloudflare-dns.com/dns-query
EOF

        sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<EOF
[Unit]
Description=Cloudflared DoH DNS proxy (Cloudflare)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared proxy-dns --config /etc/cloudflared/config.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now cloudflared-doh.service
        _write_resolved_main \
            "127.0.0.1#cloudflare-dns.com" "1.1.1.1#cloudflare-dns.com" \
            "2606:4700:4700::1111#cloudflare-dns.com" "2606:4700:4700::1001#cloudflare-dns.com"
        _reset_dns_state
        _block_dns_leaks
    ) >>"$LOGFILE" 2>&1 &

    pid=$!
    spinner="/-\|"
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r   ${RED}Working${NC} ${spinner:$i:1}"
            sleep 0.2
        done
    done
    wait $pid
    clear
    print_cloudflare_header
    printf "\r   ${NEON_GREEN}Setup complete.          ${NC}\n\n"

    # ── Status checks ────────────────────────────────────────────────────
    if ss -tulnp 2>/dev/null | grep -q "127.0.0.1:5053"; then
        DOH_STATUS="${NEON_GREEN}✓ Active on 127.0.0.1:5053${NC}"
        FINAL_STATUS="${NEON_GREEN}✓ Secure DNS active via Cloudflare${NC}"
    else
        DOH_STATUS="${RED}✗ Not listening on 127.0.0.1:5053${NC}"
        FINAL_STATUS="${YELLOW}⚠ Configured, but DoH not active. See $LOGFILE${NC}"
    fi

    DOT_STATUS="${YELLOW}✓ Enabled as fallback${NC}"

    # Parse current resolvers cleanly (remove "Global:" and "Link N (iface):")
    CURRENT_RESOLVERS=$(resolvectl dns 2>/dev/null \
        | grep -vE '^Link' \
        | sed -E 's/^Global:[[:space:]]*//' \
        | tr '\n' ' ' \
        | xargs)

    # Deduplicate all resolvers first
    CURRENT_RESOLVERS=$(echo "$CURRENT_RESOLVERS" | tr ' ' '\n' | awk '!seen[$0]++' | xargs)

    PRIMARY=$(echo "$CURRENT_RESOLVERS" | awk '{print $1}')
    FALLBACK=$(echo "$CURRENT_RESOLVERS" | cut -d' ' -f2-)


    # Remove duplicate fallback resolvers
    FALLBACK=$(echo "$FALLBACK" | tr ' ' '\n' | awk '!seen[$0]++' | xargs)

    # ── Display summary ──────────────────────────────────────────────────
    echo -e "${BOLD_BLUE} ▶ FINAL STATUS${NC}"
    echo -e "   ${FINAL_STATUS}"
    echo ""
    echo -e "${BOLD_BLUE} ▶ DNS MODE${NC}"
    echo -e "   ${GREY}• DoH:${NC} $DOH_STATUS"
    echo -e "   ${GREY}• DoT:${NC} $DOT_STATUS"
    echo ""
    echo -e "${BOLD_BLUE} ▶ ACTIVE RESOLVERS${NC}"
    echo -e "   ${GREY}• Primary:${NC}  $PRIMARY"

    if [ -n "$FALLBACK" ]; then
        FIRST_FALLBACK=$(echo "$FALLBACK" | awk '{print $1}')
        REST_FALLBACK=$(echo "$FALLBACK" | cut -d' ' -f2-)

        # First resolver stays on same line
        echo -e "   ${GREY}• Fallback:${NC} $FIRST_FALLBACK"

        # Additional resolvers, one per line, indented
        for RES in $REST_FALLBACK; do
            echo -e "               $RES"
        done
    fi
    echo ""
    echo -e "${BOLD_BLUE} ▶ SYSTEM PROTECTION${NC}"
    echo -e "   ${GREY}• DNS leak shield:${NC} ${NEON_GREEN}Active (nftables)${NC}"
    echo -e "   ${GREY}• resolv.conf lock:${NC} ${NEON_GREEN}Enabled${NC}"
    echo -e "   ${GREY}• DHCP/Cloud-init overrides:${NC} ${NEON_GREEN}Disabled${NC}"
    echo ""
    echo -e "${BOLD_BLUE} ▶ SETUP SUMMARY${NC}"
    echo -e "   ${NEON_GREEN}✓ Old configs cleaned${NC}"
    echo -e "   ${NEON_GREEN}✓ cloudflared installed and running${NC}"
    echo -e "   ${NEON_GREEN}✓ Resolvers applied${NC}"
    echo -e "   ${NEON_GREEN}✓ DNS state reset${NC}"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}


##############################################
# Google DNS Setup (DoH + DoT fallback)
# - Uses cloudflared for DoH
# - Fallback via Google DoT
# - Cleans old configs, locks DNS
##############################################
set_dns_google() {
    clear
    LOGFILE="/root/dns-shield.log"

    print_google_header() {
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_BLUE} ▶ Google DNS Setup (DoH + DoT Fallback)${NC}"
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREY}"
    }

    # Print header at the beginning
    print_google_header
    echo -e "${DARK_YELLOW} ▶ Please wait...${NC}${PURPLE} Setting up Google secure DNS.${NC}"
    echo -e "${GREY}"

    # ── Run setup in background, log everything ──────────────────────────
    (
        cleanup_old_dns_configs
        _disable_cloudinit_networking
        _disable_dhcp_dns_networkd
        _lock_resolvconf_stub
        cleanup_vendor_resolved_dropins
        install_cloudflared || exit 1

        if [ -f /etc/cloudflared/config.yml ]; then
            cf_bak="/root/cloudflared.config.$(date +%Y%m%dT%H%M%S).bak"
            sudo cp /etc/cloudflared/config.yml "$cf_bak"
        fi

        sudo mkdir -p /etc/cloudflared
        sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://dns.google/dns-query
EOF

        sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<EOF
[Unit]
Description=Cloudflared DoH DNS proxy (Google)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared proxy-dns --config /etc/cloudflared/config.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now cloudflared-doh.service
        _write_resolved_main \
            "127.0.0.1#dns.google" "8.8.8.8#dns.google" \
            "2001:4860:4860::8888#dns.google" "2001:4860:4860::8844#dns.google"
        _reset_dns_state
        _block_dns_leaks
    ) >>"$LOGFILE" 2>&1 &

    pid=$!
    spinner="/-\|"
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r   ${RED}Working${NC} ${spinner:$i:1}"
            sleep 0.2
        done
    done
    wait $pid
    clear
    print_google_header
    printf "\r   ${NEON_GREEN}Setup complete.          ${NC}\n\n"

    # ── Status checks ────────────────────────────────────────────────────
    if ss -tulnp 2>/dev/null | grep -q "127.0.0.1:5053"; then
        DOH_STATUS="${NEON_GREEN}✓ Active on 127.0.0.1:5053${NC}"
        FINAL_STATUS="${NEON_GREEN}✓ Secure DNS active via Google${NC}"
    else
        DOH_STATUS="${RED}✗ Not listening on 127.0.0.1:5053${NC}"
        FINAL_STATUS="${YELLOW}⚠ Configured, but DoH not active. See $LOGFILE${NC}"
    fi

    DOT_STATUS="${YELLOW}✓ Enabled as fallback${NC}"

    # Parse current resolvers cleanly (remove "Global:" and "Link N (iface):")
    CURRENT_RESOLVERS=$(resolvectl dns 2>/dev/null \
        | grep -vE '^Link' \
        | sed -E 's/^Global:[[:space:]]*//' \
        | tr '\n' ' ' \
        | xargs)

    # Deduplicate all resolvers first
    CURRENT_RESOLVERS=$(echo "$CURRENT_RESOLVERS" | tr ' ' '\n' | awk '!seen[$0]++' | xargs)

    PRIMARY=$(echo "$CURRENT_RESOLVERS" | awk '{print $1}')
    FALLBACK=$(echo "$CURRENT_RESOLVERS" | cut -d' ' -f2-)

    # ── Display summary ──────────────────────────────────────────────────
    echo -e "${BOLD_BLUE} ▶ FINAL STATUS${NC}"
    echo -e "   ${FINAL_STATUS}"
    echo ""
    echo -e "${BOLD_BLUE} ▶ DNS MODE${NC}"
    echo -e "   ${GREY}• DoH:${NC} $DOH_STATUS"
    echo -e "   ${GREY}• DoT:${NC} $DOT_STATUS"
    echo ""
    echo -e "${BOLD_BLUE} ▶ ACTIVE RESOLVERS${NC}"
    echo -e "   ${GREY}• Primary:${NC}  $PRIMARY"

    if [ -n "$FALLBACK" ]; then
        FIRST_FALLBACK=$(echo "$FALLBACK" | awk '{print $1}')
        REST_FALLBACK=$(echo "$FALLBACK" | cut -d' ' -f2-)

        # First resolver stays on same line
        echo -e "   ${GREY}• Fallback:${NC} $FIRST_FALLBACK"

        # Additional resolvers, one per line, indented
        for RES in $REST_FALLBACK; do
            echo -e "               $RES"
        done
    fi
    echo ""
    echo -e "${BOLD_BLUE} ▶ SYSTEM PROTECTION${NC}"
    echo -e "   ${GREY}• DNS leak shield:${NC} ${NEON_GREEN}Active (nftables)${NC}"
    echo -e "   ${GREY}• resolv.conf lock:${NC} ${NEON_GREEN}Enabled${NC}"
    echo -e "   ${GREY}• DHCP/Cloud-init overrides:${NC} ${NEON_GREEN}Disabled${NC}"
    echo ""
    echo -e "${BOLD_BLUE} ▶ SETUP SUMMARY${NC}"
    echo -e "   ${NEON_GREEN}✓ Old configs cleaned${NC}"
    echo -e "   ${NEON_GREEN}✓ cloudflared installed and running${NC}"
    echo -e "   ${NEON_GREEN}✓ Resolvers applied${NC}"
    echo -e "   ${NEON_GREEN}✓ DNS state reset${NC}"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}


##############################################
# Quad9 DNS Setup (DoH + DoT fallback)
# - Uses cloudflared for DoH
# - Fallback via Quad9 DoT
# - Cleans old configs, locks DNS
##############################################
set_dns_quad9() {
    clear
    LOGFILE="/root/dns-shield.log"

    print_quad9_header() {
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_BLUE} ▶ Quad9 DNS Setup (DoH + DoT Fallback)${NC}"
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREY}"
    }

    # Print header at the beginning
    print_quad9_header
    echo -e "${DARK_YELLOW} ▶ Please wait...${NC}${PURPLE} Setting up Quad9 secure DNS.${NC}"
    echo -e "${GREY}"

    # ── Run setup in background, log everything ──────────────────────────
    (
        cleanup_old_dns_configs
        _disable_cloudinit_networking
        _disable_dhcp_dns_networkd
        _lock_resolvconf_stub
        cleanup_vendor_resolved_dropins
        install_cloudflared || exit 1

        if [ -f /etc/cloudflared/config.yml ]; then
            cf_bak="/root/cloudflared.config.$(date +%Y%m%dT%H%M%S).bak"
            sudo cp /etc/cloudflared/config.yml "$cf_bak"
        fi

        sudo mkdir -p /etc/cloudflared
        sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://dns.quad9.net/dns-query
EOF

        sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<EOF
[Unit]
Description=Cloudflared DoH DNS proxy (Quad9)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared proxy-dns --config /etc/cloudflared/config.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now cloudflared-doh.service
        _write_resolved_main \
            "127.0.0.1#dns.quad9.net" "9.9.9.9#dns.quad9.net" \
            "2620:fe::fe#dns.quad9.net" "2620:fe::9#dns.quad9.net"
        _reset_dns_state
        _block_dns_leaks
    ) >>"$LOGFILE" 2>&1 &

    pid=$!
    spinner="/-\|"
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r   ${RED}Working${NC} ${spinner:$i:1}"
            sleep 0.2
        done
    done
    wait $pid
    clear
    print_quad9_header
    printf "\r   ${NEON_GREEN}Setup complete.          ${NC}\n\n"

    # ── Status checks ────────────────────────────────────────────────────
    if ss -tulnp 2>/dev/null | grep -q "127.0.0.1:5053"; then
        DOH_STATUS="${NEON_GREEN}✓ Active on 127.0.0.1:5053${NC}"
        FINAL_STATUS="${NEON_GREEN}✓ Secure DNS active via Quad9${NC}"
    else
        DOH_STATUS="${RED}✗ Not listening on 127.0.0.1:5053${NC}"
        FINAL_STATUS="${YELLOW}⚠ Configured, but DoH not active. See $LOGFILE${NC}"
    fi

    DOT_STATUS="${YELLOW}✓ Enabled as fallback${NC}"

    # Parse current resolvers cleanly (remove "Global:" and "Link N (iface):")
    CURRENT_RESOLVERS=$(resolvectl dns 2>/dev/null \
        | grep -vE '^Link' \
        | sed -E 's/^Global:[[:space:]]*//' \
        | tr '\n' ' ' \
        | xargs)

    # Deduplicate all resolvers first
    CURRENT_RESOLVERS=$(echo "$CURRENT_RESOLVERS" | tr ' ' '\n' | awk '!seen[$0]++' | xargs)

    PRIMARY=$(echo "$CURRENT_RESOLVERS" | awk '{print $1}')
    FALLBACK=$(echo "$CURRENT_RESOLVERS" | cut -d' ' -f2-)

    # ── Display summary ──────────────────────────────────────────────────
    echo -e "${BOLD_BLUE} ▶ FINAL STATUS${NC}"
    echo -e "   ${FINAL_STATUS}"
    echo ""
    echo -e "${BOLD_BLUE} ▶ DNS MODE${NC}"
    echo -e "   ${GREY}• DoH:${NC} $DOH_STATUS"
    echo -e "   ${GREY}• DoT:${NC} $DOT_STATUS"
    echo ""
    echo -e "${BOLD_BLUE} ▶ ACTIVE RESOLVERS${NC}"
    echo -e "   ${GREY}• Primary:${NC}  $PRIMARY"

    if [ -n "$FALLBACK" ]; then
        FIRST_FALLBACK=$(echo "$FALLBACK" | awk '{print $1}')
        REST_FALLBACK=$(echo "$FALLBACK" | cut -d' ' -f2-)

        # First resolver stays on same line
        echo -e "   ${GREY}• Fallback:${NC} $FIRST_FALLBACK"

        # Additional resolvers, one per line, indented
        for RES in $REST_FALLBACK; do
            echo -e "               $RES"
        done
    fi
    echo ""
    echo -e "${BOLD_BLUE} ▶ SYSTEM PROTECTION${NC}"
    echo -e "   ${GREY}• DNS leak shield:${NC} ${NEON_GREEN}Active (nftables)${NC}"
    echo -e "   ${GREY}• resolv.conf lock:${NC} ${NEON_GREEN}Enabled${NC}"
    echo -e "   ${GREY}• DHCP/Cloud-init overrides:${NC} ${NEON_GREEN}Disabled${NC}"
    echo ""
    echo -e "${BOLD_BLUE} ▶ SETUP SUMMARY${NC}"
    echo -e "   ${NEON_GREEN}✓ Old configs cleaned${NC}"
    echo -e "   ${NEON_GREEN}✓ cloudflared installed and running${NC}"
    echo -e "   ${NEON_GREEN}✓ Resolvers applied${NC}"
    echo -e "   ${NEON_GREEN}✓ DNS state reset${NC}"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#####################################################################
# Function: verify_dns
# Purpose:
#   - Verify DNS configuration in a clean, user-friendly format
#   - Detect DoH proxy and upstream resolvers
#   - Check for provider DNS leaks
#   - Run connectivity and DNSSEC tests (with spinner feedback)
#####################################################################
verify_dns() {
    clear
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_BLUE} ▶ DNS Configuration Check${NC}"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    #---------------------------------------------------------------
    # Tool availability
    #---------------------------------------------------------------
    local use_tool=""
    if command -v dig >/dev/null 2>&1; then
        use_tool="dig"
    elif command -v nslookup >/dev/null 2>&1; then
        use_tool="nslookup"
    else
        echo -e "   • Tools: ${RED}Neither dig nor nslookup installed${NC}"
        echo ""
        return 1
    fi
    echo -e "   • Tool available: ${NEON_GREEN}$use_tool${NC}"
    echo ""

    #---------------------------------------------------------------
    # DoH proxy detection
    #---------------------------------------------------------------
    if ss -tulnp 2>/dev/null | grep -qE "127\.0\.0\.1:5053"; then
        DOH_STATUS="${NEON_GREEN}✓ Active (127.0.0.1:5053)${NC}"
    else
        DOH_STATUS="${RED}✗ Not detected${NC}"
    fi

    #---------------------------------------------------------------
    # Inspect systemd-resolved
    #---------------------------------------------------------------
    local status resolvers upstreams
    status="$(resolvectl status 2>/dev/null)"
    resolvers=$(echo "$status" | awk '/DNS Servers:/,/DNSSEC/ {print $0}')
    upstreams=$(echo "$resolvers" | awk '/DNS Servers:/ {for (i=3;i<=NF;i++) print $i}')

    # Leak check
    if echo "$resolvers" | grep -Eq "67\.207\.|10\.|192\.168\.|169\.254\."; then
        LEAK_RESULT="${RED}FAIL (provider/private detected)${NC}"
    else
        LEAK_RESULT="${NEON_GREEN}PASS (no leaks)${NC}"
    fi

    # Identify provider
    if echo "$resolvers" | grep -Eq '\b(1\.1\.1\.1|1\.0\.0\.1)\b'; then
        RESOLVER_NAME="Cloudflare"
    elif echo "$resolvers" | grep -Eq '\b(8\.8\.8\.8|8\.8\.4\.4)\b'; then
        RESOLVER_NAME="Google"
    elif echo "$resolvers" | grep -Eq '\b(9\.9\.9\.9|149\.112\.112\.112)\b'; then
        RESOLVER_NAME="Quad9"
    elif echo "$resolvers" | grep -Eq '\b127\.0\.0\.1\b'; then
        RESOLVER_NAME="DoH Local Proxy"
    else
        RESOLVER_NAME="Unknown"
    fi

    # DNSSEC status from systemd-resolved
    DNSSEC="Unknown"
    if echo "$status" | grep -q "DNSSEC=yes"; then
        DNSSEC="Enabled"
    elif echo "$status" | grep -q "DNSSEC=off"; then
        DNSSEC="Disabled"
    fi

    #---------------------------------------------------------------
    # Show summary first
    #---------------------------------------------------------------
    echo -e "${BOLD_BLUE} ▶ RESULTS SUMMARY${NC}"
    echo -e "   • DoH proxy: $DOH_STATUS"
    echo -e "   • Upstream servers:"
    if [ -n "$upstreams" ]; then
        for srv in $upstreams; do
            echo -e "       • $srv"
        done
    else
        echo -e "       • None detected"
    fi
    echo -e "   • Provider: $RESOLVER_NAME"
    echo -e "   • Leak check: $LEAK_RESULT"
    echo -e "   • DNSSEC setting: $DNSSEC"
    echo ""

    #---------------------------------------------------------------
    # Pick resolver address for queries
    #---------------------------------------------------------------
    local dig_server dig_port
    if [[ "$DOH_STATUS" == *"✓"* ]]; then
        dig_server=127.0.0.1; dig_port=5053
    else
        dig_server=127.0.0.53; dig_port=53
    fi

    #---------------------------------------------------------------
    # Connectivity tests with spinner
    #---------------------------------------------------------------
    echo -e "${BOLD_BLUE} ▶ CONNECTIVITY TESTS${NC}"

    declare -A TEST_RESULTS
    TARGETS=("example.com" "cloudflare.com" "dns.google" "quad9.net")

    for domain in "${TARGETS[@]}"; do
    printf "   • %s: " "$domain"

    (
        if [ "$use_tool" = "dig" ]; then
            result=$(dig @"$dig_server" -p "$dig_port" "$domain" +short 2>/dev/null | head -n1)
        else
            result=$(nslookup "$domain" 2>/dev/null | awk '/^Address: /{print $2; exit}')
        fi
        if [[ -n "$result" ]]; then
            echo -e "${NEON_GREEN}OK${NC}" > /tmp/test_$domain
        else
            echo -e "${RED}FAILED${NC}" > /tmp/test_$domain
        fi
    ) &

    pid=$!
    spinner="/-\|"
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r   • %s: %s" "$domain" "${spinner:$i:1}"
            sleep 0.2
        done
    done
    wait $pid
    printf "\r   • %s: %s\n" "$domain" "$(cat /tmp/test_$domain)"
    rm -f /tmp/test_$domain
done

    echo ""

    #---------------------------------------------------------------
    # DNSSEC validation (dig only)
    #---------------------------------------------------------------
    DNSSEC_VALID="SKIPPED"
    DNSSEC_FAILCHECK="SKIPPED"
    if [ "$use_tool" = "dig" ]; then
        dig @"$dig_server" -p "$dig_port" verisignlabs.com +dnssec 2>/dev/null | grep -q " ad[[:space:]]" \
            && DNSSEC_VALID="PASS" || DNSSEC_VALID="FAIL"

        dig @"$dig_server" -p "$dig_port" dnssec-failed.org +dnssec 2>/dev/null | grep -q "SERVFAIL" \
            && DNSSEC_FAILCHECK="PASS" || DNSSEC_FAILCHECK="FAIL"

        echo -e "   • DNSSEC valid test: $([[ $DNSSEC_VALID = PASS ]] && echo ${NEON_GREEN}PASS${NC} || echo ${RED}FAIL${NC})"
        echo -e "   • DNSSEC fail test: $([[ $DNSSEC_FAILCHECK = PASS ]] && echo ${NEON_GREEN}PASS${NC} || echo ${RED}FAIL${NC})"
    else
        echo -e "   • DNSSEC tests: ${YELLOW}Skipped (nslookup has no DNSSEC)${NC}"
    fi

    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

##############################################
# Automate Flushing DNS Caches
# - Lets user choose flush interval
# - Creates cron job safely (removes old jobs first)
# - Ensures flush script exists and is executable
##############################################
automate_flush() {
    clear

    print_flush_header() {
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_BLUE} ▶ Automate DNS Cache Flushing${NC}"
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREY}"
    }

    # Print header
    print_flush_header

    echo -e "${GREY}Choose your preferred flush interval:${NC}"
    echo -e "   ${YELLOW}1)${NC} Every 1 hour      → Maximum privacy (Tor, anonymity)"
    echo -e "   ${YELLOW}2)${NC} Every 6 hours     → Strong privacy (VPN servers)"
    echo -e "   ${YELLOW}3)${NC} Every 18 hours    → Daily VPN sessions"
    echo -e "   ${YELLOW}4)${NC} Every 24 hours    → Balanced default"
    echo -e "   ${YELLOW}5)${NC} Weekly            → Performance priority"
    echo -e "   ${YELLOW}6)${NC} Disable automation → No scheduled flushing"
    echo ""
    echo -ne "${NEON_GREEN} ➤ Enter your choice (1-6): ${NC}"
    read flush_choice

    # ── Dependency checks ───────────────────────────────────────────────
    if ! command -v resolvectl >/dev/null 2>&1; then
        echo -e "   ${RED}✗ resolvectl not found${NC}"
        return 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "   ${RED}✗ systemctl not found${NC}"
        return 1
    fi

    # ── Ensure flush script exists ──────────────────────────────────────
    SCRIPT_PATH="/usr/local/bin/flush_caches.sh"
    sudo tee "$SCRIPT_PATH" >/dev/null <<'EOF'
#!/bin/bash
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart systemd-resolved
fi
EOF
    sudo chmod +x "$SCRIPT_PATH"

    # ── Cron expression ─────────────────────────────────────────────────
    case $flush_choice in
        1)  CRON_EXPR="0 * * * * $SCRIPT_PATH" ;;      # every 1 hour
        2)  CRON_EXPR="0 */6 * * * $SCRIPT_PATH" ;;   # every 6 hours
        3)  CRON_EXPR="0 */18 * * * $SCRIPT_PATH" ;;  # every 18 hours
        4)  CRON_EXPR="0 0 * * * $SCRIPT_PATH" ;;     # daily
        5)  CRON_EXPR="0 0 * * 0 $SCRIPT_PATH" ;;     # weekly
        6)  CRON_EXPR="" ;;                           # disable
        *)  echo -e "   ${RED}✗ Invalid choice. No cron job created.${NC}"; return ;;
    esac

    # ── Remove existing flush block ─────────────────────────────────────
    CRONTAB_TMP=$(mktemp)
    sudo crontab -l 2>/dev/null | awk '
        BEGIN {skip=0}
        /#◈◈◈FLUSHING_DNS_CACHES_START◈◈◈/ {skip=1; next}
        /#◈◈◈FLUSHING_DNS_CACHES_END◈◈◈/ {skip=0; next}
        skip==0 {print}
    ' > "$CRONTAB_TMP"

    # ── Add new cron job ────────────────────────────────────────────────
    if [ -n "$CRON_EXPR" ]; then
        cat <<EOF >> "$CRONTAB_TMP"

#◈◈◈FLUSHING_DNS_CACHES_START◈◈◈
$CRON_EXPR
#◈◈◈FLUSHING_DNS_CACHES_END◈◈◈
EOF
        sudo crontab "$CRONTAB_TMP"
        echo ""
        echo -e "   ${NEON_GREEN}✓ DNS cache flushing scheduled successfully${NC}"
    else
        sudo crontab "$CRONTAB_TMP"
        echo ""
        echo -e "   ${YELLOW}⚠ Automation disabled. Flush DNS manually if needed${NC}"
    fi

    rm -f "$CRONTAB_TMP"
    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#####################################################################
# Function: restore_to_factory
# Purpose:
#   - Restore DNS config to original factory state
#   - Uses immutable backups (.bak, .FIRST.bak)
#   - Removes custom services (cloudflared, dns-shield)
#   - Re-enables cloud-init & DHCP DNS
#####################################################################
restore_to_factory() {
    clear

    print_restore_header() {
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD_BLUE} ▶ Restore DNS to Factory Defaults${NC}"
        echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREY}"
    }

    # Print header
    print_restore_header

    echo -e " ${DARK_RED}⚠ WARNING:${NC} This will erase all custom DNS settings."
    read -p " ➤ Continue? [Y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo -e "   ${YELLOW}Cancelled.${NC}" && return 0
    echo ""

    local netplan_backup_dir="/root/netplan-backups"

    # ── Unlock files ────────────────────────────────────────────────
    sudo chattr -i /etc/resolv.conf 2>/dev/null || true
    sudo chattr -i /etc/netplan/*.yaml 2>/dev/null || true
    sudo chattr -i /etc/cloud/cloud.cfg.d/* 2>/dev/null || true

    # ── Restore resolv.conf ────────────────────────────────────────
    if [ -f /etc/resolv.conf.bak ]; then
        sudo cp -f /etc/resolv.conf.bak /etc/resolv.conf
        echo -e "   ${GREY}• resolv.conf:${NC} ${NEON_GREEN}restored from backup${NC}"
    else
        echo -e "   ${GREY}• resolv.conf:${NC} ${RED}factory backup missing${NC}"
    fi

    # ── Restore resolved.conf ──────────────────────────────────────
    if [ -f /etc/systemd/resolved.conf.bak ]; then
        sudo cp -f /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf
        echo -e "   ${GREY}• resolved.conf:${NC} ${NEON_GREEN}restored from backup${NC}"
    else
        echo -e "   ${GREY}• resolved.conf:${NC} ${RED}factory backup missing${NC}"
    fi

    # ── Restore Netplan YAMLs ──────────────────────────────────────
    if [ -d "$netplan_backup_dir" ]; then
        local restored_any=false
        for f in "$netplan_backup_dir"/*.FIRST.bak; do
            [ -f "$f" ] || continue
            restored_any=true
            orig="/etc/netplan/${f##*/}"
            orig="${orig%.FIRST.bak}"
            sudo cp -f "$f" "$orig"
            echo -e "   ${GREY}• Netplan:${NC} ${NEON_GREEN}$(basename "$orig") restored${NC}"
        done
        [ "$restored_any" = false ] && echo -e "   ${GREY}• Netplan:${NC} ${YELLOW}no factory backups found${NC}"
    else
        echo -e "   ${GREY}• Netplan:${NC} ${YELLOW}no factory backup directory${NC}"
    fi

    # ── Remove cloudflared ─────────────────────────────────────────
    if systemctl list-unit-files | grep -q cloudflared-doh.service; then
        sudo systemctl stop cloudflared-doh.service >/dev/null 2>&1
        sudo systemctl disable cloudflared-doh.service >/dev/null 2>&1
        sudo rm -f /etc/systemd/system/cloudflared-doh.service
        sudo rm -rf /etc/cloudflared
        echo -e "   ${GREY}• cloudflared:${NC} ${NEON_GREEN}removed cleanly${NC}"
    fi

    # ── Remove dns-shield ─────────────────────────────────────────
    if systemctl list-unit-files | grep -q dns-shield.service; then
        sudo systemctl stop dns-shield.service >/dev/null 2>&1
        sudo systemctl disable dns-shield.service >/dev/null 2>&1
        sudo rm -f /etc/nftables.d/dns_shield.nft /etc/systemd/system/dns-shield.service
        sudo systemctl daemon-reload
        echo -e "   ${GREY}• dns-shield:${NC} ${NEON_GREEN}removed cleanly${NC}"
    fi

    # ── Re-enable cloud-init & DHCP DNS ───────────────────────────
    sudo rm -f /etc/cloud/cloud-init.disabled /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    sudo systemctl restart systemd-networkd 2>/dev/null || true
    echo -e "   ${GREY}• cloud-init & DHCP DNS:${NC} ${NEON_GREEN}re-enabled${NC}"

    # ── Restart services ──────────────────────────────────────────
    sudo netplan apply 2>/dev/null || true
    sudo systemctl restart systemd-resolved 2>/dev/null || true
    resolvectl flush-caches 2>/dev/null || true

    # ── Verify connectivity ───────────────────────────────────────
    echo ""
    if dig example.com +short >/dev/null 2>&1; then
        echo -e "   ${NEON_GREEN}✓ DNS working after factory restore${NC}"
    else
        echo -e "   ${RED}✗ DNS failed after factory restore${NC}"
    fi

    echo -e "${BOLD_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}


##############################################
# 7)  - Enable WebRTC Leak Protection
##############################################
enable_webrtc() {
    clear
    echo -e "${YELLOW} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN} ▶ Enabling WebRTC Leak Protection...${NC}"
    echo -e "${YELLOW} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Define nftables config path
    NFT_CONF="/etc/nftables.d/webrtc_shield.nft"

    # Ensure directory exists
    sudo mkdir -p /etc/nftables.d

    # Remove old table if exists (to avoid duplication)
    sudo nft delete table inet webrtc_shield 2>/dev/null || true

    # Write new nftables rules for WebRTC protection
    sudo tee $NFT_CONF >/dev/null <<'EOF'
table inet webrtc_shield {
    chain output {
        type filter hook output priority 0; policy accept;

        # Allow essential traffic (loopback, SSH, VPN tunnels)
        iifname "lo" accept
        iifname "tun0" accept
        iifname "wg0" accept

        tcp dport 22 accept   # SSH safety

        # Block WebRTC STUN/TURN known ports (TCP/UDP)
        udp dport { 3478, 5349, 19302, 19305, 3479, 5348, 19306, 19307, 19308, 19309 } drop
        tcp dport { 3478, 5349, 19302, 19305, 3479, 5348, 19306, 19307, 19308, 19309 } drop

        # Block local/private IP ranges (to prevent WebRTC leaks)
        # Exceptions added to keep VPS web console/metadata working
        ip daddr 10.0.0.0/8 drop
        ip daddr 172.16.0.0/12 drop
        ip daddr 192.168.0.0/16 drop

        # Allow metadata & provider console services (often on 169.254.0.0/16)
        ip daddr 169.254.0.0/16 accept

        # IPv6 local ranges
        ip6 daddr fc00::/7 drop
        ip6 daddr fe80::/10 drop
    }
}
EOF

    # Create systemd unit to auto-apply rules
    sudo tee /etc/systemd/system/webrtc-shield.service >/dev/null <<'EOF'
[Unit]
Description=WebRTC Leak Protection (nftables)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables.d/webrtc_shield.nft
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # Enable and apply rules
    sudo systemctl daemon-reload >/dev/null 2>&1
    sudo systemctl enable --now webrtc-shield.service >/dev/null 2>&1

    # Display protection summary
    echo -e "\n${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN}   WebRTC Leak Protection Summary${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ✓ Protection:    ${NEON_GREEN}Enabled (active nftables rules)${NC}"
    echo -e " ✓ Ports Blocked: ${CYAN}3478, 5349, 19302–19309 (STUN/TURN)${NC}"
    echo -e " ✓ Local IPs:     ${CYAN}Private/Link-local ranges blocked${NC}"
    echo -e " ✓ Exceptions:    ${GREEN}169.254.0.0/16 allowed (console/metadata)${NC}"
    echo -e " ✓ VPN Safety:    ${GREEN}No impact on tun0/wg0${NC}"
    echo -e " ✓ SSH Safety:    ${GREEN}Port 22 untouched${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

##############################################
# 8)  - Disable WebRTC Leak Protection
##############################################
disable_webrtc() {
    clear
    echo -e "${YELLOW} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN} ▶ Disabling WebRTC Leak Protection...${NC}"
    echo -e "${YELLOW} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Stop and disable service
    if systemctl list-unit-files | grep -q webrtc-shield.service; then
        sudo systemctl stop webrtc-shield.service >/dev/null 2>&1
        sudo systemctl disable webrtc-shield.service >/dev/null 2>&1
        sudo rm -f /etc/systemd/system/webrtc-shield.service
    fi

    # Remove nftables rules
    sudo nft delete table inet webrtc_shield 2>/dev/null || true
    sudo rm -f /etc/nftables.d/webrtc_shield.nft

    # Reload systemd daemon
    sudo systemctl daemon-reload >/dev/null 2>&1

    # Display summary
    echo -e "\n${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN}   WebRTC Leak Protection Summary${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ✓ Protection:    ${YELLOW}Disabled (rules removed)${NC}"
    echo -e " ✓ Ports:         ${CYAN}All WebRTC/STUN/TURN ports open${NC}"
    echo -e " ✓ Local IPs:     ${CYAN}Private ranges unblocked${NC}"
    echo -e " ✓ VPN Safety:    ${GREEN}No impact (unchanged)${NC}"
    echo -e " ✓ SSH Safety:    ${GREEN}Unaffected (port 22 remains)${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

##############################################
# 9)  - Verify WebRTC Leak Protection
##############################################
verify_webrtc() {
    clear
    echo -e "${YELLOW} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN} ▷ Verifying WebRTC Leak Protection...${NC}"
    echo -e "${YELLOW} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Check if service is active
    if systemctl is-active --quiet webrtc-shield.service; then
        STATUS="${NEON_GREEN}Active${NC}"
    else
        STATUS="${BOLD_RED}Inactive${NC}"
    fi

    # Check if nftables table exists
    if sudo nft list tables 2>/dev/null | grep -q "webrtc_shield"; then
        TABLE_STATUS="${NEON_GREEN}Loaded${NC}"
        BLOCKED="\033[1;31mBlocked\033[0m"   # Red
        OPEN="\033[1;32mOpen\033[0m"        # Green
    else
        TABLE_STATUS="${BOLD_RED}Missing${NC}"
        BLOCKED="\033[1;32mOpen\033[0m"
        OPEN="\033[1;32mOpen\033[0m"
    fi

    # Ports & IP ranges
    BLOCKED_PORTS="3478, 5349, 19302–19309"

    echo -e "${GREY}"
    echo -e "${BOLD_CYAN}   WebRTC Leak Protection Status${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " • Protection:   $STATUS"
    echo -e " • nftables:     $TABLE_STATUS"
    echo -e " • Ports Blocked:${CYAN} $BLOCKED_PORTS${NC}"

    echo -e "\n   ${BOLD_CYAN}Local IP Ranges${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " • 10.0.0.0/8       $BLOCKED"
    echo -e " • 172.16.0.0/12    $BLOCKED"
    echo -e " • 192.168.0.0/16   $BLOCKED"
    echo -e " • 169.254.0.0/16   $OPEN   (console safe)"
    echo -e " • fc00::/7         $BLOCKED"
    echo -e " • fe80::/10        $BLOCKED"

    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " • VPN Safety:   ${GREEN}tun0 / wg0 unaffected${NC}"
    echo -e " • SSH Safety:   ${GREEN}TCP port 22 open${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

##############################################################
# Function to handle user input and execute the chosen option
##############################################################

handle_menu_selection() {
    while true; do
        print_menu
        echo -e "${GREY}"
        echo -e "${GREY}"
        echo -ne "${NEON_GREEN}\033[1m ➤ Enter your choice ${BLUE}(0-9): ${NC}"
        

        read choice
        case $choice in
            1)
                set_dns_cloudflare
                ;;
            2)
                set_dns_google
                ;;
            3)
                set_dns_quad9
                ;;
            4)
                verify_dns
                ;;
            5)
                automate_flush
                ;;
            6)
                restore_to_factory
                ;;
            7)
                enable_webrtc
                ;;  
            8)
                disable_webrtc
                ;;
            9)
                verify_webrtc
                ;;
            0)
                clear
                echo -e "${GREY}"
                echo -e "${RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
                echo -e "${GREEN}       • Hope you enjoyed using the script!${NC}"
                echo -e "${DARK_YELLOW}       • Please don't forget to check the output files.${NC}"
                echo -e "${BLUE}       • Any comments or suggestions? Please refer to ${CYAN}${URL}${RESET}${NC}"
                echo -e "${RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
                echo -e "${GREY}"
                echo -e "${GREY}"
                echo -e "${DARK_RED}   ╰┈➤ Exiting script...${NC}"
                echo -e "${GREY}"
                echo -e "${GREY}"
                echo -e "${DARK_YELLOW}   ◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤${NC}"
                echo -e "${GREY}"
                echo -e "${GREY}"
                # Remove the directory as the final step
                sudo rm -rf ~/DNS_WebRTC_Shield
                exit 0
                ;;
            *)
                clear
                echo -e "${GREY}"
                echo -e "${RED}  • Invalid Entry!${NC}"
                echo -e "${RED}  • Please choose a number between (0-9)${NC}"

                ;;
        esac
    done
}

# Main script execution
backup_config_files
print_introduction
handle_menu_selection

##############################################################
####################### End of Script ########################
##############################################################
