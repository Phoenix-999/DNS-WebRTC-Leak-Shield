#!/bin/bash

#******************************************************************#
# Title: DNS & WebRTC Leak Shield
# Description: Prevent DNS & WebRTC Leak in VPS
# Author: Phoenix-999
# Link: github.com/Phoenix-999
# Date: July 21, 2024
#******************************************************************#

###############################
# Define ANSI color codes
###############################

RED='\033[0;31m'
DARK_RED='\033[1;31m'
BOLD_RED="\033[1;31m"
YELLOW='\033[1;33m'
DARK_YELLOW="\033[0;33m"
BLUE='\033[0;34m'
DARK_BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'
GREEN='\033[0;32m'
NEON_GREEN='\033[1;38;5;154m'
PURPLE='\033[0;35m'
GREY='\033[0;37m'
PLAIN='\033[0m'
BOLD="\033[1m"
RESET="\033[0m"
NC='\033[0m'  # No Color

# URL
URL="github.com/Phoenix-999"

##############################################
# Function to back up configuration files
##############################################
backup_config_files() {
    # Define the backup file paths
    local resolv_backup="/etc/resolv.conf.bak"
    local resolved_backup="/etc/systemd/resolved.conf.bak"

    # Check if the backup for resolv.conf exists
    if [ -f "$resolv_backup" ]; then
        # Backup file already exists, skip backup
        :
    else
        # Create backup for /etc/resolv.conf
        sudo cp /etc/resolv.conf "$resolv_backup" > /dev/null 2>&1
    fi

    # Check if the backup for resolved.conf exists
    if [ -f "$resolved_backup" ]; then
        # Backup file already exists, skip backup
        :
    else
        # Create backup for /etc/systemd/resolved.conf
        sudo cp /etc/systemd/resolved.conf "$resolved_backup" > /dev/null 2>&1
    fi
}

# Call the function to perform the backup
backup_config_files

##############################################
# Function to print the introduction message
##############################################

print_introduction() {
    clear
    echo -e "${GREY}"
    echo -e "${PURPLE}╭━━━━━━━━━━━━━━━━━━━━∙⋆⋅⋆∙━━━━━━━━━━━━━━━━━━━╮${NC}"
    echo -e "${BLUE}\033[1m    ✭✭✭✭✭✭ DNS & WebRTC Leak Shield ✭✭✭✭✭✭ \033[0m${NC}"
    echo -e "${PURPLE}╰━━━━━━━━━━━━━━━━━━━━∙⋆⋅⋆∙━━━━━━━━━━━━━━━━━━━╯${NC}"
}

##############################################
# Function to print the menu
##############################################

print_menu() {
    echo -e "${YELLOW}\033[1m ____________________________________________\033[0m${NC}"
    echo -e "${BLUE}"
    echo -e "${BLUE}| 1)  - Set DNS ${DARK_RED}▷${RESET}${BLUE} Cloudflare ${DARK_YELLOW}(Recommended${RESET})"
    echo -e "${BLUE}| 2)  - Set DNS ${DARK_RED}▷${RESET}${BLUE} Google"
    echo -e "${BLUE}| 3)  - Set DNS ${DARK_RED}▷${RESET}${BLUE} Quad9"
    echo -e "${BLUE}| 4)  - Verify DNS Configuration"
    echo -e "${BLUE}| 5)  - Automate Flushing DNS Caches"
    echo -e "${BLUE}| 6)  - Restoring Default Server DNS Settings"
    echo -e "${BLUE}| 7)  - Enable WebRTC Leak Protection"
    echo -e "${BLUE}| 8)  - Disable WebRTC Leak Protection"
    echo -e "${BLUE}"
    echo -e "${DARK_RED}| 0  - Exit"
    echo -e "${YELLOW}\033[1m ____________________________________________\033[0m${NC}"
}

##############################################
# 1)  - Set DNS ▷ Cloudflare (Recommended)
##############################################
set_dns_cloudflare() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Backing up configuration files...${NC}"
    echo -e "${GREEN} ▷ Setting Up Cloudflare DNS...${NC}"
    echo -e "${GREY}"

    # Check if /etc/resolv.conf is immutable
     immutable_set=false
    if sudo lsattr /etc/resolv.conf 2>/dev/null | grep -q 'i-'; then
        immutable_set=true
        echo -e "\e[3m${PURPLE}  • /etc/resolv.conf is immutable. Removing immutable attribute...\e[0m${NC}"
        sudo chattr -i /etc/resolv.conf
    else
        echo -e "\e[3m${PURPLE}  • /etc/resolv.conf is not immutable. Proceeding...\e[0m${NC}"
    fi

    # Flush DNS cache
    sudo resolvectl flush-caches
    sudo systemctl restart systemd-resolved

    # Remove existing /etc/resolv.conf
    sudo rm /etc/resolv.conf

    # Create new /etc/resolv.conf
    sudo tee /etc/resolv.conf > /dev/null <<EOL
# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
# Do not edit.
#
# This file might be symlinked as /etc/resolv.conf. If you're looking at
# /etc/resolv.conf and seeing this text, you have followed the symlink.
#
# This is a dynamic resolv.conf file for connecting local clients to the
# internal DNS stub resolver of systemd-resolved. This file lists all
# configured search domains.
#
# Run "resolvectl status" to see details about the uplink DNS servers
# currently in use.
#
# Third party programs should typically not access this file directly, but only
# through the symlink at /etc/resolv.conf. To manage man:resolv.conf(5) in a
# different way, replace this symlink by a static file or a different symlink.
#
# See man:systemd-resolved.service(8) for details about the supported modes of
# operation for /etc/resolv.conf.

