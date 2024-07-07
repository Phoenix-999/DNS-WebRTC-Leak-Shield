# DNS-WebRTC-Leak-Shield
_DNS &amp; WebRTC Leak Shield - Protecting Your Online Privacy_
_________________________________________________________________

<details>
<summary> DNS Leak Shield (Server Side) ➡️ Click to Open </summary>

## DNS Leak Shield for VPS Server
Securing Your VPS with Cloudflare DNS on Linux

Introduction: Securing your VPS server by directing DNS queries through trusted servers like Cloudflare's is essential for enhancing security, ensuring a secure connection, and preventing DNS leaks. Follow these detailed steps to configure your Linux-based VPS to exclusively use Cloudflare DNS.

Prerequisites

  > - You should have root or sudo access to your Linux system.
  > - Basic knowledge of terminal commands.
#

### Step 1: Backup Current Configuration
Before making any changes, it's crucial to back up your current DNS configuration:
_This ensures you can revert back if needed._
```bash
sudo cp /etc/resolv.conf /etc/resolv.conf.bak
```

DNS Flushing:
To ensure that any existing DNS cache is cleared, you can flush the DNS cache using the following command:

```bash
sudo resolvectl flush-caches
sudo systemd-resolve --flush-caches
```

#

### Step 2: Configure /etc/resolv.conf
Edit the `/etc/resolv.conf` file to specify Cloudflare's DNS servers:
```bash
sudo nano /etc/resolv.conf
```
Ensure the file contains only these lines:
```conf                                           
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

options dnssec dnssec-ok edns0 trust-ad rotate no-check-names inet6 timeout 2
options tls-ca-file /etc/ssl/certs/ca-certificates.crt
options tls-cert-file /etc/cloudflared/cert.pem
options tls-key-file /etc/cloudflared/key.pem
options dnssec-validation yes
options edns-client-subnet 24
options cache-size 1000
options cache-min-ttl 300
options cache-max-ttl 3600
nameserver 1.1.1.1
nameserver 2606:4700:4700::1111
nameserver 1.0.0.1
nameserver 2606:4700:4700::1001
#options log-facility local0
#options log-level 1

```
Save and exit the editor (Ctrl+X, Y, Enter).
#

### Step 3: Prevent Overwriting of /etc/resolv.conf
Protect `/etc/resolv.conf` from being overwritten by setting the immutable attribute:

🚩 This command securely **`locks the file`** , prevents other programs from modifying  it

```bash
sudo chmod 0444 /etc/resolv.conf
```
OR

```bash
sudo chattr +i /etc/resolv.conf
```

#### ⚠️  Additional Note:
If you need to modify `/etc/resolv.conf` in the future, remember to remove the immutable attribute:

```bash
sudo chmod 0644 /etc/resolv.conf
```
OR
```bash
sudo chattr -i /etc/resolv.conf
```

#

### Step 4: Configure systemd-resolved (Optional)
If your VPS uses `systemd-resolved`, configure it to use Cloudflare's DNS servers:
```bash
sudo nano /etc/systemd/resolved.conf
```
Add or update these lines:

```conf
[Resolve]
DNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001
DNSOverTLS=yes
DNSOverUDP=no
DNSSEC=yes
DNSSECMode=yes
DNSSECValidation=yes
Cache=yes
CacheSize=100M
CacheExpire=3600
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
CacheExpire=3600
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
```

Save the file (Ctrl+X, Y, Enter) and restart systemd-resolved:
```bash
sudo systemctl restart systemd-resolved
```

#

### Step 5: Verify DNS Configuration
Verify that DNS resolution is correctly using Cloudflare's servers:
Ensure the output shows queries resolved via 1.1.1.1 and 1.0.0.1.
```bash
nslookup example.com
```

#

### Step 6: Persistent Configuration Across Reboots
To ensure these settings persist across reboots, follow these steps:

