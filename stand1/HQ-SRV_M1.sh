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

# Dok 4 / Стенд 1 / Модуль 1 / HQ-SRV
hostnamectl set-hostname hq-srv.au-team.irpo
mkdir -p /etc/net/ifaces/ens19
echo '192.168.1.10/27' > /etc/net/ifaces/ens19/ipv4address
echo 'default via 192.168.1.1' > /etc/net/ifaces/ens19/ipv4route
echo 'nameserver 77.88.8.8' > /etc/net/ifaces/ens19/resolv.conf
echo 'nameserver 77.88.8.8' > /etc/resolv.conf

create_sshuser
harden_sshd
install_pkgs dnsmasq tzdata
backup_file /etc/dnsmasq.conf
cat > /etc/dnsmasq.conf <<'EOF'
no-resolv
domain=au-team.irpo
server=77.88.8.8
interface=*
address=/hq-rtr.au-team.irpo/192.168.1.1
ptr-record=1.1.168.192.in-addr.arpa,hq-rtr.au-team.irpo
address=/br-rtr.au-team.irpo/192.168.3.1
address=/hq-srv.au-team.irpo/192.168.1.10
ptr-record=10.1.168.192.in-addr.arpa,hq-srv.au-team.irpo
address=/hq-cli.au-team.irpo/192.168.2.10
ptr-record=10.2.168.192.in-addr.arpa,hq-cli.au-team.irpo
address=/br-srv.au-team.irpo/192.168.3.10
address=/docker.au-team.irpo/172.16.70.1
address=/web.au-team.irpo/172.16.80.1
EOF
append_unique '192.168.1.1 hq-rtr.au-team.irpo' /etc/hosts
systemctl enable --now dnsmasq || true
systemctl restart dnsmasq || true

timedatectl set-timezone Europe/Moscow || true
systemctl restart network || true
echo 'OK: HQ-SRV M1 настроен. SSH слушает PRIMARY_SSH_PORT=2014 и, по умолчанию, SECONDARY_SSH_PORT=2026.'