#########################################################
#------Configure to use Cloudflare's DNS server---------# 
#########################################################


# Configuration options for DNS resolution:
options dnssec dnssec-ok edns0 trust-ad rotate no-check-names inet6 timeout 2

# Primary DNS server IP address (Cloudflare DNS)
nameserver 1.0.0.1

# Specify default domain for DNS search (optional)
# search .

#########################################################
#-------------------------END---------------------------# 
#########################################################
EOL

    # Remove existing /etc/systemd/resolved.conf
    sudo rm /etc/systemd/resolved.conf

    # Create new /etc/systemd/resolved.conf
    sudo tee /etc/systemd/resolved.conf > /dev/null <<EOL
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it under the
#  terms of the GNU Lesser General Public License as published by the Free
#  Software Foundation; either version 2.1 of the License, or (at your option)
#  any later version.
#
# Entries in this file show the compile time defaults. Local configuration
# should be created by either modifying this file (or a copy of it placed in
# /etc/ if the original file is shipped in /usr/), or by creating "drop-ins" in
# the /etc/systemd/resolved.conf.d/ directory. The latter is generally
# recommended. Defaults can be restored by simply deleting the main
# configuration file and all drop-ins located in /etc/.
#
# Use 'systemd-analyze cat-config systemd/resolved.conf' to display the full config.
#
# See resolved.conf(5) for details.

[Resolve]

#########################################################
#------Configure to use Cloudflare's DNS server---------# 
#########################################################

DNS=security.cloudflare-dns.com
DNSOverTLS=yes
DNSOverUDP=no
DNSSEC=yes
DNSSECMode=yes
DNSSECValidation=yes
Cache=yes
CacheSize=100M
CacheExpire=7200
CacheFromLocalhost=yes
ReadEtcHosts=yes
LogQueries=yes
QueryTimeout=2
QueryRetries=3
QueryRetryInterval=100

# Additional security features
DNSStubListener=yes
DNSStubListenerAddress=127.0.0.1
DNSStubListenerPort=5533

# Enable DNS encryption with Cloudflare's DNSCrypt
DNSCrypt=yes
DNSCryptProvider=2.dnscrypt-cert.cloudflare.com
DNSCryptResolver=1.1.1.1

# Enable DNS query logging with filtering
LogQueries=yes
LogFormat=json
LogFile=/var/log/dns-queries.log
LogFilter=yes
LogFilterReject=private,rejected,cached,invalid

# Enable DNS caching with aggressive caching
Cache=yes
CacheSize=100M
CacheExpire=7200
CacheFromLocalhost=yes
CacheAggressive=yes

# Enable DNS query rate limiting
RateLimit=yes
RateLimitInterval=1m
RateLimitBurst=100
RateLimitSize=100M

# Additional optimizations
MulticastDNS=yes
LLMNR=yes
DNSPriority=strict

#########################################################
#-------------------------END---------------------------# 
#########################################################
EOL

    # Restart systemd-resolved
    echo -e "\e[3m${PURPLE}  • Restarting systemd-resolved...\e[0m${NC}"
    sudo systemctl restart systemd-resolved

 # Set /etc/resolv.conf as immutable if it was initially set
    if [ "$immutable_set" = true ]; then
        echo -e "\e[3m${PURPLE}  • Setting /etc/resolv.conf as immutable...\e[0m${NC}"
        sudo chattr +i /etc/resolv.conf
    fi

    # Enable and restart systemd-networkd
    echo -e "\e[3m${PURPLE}  • Enabling and restarting systemd-networkd...\e[0m${NC}"
    sudo systemctl enable systemd-resolved
    sudo systemctl restart systemd-networkd

    echo -e "${GREY}"
    echo -e "${NEON_GREEN}\033[1m | ✓ Cloudflare's DNS Configuration Update Completed Successfully${NC}"
    echo -e "${GREY}"
}

##############################################
# 2)  - Set DNS ▷ Google
##############################################

set_dns_google() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Backing up configuration files...${NC}"
    echo -e "${GREEN} ▷ Setting Up Google DNS...${NC}"
    echo -e "${GREY}"

     # Check if /etc/resolv.conf is immutable
    immutable_set=false
    if sudo lsattr /etc/resolv.conf 2>/dev/null | grep -q 'i-'; then
        immutable_set=true
        echo -e "\e[3m${PURPLE}  • /etc/resolv.conf is immutable. Removing immutable attribute...\e[0m${NC}"
        sudo chattr -i /etc/resolv.conf
    else
        echo -e "\e[3m${PURPLE}  • /etc/resolv.conf is not immutable. Proceeding...\e[0m${NC}"
    fi


    # Flush DNS cache
    sudo resolvectl flush-caches
    sudo systemctl restart systemd-resolved

    # Remove existing /etc/resolv.conf
    sudo rm /etc/resolv.conf

    # Create new /etc/resolv.conf
    sudo tee /etc/resolv.conf > /dev/null <<EOL
# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
# Do not edit.
#
# This file might be symlinked as /etc/resolv.conf. If you're looking at
# /etc/resolv.conf and seeing this text, you have followed the symlink.
#
# This is a dynamic resolv.conf file for connecting local clients to the
# internal DNS stub resolver of systemd-resolved. This file lists all
# configured search domains.
#
# Run "resolvectl status" to see details about the uplink DNS servers
# currently in use.
#
# Third party programs should typically not access this file directly, but only
# through the symlink at /etc/resolv.conf. To manage man:resolv.conf(5) in a
# different way, replace this symlink by a static file or a different symlink.
#
# See man:systemd-resolved.service(8) for details about the supported modes of
# operation for /etc/resolv.conf.

