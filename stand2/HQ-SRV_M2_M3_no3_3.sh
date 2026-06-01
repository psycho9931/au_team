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

# Dok 4 / Стенд 2 / Модули 2-3 без задания 3.3 / HQ-SRV
# Делает: DNS additions, chrony client, RAID0/NFS, Apache+MariaDB web, GOST CA, CUPS, rsyslog collector/logrotate, Zabbix compose/agent, fail2ban.
ISO_DEV="${ISO_DEV:-/dev/sr0}"
ISO_MNT="${ISO_MNT:-/mount}"
DISK1="${DISK1:-/dev/sdb}"
DISK2="${DISK2:-/dev/sdc}"
RAID_DEV="${RAID_DEV:-/dev/md0}"
PRIMARY_SSH_PORT="${PRIMARY_SSH_PORT:-2014}"
SECONDARY_SSH_PORT="${SECONDARY_SSH_PORT:-2026}"

install_pkgs rsyslog fail2ban python3-module-systemd docker-engine docker-compose-v2 cups cups-pdf chrony nfs-server nfs-utils mdadm lamp-server openssl-gost-engine zabbix-agent logrotate

if [ -f /etc/dnsmasq.conf ]; then
  append_unique 'server=/au-team.irpo/192.168.3.10' /etc/dnsmasq.conf
  append_unique 'address=/mon.au-team.irpo/172.16.70.1' /etc/dnsmasq.conf
  systemctl restart dnsmasq || true
else
  echo 'WARN: /etc/dnsmasq.conf не найден. Сначала выполните Модуль 1 на HQ-SRV.'
fi

backup_file /etc/chrony.conf
cat > /etc/chrony.conf <<'EOF'
# pool pool.ntp.org iburst
server 172.16.70.1 iburst prefer
EOF
systemctl enable --now chronyd || true
systemctl restart chronyd || true

if [ -b "$DISK1" ] && [ -b "$DISK2" ]; then
  if [ ! -e "$RAID_DEV" ]; then
    mdadm --create "$RAID_DEV" --level=0 --raid-devices=2 "$DISK1" "$DISK2" --force
    mkfs -t ext4 "$RAID_DEV"
  fi
  echo 'DEVICE partitions' > /etc/mdadm.conf
  mdadm --detail --scan | awk '/ARRAY/ {print}' >> /etc/mdadm.conf || true
  mkdir -p /raid
  append_unique "$RAID_DEV /raid ext4 defaults 0 0" /etc/fstab
  mount -a || true
else
  echo "WARN: $DISK1 или $DISK2 не найдены; RAID/NFS-хранилище не создавалось. Проверьте lsblk."
fi

mkdir -p /raid/nfs
chmod 777 /raid/nfs
append_unique '/raid/nfs 192.168.2.0/28(rw,no_root_squash)' /etc/exports
exportfs -arv || true
systemctl enable --now nfs-server || systemctl enable --now nfs || true

mkdir -p "$ISO_MNT"
mountpoint -q "$ISO_MNT" || mount "$ISO_DEV" "$ISO_MNT" 2>/dev/null || true
systemctl enable --now mariadb || systemctl enable --now mysqld || true
if [ -d "$ISO_MNT/web" ]; then
  cp -f "$ISO_MNT/web/index.php" /var/www/html/ 2>/dev/null || true
  cp -f "$ISO_MNT/web/logo.png" /var/www/html/ 2>/dev/null || true
  cp -rf "$ISO_MNT/web/images" /var/www/html/ 2>/dev/null || true
fi
mysql_cmd="mariadb"; command -v mariadb >/dev/null 2>&1 || mysql_cmd="mysql"
$mysql_cmd -u root <<'SQL' || true
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
if [ -f "$ISO_MNT/web/dump.sql" ]; then
  $mysql_cmd -u web -p'P@ssw0rd' -D webdb < "$ISO_MNT/web/dump.sql" || true
fi
echo 'INFO: проверьте /var/www/html/index.php: DB host=localhost, db=webdb, user=web, password=P@ssw0rd.'
systemctl enable --now httpd2 || systemctl enable --now apache2 || true

