#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PANEL_DIR="/var/www/pterodactyl"
TZ="Asia/Kolkata"
DOMAIN=""
ADMIN_EMAIL=""
ADMIN_USER=""
ADMIN_PASS=""
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS=""
PHP_VERSION=""

die(){ echo; echo "[ERROR] $*" >&2; exit 1; }
pause(){ echo; read -r -p "Press Enter to continue..." _; }
root(){ [[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"; }
banner(){
clear
echo "╔══════════════════════════════════════════════╗"
echo "║     NEXYONCLOUD PTERODACTYL MANAGER         ║"
echo "╚══════════════════════════════════════════════╝"
echo
}
valid_domain(){ [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; }
valid_email(){ [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; }
secret(){ openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c 32; }

detect_os(){
  . /etc/os-release
  case "$ID:$VERSION_ID" in
    ubuntu:22.04|ubuntu:24.04|debian:11|debian:12|debian:13) ;;
    *) die "Supported: Ubuntu 22.04/24.04 or Debian 11/12/13. Found: $PRETTY_NAME";;
  esac
  if [[ "$ID" == ubuntu ]]; then
    [[ "$VERSION_ID" == 22.04 ]] && PHP_VERSION="8.2" || PHP_VERSION="8.3"
  elif [[ "$VERSION_ID" == 11 ]]; then PHP_VERSION="8.2"
  else PHP_VERSION="8.2"; fi
}

install_deps(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg unzip tar nginx mariadb-server redis-server \
    certbot python3-certbot-nginx openssl cron git

  if [[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 ]]; then
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update
  fi
  if [[ "$ID" == debian && "$VERSION_ID" == 11 ]]; then
    apt-get install -y lsb-release apt-transport-https
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg
    echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
    apt-get update
  fi

  apt-get install -y "php$PHP_VERSION" "php$PHP_VERSION-cli" "php$PHP_VERSION-common" \
    "php$PHP_VERSION-fpm" "php$PHP_VERSION-gd" "php$PHP_VERSION-mysql" \
    "php$PHP_VERSION-mbstring" "php$PHP_VERSION-bcmath" "php$PHP_VERSION-xml" \
    "php$PHP_VERSION-curl" "php$PHP_VERSION-zip"

  systemctl enable --now mariadb redis-server nginx cron "php$PHP_VERSION-fpm"

  if ! command -v composer >/dev/null 2>&1; then
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer.php
    php /tmp/composer.php --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer.php
  fi
}

input_config(){
  banner
  echo "PTERODACTYL PANEL INSTALLATION"
  echo
  read -r -p "• Panel Domain [panel.nobita.indevs.in] : " DOMAIN
  DOMAIN="${DOMAIN:-panel.nobita.indevs.in}"
  valid_domain "$DOMAIN" || die "Invalid domain."

  read -r -p "• Admin Email [admin@gmail.com] : " ADMIN_EMAIL
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@gmail.com}"
  valid_email "$ADMIN_EMAIL" || die "Invalid email."

  read -r -p "• Admin Username [admin] : " ADMIN_USER
  ADMIN_USER="${ADMIN_USER:-admin}"
  [[ "$ADMIN_USER" =~ ^[A-Za-z0-9._-]{3,32}$ ]] || die "Invalid username."

  echo
  echo "• Admin Password"
  echo "  Leave empty to generate a secure random password."
  read -r -s -p "╰─> " ADMIN_PASS
  echo
  [[ -n "$ADMIN_PASS" ]] || ADMIN_PASS="$(secret)"
  [[ ${#ADMIN_PASS} -ge 8 ]] || die "Password must be at least 8 characters."

  DB_PASS="$(secret)"

  echo
  echo "┌─[ REVIEW CONFIGURATION ]────────────────────────────────┐"
  printf "│ Domain:     %-41s│\n" "$DOMAIN"
  printf "│ Email:      %-41s│\n" "$ADMIN_EMAIL"
  printf "│ User:       %-41s│\n" "$ADMIN_USER"
  printf "│ Version:    %-41s│\n" "Latest stable Pterodactyl 1.x"
  printf "│ Timezone:   %-41s│\n" "$TZ"
  printf "│ HTTPS:      %-41s│\n" "Enabled"
  echo "└─────────────────────────────────────────────────────────┘"
  echo
  read -r -p "Start Installation? (y/n): " yes
  [[ "$yes" =~ ^[Yy]$ ]] || exit 0
}

database(){
  mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
}

panel(){
  rm -rf "$PANEL_DIR"
  mkdir -p "$PANEL_DIR"
  cd "$PANEL_DIR"
  curl -fL --retry 3 -o panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf panel.tar.gz
  rm panel.tar.gz
  cp .env.example .env
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

  php artisan key:generate --force

  php artisan p:environment:setup \
    --author="$ADMIN_EMAIL" --url="https://$DOMAIN" --timezone="$TZ" \
    --cache=redis --session=redis --queue=redis \
    --redis-host=127.0.0.1 --redis-port=6379 --redis-password=null --redis-database=0

  php artisan p:environment:database \
    --host=127.0.0.1 --port=3306 --database="$DB_NAME" --username="$DB_USER" --password="$DB_PASS"

  php artisan p:environment:mail \
    --driver=log --host=127.0.0.1 --port=25 \
    --username=null --password=null --encryption=null \
    --from="$ADMIN_EMAIL" --from-name="NexyonCloud Pterodactyl"

  php artisan migrate --seed --force

  # Pterodactyl's own command creates the real administrator.
  printf "yes\n%s\n%s\n%s\n%s\n" "$ADMIN_EMAIL" "$ADMIN_USER" "$ADMIN_PASS" "$ADMIN_PASS" |
    php artisan p:user:make

  chown -R www-data:www-data "$PANEL_DIR"
  chmod -R 755 storage bootstrap/cache
}

nginx_config(){
cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $PANEL_DIR/public;
    index index.php;
    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht { deny all; }
}
EOF
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
}

services(){
cat >/etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $PANEL_DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now pteroq
mkdir -p /etc/cron.d
echo "* * * * * www-data /usr/bin/php $PANEL_DIR/artisan schedule:run >> /dev/null 2>&1" >/etc/cron.d/pterodactyl
chmod 644 /etc/cron.d/pterodactyl
}

https(){
  # DNS must already point at this server; certbot will fail rather than pretending HTTPS is enabled.
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect -m "$ADMIN_EMAIL"
}

save(){
  umask 077
  cat >/root/nexyoncloud-pterodactyl-credentials.txt <<EOF
Panel URL: https://$DOMAIN
Admin Email: $ADMIN_EMAIL
Admin Username: $ADMIN_USER
Admin Password: $ADMIN_PASS
Database: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASS
Timezone: $TZ
APP_KEY:
$(grep '^APP_KEY=' "$PANEL_DIR/.env" || true)
EOF
}

install_panel(){
  root; detect_os; input_config
  echo; echo "[1/7] Installing dependencies..."
  install_deps
  echo "[2/7] Creating database..."
  database
  echo "[3/7] Installing Pterodactyl..."
  panel
  echo "[4/7] Configuring NGINX..."
  nginx_config
  echo "[5/7] Configuring queue + scheduler..."
  services
  echo "[6/7] Enabling HTTPS..."
  https
  echo "[7/7] Saving credentials..."
  save
  echo
  echo "╔══════════════════════════════════════════════╗"
  echo "║          INSTALLATION COMPLETE               ║"
  echo "╚══════════════════════════════════════════════╝"
  echo
  echo "Panel: https://$DOMAIN"
  echo "Admin: $ADMIN_USER"
  echo "Credentials: /root/nexyoncloud-pterodactyl-credentials.txt"
  echo
  pause
}

update_panel(){
  root
  [[ -d "$PANEL_DIR" ]] || { echo "Pterodactyl is not installed."; pause; return; }
  cd "$PANEL_DIR"
  php artisan down || true
  curl -fL --retry 3 -o /tmp/panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf /tmp/panel.tar.gz --overwrite
  rm -f /tmp/panel.tar.gz
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
  php artisan migrate --seed --force
  php artisan view:clear
  php artisan config:clear
  chown -R www-data:www-data "$PANEL_DIR"
  php artisan up
  systemctl restart pteroq
  echo "Panel updated successfully."
  pause
}

status(){
  banner
  echo "PTERODACTYL HEALTH CHECK"
  echo
  for s in nginx mariadb redis-server pteroq; do
    if systemctl is-active --quiet "$s"; then printf "[ OK ] %-18s active\n" "$s"; else printf "[FAIL] %-18s inactive\n" "$s"; fi
  done
  if [[ -f "$PANEL_DIR/.env" ]]; then echo "[ OK ] Panel files present"; else echo "[FAIL] Panel files missing"; fi
  if command -v nginx >/dev/null && nginx -t >/dev/null 2>&1; then echo "[ OK ] NGINX configuration"; else echo "[FAIL] NGINX configuration"; fi
  echo
  pause
}

uninstall(){
  root
  echo "WARNING: This removes the Pterodactyl panel, database and configuration."
  read -r -p "Type UNINSTALL to continue: " x
  [[ "$x" == UNINSTALL ]] || { echo "Cancelled."; pause; return; }
  systemctl disable --now pteroq 2>/dev/null || true
  rm -f /etc/systemd/system/pteroq.service /etc/cron.d/pterodactyl
  systemctl daemon-reload
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
  rm -rf "$PANEL_DIR"
  mariadb -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; DROP USER IF EXISTS '$DB_USER'@'127.0.0.1'; FLUSH PRIVILEGES;" || true
  nginx -t && systemctl reload nginx || true
  echo "Panel removed. System packages were intentionally left installed."
  pause
}

menu(){
while true; do
  banner
  echo "1) Install Panel"
  echo "2) Update Panel"
  echo "3) Status / Health Check"
  echo "4) Uninstall Panel"
  echo "5) Exit"
  echo
  read -r -p "Select an option [1-5]: " choice
  case "$choice" in
    1) install_panel;;
    2) update_panel;;
    3) status;;
    4) uninstall;;
    5) exit 0;;
    *) echo "Invalid option."; sleep 1;;
  esac
done
}
menu