#########################################################
#------Configure to use Google's DNS server-------------# 
#########################################################


# Configuration options for DNS resolution:
options dnssec dnssec-ok edns0 trust-ad rotate no-check-names inet6 timeout 2

# Primary DNS server IP address (Google DNS)
nameserver 8.8.8.8
nameserver 8.8.4.4

# Specify default domain for DNS search (optional)
# search .

#########################################################
#-------------------------END---------------------------# 
#########################################################
EOL

    # Remove existing /etc/systemd/resolved.conf
    sudo rm /etc/systemd/resolved.conf

    # Create new /etc/systemd/resolved.conf
    sudo tee /etc/systemd/resolved.conf > /dev/null <<EOL
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it under the
#  terms of the GNU Lesser General Public License as published by the Free
#  Software Foundation; either version 2.1 of the License, or (at your option)
#  any later version.
#
# Entries in this file show the compile time defaults. Local configuration
# should be created by either modifying this file (or a copy of it placed in
# /etc/ if the original file is shipped in /usr/), or by creating "drop-ins" in
# the /etc/systemd/resolved.conf.d/ directory. The latter is generally
# recommended. Defaults can be restored by simply deleting the main
# configuration file and all drop-ins located in /etc/.
#
# Use 'systemd-analyze cat-config systemd/resolved.conf' to display the full config.
#
# See resolved.conf(5) for details.

[Resolve]

#########################################################
#------Configure to use Google's DNS server--------------#
#########################################################

DNS=8.8.8.8 8.8.4.4
DNSOverTLS=yes
DNSOverUDP=no
DNSSEC=yes
DNSSECMode=yes
DNSSECValidation=yes
Cache=yes
CacheSize=100M
CacheExpire=7200
CacheFromLocalhost=yes
ReadEtcHosts=yes
LogQueries=yes
QueryTimeout=2
QueryRetries=3
QueryRetryInterval=100

# Additional security features
DNSStubListener=yes
DNSStubListenerAddress=127.0.0.1
DNSStubListenerPort=5533

# Enable DNS encryption with Google's DNSCrypt
# Note: DNSCrypt is not natively supported by systemd-resolved
# You would need a separate DNSCrypt proxy for this functionality
# DNSCrypt=yes
# DNSCryptProvider=2.dnscrypt-cert.dns.google
# DNSCryptResolver=8.8.8.8

# Enable DNS query logging with filtering
LogQueries=yes
LogFormat=json
LogFile=/var/log/dns-queries.log
LogFilter=yes
LogFilterReject=private,rejected,cached,invalid

# Enable DNS caching with aggressive caching
Cache=yes
CacheSize=100M
CacheExpire=7200
CacheFromLocalhost=yes
CacheAggressive=yes

# Enable DNS query rate limiting
RateLimit=yes
RateLimitInterval=1m
RateLimitBurst=100
RateLimitSize=100M

# Additional optimizations
MulticastDNS=yes
LLMNR=yes
DNSPriority=strict

#########################################################
#-------------------------END---------------------------# 
#########################################################
EOL

    # Restart systemd-resolved
    echo -e "\e[3m${PURPLE}  • Restarting systemd-resolved...\e[0m${NC}"
    sudo systemctl restart systemd-resolved

    # Set /etc/resolv.conf as immutable
    echo -e "\e[3m${PURPLE}  • Setting /etc/resolv.conf as immutable...\e[0m${NC}"
    sudo chattr +i /etc/resolv.conf

    # Enable and restart systemd-networkd
    echo -e "\e[3m${PURPLE}  • Enabling and restarting systemd-networkd...\e[0m${NC}"
    sudo systemctl enable systemd-resolved
    sudo systemctl restart systemd-networkd

    echo -e "${GREY}"
    echo -e "${NEON_GREEN}\033[1m | ✓ Google DNS Configuration Update Completed Successfully${NC}"
    echo -e "${GREY}"
    echo -e "${BLUE}\033[1m ____________________________________________\033[0m${NC}"
}

##############################################
# 3)  - Set DNS ▷ Quad9
##############################################

set_dns_quad9() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Backing up configuration files...${NC}"
    echo -e "${GREEN} ▷ Setting Up Quad9 DNS...${NC}"
    echo -e "${GREY}"

    # Check if /etc/resolv.conf is immutable
    immutable_set=false
    if sudo lsattr /etc/resolv.conf 2>/dev/null | grep -q 'i-'; then
        immutable_set=true
        echo -e "\e[3m${PURPLE}  • /etc/resolv.conf is immutable. Removing immutable attribute...\e[0m${NC}"
        sudo chattr -i /etc/resolv.conf
    else
        echo -e "\e[3m${PURPLE}  • /etc/resolv.conf is not immutable. Proceeding...\e[0m${NC}"
    fi

    # Flush DNS cache
    sudo resolvectl flush-caches
    sudo systemctl restart systemd-resolved

    # Remove existing /etc/resolv.conf
    sudo rm /etc/resolv.conf

    # Create new /etc/resolv.conf
    sudo tee /etc/resolv.conf > /dev/null <<EOL
# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
# Do not edit.
#
# This file might be symlinked as /etc/resolv.conf. If you're looking at
# /etc/resolv.conf and seeing this text, you have followed the symlink.
#
# This is a dynamic resolv.conf file for connecting local clients to the
# internal DNS stub resolver of systemd-resolved. This file lists all
# configured search domains.
#
# Run "resolvectl status" to see details about the uplink DNS servers
# currently in use.
#
# Third party programs should typically not access this file directly, but only
# through the symlink at /etc/resolv.conf. To manage man:resolv.conf(5) in a
# different way, replace this symlink by a static file or a different symlink.
#
# See man:systemd-resolved.service(8) for details about the supported modes of
# operation for /etc/resolv.conf.

#########################################################
#------Configure to use Quad9's DNS server--------------# 
#########################################################

# Configuration options for DNS resolution:
options dnssec dnssec-ok edns0 trust-ad rotate no-check-names inet6 timeout 2

# Primary DNS server IP address (Quad9 DNS)
nameserver 9.9.9.9
nameserver 149.112.112.112

# Specify default domain for DNS search (optional)
# search .

#########################################################
#-------------------------END---------------------------# 
#########################################################
EOL

    # Remove existing /etc/systemd/resolved.conf
    sudo rm /etc/systemd/resolved.conf

    # Create new /etc/systemd/resolved.conf
    sudo tee /etc/systemd/resolved.conf > /dev/null <<EOL
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it under the
#  terms of the GNU Lesser General Public License as published by the Free
#  Software Foundation; either version 2.1 of the License, or (at your option)
#  any later version.
#
# Entries in this file show the compile time defaults. Local configuration
# should be created by either modifying this file (or a copy of it placed in
# /etc/ if the original file is shipped in /usr/), or by creating "drop-ins" in
# the /etc/systemd/resolved.conf.d/ directory. The latter is generally
# recommended. Defaults can be restored by simply deleting the main
# configuration file and all drop-ins located in /etc/.
#
# Use 'systemd-analyze cat-config systemd/resolved.conf' to display the full config.
#
# See resolved.conf(5) for details.

[Resolve]

#########################################################
#------Configure to use Quad9's DNS server--------------#
#########################################################

DNS=9.9.9.9 149.112.112.112
DNSOverTLS=yes
DNSOverUDP=no
DNSSEC=yes
DNSSECMode=yes
DNSSECValidation=yes
Cache=yes
CacheSize=100M
CacheExpire=7200
CacheFromLocalhost=yes
ReadEtcHosts=yes
LogQueries=yes
QueryTimeout=2
QueryRetries=3
QueryRetryInterval=100

# Additional security features
DNSStubListener=yes
DNSStubListenerAddress=127.0.0.1
DNSStubListenerPort=5533

# Enable DNS encryption with Quad9's DNSCrypt
# Note: DNSCrypt is not natively supported by systemd-resolved
# You would need a separate DNSCrypt proxy for this functionality
# DNSCrypt=yes
# DNSCryptProvider=2.dnscrypt-cert.quad9.net
# DNSCryptResolver=9.9.9.9

# Enable DNS query logging with filtering
LogQueries=yes
LogFormat=json
LogFile=/var/log/dns-queries.log
LogFilter=yes
LogFilterReject=private,rejected,cached,invalid

# Enable DNS caching with aggressive caching
Cache=yes
CacheSize=100M
CacheExpire=7200
CacheFromLocalhost=yes
CacheAggressive=yes

# Enable DNS query rate limiting
RateLimit=yes
RateLimitInterval=1m
RateLimitBurst=100
RateLimitSize=100M

# Additional optimizations
MulticastDNS=yes
LLMNR=yes
DNSPriority=strict

#########################################################
#-------------------------END---------------------------# 
#########################################################
EOL

    # Restart systemd-resolved
    echo -e "\e[3m${PURPLE}  • Restarting systemd-resolved...\e[0m${NC}"
    sudo systemctl restart systemd-resolved

    # Set /etc/resolv.conf as immutable
    echo -e "\e[3m${PURPLE}  • Setting /etc/resolv.conf as immutable...\e[0m${NC}"
    sudo chattr +i /etc/resolv.conf

    # Enable and restart systemd-networkd
    echo -e "\e[3m${PURPLE}  • Enabling and restarting systemd-networkd...\e[0m${NC}"
    sudo systemctl enable systemd-resolved
    sudo systemctl restart systemd-networkd

    echo -e "${GREY}"
    echo -e "${NEON_GREEN}\033[1m | ✓ Quad9's DNS Configuration Update Completed Successfully${NC}"
    echo -e "${GREY}"
    echo -e "${BLUE}\033[1m ____________________________________________\033[0m${NC}"
}


##############################################
# 4)  - Verify DNS Configuration
##############################################

verify_dns() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Verifying DNS Configuration...${NC}"

    # Define domains to test
    domains=("example.com" "google.com" "cloudflare.com" "quad9.net")

    # Print table header with proper alignment
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────${NC}"
    printf "${BOLD_CYAN}%-25s %-20s %-20s${NC}\n" "Domain" "DNS Server Used" "Resolved IP Address"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────${NC}"

    for domain in "${domains[@]}"; do
        nslookup_output=$(nslookup "$domain" 2>&1)
        nslookup_status=$?

        if [ $nslookup_status -ne 0 ]; then
            dns_server="Error"
            resolved_ip="Error"
        else
            # Extract the DNS server IP used
            dns_server=$(echo "$nslookup_output" | grep 'Server:' | awk '{print $2}')
            if [ -z "$dns_server" ]; then
                dns_server="Not available"
            fi

            # Extract the resolved IP address
            resolved_ip=$(echo "$nslookup_output" | grep 'Address:' | tail -n 1 | awk '{print $2}')
            if [ -z "$resolved_ip" ]; then
                resolved_ip="Not available"
            fi
        fi
        
        # Print results in a table format with colors
        printf "${GREEN}%-25s${NC} ${DARK_RED}%-20s${NC} ${DARK_YELLOW}%-20s${NC}\n" "${domain}" "${dns_server}" "${resolved_ip}"
    done
    
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${NEON_GREEN} | ✓ DNS Resolution Results, Successfully Completed.${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${GREY}"
}

