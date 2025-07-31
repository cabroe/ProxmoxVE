#!/usr/bin/env bash

# Universal CrowdSec Installer for Debian/Ubuntu and Alpine Linux
set -euo pipefail

APP="CrowdSec"
hostname="$(hostname)"

# Farben (optional, keine doppelten Backslashes!)
YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"
CM="${GN}✓${CL}"

function msg_info() { echo -e " ${YW}$1...${CL}"; }
function msg_ok()   { echo -e " ${CM} ${GN}$1${CL}"; }
function error_exit() { echo -e "${RD}‼ ERROR $1${CL}" 1>&2; exit 1; }

# OS-Erkennung
if command -v apk >/dev/null 2>&1; then
    OS="alpine"
elif command -v apt-get >/dev/null 2>&1; then
    OS="debian"
else
    error_exit "Unsupported OS. Only Alpine Linux and Debian/Ubuntu are supported."
fi

if command -v pveversion >/dev/null 2>&1; then
    error_exit "Can't install on Proxmox."
fi

read -p "This will install ${APP} on $hostname ($OS). Proceed (y/n)? " yn
case $yn in
    [Yy]*) ;;
    *) exit ;;
esac

clear
echo -e "${BL}
   _____                      _  _____           
  / ____|                    | |/ ____|          
 | |     _ __ _____      ____| | (___   ___  ___ 
 | |    |  __/ _ \ \ /\ / / _  |\___ \ / _ \/ __|
 | |____| | | (_) \ V  V / (_| |____) |  __/ (__ 
  \_____|_|  \___/ \_/\_/ \__ _|_____/ \___|\___| ($OS)
${CL}"

if [ "$OS" = "alpine" ]; then
    msg_info "Adding testing repository"
    echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing" | tee -a /etc/apk/repositories >/dev/null
    apk update >/dev/null
    msg_ok "Repository added"

    msg_info "Installing CrowdSec"
    apk add crowdsec@testing >/dev/null
    msg_ok "CrowdSec installed"

    msg_info "Registering with Central API"
    cscli capi register
    msg_ok "CAPI registration done"

    msg_info "Updating hub"
    cscli hub update >/dev/null
    msg_ok "Hub updated"

    msg_info "Enrolling console"
    cscli console enroll -e context clci9rq9q0000jp0801umtmqz >/dev/null
    msg_ok "Console enrolled"

    msg_info "Enabling and starting service"
    rc-update add crowdsec default >/dev/null
    rc-service crowdsec start >/dev/null
    msg_ok "Service enabled and started"

    echo -e "${GN}CrowdSec Installation completed successfully!${CL}"
    rc-service crowdsec status || true

elif [ "$OS" = "debian" ]; then
    msg_info "Updating apt and installing dependencies"
    apt-get update -qq
    apt-get install -y curl gnupg >/dev/null
    msg_ok "Dependencies installed"

    msg_info "Running CrowdSec installer"
    curl -fsSL https://install.crowdsec.net | bash >/dev/null
    msg_ok "CrowdSec repository set up"

    msg_info "Installing CrowdSec"
    apt-get update -qq
    apt-get install -y crowdsec >/dev/null
    msg_ok "CrowdSec installed"

    msg_info "Installing firewall bouncer"
    apt-get install -y crowdsec-firewall-bouncer-iptables >/dev/null
    msg_ok "Firewall bouncer installed"

    echo -e "${GN}CrowdSec Installation completed successfully!${CL}"
    systemctl status crowdsec || true
fi

echo -e "${BL}Next steps:${CL}"
echo -e "  ${YW}cscli capi register${CL} (falls noch nicht gemacht)"
echo -e "  ${YW}cscli hub update${CL}"
echo -e "  ${YW}cscli console enroll -e context <your-key>${CL}"
echo -e "  ${YW}cscli decisions list${CL}"
