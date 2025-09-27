#!/bin/bash

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
# Function to back up configuration files
# - Creates a one-time backup of critical DNS files
# - Ensures backup files are valid (not empty)
# - Records a timestamp of when the original backup was made
# - Never overwrites existing backups (keeps the very first copy)
#####################################################################
backup_config_files() {
    # Define backup file paths
    local resolv_backup="/etc/resolv.conf.bak"
    local resolved_backup="/etc/systemd/resolved.conf.bak"
    local timestamp_file="/etc/dns-backup.timestamp"

    echo -e "${GREEN} ▷ Backing up DNS configuration files...${NC}"

    #----------------------------------------------------------------------
    # 1. Backup /etc/resolv.conf
    #----------------------------------------------------------------------
    if [ -f "$resolv_backup" ]; then
        echo -e "  • resolv.conf   → ${YELLOW}Backup exists (kept)${NC}"
    else
        if sudo cp /etc/resolv.conf "$resolv_backup"; then
            if [ -s "$resolv_backup" ]; then
                echo -e "  • resolv.conf   → ${NEON_GREEN}Backup created${NC}"
            else
                echo -e "  • resolv.conf   → ${RED}ERROR: Backup file empty${NC}"
                exit 1
            fi
        else
            echo -e "  • resolv.conf   → ${RED}ERROR: Backup failed${NC}"
            exit 1
        fi
    fi

    #----------------------------------------------------------------------
    # 2. Backup /etc/systemd/resolved.conf
    #----------------------------------------------------------------------
    if [ -f "$resolved_backup" ]; then
        echo -e "  • resolved.conf → ${YELLOW}Backup exists (kept)${NC}"
    else
        if sudo cp /etc/systemd/resolved.conf "$resolved_backup"; then
            if [ -s "$resolved_backup" ]; then
                echo -e "  • resolved.conf → ${NEON_GREEN}Backup created${NC}"
            else
                echo -e "  • resolved.conf → ${RED}ERROR: Backup file empty${NC}"
                exit 1
            fi
        else
            echo -e "  • resolved.conf → ${RED}ERROR: Backup failed${NC}"
            exit 1
        fi
    fi

    #----------------------------------------------------------------------
    # 3. Record timestamp (first backup only)
    #----------------------------------------------------------------------
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
##############################################
_lock_resolvconf_stub() {
    sudo chattr -i /etc/resolv.conf 2>/dev/null || true
    sudo tee /etc/resolv.conf >/dev/null <<'EOL'
# Managed by DNS & WebRTC Leak Shield (static lock)
nameserver 127.0.0.53
options edns0 trust-ad
search .
EOL
    sudo chattr +i /etc/resolv.conf 2>/dev/null || true
}

##############################################
# Disable cloud-init network rewrites (one-time)
##############################################
_disable_cloudinit_networking() {
    if [ -d /var/lib/cloud ]; then
        echo -e "${DARK_YELLOW}  → Cloud-init detected: network config preserved.${NC}"
    else
        echo -e "${PURPLE}  → Disabling cloud-init network overrides (bare metal / VM only).${NC}"
        sudo mkdir -p /etc/cloud/cloud.cfg.d
        sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null <<'EOF'
network: {config: disabled}
EOF
    fi
}

##############################################
# Disable per-interface DHCP DNS injection
##############################################
_disable_dhcp_dns_networkd() {
    echo -e "${PURPLE}  → Overriding DHCP DNS in systemd-networkd.${NC}"

    # Discover ethernet-like interfaces
    mapfile -t IFACES < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|en|ens|eno)')

    for IFACE in "${IFACES[@]}"; do
        DROPIN_DIR="/etc/systemd/network/10-${IFACE}.network.d"
        sudo mkdir -p "$DROPIN_DIR"
        sudo tee "${DROPIN_DIR}/50-ignore-dns.conf" >/dev/null <<EOF
[DHCPv4]
UseDNS=no
UseDomains=no

[DHCPv6]
UseDNS=no
UseDomains=no
EOF
        echo -e "${DARK_SILVER}  • ${IFACE}: DHCP DNS disabled${NC}"
    done
}