##############################################
# 5)  - Automate Flushing DNS Caches
##############################################

automate_flush() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Automating Flushing DNS Caches...${NC}"
    
    # Create and edit the script file
    sudo bash -c 'cat > /usr/local/bin/flush_caches.sh << "EOF"
#!/bin/bash

INTERVAL=86400  # 24 hours in seconds
TIMESTAMP_FILE="/var/tmp/flush_caches.timestamp"

# Function to check if a command exists
command_exists() {
    which "$1" >/dev/null 2>&1
}

# Ensure necessary commands are available
if ! command_exists resolvectl; then
    echo -e "${RED}  • ERROR: 'resolvectl' command is not available.${NC}"
    exit 1
fi
if ! command_exists systemctl; then
    echo -e "${RED}  • ERROR: 'systemctl' command is not available.${NC}"
    exit 1
fi

# Determine the last run time
if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_RUN=$(cat "$TIMESTAMP_FILE")
else
    LAST_RUN=0
fi

CURRENT_TIME=$(date +%s)

# Execute commands if interval has passed
if (( CURRENT_TIME - LAST_RUN >= INTERVAL )); then
    if sudo resolvectl flush-caches && sudo systemctl restart systemd-resolved; then
        echo -e "${GREEN}  • Successfully flushed DNS caches and restarted systemd-resolved.${NC}"
        echo -e "${GREEN}  • $CURRENT_TIME > "$TIMESTAMP_FILE"${NC}"
    else
        echo -e "${RED}  • ERROR: Failed to flush DNS caches or restart systemd-resolved.${NC}"
    fi
else

    echo -e "${DARK_YELLOW}  • Attention: Not enough time has passed since the last run.${NC}"
fi
EOF'

    # Make the script executable
    sudo chmod +x /usr/local/bin/flush_caches.sh

    # Save the current crontab to a variable
    CURRENT_CRONTAB=$(sudo crontab -l 2>/dev/null)

    # Define the new lines to be added
    NEW_CRON_JOBS=$(cat <<EOF

#########################################################
#------------Automating Flushing DNS Caches-------------#
#########################################################

0 * * * * /usr/local/bin/flush_caches.sh
@reboot /usr/local/bin/flush_caches.sh

#########################################################
#-------------------------END---------------------------#
#########################################################
EOF
)

    # Check if the new cron jobs are already present
    if ! echo "$CURRENT_CRONTAB" | grep -q '/usr/local/bin/flush_caches.sh'; then
        # Append new cron jobs to the end of the existing ones
        echo "$CURRENT_CRONTAB$NEW_CRON_JOBS" | sudo crontab - > /dev/null 2>&1
    fi

    # Flush DNS cache immediately
    sudo resolvectl flush-caches
    sudo systemctl restart systemd-resolved
    echo -e "${GREY}"
    echo -e "${NEON_GREEN} | ✓ DNS cache flushing automation set up successfully.${NC}"
    echo -e "${GREY}"
}

##############################################
# 6)  - Restoring Default Server Settings
##############################################

