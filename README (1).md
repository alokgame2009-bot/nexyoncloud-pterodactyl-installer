# NexyonCloud Pterodactyl Manager

Professional, reviewable Bash manager for installing and maintaining the **current Pterodactyl 1.x Panel** on a clean Ubuntu VPS.

> NexyonCloud is an independent community project. It is not affiliated with or endorsed by Pterodactyl.

## Menu

```text
╔══════════════════════════════════════════════╗
║     NEXYONCLOUD PTERODACTYL MANAGER         ║
╚══════════════════════════════════════════════╝

1) Install Panel
2) Update Panel
3) Status / Health Check
4) Uninstall Panel
5) Exit
```

There is **no separate Backup Panel menu item**. Safety backups are created internally when an update or uninstall needs them.

## What is real / supported

The script performs real system operations. It does not simulate installation progress or fake service checks.

### Install Panel

- Checks Ubuntu 22.04/24.04 LTS.
- Detects the VPS public IPv4.
- Asks for the Panel domain and timezone.
- Installs PHP 8.3, PHP-FPM extensions, MariaDB, Redis, NGINX, Composer 2 and required utilities.
- Downloads the current Pterodactyl 1.x release directly from the official Pterodactyl GitHub release archive.
- Creates the Panel database and database user locally.
- Runs the official Pterodactyl 1.x environment setup commands.
- Runs database migrations and seeds.
- Configures NGINX.
- Configures the queue worker and scheduler.
- Optionally obtains a Let's Encrypt certificate.
- Sets correct `www-data` permissions.

### Update Panel

- Checks the installed Panel version.
- Checks the newest Pterodactyl 1.x release rather than blindly following a future 2.x release.
- Offers a safety backup before changing files.
- Enables Laravel maintenance mode.
- Stops the queue worker while the application is replaced.
- Preserves `.env`, `APP_KEY`, and `storage/`.
- Installs Composer dependencies.
- Runs `composer check-platform-reqs --no-dev`.
- Runs migrations/seeds and clears caches.
- Restarts the queue worker and exits maintenance mode.

The updater deliberately does **not** run `php artisan key:generate`.

### Status / Health Check

Checks real service state for:

- NGINX
- MariaDB
- Redis
- PHP-FPM
- Pterodactyl queue worker
- NGINX configuration
- Panel version
- `.env` / `APP_KEY` presence
- Disk usage
- RAM usage
- Public IPv4

### Uninstall Panel

- Requires explicit `UNINSTALL` confirmation.
- Offers a final safety backup.
- Removes the Panel application files.
- Removes the Pterodactyl queue service.
- Removes the Panel NGINX configuration.
- Preserves the database by default.
- Separately asks whether the Panel database/user should be deleted.
- Does **not** remove Wings, Docker, MariaDB, Redis or unrelated packages.

## Requirements

- Ubuntu 22.04 LTS or Ubuntu 24.04 LTS
- Root access
- Public IPv4
- A DNS A record for the Panel domain
- A fresh VPS is strongly recommended

Pterodactyl's official 1.x documentation supports Ubuntu 22.04 and 24.04 and lists PHP 8.2/8.3, MariaDB/MySQL, Redis, a web server and Composer 2 among the Panel dependencies.

## Install from GitHub

Clone your own reviewed repository:

```bash
git clone https://github.com/YOUR_GITHUB_USER/nexyon-pterodactyl-installer.git
cd nexyon-pterodactyl-installer
chmod +x install.sh
sudo ./install.sh
```

Or:

```bash
sudo bash install.sh
```

Do not run an unknown `curl | bash` installer without reviewing its source first.

## DNS before HTTPS

If your Panel domain is:

```text
panel.example.com
```

create an A record:

```text
panel.example.com  ->  YOUR_VPS_PUBLIC_IPV4
```

Wait until DNS resolves to the VPS before selecting Let's Encrypt HTTPS in the installer.

## First administrator

After installation:

```bash
cd /var/www/pterodactyl
php artisan p:user:make
```

Follow the prompts to create the first administrator account.

## Backups

The manager does not expose a standalone backup menu item, but it can create encrypted-by-permissions safety archives during update/uninstall operations.

Backups are stored at:

```text
/root/pterodactyl-backups/
```

They can contain:

- `.env` and `APP_KEY`
- Panel database dump
- Panel files
- NGINX configuration

Keep an additional copy outside the VPS. Never publish `.env` or database dumps to GitHub.

## Wings

This project installs **Panel only**.

Wings is the separate daemon that runs on game nodes. After the Panel is working, install and configure Wings separately on the node VPS, then create the node inside the Panel.

## Themes and extensions

Do not install a theme or extension before confirming it supports your exact Panel release. Third-party themes/extensions can modify Panel files and may require a compatibility update after a Panel update.

Always keep a safety backup before modifying a production Panel.

## Security checklist

- Restrict SSH port 22 to your own IP where possible.
- Expose only the required web ports 80/443 for the Panel.
- Do not publicly expose MariaDB 3306 or Redis 6379.
- Use a strong administrator password.
- Keep `.env`, API tokens and `APP_KEY` private.
- Keep the VPS and Panel updated.
- Back up before Panel/theme/extension changes.
- Use a separate VPS/node for Wings when appropriate.

## Logs

Manager activity is written to:

```text
/var/log/nexyon-pterodactyl-manager.log
```

The Panel itself keeps its own Laravel logs under:

```text
/var/www/pterodactyl/storage/logs/
```

## Official Pterodactyl resources

- https://pterodactyl.io/
- https://docs.pterodactyl.io/
- https://docs.pterodactyl.io/v1/panel/getting-started
- https://github.com/pterodactyl/panel/releases

## License

The NexyonCloud manager script is released under the MIT License in this repository. Pterodactyl remains a separate project with its own license and terms.


## Compatibility Fixes in this build

- Removed the unsupported `--redis-password` argument; uses Pterodactyl 1.x `--redis-pass` syntax.
- Uses non-interactive supported flags for database and administrator creation.
- Enforces the documented administrator password complexity (8+ characters, mixed case, and a number).
- Includes PHP Intl extension.
- Keeps Asia/Kolkata and automatic HTTPS behavior.
