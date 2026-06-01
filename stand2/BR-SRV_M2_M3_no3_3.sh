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

# Dok 4 / Стенд 2 / Модули 2-3 без задания 3.3 / BR-SRV
# Делает: Samba DC, hquser1-5/hq, chrony, Ansible, Docker testapp, rsyslog client, zabbix-agent, import helper, playbook copy.
ISO_DEV="${ISO_DEV:-/dev/sr0}"
ISO_MNT="${ISO_MNT:-/mount}"
PRIMARY_SSH_PORT="${PRIMARY_SSH_PORT:-2014}"
APP_IMAGE="${APP_IMAGE:-site:latest}"
DB_IMAGE="${DB_IMAGE:-mariadb:latest}"

install_pkgs task-samba-dc ansible sshpass docker-engine docker-compose-v2 python3-module-pip chrony rsyslog zabbix-agent
backup_file /etc/chrony.conf
cat > /etc/chrony.conf <<'EOF'
# pool pool.ntp.org iburst
server 172.16.80.1 iburst prefer
EOF
systemctl enable --now chronyd || true
systemctl restart chronyd || true

if ! samba-tool domain info 127.0.0.1 >/dev/null 2>&1; then
  rm -f /etc/samba/smb.conf
  samba-tool domain provision --realm=AU-TEAM.IRPO --domain=AU-TEAM --server-role=dc --dns-backend=SAMBA_INTERNAL --option='dns forwarder=192.168.1.10' --adminpass='123qweR%' --use-rfc2307
  mv -f /var/lib/samba/private/krb5.conf /etc/krb5.conf || true
  echo 'INFO: после первого provision рекомендуется reboot BR-SRV, затем повторный запуск этого скрипта.'
fi
systemctl enable samba || true
systemctl restart samba || true
for i in 1 2 3 4 5; do
  samba-tool user show "hquser$i" >/dev/null 2>&1 || samba-tool user add "hquser$i" '123qweR%'
done
samba-tool group show hq >/dev/null 2>&1 || samba-tool group add hq
samba-tool group addmembers hq hquser1,hquser2,hquser3,hquser4,hquser5 || true

apt-repo add rpm http://altrepo.ru/local-p10 noarch local-p10 || true
apt-get update || true
apt-get install -y sudo-samba-schema || true

mkdir -p /etc/ansible/PC-INFO
cat > /etc/ansible/hosts <<EOF
HQ-SRV ansible_host=192.168.1.10 ansible_user=sshuser ansible_password=P@ssw0rd ansible_port=${PRIMARY_SSH_PORT}
HQ-CLI ansible_host=192.168.2.10 ansible_user=user ansible_password=resu ansible_port=22
HQ-RTR ansible_host=172.16.70.2 ansible_user=net_admin ansible_password=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
BR-RTR ansible_host=192.168.3.1 ansible_user=net_admin ansible_password=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
cat > /etc/ansible/ansible.cfg <<'EOF'
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
deprecation_warnings = False
EOF
ansible-galaxy collection install ansible.netcommon || true
ansible-galaxy collection install cisco.ios || true
pip3 install ansible-pylibssh || true

systemctl enable --now docker.service || true
mkdir -p "$ISO_MNT"
mountpoint -q "$ISO_MNT" || mount "$ISO_DEV" "$ISO_MNT" 2>/dev/null || true
[ -f "$ISO_MNT/docker/site_latest.tar" ] && docker load < "$ISO_MNT/docker/site_latest.tar" || true
[ -f "$ISO_MNT/docker/mariadb_latest.tar" ] && docker load < "$ISO_MNT/docker/mariadb_latest.tar" || true
mkdir -p /root/testapp
cat > /root/testapp/compose.yaml <<EOF
services:
  database:
    container_name: db
    image: ${DB_IMAGE}
    restart: always
    ports:
      - "3306:3306"
    environment:
      MARIADB_DATABASE: "testdb"
      MARIADB_USER: "test"
      MARIADB_PASSWORD: "P@ssw0rd"
      MARIADB_ROOT_PASSWORD: "toor"
  app:
    container_name: testapp
    image: ${APP_IMAGE}
    restart: always
    ports:
      - "8080:8080"
    environment:
      DB_TYPE: "maria"
      DB_HOST: "192.168.3.10"
      DB_PORT: "3306"
      DB_NAME: "testdb"
      DB_USER: "test"
      DB_PASS: "P@ssw0rd"
    depends_on:
      - database
