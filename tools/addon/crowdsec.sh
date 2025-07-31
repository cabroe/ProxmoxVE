#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Modified for Alpine Linux CrowdSec installation

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\r\033[K"
HOLD="-"
CM="${GN}✓${CL}"
APP="CrowdSec"
hostname="$(hostname)"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local reason="Unknown failure occured."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  exit "$EXIT"
}

# Detect OS and set variables
if command -v apk >/dev/null 2>&1; then
  OS="alpine"
  PKG_MGR="apk"
  INSTALL_CMD="apk add"
  UPDATE_CMD="apk update"
  SERVICE_MGR="rc-service"
  SERVICE_ENABLE="rc-update add"
elif command -v apt-get >/dev/null 2>&1; then
  OS="debian"
  PKG_MGR="apt-get"
  INSTALL_CMD="apt-get install -y"
  UPDATE_CMD="apt-get update"
  SERVICE_MGR="systemctl"
  SERVICE_ENABLE="systemctl enable"
else
  echo -e "⚠️  Unsupported OS. This script supports Alpine Linux and Debian-based systems only."
  exit 1
fi

if command -v pveversion >/dev/null 2>&1; then
  echo -e "⚠️  Can't Install on Proxmox "
  exit
fi

while true; do
  read -p "This will Install ${APP} on $hostname ($OS). Proceed(y/n)?" yn
  case $yn in
  [Yy]*) break ;;
  [Nn]*) exit ;;
  *) echo "Please answer yes or no." ;;
  esac
done

clear

function header_info() {
  local os_label=""
  if [ "$OS" = "alpine" ]; then
    os_label="(Alpine)"
  elif [ "$OS" = "debian" ]; then
    os_label="(Debian)"
  fi

  echo -e "${BL}
   _____                      _  _____           
  / ____|                    | |/ ____|          
 | |     _ __ _____      ____| | (___   ___  ___ 
 | |    |  __/ _ \ \ /\ / / _  |\___ \ / _ \/ __|
 | |____| | | (_) \ V  V / (_| |____) |  __/ (__ 
  \_____|_|  \___/ \_/\_/ \__ _|_____/ \___|\___| $os_label
${CL}"
}

header_info

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

# OS-specific installation functions
function install_alpine() {
  msg_info "Setting up ${APP} Repository (Alpine)"
  echo "@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing" | tee -a /etc/apk/repositories &>/dev/null
  $UPDATE_CMD &>/dev/null
  msg_ok "Setup ${APP} Repository"

  msg_info "Installing ${APP}"
  $INSTALL_CMD crowdsec@testing &>/dev/null
  msg_ok "Installed ${APP} on $hostname"

  msg_info "Registering with ${APP} Central API"
  echo "You will be prompted for an email address for CAPI registration..."
  sleep 2
  cscli capi register
  msg_ok "Registered with ${APP} Central API"

  msg_info "Updating ${APP} Hub"
  cscli hub update &>/dev/null
  msg_ok "Updated ${APP} Hub"

  msg_info "Enrolling with ${APP} Console"
  cscli console enroll -e context clci9rq9q0000jp0801umtmqz &>/dev/null
  msg_ok "Enrolled with ${APP} Console"

  msg_info "Installing ${APP} Firewall Bouncer"
  $INSTALL_CMD crowdsec-firewall-bouncer@testing &>/dev/null || {
    echo -e "${YW}Note: Firewall bouncer not available in Alpine repo${CL}"
  }
  msg_ok "Setup ${APP} Firewall Bouncer"

  msg_info "Enabling ${APP} Service"
  $SERVICE_ENABLE crowdsec default &>/dev/null
  $SERVICE_MGR crowdsec start &>/dev/null
  msg_ok "Enabled ${APP} Service"
}

function install_debian() {
  msg_info "Setting up ${APP} Repository (Debian)"
  $UPDATE_CMD &>/dev/null
  $INSTALL_CMD curl &>/dev/null
  $INSTALL_CMD gnupg &>/dev/null
  curl -fsSL "https://install.crowdsec.net" | bash &>/dev/null
  msg_ok "Setup ${APP} Repository"

  msg_info "Installing ${APP}"
  $UPDATE_CMD &>/dev/null
  $INSTALL_CMD crowdsec &>/dev/null
  msg_ok "Installed ${APP} on $hostname"

  msg_info "Installing ${APP} Common Bouncer"
  $INSTALL_CMD crowdsec-firewall-bouncer-iptables &>/dev/null
  msg_ok "Installed ${APP} Common Bouncer"
}

# Execute OS-specific installation
if [ "$OS" = "alpine" ]; then
  install_alpine
elif [ "$OS" = "debian" ]; then
  install_debian
fi

# Common post-installation steps
echo -e "${GN}${APP} Installation completed successfully!${CL}"

if [ "$OS" = "alpine" ]; then
  echo -e "${BL}Service Status:${CL}"
  $SERVICE_MGR crowdsec status || true
  echo -e "${BL}Next Steps:${CL}"
  echo -e "• Check logs: ${YW}tail -f /var/log/crowdsec.log${CL}"
  echo -e "• View decisions: ${YW}cscli decisions list${CL}"
  echo -e "• Install collections: ${YW}cscli collections install crowdsecurity/linux${CL}"
elif [ "$OS" = "debian" ]; then
  echo -e "${BL}Next Steps:${CL}"
  echo -e "• Register with CAPI: ${YW}cscli capi register${CL}"
  echo -e "• Update hub: ${YW}cscli hub update${CL}"
  echo -e "• Enroll console: ${YW}cscli console enroll -e context <your-key>${CL}"
fi

msg_ok "Completed Successfully!"
