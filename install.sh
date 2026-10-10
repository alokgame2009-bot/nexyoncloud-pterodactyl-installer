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
secret(){
  local a b c
  a="$(openssl rand -hex 10)"
  b="$(printf '%c' $((65 + $(od -An -N1 -tu1 /dev/urandom) % 26)))"
  c="$(( $(od -An -N1 -tu1 /dev/urandom) % 10 ))"
  printf '%s%s%s' "$b" "$c" "$a"
}

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
    "php$PHP_VERSION-curl" "php$PHP_VERSION-zip" "php$PHP_VERSION-intl"

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

  php artisan p:environment:setup -n \
    --author="$ADMIN_EMAIL" --url="https://$DOMAIN" --timezone="$TZ" \
    --cache=redis --session=redis --queue=redis \
    --redis-host=127.0.0.1 --redis-port=6379 --redis-pass=""

  php artisan p:environment:database -n \
    --host=127.0.0.1 --port=3306 --database="$DB_NAME" --username="$DB_USER" --password="$DB_PASS"

  # Current Pterodactyl versions do not provide a --from-name option here.
  # Configure the mailer with the supported command, then set the From address/name
  # directly in .env so the installer remains non-interactive.
  php artisan p:environment:mail -n \
    --driver=log --host=127.0.0.1 --port=25 \
    --username=null --password=null --encryption=null \
    --from="$ADMIN_EMAIL"
  sed -i 's/^MAIL_FROM_NAME=.*/MAIL_FROM_NAME="NexyonCloud Pterodactyl"/' .env

  php artisan migrate --seed --force

  # Create the real Pterodactyl administrator using supported CLI options.
  # This avoids fragile interactive prompt piping and ensures the account is root-admin.
  php artisan p:user:make \
    --email="$ADMIN_EMAIL" \
    --username="$ADMIN_USER" \
    --name-first="NexyonCloud" \
    --name-last="Admin" \
    --password="$ADMIN_PASS" \
    --admin=1

  chown -R www-data:www-data "$PANEL_DIR"
  chmod -R 755 storage/* bootstrap/cache/* 2>/dev/null || true
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

install_wings(){
  root
  echo
  echo "NEXYONCLOUD WINGS INSTALLER (DOMAIN + SSL)"
  echo "This installs Docker and the Wings binary inside this installer."
  echo "It does not launch or download the separate pterodactyl-installer script."
  echo
  read -r -p "Continue with Wings installation? (y/n): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || return 0

  if [[ ! -r /etc/os-release ]]; then
    echo "Cannot identify Linux distribution."; pause; return 1
  fi
  . /etc/os-release
  case "$ID" in
    ubuntu|debian) ;;
    *) echo "Wings installer currently supports Ubuntu and Debian in this menu."; pause; return 1;;
  esac

  local WINGS_DOMAIN WINGS_EMAIL default_domain cert_path key_path nginx_was_active
  default_domain=""
  if [[ -s /etc/pterodactyl/config.yml ]]; then
    # Prefer the domain already referenced by the node's Let's Encrypt certificate path.
    default_domain="$(sed -nE 's/^[[:space:]]*cert:[[:space:]]*\/etc\/letsencrypt\/live\/([^/]+)\/fullchain\.pem[[:space:]]*$/\1/p' /etc/pterodactyl/config.yml | head -n1)"
    if [[ -z "$default_domain" ]]; then
      default_domain="$(sed -nE 's#^[[:space:]]*remote:[[:space:]]*https?://([^/:]+).*#\1#p' /etc/pterodactyl/config.yml | head -n1)"
    fi
  fi
  echo
  echo "Wings HTTPS certificate setup (Let's Encrypt)"
  echo "Enter the domain you want to use for this Wings node."
  echo "Before continuing, its DNS A record must point to this VPS public IP and inbound TCP port 80 must be reachable."
  read -r -p "Enter Wings node domain (e.g. node.example.com)${default_domain:+ [$default_domain]}: " WINGS_DOMAIN
  WINGS_DOMAIN="${WINGS_DOMAIN:-$default_domain}"
  valid_domain "$WINGS_DOMAIN" || { echo "A valid node domain is required for SSL."; pause; return 1; }
  read -r -p "Email for Let's Encrypt certificate notices (e.g. your Gmail): " WINGS_EMAIL
  valid_email "$WINGS_EMAIL" || { echo "A valid email address is required."; pause; return 1; }

  local arch wings_asset
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
    amd64|x86_64) wings_asset="wings_linux_amd64";;
    arm64|aarch64) wings_asset="wings_linux_arm64";;
    *) echo "Unsupported CPU architecture: $arch"; pause; return 1;;
  esac

  export DEBIAN_FRONTEND=noninteractive
  echo "[1/4] Installing required packages and Docker..."
  apt-get update || { echo "apt update failed."; pause; return 1; }
  apt-get install -y ca-certificates curl tar docker.io certbot || { echo "Package installation failed."; pause; return 1; }
  systemctl enable --now docker || { echo "Docker service failed to start."; pause; return 1; }

  echo "[2/4] Downloading the Wings binary..."
  install -d -m 0755 /usr/local/bin /etc/pterodactyl
  local tmpfile
  tmpfile="$(mktemp)"
  if ! curl -fL --retry 3 "https://github.com/pterodactyl/wings/releases/latest/download/${wings_asset}" -o "$tmpfile"; then
    rm -f "$tmpfile"
    echo "Could not download Wings (${wings_asset})."; pause; return 1
  fi
  install -m 0755 "$tmpfile" /usr/local/bin/wings
  rm -f "$tmpfile"

  echo "[3/4] Creating the Wings systemd service..."
  cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable wings

  echo "[4/5] Requesting Wings HTTPS certificate..."
  nginx_was_active=0
  if systemctl is-active --quiet nginx 2>/dev/null; then
    nginx_was_active=1
    systemctl stop nginx || { echo "Could not stop NGINX temporarily; cannot use standalone certificate validation."; pause; return 1; }
  fi
  if certbot certonly --standalone --preferred-challenges http -d "$WINGS_DOMAIN" \
      --non-interactive --agree-tos --email "$WINGS_EMAIL"; then
    cert_path="/etc/letsencrypt/live/$WINGS_DOMAIN/fullchain.pem"
    key_path="/etc/letsencrypt/live/$WINGS_DOMAIN/privkey.pem"
    if [[ -s /etc/pterodactyl/config.yml ]]; then
      # Update certificate/key paths in the panel-generated Wings config.
      sed -i -E \
        -e "s#^([[:space:]]*cert:[[:space:]]*).*/fullchain\.pem[[:space:]]*$#\1$cert_path#" \
        -e "s#^([[:space:]]*key:[[:space:]]*).*/privkey\.pem[[:space:]]*$#\1$key_path#" \
        /etc/pterodactyl/config.yml
      echo "Updated TLS certificate paths in /etc/pterodactyl/config.yml."
    else
      echo "Certificate created. Add the Panel-generated node config to /etc/pterodactyl/config.yml before starting Wings."
    fi
  else
    echo "Let's Encrypt certificate request failed. Check DNS, port 80/security-group rules, and try again."
  fi
  if [[ "$nginx_was_active" == 1 ]]; then
    systemctl start nginx || echo "WARNING: NGINX did not restart; check: systemctl status nginx"
  fi

  echo "[5/5] Checking configuration..."
  if [[ -s /etc/pterodactyl/config.yml && -s "/etc/letsencrypt/live/$WINGS_DOMAIN/fullchain.pem" && -s "/etc/letsencrypt/live/$WINGS_DOMAIN/privkey.pem" ]]; then
    if systemctl restart wings && systemctl is-active --quiet wings; then
      echo "Wings installed, HTTPS certificate configured, and service is running."
    else
      echo "Wings/certificate installed, but Wings did not start. Check: journalctl -u wings -n 100 --no-pager"
    fi
  else
    echo
    echo "Wings binary and service installed, but startup is waiting for a valid config and SSL certificate."
    echo "Panel: Admin → Nodes → your node → Configuration"
    echo "Config path: /etc/pterodactyl/config.yml"
    echo "After config/certificate is ready, run: systemctl start wings"
  fi
  echo
  echo "Wings binary: /usr/local/bin/wings"
  echo "Config path:  /etc/pterodactyl/config.yml"
  echo "Service:      systemctl status wings"
  pause
}