control openssl-gost enabled || true
mkdir -p /root/ca-gost
cd /root/ca-gost
if [ ! -f ca.key ]; then
  openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:TCB -out ca.key
  openssl req -new -x509 -md_gost12_256 -days 30 -key ca.key -out ca.cer -subj '/C=RU/ST=Exam/L=Exam/O=AU-Team/OU=IRPO/CN=hq-srv.au-team.irpo'
  for name in web.au-team.irpo docker.au-team.irpo; do
    openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A -out "$name.key"
    openssl req -new -md_gost12_256 -key "$name.key" -out "$name.csr" -subj "/C=RU/ST=Exam/L=Exam/O=AU-Team/OU=IRPO/CN=$name"
    openssl x509 -req -in "$name.csr" -CA ca.cer -CAkey ca.key -CAcreateserial -out "$name.cer" -days 30
  done
fi

systemctl enable --now cups || true
cupsctl --remote-any --share-printers || true
systemctl restart cups || true

mkdir -p /opt
cat > /etc/rsyslog.d/99-remote-collector.conf <<'EOF'
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
$template RemoteLogs,"/opt/%HOSTNAME%/%PROGRAMNAME%.log"
*.warning ?RemoteLogs
EOF
systemctl enable --now rsyslog || true
systemctl restart rsyslog || true
cat > /etc/logrotate.d/rsyslog-remote.conf <<'EOF'
/opt/*/*.log {
    weekly
    size 10M
    compress
    missingok
    notifempty
}
EOF

systemctl enable --now docker || true
mkdir -p /root/zabbix
cat > /root/zabbix/compose.yml <<'EOF'
services:
  zabbix-postgresdb:
    image: postgres:latest
    container_name: zabbix-postgresdb
    restart: unless-stopped
    environment:
      TZ: "Europe/Moscow"
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbixpass
    volumes:
      - /opt/zabbix/postgresdb/data:/var/lib/postgresql/data
  zabbix-server:
    image: zabbix/zabbix-server-pgsql:latest
    container_name: zabbix-server
    restart: unless-stopped
    environment:
      TZ: "Europe/Moscow"
      DB_SERVER_HOST: zabbix-postgresdb
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbixpass
    depends_on:
      - zabbix-postgresdb
  zabbix-web:
    image: zabbix/zabbix-web-nginx-pgsql:latest
    container_name: zabbix-web
    restart: unless-stopped
    environment:
      TZ: "Europe/Moscow"
      DB_SERVER_HOST: zabbix-postgresdb
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbixpass
      ZBX_SERVER_HOST: zabbix-server
      PHP_TZ: "Europe/Moscow"
    ports:
      - "8000:8080"
      - "8443:8443"
    depends_on:
      - zabbix-postgresdb
      - zabbix-server
EOF
(cd /root/zabbix && docker compose up -d) || true

if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
  sed -i -E 's/^Server=.*/Server=0.0.0.0\/0/' /etc/zabbix/zabbix_agentd.conf || true
  sed -i -E 's/^ServerActive=.*/ServerActive=192.168.1.10/' /etc/zabbix/zabbix_agentd.conf || true
  grep -q '^Server=' /etc/zabbix/zabbix_agentd.conf || echo 'Server=0.0.0.0/0' >> /etc/zabbix/zabbix_agentd.conf
  grep -q '^ServerActive=' /etc/zabbix/zabbix_agentd.conf || echo 'ServerActive=192.168.1.10' >> /etc/zabbix/zabbix_agentd.conf
  systemctl enable --now zabbix_agentd || true
  systemctl restart zabbix_agentd || true
fi

mkdir -p /etc/fail2ban/jail.d
[ -f /etc/fail2ban/jail.conf ] && sed -i 's/^#before = paths-alinux-systemd.conf/before = paths-alinux-systemd.conf/' /etc/fail2ban/jail.conf || true
cat > /etc/fail2ban/jail.d/sshd.conf <<EOF
[sshd]
enabled = true
port = ${PRIMARY_SSH_PORT},${SECONDARY_SSH_PORT}
maxretry = 3
findtime = 180
bantime = 60
EOF
systemctl enable --now fail2ban || true
systemctl restart fail2ban || true

echo 'OK: HQ-SRV M2/M3 без 3.3 настроен. Сертификаты лежат в /root/ca-gost. Вручную: index.php, Zabbix GUI, CryptoPro/CyberBackup.'