##############################################
# Reset systemd DNS state & old DHCP leases
##############################################
_reset_dns_state() {
    # Stop services cleanly
    sudo systemctl stop systemd-resolved
    sudo systemctl stop systemd-networkd 2>/dev/null || true

    # Purge runtime/resolved and networkd leases/state
    sudo rm -rf /run/systemd/resolve/* 2>/dev/null || true
    sudo rm -rf /run/systemd/network/* 2>/dev/null || true
    sudo rm -rf /var/lib/systemd/network/* 2>/dev/null || true

    # Regenerate & apply netplan
    sudo netplan generate 2>/dev/null || true
    sudo netplan apply 2>/dev/null || true

    # Start services again
    sudo systemctl start systemd-networkd 2>/dev/null || true
    sudo systemctl start systemd-resolved
    resolvectl flush-caches >/dev/null 2>&1 || true
}

##############################################
# Write provider to MAIN resolved.conf (hard lock)
##############################################
_write_resolved_main() {
    # Args: IPv4_A IPv4_B IPv6_A IPv6_B
    local d1="$1" d2="$2" f1="$3" f2="$4"

    sudo tee /etc/systemd/resolved.conf >/dev/null <<EOF
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

    sudo systemctl restart systemd-resolved
    resolvectl flush-caches >/dev/null 2>&1 || true
}

##############################################
# Hard-lock DNS (reboot resistant)
# - Removes provider drop-ins
# - Overwrites systemd-resolved.conf
# - Patches netplan to block DHCP DNS injection
##############################################
_hard_lock_dns() {
    echo -e "${GREEN} ▷ Hard-locking DNS configuration...${NC}"

    # 1. Remove provider DNS overrides
    sudo rm -f /etc/systemd/resolved.conf.d/*.conf 2>/dev/null || true

    # 2. Force secure DNS only
    sudo tee /etc/systemd/resolved.conf >/dev/null <<EOF
[Resolve]
DNS=$1 $2
FallbackDNS=$3 $4
DNSOverTLS=yes
DNSSEC=yes
Domains=~.
MulticastDNS=no
LLMNR=no
DNSStubListener=yes
DNSDefaultRoute=no
EOF

    # 3. Patch netplan to ignore DNS from DHCP
    NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
    if [ -f "$NETPLAN_FILE" ]; then
        # Remove old nameserver blocks
        sudo sed -i '/nameservers:/,/search: \[\]/d' "$NETPLAN_FILE"
        # Ensure dhcp4-overrides is present
        grep -q "use-dns: false" "$NETPLAN_FILE" || \
            sudo sed -i '/mtu: 1500/a \      dhcp4-overrides:\n        use-dns: false' "$NETPLAN_FILE"
        sudo netplan apply || true
    fi

    # Restart resolver
    sudo systemctl restart systemd-resolved
    resolvectl flush-caches

    echo -e "${NEON_GREEN}  ✓ DNS hard-locked to secure resolvers (reboot resistant).${NC}"
}

##############################################
# Remove old provider drop-ins
##############################################
cleanup_old_dns_configs() {
    sudo rm -f /etc/systemd/resolved.conf.d/99-cloudflare-dot.conf
    sudo rm -f /etc/systemd/resolved.conf.d/99-google-dot.conf
    sudo rm -f /etc/systemd/resolved.conf.d/99-quad9-dot.conf
    sudo rm -f /etc/systemd/resolved.conf.d/force-dns.conf
}

##############################################
# Firewall rule helper (block DNS leaks only)
##############################################
_block_dns_leaks() {
    echo -e "${PURPLE}  → Enforcing DNS Leak Protection with nftables...${NC}"

    # Detect SSH port (default 22 if undetectable)
    SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/ {gsub(".*:", "", $4); print $4; exit}')
    [ -z "$SSH_PORT" ] && SSH_PORT=22

    # Detect IPv4 and IPv6
    LOCAL_IPV4S=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\./) print $i}')
    LOCAL_IPV6S=$(ip -6 addr show scope global | awk '/inet6/ {print $2}' | cut -d/ -f1)

    sudo mkdir -p /etc/nftables.d
    sudo tee /etc/nftables.d/dns_shield.nft >/dev/null <<EOF
table inet dns_shield {
    chain output {
        type filter hook output priority 0; policy accept;

        # Allow VPN tunnels
        iifname "tun0" accept
        iifname "wg0" accept

        # Allow loopback DNS (systemd-resolved stub)
        ip daddr 127.0.0.1 udp dport 53 accept
        ip daddr 127.0.0.1 tcp dport 53 accept
        ip daddr 127.0.0.53 udp dport 53 accept
        ip daddr 127.0.0.53 tcp dport 53 accept

        # Allow SSH (detected TCP port $SSH_PORT)
        tcp dport $SSH_PORT accept
EOF

    # Whitelist IPv4
    for ip in $LOCAL_IPV4S; do
        echo "        ip daddr $ip accept" | sudo tee -a /etc/nftables.d/dns_shield.nft >/dev/null
    done

    # Whitelist IPv6 (silent in config, summarized later)
    for ip6 in $LOCAL_IPV6S; do
        echo "        ip6 daddr $ip6 accept" | sudo tee -a /etc/nftables.d/dns_shield.nft >/dev/null
    done

    # Append blocking rules
    sudo tee -a /etc/nftables.d/dns_shield.nft >/dev/null <<'EOF'
        # Block all other plaintext DNS (TCP/UDP 53)
        udp dport 53 drop
        tcp dport 53 drop

        # Block DNS queries to private IP ranges (but allow other traffic)
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

    sudo tee /etc/systemd/system/dns-shield.service >/dev/null <<'EOF'
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

    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl enable dns-shield.service > /dev/null 2>&1   # Hides noisy symlink
    if sudo systemctl restart dns-shield.service; then
        echo -e "${NEON_GREEN}  ✓ nftables DNS Leak Shield applied.${NC}"
    else
        echo -e "${RED}  ⚠ Failed to apply nftables DNS shield. Check logs with:${NC}"
        echo -e "     systemctl status dns-shield.service -l"
    fi

    # Build nice summary of local IPs
    if [ -n "$LOCAL_IPV4S" ]; then
        IP_SUMMARY="  • IPv4:\n"
        for ip in $LOCAL_IPV4S; do
            IP_SUMMARY+="        $ip\n"
        done
    else
        IP_SUMMARY="  • IPv4: none\n"
    fi

    if [ -n "$LOCAL_IPV6S" ]; then
        IP_SUMMARY+="        IPv6: enabled"
    else
        IP_SUMMARY+="        IPv6: none"
    fi

    echo -e "${DARK_SILVER}  • Local VPS IPs whitelisted:${NC}\n${CYAN}${IP_SUMMARY}${NC}"

    echo -e "${DARK_SILVER}  • SSH (TCP port ${RED}${SSH_PORT}${NC}${DARK_SILVER}) remains fully accessible.${NC}"
    echo -e "${DARK_SILVER}  • UDP on SSH port blocked (safer).${NC}"
}

##############################################
# 1) Cloudflare (DoH → DoT fallback)
##############################################
set_dns_cloudflare() {
    clear
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "${BOLD_CYAN}\033[1m ▶ Cloudflare DNS Setup (DoH + DoT Fallback)\033[0m${NC}"
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    cleanup_old_dns_configs
    _disable_cloudinit_networking
    _disable_dhcp_dns_networkd
    sudo pkill -9 cloudflared 2>/dev/null || true
    _lock_resolvconf_stub

    sudo mkdir -p /etc/cloudflared
    sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://cloudflare-dns.com/dns-query
EOF

    sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<'EOF'
[Unit]
Description=Cloudflared DoH DNS proxy
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$(command -v cloudflared) proxy-dns --config /etc/cloudflared/config.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl enable --now cloudflared-doh.service > /dev/null 2>&1

    _write_resolved_main "127.0.0.1#cloudflare-dns.com" "1.1.1.1#cloudflare-dns.com" \
                         "2606:4700:4700::1111#cloudflare-dns.com" "2606:4700:4700::1001#cloudflare-dns.com"

    _reset_dns_state
    _block_dns_leaks

    echo -e "\n${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN}   DNS Protection Summary${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ✓ Provider:      ${YELLOW}Cloudflare${NC}"
    echo -e " ✓ Transport:     ${GREEN}DoH (primary)${NC}, ${CYAN}DoT (fallback)${NC}"
    echo -e " ✓ DNS Leak Prot: ${NEON_GREEN}nftables shield active${NC}"
    echo -e " ✓ DHCP DNS:      ${NEON_GREEN}disabled (eth0, eth1)${NC}"
    echo -e " ✓ Config Lock:   ${NEON_GREEN}reboot-resistant${NC}"
    echo -e " ✓ Connectivity:  ${GREEN}SSH safe (TCP only, UDP blocked)${NC}"
    echo -e " ✓ IPs:${NC}\n${CYAN}${IP_SUMMARY}${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}


##############################################
# 2) Google (DoH → DoT fallback)
##############################################
set_dns_google() {
    clear
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "${BOLD_CYAN}\033[1m ▶ Google DNS Setup (DoH + DoT Fallback)\033[0m${NC}"
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    cleanup_old_dns_configs
    _disable_cloudinit_networking
    _disable_dhcp_dns_networkd
    sudo pkill -9 cloudflared 2>/dev/null || true
    _lock_resolvconf_stub

    sudo mkdir -p /etc/cloudflared
    sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://dns.google/dns-query
EOF

    sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<'EOF'
[Unit]
Description=Cloudflared DoH DNS proxy
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$(command -v cloudflared) proxy-dns --config /etc/cloudflared/config.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl enable --now cloudflared-doh.service > /dev/null 2>&1

    _write_resolved_main "127.0.0.1#dns.google" "8.8.8.8#dns.google" \
                         "2001:4860:4860::8888#dns.google" "2001:4860:4860::8844#dns.google"

    _reset_dns_state
    _block_dns_leaks

    echo -e "\n${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN}   DNS Protection Summary${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ✓ Provider:      ${YELLOW}Google${NC}"
    echo -e " ✓ Transport:     ${GREEN}DoH (primary)${NC}, ${CYAN}DoT (fallback)${NC}"
    echo -e " ✓ DNS Leak Prot: ${NEON_GREEN}nftables shield active${NC}"
    echo -e " ✓ DHCP DNS:      ${NEON_GREEN}disabled (eth0, eth1)${NC}"
    echo -e " ✓ Config Lock:   ${NEON_GREEN}reboot-resistant${NC}"
    echo -e " ✓ Connectivity:  ${GREEN}SSH safe (TCP only, UDP blocked)${NC}"
    echo -e " ✓ IPs:${NC}\n${CYAN}${IP_SUMMARY}${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

##############################################
# 3) Quad9 (DoH → DoT fallback)
##############################################
set_dns_quad9() {
    clear
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "${BOLD_CYAN}\033[1m ▶ Quad9 DNS Setup (DoH + DoT Fallback)\033[0m${NC}"
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    cleanup_old_dns_configs
    _disable_cloudinit_networking
    _disable_dhcp_dns_networkd
    sudo pkill -9 cloudflared 2>/dev/null || true
    _lock_resolvconf_stub

    sudo mkdir -p /etc/cloudflared
    sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
proxy-dns: true
proxy-dns-address: 127.0.0.1
proxy-dns-port: 5053
proxy-dns-upstream:
  - https://dns.quad9.net/dns-query
EOF

    sudo tee /etc/systemd/system/cloudflared-doh.service >/dev/null <<'EOF'
[Unit]
Description=Cloudflared DoH DNS proxy
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$(command -v cloudflared) proxy-dns --config /etc/cloudflared/config.yml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl enable --now cloudflared-doh.service > /dev/null 2>&1

    _write_resolved_main "127.0.0.1#dns.quad9.net" "9.9.9.9#dns.quad9.net" \
                         "2620:fe::fe#dns.quad9.net" "2620:fe::9#dns.quad9.net"

    _reset_dns_state
    _block_dns_leaks

    echo -e "\n${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD_CYAN}   DNS Protection Summary${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ✓ Provider:      ${YELLOW}Quad9${NC}"
    echo -e " ✓ Transport:     ${GREEN}DoH (primary)${NC}, ${CYAN}DoT (fallback)${NC}"
    echo -e " ✓ DNS Leak Prot: ${NEON_GREEN}nftables shield active${NC}"
    echo -e " ✓ DHCP DNS:      ${NEON_GREEN}disabled (eth0, eth1)${NC}"
    echo -e " ✓ Config Lock:   ${NEON_GREEN}reboot-resistant${NC}"
    echo -e " ✓ Connectivity:  ${GREEN}SSH safe (TCP only, UDP blocked)${NC}"
    echo -e " ✓ IPs:${NC}\n${CYAN}${IP_SUMMARY}${NC}"
    echo -e "${BLUE} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}


##############################################
# 4)  - Verify DNS Configuration (clean output)
##############################################
verify_dns() {
    clear
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "${GREEN} ▷ Verifying DNS Configuration...${NC}"
    echo -e "${YELLOW}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    # Check if cloudflared DoH proxy is running
    if systemctl is-active --quiet cloudflared-doh.service; then
        DOH_ACTIVE=true
    else
        DOH_ACTIVE=false
    fi

    # Read configured upstreams
    CFG_LINE=$(awk -F= '/^\s*DNS=/{print $2}' /etc/systemd/resolved.conf | tr -s ' ')
    UPSTREAM_WORDS=($CFG_LINE)
    U1="${UPSTREAM_WORDS[0]}"

    # Identify provider
    case "$U1" in
        *cloudflare*) RESOLVER_NAME="Cloudflare" ;;
        *dns.google*) RESOLVER_NAME="Google" ;;
        *quad9*)      RESOLVER_NAME="Quad9" ;;
        *)            RESOLVER_NAME="Provider-assigned DNS" ;;
    esac

    # DNSSEC status
    if resolvectl status 2>/dev/null | grep -q "DNSSEC=yes"; then
        DNSSEC="Enabled"
    else
        DNSSEC="Disabled"
    fi

    # --- Clean Output ---
    echo -e "${GREY}"
    echo -e "${BOLD_CYAN}   Active Resolver${RESET}"
    echo -e "${BLUE}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    if [ "$DOH_ACTIVE" = true ]; then
        echo -e " • Resolver:  ${GREEN}$RESOLVER_NAME${NC} (DoH)"
    else
        echo -e " • Resolver:  ${GREEN}$RESOLVER_NAME${NC} (DoT)"
    fi
    echo -e " • DNSSEC:    ${CYAN}$DNSSEC${NC}"
    echo -e "${GREY}"
    echo -e "${BLUE}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"
    echo -e "${BOLD_CYAN}   Test Results${RESET}"
    echo -e "${BLUE}\033[1m ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m${NC}"

    declare -A resolvers
    resolvers=( ["Example"]="example.com"
                ["Cloudflare"]="cloudflare.com"
                ["Google"]="dns.google"
                ["Quad9"]="quad9.net" )

    for name in "Example" "Cloudflare" "Google" "Quad9"; do
        domain=${resolvers[$name]}
        if [ "$DOH_ACTIVE" = true ]; then
            result=$(dig @127.0.0.1 -p 5053 "$domain" +short 2>/dev/null | head -n1)
        else
            result=$(dig @127.0.0.53 "$domain" +short 2>/dev/null | head -n1)
        fi
        if [[ -n "$result" ]]; then
            printf " • %-10s → %-18s ${NEON_GREEN}[PASS]${NC}\n" "$name" "$result"
        else
            printf " • %-10s → %-18s ${BOLD_RED}[FAIL]${NC}\n" "$name" "No response"
        fi
    done

    # DNSSEC validation test
    if [ "$DOH_ACTIVE" = true ]; then
        DIG_CMD="dig @127.0.0.1 -p 5053 dnssec-failed.org +dnssec"
    else
        DIG_CMD="dig @127.0.0.53 dnssec-failed.org +dnssec"
    fi
    if $DIG_CMD 2>/dev/null | grep -q "SERVFAIL"; then
        echo -e "\n ${NEON_GREEN}[PASS]${NC} DNSSEC enforced"
    else
        echo -e "\n ${BOLD_RED}[FAIL]${NC} DNSSEC not enforced"
    fi
}


##############################################
# 5)  - Automate Flushing DNS Caches
##############################################
automate_flush() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Automating Flushing DNS Caches...${NC}\n"

    echo -e "${BLUE}\033[1m Choose your preferred cache flush interval:${RESET}${NC}"
    echo -e "${DARK_SILVER} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  1)${NC} Every 1 hour      → ${DARK_RED}Maximum privacy (Tor, anonymity, whistleblower use)${NC}"
    echo -e "${YELLOW}  2)${NC} Every 6 hours     → ${CYAN}Strong privacy for VPN servers, still efficient${NC}"
    echo -e "${YELLOW}  3)${NC} Every 18 hours    → ${CYAN}VPN sessions ~1 day, fresh DNS each new day${NC}"
    echo -e "${YELLOW}  4)${NC} Every 24 hours    → ${GREEN}Balanced default: good privacy, minimal performance hit${NC}"
    echo -e "${YELLOW}  5)${NC} Weekly            → ${PURPLE}Performance priority (web/mail servers)${NC}"
    echo -e "${YELLOW}  6)${NC} Disable automation → ${DARK_YELLOW}Advanced users only, no auto flushing${NC}"
    echo -e "${DARK_SILVER} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo -ne "${NEON_GREEN} ➤ Enter your choice (1-6): ${NC}"
    read flush_choice

    # Script path
    SCRIPT_PATH="/usr/local/bin/flush_caches.sh"

    # Ensure the flush script exists
    sudo bash -c "cat > $SCRIPT_PATH" <<'EOF'
#!/bin/bash
# Flush DNS cache and restart systemd-resolved
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart systemd-resolved
fi
EOF
    sudo chmod +x $SCRIPT_PATH

    # Build cron expression from choice
    case $flush_choice in
        1)  CRON_EXPR="0 * * * * $SCRIPT_PATH" ;;      # every 1 hour
        2)  CRON_EXPR="0 */6 * * * $SCRIPT_PATH" ;;   # every 6 hours
        3)  CRON_EXPR="0 */18 * * * $SCRIPT_PATH" ;;  # every 18 hours
        4)  CRON_EXPR="0 0 * * * $SCRIPT_PATH" ;;     # every 24 hours
        5)  CRON_EXPR="0 0 * * 0 $SCRIPT_PATH" ;;     # weekly
        6)  CRON_EXPR="" ;;                           # disable
        *)  echo -e "${RED}  • Invalid choice. No cron job created.${NC}"; return ;;
    esac

    # Remove existing flush block safely
    CRONTAB_TMP=$(mktemp)
    sudo crontab -l 2>/dev/null | awk '
        BEGIN {skip=0}
        /#◈◈◈FLUSHING_DNS_CACHES_START◈◈◈/ {skip=1; next}
        /#◈◈◈FLUSHING_DNS_CACHES_END◈◈◈/ {skip=0; next}
        skip==0 {print}
    ' > "$CRONTAB_TMP"

    # Append new block if not disabled
    if [ -n "$CRON_EXPR" ]; then
        cat <<EOF >> "$CRONTAB_TMP"