Protect `/etc/resolv.conf`
Make sure /etc/resolv.conf remains unchanged:
```bash
sudo chattr +i /etc/resolv.conf
```

#

Enable systemd-resolved on Boot
Ensure systemd-resolved starts automatically:
```bash
sudo systemctl enable systemd-resolved
```

_________________________________________________________________

## 🔴 Reverting to Original VPS Settings


### Step 1: Restore Original DNS Configuration
To revert to the original VPS DNS settings:

▶ Remove Immutable Attribute:
```bash
sudo chmod 0644 /etc/resolv.conf
```
OR

```bash
sudo chattr -i /etc/resolv.conf
```
#
▶ Restore Original /etc/resolv.conf:
This command replaces the modified file with the original backup.
```bash
sudo mv /etc/resolv.conf.bak /etc/resolv.conf
```
#
▶ Disable systemd-resolved (if enabled):
```bash
sudo systemctl disable systemd-resolved
```
#
▶ Restart Networking Service:
```bash
sudo systemctl restart systemd-networkd
```
________________________________________________________________

</details>


________________________________________________________________

<details>
<summary> WebRTC Leak Shield (Server Side) ➡️ Click to Open </summary>

## WebRTC Leak Shield for VPS Server
Block WebRTC Traffic, Securing Your VPS by Blocking WebRTC Traffic Using iptables and UFW

Introduction: This guide will help you block WebRTC traffic using iptables and ufw on a Linux system. WebRTC (Web Real-Time Communication) is often used for video conferencing and peer-to-peer communication, but it can expose your IP address even when using a VPN. Blocking WebRTC traffic can help enhance your privacy.

Prerequisites

  > - You should have root or sudo access to your Linux system.
  > - Basic knowledge of terminal commands.
#
### Step 1: Backing Up Current Firewall Rules
Before making any changes, it's important to back up your current iptables and UFW rules.

**Backup iptables Rules:**
Open a terminal.Run the following command to save current iptables rules to a backup file
```bash
sudo iptables-save > iptables_backup.txt
sudo ip6tables-save > ip6tables_backup.txt
```

**Backup UFW Rules:**
Run the following commands to copy UFW configuration files to backup files
```bash
sudo cp /etc/ufw/user.rules ufw_backup.txt
sudo cp /etc/ufw/user6.rules ufw6_backup.txt
```
#

### Step 2: Block WebRTC TCP & UDP Ports (iptables):
Open a terminal and execute the following commands:
```bash
# Ensure you are root
sudo su

# Block WebRTC TCP Ports 10000 to 20000 for IPv4
iptables -A OUTPUT -p tcp --dport 10000:20000 -j REJECT

# Block WebRTC UDP Ports 3478, 5349, 19302 for IPv4
iptables -A OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT

# Block WebRTC UDP Ports 3478, 5349, 19302 for IPv6
ip6tables -A OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT

# Save iptables rules for IPv4 and IPv6
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# Start iptables service (if not already started)
service iptables start
systemctl start iptables

```

**Make iptables Rules Persistent**

To ensure these rules are persistent across reboots, install iptables-persistent.
During the installation, you will be prompted to save the current rules. Confirm this for both IPv4 and IPv6.
```bash
sudo apt-get install iptables-persistent
```

If you need to save the rules manually after making changes, use:
```bash
sudo netfilter-persistent save
```

**Verify iptables Rules:**

To verify that the rules have been applied correctly, you can list the iptables rules:
```bash
iptables -L
ip6tables -L
```
#

### Step 3:  Block WebRTC TCP and UDP Ports (UFW):
Open a terminal and execute the following commands:

```bash
# Ensure you are root
sudo su

# Block WebRTC TCP Ports 3478, 5349, 19302, 19305, 3479, 5348, 19306 (Outgoing)
ufw deny out proto tcp from any to any port 3478,5349,19302,19305,3479,5348,19306

# Block WebRTC TCP Ports 3478, 5349, 19302, 19305, 3479, 5348, 19306 (Incoming)
ufw deny in proto tcp from any to any port 3478,5349,19302,19305,3479,5348,19306

# Block WebRTC UDP Ports 3478, 5349, 19302, 19305, 3479, 5348, 19306 (Outgoing)
ufw deny out proto udp from any to any port 3478,5349,19302,19305,3479,5348,19306

# Block WebRTC UDP Ports 3478, 5349, 19302, 19305, 3479, 5348, 19306 (Incoming)
ufw deny in proto udp from any to any port 3478,5349,19302,19305,3479,5348,19306

# Reload UFW to apply changes
ufw reload
```

**Ensure UFW Rules are Persistent**

UFW rules are automatically persistent, but ensure that UFW is enabled
```bash
sudo ufw enable
```

**Verify UFW Rules:**

To verify that the UFW rules have been applied correctly, you can check the UFW status:
```bash
ufw status verbose
```
_________________________________________________________________

## 🔴 Reverting to Original VPS Settings
If you need to revert to your previous firewall rules:

**Restore iptables Rules:**
```bash
iptables-restore < /etc/iptables/rules.v4
ip6tables-restore < /etc/iptables/rules.v6
```

**Restore UFW Rules:**
```bash
cp ufw_backup.txt /etc/ufw/user.rules
cp ufw6_backup.txt /etc/ufw/user6.rules

# Reload UFW to apply changes
ufw reload
```

</details>

________________________________________________________________

<details>
<summary> WebRTC Leak Shield (MacOS & Linux) ➡️ Click to Open </summary>

## WebRTC Leak Shield for MacOS & Linux

Securing Your System by Blocking WebRTC Traffic Using iptables and UFW
WebRTC ports can be blocked using the Packet Filter (PF) firewall on macOS and Linux.

Prerequisites

  > - You should have root or sudo access to your Linux system.
  > - Basic knowledge of terminal commands.
#

### Step 1: Open the Terminal

On macOS: Terminal can be found in the Applications/Utilities folder, or use Spotlight to search for it.
On Linux: Terminal can be found in the Applications menu or use the keyboard shortcut Ctrl+Alt+T.

### Step 2: Edit the PF Configuration File
Open the PF configuration file using the following command in the Terminal.
```bash
sudo nano /etc/pf.conf
```

### Step 3: Add the WebRTC Blocking Rules
Copy the following rules and paste them at the end of the PF configuration file

```bash
# Block WebRTC leaks
block drop out proto udp from any to any port {3478, 5349, 19302, 19305, 3479, 5348, 19306}
block drop out proto tcp from any to any port {3478, 5349, 19302, 19305, 3479, 5348, 19306}
block drop in proto udp from any to any port {3478, 5349, 19302, 19305, 3479, 5348, 19306}
block drop in proto tcp from any to any port {3478, 5349, 19302, 19305, 3479, 5348, 19306}
```

### Step 4: Save and Close the PF Configuration File
Press Ctrl+X to exit the editor.
Press Y to save the changes.
Press Enter to confirm the file name.

### Step 5: Reload the PF Configuration
Reload the PF configuration to apply the new rules using the following command
```bash
sudo pfctl -f /etc/pf.conf
```

### Step 6: Verify the Rules
Verify that the rules have been loaded correctly by using the following command
```bash
sudo pfctl -s rules
```

These steps will effectively block WebRTC leaks using PF on a macOS or Linux system.
This will help protect the real IP address when using a VPN and enhance online privacy.

</details>
________________________________________________________________

<details>
<summary> WebRTC Leak Shield (Windows) ➡️ Click to Open </summary>

## WebRTC Leak Shield for Windows

Securing Your System by Blocking WebRTC Traffic Using iptables and UFW
WebRTC ports can be blocked using the Packet Filter (PF) firewall on macOS and Linux.

</details>