restor_to_default() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Restoring Default Server Settings...${NC}"
    echo -e "${GREY}"

    # Check if sudo is available
    if ! command -v sudo &> /dev/null; then
        echo -e "${RED}  • ERROR: sudo is not installed or not found in PATH.${NC}"
        return
    fi

    # Check if backup files exist
    if [ ! -f /etc/resolv.conf.bak ] || [ ! -f /etc/systemd/resolved.conf.bak ]; then
        echo -e "${RED}  • ERROR: Backup files do not exist. Cannot restore default settings.${NC}"
        return
    fi

    # Remove immutable attribute and restore default settings
    echo -e "\e[3m${PURPLE}  • Restoring /etc/resolv.conf...\e[0m${NC}"
    if sudo chattr -i /etc/resolv.conf && sudo cp /etc/resolv.conf.bak /etc/resolv.conf; then
        echo -e "${PURPLE}  • /etc/resolv.conf restored successfully.${NC}"
    else
        echo -e "${RED}  • Failed to restore /etc/resolv.conf.${NC}"
        return
    fi

    echo -e "\e[3m${PURPLE}  • Restoring /etc/systemd/resolved.conf...\e[0m${NC}"
    if sudo cp /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf; then
        echo -e "${PURPLE}  • /etc/systemd/resolved.conf restored successfully.${NC}"
    else
        echo -e "${RED}  • Failed to restore /etc/systemd/resolved.conf.${NC}"
        return
    fi

    # Reload systemd and restart services
    echo -e "\e[3m${PURPLE}  • Restarting systemd-resolved...\e[0m${NC}"
    if sudo systemctl restart systemd-resolved; then
        echo -e "${PURPLE}  • Systemd-resolved restarted successfully.${NC}"
    else
        echo -e "${RED}  • Failed to restart systemd-resolved. Check status and logs for details.${NC}"
        systemctl status systemd-resolved.service
        journalctl -xeu systemd-resolved.service
        return
    fi

    echo -e "\e[3m${PURPLE}  • Enabling and restarting systemd-networkd...\e[0m${NC}"
    enable_output=$(sudo systemctl enable systemd-networkd --quiet 2>&1)
    if sudo systemctl restart systemd-networkd; then
        echo -e "${PURPLE}  • Systemd-networkd restarted successfully.${NC}"
    else
        echo -e "${RED}  • Failed to restart systemd-networkd.${NC}"
        systemctl status systemd-networkd.service
        journalctl -xeu systemd-networkd.service
        return
    fi

    # Print enable output if it contains any messages
    if [ -n "$enable_output" ]; then
        echo -e "${GREEN}${enable_output}${NC}"
    fi

    # Clean up DNS cache flushing automation
    echo -e "\e[3m${PURPLE}  • Removing DNS cache flushing automation...\e[0m${NC}"

    # Remove the DNS cache flushing script
    if sudo rm -f /usr/local/bin/flush_caches.sh; then
        echo -e "${PURPLE}  • Flushing DNS caches script removed successfully.${NC}"
    else
        echo -e "${RED}  • Failed to remove flushing DNS caches script.${NC}"
    fi

    # Remove cron job entries including comment blocks
    CRONTAB_TMP=$(mktemp)
    sudo crontab -l 2>/dev/null | \
    awk '!/#########################################################/ {print}' | \
    awk '!/Automating Flushing DNS Caches/ {print}' | \
    awk '!/0 \* \* \* \* \/usr\/local\/bin\/flush_caches.sh/ {print}' | \
    awk '!/@reboot \/usr\/local\/bin\/flush_caches.sh/ {print}' | \
    awk '!/-------------------------END---------------------------#/ {print}' > "$CRONTAB_TMP"
    if sudo crontab "$CRONTAB_TMP"; then
        echo -e "${PURPLE}  • Cron job entries for DNS cache flushing and comments removed successfully.${NC}"
    else
        echo -e "${RED}  • Failed to remove cron job entries.${NC}"
    fi
    rm -f "$CRONTAB_TMP"

    echo -e "${GREY}"
    echo -e "${NEON_GREEN}\033[1m | ✓ Server Restored to Factory Default Settings Successfully${NC}"
    echo -e "${GREY}"
    echo -e "${BLUE}\033[1m ____________________________________________\033[0m${NC}"
}

############################################
# 7)  - Enable WebRTC Leak Protection
############################################
enable_webrtc() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ WebRTC Leak Protection Setup...${NC}"
    echo -e "${GREY}"

    # Function to display a progress bar on a single line
    show_progress() {
    local PROGRESS=$1
    local TOTAL=$2
    local WIDTH=30
    local PERCENT=$((PROGRESS * 100 / TOTAL))
    local FILLED=$((PERCENT * WIDTH / 100))
    local EMPTY=$((WIDTH - FILLED))

    # Use block characters for the progress bar
    local BOX_FILL="*"
    local BOX_EMPTY=""

    # Print the progress bar
   printf "\r  • [${GREEN}%${FILLED}s${RESET}${BOX_EMPTY}%${EMPTY}s] %d%%" "$(printf "%${FILLED}s" | tr ' ' "$BOX_FILL")" "$(printf "%${EMPTY}s")" $PERCENT
}

    # Function to install a package and suppress output
    ensure_package() {
        local PACKAGE=$1
        if ! dpkg -l | grep -q "$PACKAGE"; then
            echo -e "\e[3m${PURPLE}  • Installing $PACKAGE...\e[0m${NC}"
            # Simulate progress bar for package installation
            for i in $(seq 1 100); do
                show_progress $i 100
                sleep 0.05  # Simulate time delay for installation
            done
            echo -e "\r\e[3m${GREEN}  • $PACKAGE installed successfully.\e[0m${NC}"
        fi
    }

    # Suppress output from apt-get update
    echo -e "\e[3m${PURPLE}  • Updating package list...\e[0m${NC}"
    echo -e "\e[3m${PURPLE}  • Installation is in Progress\e[0m${NC}"

    # Simulate progress bar for update
    for i in $(seq 1 100); do
        show_progress $i 100
        sleep 0.01  # Simulate time delay for update
    done
    echo -e "\n\e[3m${PURPLE}  • Package list updated.\e[0m${NC}"

    # Suppress output from UFW commands
    echo -e "\e[3m${PURPLE}  • Ensuring essential packages are installed...\e[0m${NC}"
    ensure_package "ufw"
    ensure_package "iptables"

    # Check UFW status and handle accordingly
    if ! sudo ufw status | grep -q "Status: active"; then
        echo -e "\e[3m${PURPLE}  • Enabling UFW...\e[0m${NC}"
        if sudo ufw --force enable &> /dev/null; then
            echo -e "\e[3m${GREEN}  • UFW enabled successfully.\e[0m${NC}"
        else
            echo -e "\e[3m${RED}  • Failed to enable UFW.\e[0m${NC}" >&2
        fi
    fi

    echo -e "\e[3m${PURPLE}  • Setting default UFW policies...\e[0m${NC}"
    sudo ufw default deny incoming &> /dev/null
    sudo ufw default allow outgoing &> /dev/null

    echo -e "\e[3m${PURPLE}  • Allowing SSH through UFW...\e[0m${NC}"
    sudo ufw allow ssh &> /dev/null

    echo -e "\e[3m${PURPLE}  • Blocking WebRTC ports via UFW...\e[0m${NC}"
    sudo ufw deny out proto tcp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null
    sudo ufw deny in proto tcp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null
    sudo ufw deny out proto udp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null
    sudo ufw deny in proto udp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null

    IPTABLES_SCRIPT="/etc/iptables/iptables-rules.sh"
    echo -e "\e[3m${PURPLE}  • Creating iptables rules script...\e[0m${NC}"
    sudo mkdir -p /etc/iptables
    cat << 'EOF' | sudo tee $IPTABLES_SCRIPT > /dev/null
