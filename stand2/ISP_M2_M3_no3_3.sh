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

# Dok 4 / Стенд 2 / Модули 2-3 без задания 3.3 / ISP
# Делает: chrony-сервер, nginx reverse proxy, basic-auth, HTTPS при наличии сертификатов в /etc/nginx/ssl.
install_pkgs chrony nginx apache2 openssl-gost-engine
control openssl-gost enabled || true
backup_file /etc/chrony.conf
cat > /etc/chrony.conf <<'EOF'
# pool pool.ntp.org iburst
server 89.109.251.21 iburst prefer
hwtimestamp *
local stratum 5
allow 0/0
EOF
systemctl enable --now chronyd || true
systemctl restart chronyd || true

mkdir -p /etc/nginx/sites-available.d /etc/nginx/sites-enabled.d /etc/nginx/ssl
if command -v htpasswd >/dev/null 2>&1; then
  htpasswd -bc /etc/nginx/.htpasswd WEB 'P@ssw0rd' || true
else
  echo 'WARN: htpasswd не найден; basic-auth файл не создан.'
fi
backup_file /etc/nginx/sites-available.d/default.conf
cat > /etc/nginx/sites-available.d/default.conf <<'EOF'
server {
    listen 80;
    server_name web.au-team.irpo;
    location / {
        proxy_pass http://172.16.70.2:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
server {
    listen 80;
    server_name docker.au-team.irpo;
    location / {
        proxy_pass http://172.16.80.2:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
server {
    listen 80;
    server_name mon.au-team.irpo;
    location / {
        proxy_pass http://172.16.70.2:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
if [ -f /etc/nginx/ssl/web.au-team.irpo.cer ] && [ -f /etc/nginx/ssl/web.au-team.irpo.key ] && [ -f /etc/nginx/ssl/docker.au-team.irpo.cer ] && [ -f /etc/nginx/ssl/docker.au-team.irpo.key ]; then
  cat >> /etc/nginx/sites-available.d/default.conf <<'EOF'
server {
    listen 443 ssl;
    server_name web.au-team.irpo;
    ssl_certificate /etc/nginx/ssl/web.au-team.irpo.cer;
    ssl_certificate_key /etc/nginx/ssl/web.au-team.irpo.key;
    ssl_ciphers GOST2012-GOST8912-GOST8912:HIGH:MEDIUM;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_pass http://172.16.70.2:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
server {
    listen 443 ssl;
    server_name docker.au-team.irpo;
    ssl_certificate /etc/nginx/ssl/docker.au-team.irpo.cer;
    ssl_certificate_key /etc/nginx/ssl/docker.au-team.irpo.key;
    ssl_ciphers GOST2012-GOST8912-GOST8912:HIGH:MEDIUM;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_pass http://172.16.80.2:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
else
  echo 'INFO: HTTPS-блоки не добавлены. Скопируйте сертификаты/ключи в /etc/nginx/ssl и повторите скрипт.'
fi
ln -sf /etc/nginx/sites-available.d/default.conf /etc/nginx/sites-enabled.d/default.conf
nginx -t || true
systemctl enable --now nginx || true
systemctl restart nginx || true
echo 'OK: ISP M2/M3 без 3.3 настроен.'
