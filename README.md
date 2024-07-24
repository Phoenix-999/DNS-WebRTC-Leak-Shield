# DNS-WebRTC-Leak-Shield
DNS &amp; WebRTC Leak Shield -
Protecting online privacy requires guarding against DNS and WebRTC leaks, potential vulnerabilities that can unintentionally expose real IP addresses.
This guide offers straightforward methods and tools to prevent these leaks across various platforms and environments.
_________________________________________________________________
## ⚙️ Automated DNS & WebRTC Leak Shield Configuration

This is an Automated Configuration Script for DNS, WebRTC Leak Protection on Ubuntu/Debian VPS! This Bash script is designed to simplify the process of setting up and configuring DNS and WebRTC leak protection on your VPS. With an easy-to-use menu interface, you can quickly choose from various DNS providers such as Cloudflare, Google, and Quad9, and enable or disable WebRTC leak protection to secure your VPS and protect your privacy. The script also includes functions to back up and restore configuration files, ensuring that your settings are always safe.

## Prerequisites:

Ubuntu & Debian
  * Linux `AMD64` Processor Architecture
  * Linux `ARM64` Processor Architecture
  * Ensure that the sudo and wget packages are installed on your system:

Before you start, ensure that your system meets the following requirements:
```bash
sudo apt update -q && sudo apt upgrade -y
sudo apt install -y sudo wget build-essential aptitude
```
Root Access is Required. If the user is not root, first run:
```bash
sudo -i
```

