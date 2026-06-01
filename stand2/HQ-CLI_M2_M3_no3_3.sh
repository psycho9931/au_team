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

# Dok 4 / Стенд 2 / Модули 2-3 без задания 3.3 / HQ-CLI
# Делает: пакеты AD/SSSD, sudo provider, NFS mount, chrony, CUPS client, CA trust если ca.cer уже передан, /backup для CyberBackup.
CA_SRC="${CA_SRC:-/home/user/ca.cer}"
ISO_DEV="${ISO_DEV:-/dev/sr0}"
ISO_MNT="${ISO_MNT:-/mount}"

install_pkgs task-auth-ad-sssd libsss_sudo cups chrony yandex-browser nfs-utils
backup_file /etc/chrony.conf
cat > /etc/chrony.conf <<'EOF'
# pool pool.ntp.org iburst
server 172.16.70.1 iburst prefer
EOF
systemctl enable --now chronyd || true
systemctl restart chronyd || true

mkdir -p /mnt/nfs
chmod 777 /mnt/nfs
append_unique '192.168.1.10:/raid/nfs /mnt/nfs nfs defaults 0 0' /etc/fstab
mount -a || true

control sudo public || true
if [ -f /etc/sssd/sssd.conf ]; then
  backup_file /etc/sssd/sssd.conf
  if grep -q '^services =' /etc/sssd/sssd.conf; then
    sed -i -E 's/^services =.*/services = nss, pam, sudo/' /etc/sssd/sssd.conf
  else
    echo 'services = nss, pam, sudo' >> /etc/sssd/sssd.conf
  fi
  grep -q '^sudo_provider = ad' /etc/sssd/sssd.conf || sed -i '/^\[domain\//a sudo_provider = ad' /etc/sssd/sssd.conf || true
  systemctl restart sssd || true
fi
backup_file /etc/nsswitch.conf
if grep -q '^sudoers:' /etc/nsswitch.conf; then
  sed -i 's/^sudoers:.*/sudoers: files sss/' /etc/nsswitch.conf
else
  echo 'sudoers: files sss' >> /etc/nsswitch.conf
fi

systemctl enable --now cups || true
lpadmin -p PDF-hq-srv -E -v ipp://192.168.1.10:631/printers/Cups-PDF -m everywhere || true
lpadmin -d PDF-hq-srv || true

if [ -f "$CA_SRC" ]; then
  mkdir -p /etc/pki/ca-trust/source/anchors
  cp -f "$CA_SRC" /etc/pki/ca-trust/source/anchors/ca.cer
  update-ca-trust || true
else
  echo "INFO: CA не установлен: файл $CA_SRC не найден. Скопируйте ca.cer с HQ-SRV и повторите скрипт."
fi

mkdir -p /backup
chmod 777 /backup
mkdir -p "$ISO_MNT"
mountpoint -q "$ISO_MNT" || mount "$ISO_DEV" "$ISO_MNT" 2>/dev/null || true

echo 'OK: HQ-CLI M2/M3 без 3.3 подготовлен. Вручную: ввод в домен через GUI, CryptoPro CSP, CyberBackup agent GUI.'
