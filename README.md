# DNS-WebRTC-Leak-Shield
DNS &amp; WebRTC Leak Shield - Protecting Your Online Privacy

_________________________________________________________________

<details>
<summary> DNS Leak Shield (Server Side) ➡️ Click to Open </summary>

# DNS-Leak-Shield
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

_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
<details>
<summary> WebRTC Leak Shield (Server Side) ➡️ Click to Open </summary>
  
Introduction: This guide will help you block WebRTC traffic using iptables and ufw on a Linux system. WebRTC (Web Real-Time Communication) is often used for video conferencing and peer-to-peer communication, but it can expose your IP address even when using a VPN. Blocking WebRTC traffic can help enhance your privacy.

Prerequisites

  > - You should have root or sudo access to your Linux system.
  > - Basic knowledge of terminal commands.
#
### Step 1: Backing Up Current Firewall Rules
Before making any changes, it's important to back up your current iptables and UFW rules.

## Backup iptables Rules:




# Block WebRTC traffic using iptables
echo "Configuring iptables..."

## TCP Section

# Block WebRTC TCP Ports 10000 to 20000 for IPv4
sudo iptables -A OUTPUT -p tcp --dport 10000:20000 -j REJECT

## UDP Section

# Block WebRTC UDP Ports 3478, 5349, 19302 for IPv4
sudo iptables -A OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT

# Block WebRTC UDP Ports 3478, 5349, 19302 for IPv6
sudo ip6tables -A OUTPUT -p udp --match multiport --dports 3478,5349,19302 -j REJECT

# Save and apply iptables rules
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6

# Restore rules to ensure they are applied
sudo iptables-restore < /etc/iptables/rules.v4
sudo ip6tables-restore < /etc/iptables/rules.v6

# Start iptables services
sudo service iptables start
sudo systemctl start iptables


</details>