### Download and Run the Script
To download, set executable permissions, and run the script, use the following one-liner command:
```bash
mkdir -p ~/DNS_WebRTC_Shield && wget -qO ~/DNS_WebRTC_Shield/dns_webrtc_leak_protection.bash "https://raw.githubusercontent.com/Phoenix-999/DNS-WebRTC-Leak-Shield/main/dns_webrtc_leak_protection.bash" && chmod +x ~/DNS_WebRTC_Shield/dns_webrtc_leak_protection.bash && sudo ~/DNS_WebRTC_Shield/dns_webrtc_leak_protection.bash
```
#
### Menu Image
![Screenshot 2024-07-22 at 18 06 12](https://github.com/user-attachments/assets/14c32a55-aa32-41be-bf63-fa677a4773ee)


#
### Disclaimer:
This script is offered without any warranty or guarantee, and it is provided as is. Use it at your own discretion and risk.

________________________________________________________________

<details>
<summary> Manual Configuration Guide - WebRTC Leak Shield (MacOS & Linux) ➡️ Click to Open </summary>

## WebRTC Leak Shield for MacOS & Linux

How to Block WebRTC Leaks Using PF on macOS and Linux via Terminal
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
#############################################################
#---------------------Block WebRTC leaks--------------------#  
#############################################################

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
sudo pfctl -e
```

### Step 6: Verify the Rules
Verify that the rules have been loaded correctly by using the following command
```bash
sudo pfctl -s rules
```

### Step 7: Lock Configuration Files (Optional but Recommended)
🚩 This command securely **`/etc/pf.conf`** , prevents system from modifying it
```bash
sudo chflags schg /etc/pf.conf
```
### ⚠️ Additional Note:
If you need to modify `/etc/pf.conf` in the future, remember to remove the immutable attribute
Remove Lock Configuration Files To update the configuration, you'll need to remove the immutable flag.

```bash
sudo chflags noschg /etc/pf.conf
```

### Step 8: Reboot Resistance
To ensure that the WebCRT configuration remains disabled and starts automatically at boot-up every time, follow these steps

**Create a Launch Daemon for PF**
#
1. Create a new launch daemon configuration file.
   
   Let's name it com.**yourusername**.pfload.plist (replace **`yourusername`** with your actual macOS **`username`**):

```bash
sudo nano /Library/LaunchDaemons/com.yourusername.pfload.plist
```
#
2. Paste the following XML content into the nano editor.
  
   This XML defines a launch daemon that reloads PF at system startup
   replace **`yourusername`** with your actual macOS **`username`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yourusername.pfload</string>
    <key>Program</key>
    <string>/sbin/pfctl</string>
    <key>ProgramArguments</key>
    <array>
        <string>pfctl</string>
        <string>-e</string>
        <string>-f</string>
        <string>/etc/pf.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```
Save and exit the editor (Ctrl+X, then Y to confirm, and Enter.
#
3. Set Permissions on the Launch Daemon File
   
  Set appropriate permissions on the launch daemon file you just created
  replace **`yourusername`** with your actual macOS **`username`**
```bash
sudo chown root:wheel /Library/LaunchDaemons/com.yourusername.pfload.plist
sudo chmod 644 /Library/LaunchDaemons/com.yourusername.pfload.plist
```
#
4. Load the Launch Daemon
   
  Load the launch daemon using the launchctl command
  replace **`yourusername`** with your actual macOS **`username`**
```bash
sudo launchctl load /Library/LaunchDaemons/com.yourusername.pfload.plist
```
sudo launchctl load /Library/LaunchDaemons/com.iman.pfload.plist
#
5. Verify and Test
   
  After rebooting your Mac, Open Terminal and check the PF status to ensure it's enabled and your rules are applied:
```bash
sudo pfctl -sr
```

These steps will effectively block WebRTC leaks using PF on a macOS or Linux system.
This will help protect the real IP address when using a VPN and enhance online privacy.

</details>

________________________________________________________________


<details>
<summary> Manual Configuration Guide - WebRTC Leak Shield (Windows) ➡️ Click to Open </summary>

## WebRTC Leak Shield for Windows

Block WebRTC Leaks Using the Windows Command Prompt
WebRTC ports can be blocked using the Windows Command Prompt. This guide provides step-by-step instructions to block WebRTC leaks.

### Step 1: Open the Command Prompt as an Administrator
Right-click on the Start button and select "Command Prompt (Admin)

### Step 2: Create a New Rule to Block Outbound WebRTC Traffic
Run the following command to block outbound UDP traffic:
```bash
netsh advfirewall firewall add rule name="WebRTC Block UDP Outbound" dir=out action=block protocol=udp localport=3478,5349,19302,19305,3479,5348,19306
```
Run the following command to block outbound TCP traffic

```bash
netsh advfirewall firewall add rule name="WebRTC Block TCP Outbound" dir=out action=block protocol=tcp localport=3478,5349,19302,19305,3479,5348,19306
```

### Step 3: Create a New Rule to Block Inbound WebRTC Traffic
Run the following command to block inbound UDP traffic:
```bash
netsh advfirewall firewall add rule name="WebRTC Block UDP Inbound" dir=in action=block protocol=udp localport=3478,5349,19302,19305,3479,5348,19306
```
Run the following command to block inbound TCP traffic
```bash
netsh advfirewall firewall add rule name="WebRTC Block TCP Inbound" dir=in action=block protocol=tcp localport=3478,5349,19302,19305,3479,5348,19306
```

### Step 4: Verify the Rules
Run the following command to verify that the rules have been loaded
```bash
netsh advfirewall firewall show rule name="WebRTC Block*"
```
These steps will effectively block WebRTC leaks using the Windows Command Prompt. This will help protect the real IP address when using a VPN and enhance online privacy.

</details>

_________________________________________________________________


<details>
<summary> WebRTC Leak Shield (Browser Extensions) ➡️ Click to Open </summary>

### Browser extensions WebRTCLeak Shield
Browser extensions can be used to block WebRTC leaks. This guide provides step-by-step instructions for blocking WebRTC leaks using popular browser extensions.



## Google Chrome
Since WebRTC cannot be disabled in Chrome (desktop), add-ons are the only option (for those who do not want to just give up on using Chrome).

> [Google Chrome - WebRTC Block Extension](https://chromewebstore.google.com/detail/webrtc-leak-shield/bppamachkoflopbagkdoflbgfjflfnfl?hl=en)

#

**Disable Chrome WebRTC on Android**

On your Android device, open the URL **`chrome://flag`** or **`chrome://flags/#disable-webrtc`** in Chrome.
Scroll down and find “WebRTC STUN origin header” – then disable it. For safe measure, you can also disable the WebRTC Hardware Video Encoding/Decoding options, though it may not be necessary.


![Screenshot 2024-07-07 at 09 52 39](https://github.com/Phoenix-999/DNS-WebRTC-Leak-Shield/assets/127796122/bb20d96e-e82d-47d0-981a-5691ff27c75f)

#

## Firefox browsers
Disabling WebRTC using popular browser extensions.

> [Mozilla Firefox - WebRTC Block Extension](https://addons.mozilla.org/en-GB/firefox/addon/webrtc-leak-shield/?utm_source=addons.mozilla.org&utm_medium=referral&utm_content=search)

Disabling WebRTC is very simple in Firefox. First, type about:config into the URL bar and hit enter. Then, agree to the warning message and click the continue button.

![Screenshot 2024-07-07 at 09 48 57](https://github.com/Phoenix-999/DNS-WebRTC-Leak-Shield/assets/127796122/1846ae57-e17c-48d6-b1a0-e5e56afaa0ef)

Then, in the search box type “media.peerconnection.enabled“. Double click the preference name to change the value to “false“.

![Screenshot 2024-07-07 at 09 49 27](https://github.com/Phoenix-999/DNS-WebRTC-Leak-Shield/assets/127796122/16943af1-dd3c-4918-8c56-c31b6ec03ddc)

WebRTC is now disabled in Firefox and you won’t have to worry about WebRTC leaks.

#

## Safari macOS & iOS 

WebRTC leaks have traditionally not been an issue with Safari browsers (on Mac OS and iOS devices).
By default, Safari should have WebRTC enabled. There are no built-in settings to enable or disable WebRTC in Safari, as it is always enabled in modern versions of the browser.

</details>

_________________________________________________________________


<details>
<summary> Test for DNS & WebRTC Leaks ➡️ Click to Open </summary>

## Testing the DNS & WebRTC Leaks

It is essential to verify that the setup is effective.
Ensuring your VPN or firewall settings effectively block DNS and WebRTC leaks is crucial for maintaining online privacy.
Several online tools can help test for DNS & WebRTC leaks. This guide explains how to use these websites to ensure there are no leaks.

  > - [Dnsleaktest.com](https://www.dnsleaktest.com/)
  > 
  > - [ipleak.net](https://ipleak.net/)
  > 
  > - [Surfshark.com](https://surfshark.com/dns-leak-test)
  > 
  > - [Browserleaks](https://browserleaks.com/)



</details>

_________________________________________________________________


















