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

# Dok 4 / Стенд 1 / Модуль 1 / HQ-CLI
hostnamectl set-hostname hq-cli.au-team.irpo
install_pkgs tzdata
mkdir -p /etc/net/ifaces/ens19
cat > /etc/net/ifaces/ens19/options <<'EOF'
TYPE=eth
BOOTPROTO=dhcp
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
EOF
# DHCP должен выдать 192.168.2.10/28 от HQ-RTR.
timedatectl set-timezone Europe/Moscow || true
systemctl restart network || true
echo 'OK: HQ-CLI M1 подготовлен. Проверьте DHCP: ip -4 a show ens19.'