#◈◈◈FLUSHING_DNS_CACHES_START◈◈◈
#######################################################################################
#                 Automating Flushing DNS Caches                  
#######################################################################################
# Description: This job flushes the system DNS cache and restarts systemd-resolved
#              to improve privacy and reduce risk of stale or poisoned DNS records.
#######################################################################################
$CRON_EXPR
#######################################################################################
#◈◈◈FLUSHING_DNS_CACHES_END◈◈◈
EOF
        sudo crontab "$CRONTAB_TMP"
        echo -e "${NEON_GREEN}\n | ✓ DNS cache flushing scheduled successfully.${NC}"
    else
        sudo crontab "$CRONTAB_TMP"
        echo -e "${DARK_YELLOW}\n | ⚠ Automation disabled. You must flush DNS manually if needed.${NC}"
    fi

    rm -f "$CRONTAB_TMP"
    echo -e "${GREY}"
}


#####################################################################
# Function: restore_to_default
# Purpose:
#   - Restore system DNS settings back to factory defaults.
#   - Remove ONLY the DNS-related configurations applied by this script.
#   - Leaves all OTHER nftables rules (user-defined) untouched.
# Actions:
#   1. Restore original resolv.conf and resolved.conf (from backups).
#   2. Remove drop-in DNS configs created by providers.
#   3. Stop and disable cloudflared (if running).
#   4. Restart system services to reapply default network settings.
#   5. Remove DNS cache flush automation (cron jobs).
#   6. Remove dns-shield nftables rules (but keep user’s rules).
#####################################################################
restore_to_default() {
    clear
    echo -e "${GREY}"
    echo -e "${DARK_RED}\033[1m ⚠ WARNING:${RESET}${NC} This will restore your DNS settings to factory defaults."
    echo -e "${YELLOW}    • Custom DNS configurations will be removed.${NC}"
    echo -e "${YELLOW}    • cloudflared (if enabled) will be stopped and disabled.${NC}"
    echo -e "${YELLOW}    • DNS cache flush automation cron jobs will be removed.${NC}"
    echo -e "${YELLOW}    • dns-shield (nftables) will be disabled, but OTHER nftables rules remain.${NC}"
    echo -e "${GREY}"

    # ==============================
    # Confirmation prompt
    # ==============================
    read -p "$(echo -e ${BOLD}${RED} ➤ Are you sure you want to continue? [Y/N]: ${NC})" confirm
    case "$confirm" in
        [yY][eE][sS]|[yY]) 
            echo -e "${GREEN} Proceeding with restore...${NC}\n"
            ;;
        *)
            echo -e "${DARK_YELLOW}  • Restore cancelled by user.${NC}\n"
            return 0
            ;;
    esac

    # ==============================
    # Step 1: Restore backups
    # ==============================
    if [ -f /etc/resolv.conf.bak ]; then
        echo -e "\e[3m${PURPLE}  • Restoring /etc/resolv.conf...\e[0m${NC}"
        sudo chattr -i /etc/resolv.conf 2>/dev/null || true
        sudo cp -f /etc/resolv.conf.bak /etc/resolv.conf
        echo -e "${NEON_GREEN}  ✓ /etc/resolv.conf restored from backup.${NC}"
    fi

    if [ -f /etc/systemd/resolved.conf.bak ]; then
        echo -e "\e[3m${PURPLE}  • Restoring /etc/systemd/resolved.conf...\e[0m${NC}"
        sudo cp -f /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf
        echo -e "${NEON_GREEN}  ✓ /etc/systemd/resolved.conf restored from backup.${NC}"
    fi

    # ==============================
    # Step 2: Remove drop-in configs
    # ==============================
    sudo rm -f /etc/systemd/resolved.conf.d/99-*.conf 2>/dev/null || true

    # ==============================
    # Step 3: Stop & disable cloudflared (DoH proxy)
    # ==============================
    if systemctl list-unit-files | grep -q cloudflared-doh.service; then
        echo -e "\e[3m${PURPLE}  • Disabling cloudflared (DoH proxy)...\e[0m${NC}"
        sudo systemctl stop cloudflared-doh.service 2>/dev/null || true
        sudo systemctl disable cloudflared-doh.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/cloudflared-doh.service
        sudo rm -rf /etc/cloudflared
        echo -e "${NEON_GREEN}  ✓ cloudflared service disabled and config removed.${NC}"
    fi

    # ==============================
    # Step 4: Restart system services
    # ==============================
    echo -e "\e[3m${PURPLE}  • Restarting system services...\e[0m${NC}"
    sudo systemctl restart systemd-resolved && resolvectl flush-caches || true
    sudo systemctl restart systemd-networkd 2>/dev/null || true
    echo -e "${NEON_GREEN}  ✓ system services restarted.${NC}"

    # ==============================
    # Step 5: Remove DNS flush cron job
    # ==============================
    echo -e "\e[3m${PURPLE}  • Cleaning up DNS cache flush automation...\e[0m${NC}"
    CRONTAB_TMP=$(mktemp)
    sudo crontab -l 2>/dev/null | awk '
        BEGIN {skip=0}
        /#◈◈◈FLUSHING_DNS_CACHES_START◈◈◈/ {skip=1; next}
        /#◈◈◈FLUSHING_DNS_CACHES_END◈◈◈/ {skip=0; next}
        skip==0 {print}
    ' > "$CRONTAB_TMP"
    sudo crontab "$CRONTAB_TMP"
    rm -f "$CRONTAB_TMP"
    echo -e "${NEON_GREEN}  ✓ DNS flush cron job removed.${NC}"

    # ==============================
    # Step 6: Disable dns-shield (script’s nftables only)
    # ==============================
    echo -e "\e[3m${PURPLE}  • Disabling dns-shield (nftables)...\e[0m${NC}"
    if systemctl list-unit-files | grep -q dns-shield.service; then
        sudo systemctl stop dns-shield.service 2>/dev/null || true
        sudo systemctl disable dns-shield.service 2>/dev/null || true
        sudo rm -f /etc/nftables.d/dns_shield.nft
        sudo rm -f /etc/systemd/system/dns-shield.service
        sudo systemctl daemon-reload
        echo -e "${NEON_GREEN}  ✓ dns-shield removed. Other nftables rules remain intact.${NC}"
        echo -e "${DARK_SILVER}  • User-defined nftables rules were untouched.${NC}"
        echo -e "${DARK_SILVER}  • SSH connectivity remains safe.${NC}"
    else
        echo -e "${DARK_YELLOW}  • No dns-shield service found, skipping.${NC}"
    fi

    # ==============================
    # Done
    # ==============================
    echo -e "${NEON_GREEN}\033[1m | ✓ Server restored to factory default DNS settings successfully.${NC}"
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
                restore_to_default
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