#!/bin/bash

# Block a range of ports (10000-20000) for TCP
iptables -A OUTPUT -p tcp --dport 10000:20000 -j REJECT

# Block specific UDP ports
iptables -A OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT
ip6tables -A OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT

# Block local IP ranges (to prevent WebRTC local IP leaks)
iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
iptables -A OUTPUT -d 169.254.0.0/16 -j DROP
EOF
    sudo chmod +x $IPTABLES_SCRIPT

    SYSTEMD_SERVICE="/etc/systemd/system/iptables-rules.service"
    echo -e "\e[3m${PURPLE}  • Creating systemd service for iptables rules...\e[0m${NC}"
    cat << 'EOF' | sudo tee $SYSTEMD_SERVICE > /dev/null
[Unit]
Description=Apply iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/iptables-rules.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\e[3m${PURPLE}  • Enabling and starting iptables-rules service...\e[0m${NC}"
    sudo systemctl enable iptables-rules.service &> /dev/null
    sudo systemctl start iptables-rules.service &> /dev/null

    echo -e "\e[3m${PURPLE}  • Reloading UFW to apply changes...\e[0m${NC}"
    sudo ufw reload &> /dev/null

    echo -e "${GREY}"
    echo -e "${NEON_GREEN} | ✓ WebRTC Leak Protection has been successfully applied.${NC}"
    echo -e "${GREY}"

    # Print summary tables
    echo -e "\n${DARK_BLUE}\033[1m| ✓ Local IP Ranges Blocked${RESET}"
    echo -e "+-----------------------+------------+--------------+"
    echo -e "| ${CYAN}Port No${RESET}               | ${CYAN}Blocked By${RESET} |    ${CYAN}Status${RESET}    |"
    echo -e "+-----------------------+------------+--------------+"
    echo -e "| ${YELLOW}10.0.0.0/8${RESET}            | IPTables   |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}172.16.0.0/12${RESET}         | IPTables   |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}192.168.0.0/16${RESET}        | IPTables   |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}169.254.0.0/16${RESET}        | IPTables   |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "+-----------------------+------------+--------------+"

    echo -e "${GREY}"

    echo -e "\n${DARK_BLUE}\033[1m| ✓ Blocked UDP Ports${RESET}"
    echo -e "+----------+------------------+---------------------+"
    echo -e "| ${CYAN}Port No${RESET}   |   ${CYAN}Blocked By${RESET}    |       ${CYAN}Status${RESET}        |"
    echo -e "+----------+------------------+---------------------+"
    echo -e "| ${YELLOW}3478${RESET}      | UFW, IPTables   |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "| ${YELLOW}5349${RESET}      | UFW, IPTables   |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "| ${YELLOW}19302${RESET}     | UFW, IPTables   |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "| ${YELLOW}19305${RESET}     | UFW             |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "| ${YELLOW}3479${RESET}      | UFW             |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "| ${YELLOW}5348${RESET}      | UFW             |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "| ${YELLOW}19306${RESET}     | UFW             |       ${DARK_RED}Blocked${RESET}       |"
    echo -e "+----------+------------------+---------------------+"

    echo -e "${GREY}"

    echo -e "\n${DARK_BLUE}\033[1m| ✓ Blocked TCP and UDP Ports via UFW${RESET}"
    echo -e "+---------+-------------+------------+--------------+"
    echo -e "| ${CYAN}Port No${RESET} |  ${CYAN}Protocol${RESET}   | ${CYAN}Blocked By${RESET} |    ${CYAN}Status${RESET}    |"
    echo -e "+---------+-------------+------------+--------------+"
    echo -e "| ${YELLOW}3478${RESET}    | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}5349${RESET}    | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}19302${RESET}   | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}19305${RESET}   | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}3479${RESET}    | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}5348${RESET}    | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "| ${YELLOW}19306${RESET}   | TCP, UDP    | UFW        |    ${DARK_RED}Blocked${RESET}   |"
    echo -e "+---------+-------------+------------+--------------+"

    echo -e "${GREY}"
}

############################################
# 8)  - Disable WebRTC Leak Protection
############################################

disable_webrtc() {
    clear
    echo -e "${GREY}"
    echo -e "${GREEN} ▷ Disabling WebRTC Leak Protection...${NC}"
    echo -e "${GREY}"

    # Remove iptables rules and systemd service
    IPTABLES_SCRIPT="/etc/iptables/iptables-rules.sh"
    SYSTEMD_SERVICE="/etc/systemd/system/iptables-rules.service"

    echo -e "\e[3m${PURPLE}  • Disabling and removing iptables-rules service...\e[0m${NC}"
    if sudo systemctl is-active --quiet iptables-rules.service; then
        sudo systemctl stop iptables-rules.service &> /dev/null
    fi
    sudo systemctl disable iptables-rules.service &> /dev/null
    sudo rm -f "$SYSTEMD_SERVICE"

    echo -e "\e[3m${PURPLE}  • Removing iptables rules script...\e[0m${NC}"
    sudo rm -f "$IPTABLES_SCRIPT"

    # Restore UFW rules
    echo -e "\e[3m${PURPLE}  • Restoring UFW rules...\e[0m${NC}"
    
    # Allow previously blocked ports
    echo -e "\e[3m${PURPLE}  • Allowing WebRTC-related ports...\e[0m${NC}"
    sudo ufw allow out proto tcp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null
    sudo ufw allow in proto tcp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null
    sudo ufw allow out proto udp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null
    sudo ufw allow in proto udp from any to any port 3478,5349,19302,19305,3479,5348,19306 &> /dev/null

    # Remove iptables rules
    echo -e "\e[3m${PURPLE}  • Removing specific iptables rules...\e[0m${NC}"
    sudo iptables -D OUTPUT -d 10.0.0.0/8 -j DROP 2> /dev/null
    sudo iptables -D OUTPUT -d 172.16.0.0/12 -j DROP 2> /dev/null
    sudo iptables -D OUTPUT -d 192.168.0.0/16 -j DROP 2> /dev/null
    sudo iptables -D OUTPUT -d 169.254.0.0/16 -j DROP 2> /dev/null
    sudo iptables -D OUTPUT -p tcp --dport 10000:20000 -j REJECT 2> /dev/null
    sudo iptables -D OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT 2> /dev/null
    sudo ip6tables -D OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT 2> /dev/null

    # Reload UFW to apply changes
    echo -e "\e[3m${PURPLE}  • Reloading UFW to apply changes...\e[0m${NC}"
    sudo ufw reload &> /dev/null

    # Print summary tables
    echo -e "${GREY}"
    
    # Ports Reverted
    echo -e "\n${DARK_BLUE}\033[1m| ✓ Restored Local IP Ranges${RESET}"
    echo -e "+-----------------------+------------+--------------+"
    echo -e "| ${CYAN}IP Range${RESET}              | ${CYAN}Blocked By${RESET} |    ${CYAN}Status${RESET}    |"
    echo -e "+-----------------------+------------+--------------+"
    echo -e "| ${YELLOW}10.0.0.0/8${RESET}            | IPTables   |     ${GREEN}Open${RESET}     |"
    echo -e "| ${YELLOW}172.16.0.0/12${RESET}         | IPTables   |     ${GREEN}Open${RESET}     |"
    echo -e "| ${YELLOW}192.168.0.0/16${RESET}        | IPTables   |     ${GREEN}Open${RESET}     |"
    echo -e "| ${YELLOW}169.254.0.0/16${RESET}        | IPTables   |     ${GREEN}Open${RESET}     |"
    echo -e "+-----------------------+------------+--------------+"

    echo -e "${GREY}"

    echo -e "\n${DARK_BLUE}\033[1m| ✓ Restored UDP Ports${RESET}"
    echo -e  "+----------+------------------+---------------------+"
    echo -e "| ${CYAN}Port No${RESET}   |   ${CYAN}Blocked By${RESET}    |       ${CYAN}Status${RESET}        |"
    echo -e  "+----------+------------------+---------------------+"
    echo -e "| ${YELLOW}3478${RESET}      | UFW, IPTables   |         ${GREEN}Open${RESET}       |"
    echo -e "| ${YELLOW}5349${RESET}      | UFW, IPTables   |         ${GREEN}Open${RESET}       |"
    echo -e "| ${YELLOW}19302${RESET}     | UFW, IPTables   |         ${GREEN}Open${RESET}       |"
    echo -e "| ${YELLOW}19305${RESET}     | UFW             |         ${GREEN}Open${RESET}       |"
    echo -e "| ${YELLOW}3479${RESET}      | UFW             |         ${GREEN}Open${RESET}       |"
    echo -e "| ${YELLOW}5348${RESET}      | UFW             |         ${GREEN}Open${RESET}       |"
    echo -e "| ${YELLOW}19306${RESET}     | UFW             |         ${GREEN}Open${RESET}       |"
    echo -e  "+----------+------------------+---------------------+"

    echo -e "${GREY}"

    echo -e "\n${DARK_BLUE}\033[1m| ✓ Restored TCP and UDP Ports via UFW${RESET}"
    echo -e "+---------+-------------+------------+--------------+"
    echo -e "| ${CYAN}Port No${RESET} |  ${CYAN}Protocol${RESET}   | ${CYAN}Blocked By${RESET} |    ${CYAN}Status${RESET}    |"
    echo -e "+---------+-------------+------------+--------------+"
    echo -e "| ${YELLOW}3478${RESET}    | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e "| ${YELLOW}5349${RESET}    | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e "| ${YELLOW}19302${RESET}   | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e "| ${YELLOW}19305${RESET}   | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e "| ${YELLOW}3479${RESET}    | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e "| ${YELLOW}5348${RESET}    | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e "| ${YELLOW}19306${RESET}   | TCP, UDP    | UFW        |     ${GREEN}Open${RESET}      |"
    echo -e  "+---------+-------------+------------+--------------+"

    echo -e "${GREY}"

    echo -e "${NEON_GREEN} | ✓ WebRTC Leak Protection has been successfully disabled.${NC}"
    echo -e "${GREY}"
}

##############################################################
# Function to handle user input and execute the chosen option
##############################################################

handle_menu_selection() {
    while true; do
        print_menu
        echo -e "${GREY}"
        echo -e "${GREY}"
        echo -ne "${NEON_GREEN}\033[1m ➤ Enter your choice ${BLUE}(0-8): ${NC}"
        

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
                restor_to_default
                ;;
            7)
                enable_webrtc
                ;;  
            8)
                disable_webrtc
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
                echo -e "${RED}  • Please choose a number between (0-8)${NC}"

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