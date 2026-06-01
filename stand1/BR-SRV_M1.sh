#!/bin/bash
set -euo pipefail

need_root() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Запустите от root" >&2
    exit 1
  fi
}

backup_file() {
  local f="$1"
  if [ -f "$f" ] && [ ! -f "${f}.bak" ]; then
    cp -a "$f" "${f}.bak"
  fi
}

append_unique() {
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

install_pkgs() {
  apt-get update || true
  apt-get install -y "$@" || true
}

need_root

SSH_UID="${SSH_UID:-2014}"
PRIMARY_SSH_PORT="${PRIMARY_SSH_PORT:-2014}"
SECONDARY_SSH_PORT="${SECONDARY_SSH_PORT:-2026}"

create_sshuser() {
  if ! id sshuser >/dev/null 2>&1; then
    useradd sshuser -u "$SSH_UID" -m || useradd sshuser -u "$SSH_UID"
  fi
  echo 'sshuser:P@ssw0rd' | chpasswd
  usermod -aG wheel sshuser || true
  append_unique 'sshuser ALL=(ALL) NOPASSWD:ALL' /etc/sudoers
  mkdir -p /etc/sudoers.d
  echo 'sshuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/sshuser
  chmod 0440 /etc/sudoers.d/sshuser
}

harden_sshd() {
  local f=/etc/openssh/sshd_config
  backup_file "$f"
  touch "$f"
  for k in Port MaxAuthTries PasswordAuthentication Banner AllowUsers; do
    sed -i -E "/^[#[:space:]]*${k}[[:space:]]+/d" "$f"
  done
  {
    echo "Port ${PRIMARY_SSH_PORT}"
    if [ -n "${SECONDARY_SSH_PORT}" ] && [ "${SECONDARY_SSH_PORT}" != "${PRIMARY_SSH_PORT}" ]; then
      echo "Port ${SECONDARY_SSH_PORT}"
    fi
    echo 'MaxAuthTries 2'
    echo 'PasswordAuthentication yes'
    echo 'Banner /etc/openssh/bannermotd'
    echo 'AllowUsers sshuser'
  } >> "$f"
  mkdir -p /etc/openssh
  echo 'Authorized access only' > /etc/openssh/bannermotd
  systemctl restart sshd || systemctl restart ssh || true
}

# Dok 4 / Стенд 1 / Модуль 1 / BR-SRV
hostnamectl set-hostname br-srv.au-team.irpo
mkdir -p /etc/net/ifaces/ens19
echo '192.168.3.10/28' > /etc/net/ifaces/ens19/ipv4address
echo 'default via 192.168.3.1' > /etc/net/ifaces/ens19/ipv4route
echo 'nameserver 192.168.1.10' > /etc/net/ifaces/ens19/resolv.conf
echo 'nameserver 192.168.1.10' > /etc/resolv.conf
create_sshuser
harden_sshd
install_pkgs tzdata
timedatectl set-timezone Europe/Moscow || true
systemctl restart network || true
echo 'OK: BR-SRV M1 настроен. SSH слушает PRIMARY_SSH_PORT=2014 и, по умолчанию, SECONDARY_SSH_PORT=2026.'
