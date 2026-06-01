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

# Dok 4 / Стенд 1 / Модуль 1 / ISP
# В PDF есть противоречие в таблице и пункте "Настройка ISP".
# По умолчанию используется процедурная логика: ens20 = HQ-сеть 172.16.70.0/28, ens21 = BR-сеть 172.16.80.0/28.
HQ_IF="${HQ_IF:-ens20}"
BR_IF="${BR_IF:-ens21}"
WAN_IF="${WAN_IF:-ens19}"

hostnamectl set-hostname isp
mkdir -p "/etc/net/ifaces/${HQ_IF}" "/etc/net/ifaces/${BR_IF}"
echo '172.16.70.1/28' > "/etc/net/ifaces/${HQ_IF}/ipv4address"
echo '172.16.80.1/28' > "/etc/net/ifaces/${BR_IF}/ipv4address"

mkdir -p /etc/net
backup_file /etc/net/sysctl.conf
grep -q '^net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf || echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
backup_file /etc/sysctl.conf
grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null && sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf || echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

install_pkgs iptables tzdata
iptables -t nat -C POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
mkdir -p /etc/sysconfig
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables || true

timedatectl set-timezone Europe/Moscow || true
systemctl restart network || true
echo 'OK: ISP M1 настроен. Проверьте, что HQ-RTR смотрит в сеть 172.16.70.0/28, BR-RTR — в 172.16.80.0/28.'