EOF
(cd /root/testapp && docker compose up -d) || true

cat > /etc/rsyslog.d/99-send-to-hq.conf <<'EOF'
*.warning @@192.168.1.10:514
*.warning @192.168.1.10:514
EOF
systemctl enable --now rsyslog || true
systemctl restart rsyslog || true

if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
  sed -i -E 's/^Server=.*/Server=0.0.0.0\/0/' /etc/zabbix/zabbix_agentd.conf || true
  sed -i -E 's/^ServerActive=.*/ServerActive=192.168.1.10/' /etc/zabbix/zabbix_agentd.conf || true
  grep -q '^Server=' /etc/zabbix/zabbix_agentd.conf || echo 'Server=0.0.0.0/0' >> /etc/zabbix/zabbix_agentd.conf
  grep -q '^ServerActive=' /etc/zabbix/zabbix_agentd.conf || echo 'ServerActive=192.168.1.10' >> /etc/zabbix/zabbix_agentd.conf
  systemctl enable --now zabbix_agentd || true
  systemctl restart zabbix_agentd || true
fi

cat > /root/import_users_from_csv.sh <<'EOF'
#!/bin/bash
set -euo pipefail
CSV="${1:-/opt/Users.csv}"
[ -f "$CSV" ] || { echo "CSV not found: $CSV" >&2; exit 1; }
python3 - <<'PYCSV' "$CSV" > /tmp/import_users_samba.sh
import csv, re, sys
path=sys.argv[1]
def norm(s):
    return re.sub(r'[^a-zа-я0-9]+', '_', (s or '').strip().lower())
with open(path, encoding='utf-8-sig', newline='') as f:
    sample=f.read(4096); f.seek(0)
    try: dialect=csv.Sniffer().sniff(sample, delimiters=';,')
    except Exception: dialect=csv.excel
    reader=csv.DictReader(f, dialect=dialect)
    fields={norm(x):x for x in (reader.fieldnames or [])}
    def pick(row, names, default=''):
        for n in names:
            if n in fields and row.get(fields[n]): return str(row[fields[n]]).strip()
        return default
    print('#!/bin/bash')
    print('set -e')
    for row in reader:
        first=pick(row,['firstname','first_name','name','имя'])
        last=pick(row,['lastname','last_name','surname','фамилия'])
        login=pick(row,['username','user','login','samaccountname','учетная_запись','учётная_запись'])
        password=pick(row,['password','pass','пароль'], 'P@ssw0rd')
        if not login:
            login=(first+'.'+last).strip('.').lower().replace(' ','')
        if not login: continue
        print(f"samba-tool user show {login!r} >/dev/null 2>&1 || samba-tool user add {login!r} {password!r}")
PYCSV
bash /tmp/import_users_samba.sh
EOF
chmod +x /root/import_users_from_csv.sh
if [ -f "$ISO_MNT/Users.csv" ]; then
  iconv -f iso-8859-1 -t utf-8 "$ISO_MNT/Users.csv" > /opt/Users.csv || cp "$ISO_MNT/Users.csv" /opt/Users.csv
fi
if [ -f "$ISO_MNT/playbook/get_hostname_address.yml" ]; then
  cp -f "$ISO_MNT/playbook/get_hostname_address.yml" /etc/ansible/get_hostname_address.yml
else
  cat > /etc/ansible/get_hostname_address.yml <<'EOF'
---
- name: Inventory HQ machines
  hosts: HQ-SRV,HQ-CLI
  gather_facts: yes
  tasks:
    - name: Save hostname and IP
      delegate_to: localhost
      copy:
        dest: "/etc/ansible/PC-INFO/{{ ansible_hostname }}.yml"
        content: |
          hostname: {{ ansible_hostname }}
          ip_address: {{ ansible_default_ipv4.address | default('unknown') }}
EOF
fi

echo 'OK: BR-SRV M2/M3 без 3.3 настроен. Вручную: reboot после provision, sudo-schema-apply/create-sudo-rule/ADMC, ввод HQ-CLI в домен, CSV import/проверка.'