wings_starter(){
  root
  echo
  echo "NEXYONCLOUD WINGS STARTER"
  echo "Step 1/2: Open the Wings configuration file in nano."
  echo "Paste the configuration copied from Panel → Admin → Nodes → your node → Configuration."
  echo "Save with Ctrl+O, Enter, then exit with Ctrl+X."
  echo

  if [[ ! -x /usr/local/bin/wings ]]; then
    echo "Wings binary not found. Please run option 2 (Install Wings) first."
    pause
    return 1
  fi

  if ! command -v nano >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y nano || { echo "Could not install nano."; pause; return 1; }
  fi

  install -d -m 0755 /etc/pterodactyl
  touch /etc/pterodactyl/config.yml
  nano /etc/pterodactyl/config.yml

  echo
  if [[ ! -s /etc/pterodactyl/config.yml ]]; then
    echo "Config file is empty. Wings was NOT started. Add the node configuration and try again."
    pause
    return 1
  fi

  echo "Step 2/2: Starting Wings..."
  systemctl start wings
  if systemctl is-active --quiet wings; then
    echo "Wings started successfully."
    systemctl --no-pager --full status wings || true
  else
    echo "Wings could not start. Check the config and logs below."
    journalctl -u wings -n 40 --no-pager || true
  fi
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

uninstall_panel(){
  root
  echo
  echo "PANEL UNINSTALL"
  echo "This removes the Panel files, its NGINX site, queue worker, and scheduler entry."
  echo "System packages and unrelated NGINX sites will be kept."
  read -r -p "Type REMOVE-PANEL to continue: " confirm
  [[ "$confirm" == "REMOVE-PANEL" ]] || { echo "Cancelled."; pause; return 0; }

  local db_name="" db_user="" panel_url="" cert_domain=""
  if [[ -f "$PANEL_DIR/.env" ]]; then
    db_name="$(sed -n 's/^DB_DATABASE=//p' "$PANEL_DIR/.env" | head -n1 | tr -d '\r' | sed 's/^"//;s/"$//')"
    db_user="$(sed -n 's/^DB_USERNAME=//p' "$PANEL_DIR/.env" | head -n1 | tr -d '\r' | sed 's/^"//;s/"$//')"
    panel_url="$(sed -n 's/^APP_URL=//p' "$PANEL_DIR/.env" | head -n1 | tr -d '\r' | sed 's/^"//;s/"$//')"
    cert_domain="${panel_url#https://}"; cert_domain="${cert_domain#http://}"; cert_domain="${cert_domain%%/*}"; cert_domain="${cert_domain%%:*}"
  fi

  systemctl disable --now pteroq.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/pteroq.service /etc/cron.d/pterodactyl
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
  if [[ -d "$PANEL_DIR" ]]; then rm -rf -- "$PANEL_DIR"; fi

  if command -v mariadb >/dev/null 2>&1 && [[ -n "$db_name" && "$db_name" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo
    echo "Panel database detected: $db_name"
    read -r -p "Also permanently delete this database? Type DELETE-DB to confirm (anything else keeps it): " db_confirm
    if [[ "$db_confirm" == "DELETE-DB" ]]; then
      mariadb -e "DROP DATABASE IF EXISTS \`$db_name\`;" || echo "WARNING: Could not drop database; inspect MariaDB manually."
      if [[ -n "$db_user" && "$db_user" =~ ^[A-Za-z0-9_]+$ ]]; then
        mariadb -e "DROP USER IF EXISTS '$db_user'@'127.0.0.1'; DROP USER IF EXISTS '$db_user'@'localhost'; FLUSH PRIVILEGES;" || echo "WARNING: Could not remove the Panel database user."
      fi
    else
      echo "Database retained: $db_name"
    fi
  else
    echo "No readable Panel database settings found; no database was removed."
  fi

  if command -v nginx >/dev/null 2>&1; then
    if nginx -t; then systemctl reload nginx || echo "WARNING: NGINX reload failed; check systemctl status nginx.";
    else echo "WARNING: Remaining NGINX configuration has an error; inspect nginx -t output."; fi
  fi
  echo
  echo "Panel files and Panel-specific service entries removed. Other packages/sites were kept."
  pause
}

uninstall_wings(){
  root
  echo
  echo "WINGS UNINSTALL"
  echo "This removes Wings, its systemd service, and /etc/pterodactyl configuration."
  echo "Docker and /var/lib/pterodactyl server data/volumes will be KEPT to avoid accidental data loss."
  read -r -p "Type REMOVE-WINGS to continue: " confirm
  [[ "$confirm" == "REMOVE-WINGS" ]] || { echo "Cancelled."; pause; return 0; }

  systemctl disable --now wings.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/wings.service
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed wings.service >/dev/null 2>&1 || true
  rm -f /usr/local/bin/wings
  if [[ -d /etc/pterodactyl ]]; then
    rm -rf -- /etc/pterodactyl
  fi
  echo
  echo "Wings service, binary, and configuration removed."
  echo "Docker, images, containers, and /var/lib/pterodactyl data were preserved."
  echo "Remove server data or Docker separately only after verifying you no longer need them."
  pause
}

uninstall_menu(){
  root
  while true; do
    echo
    echo "NEXYONCLOUD UNINSTALL MENU"
    echo "1) Panel Uninstall"
    echo "2) Wings Uninstall"
    echo "3) Back to Main Menu"
    echo
    read -r -p "Select an option [1-3]: " uninstall_choice
    case "$uninstall_choice" in
      1) uninstall_panel;;
      2) uninstall_wings;;
      3) return 0;;
      *) echo "Invalid option. Choose 1, 2, or 3.";;
    esac
  done
}

menu(){
while true; do
  banner
  echo "1) Install Panel"
  echo "2) Install Wings (Domain + SSL Setup)"
  echo "3) Wings Starter (Edit config + Start Wings)"
  echo "4) Update Panel"
  echo "5) Status / Health Check"
  echo "6) Uninstall (Panel / Wings)"
  echo "7) Exit"
  echo
  read -r -p "Select an option [1-7]: " choice
  case "$choice" in
    1) install_panel;;
    2) install_wings;;
    3) wings_starter;;
    4) update_panel;;
    5) status;;
    6) uninstall_menu;;
    7) exit 0;;
    *) echo "Invalid option."; sleep 1;;
  esac
done
}
menu
