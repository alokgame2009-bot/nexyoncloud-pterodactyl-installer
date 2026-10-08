# NexyonCloud Pterodactyl Manager

Real interactive Pterodactyl 1.x installer.

Main menu:
1) Install Panel
2) Update Panel
3) Status / Health Check
4) Uninstall Panel
5) Exit

Install Panel performs actual dependency installation, MariaDB/Redis setup, current Pterodactyl release download, Composer install, migrations/seeding, real administrator creation, NGINX configuration, Let's Encrypt HTTPS and queue/scheduler setup.

Requirements:
- Root server
- Ubuntu 22.04/24.04 or Debian 11/12/13
- Fresh server recommended
- DNS A/AAAA record for the panel domain must already point to the server
- Ports 80/443 reachable for Let's Encrypt

Run:
sudo bash nexyoncloud-installer.sh

The admin password is never hard-coded. Leaving it empty generates a random password and stores credentials at:
`/root/nexyoncloud-pterodactyl-credentials.txt`

## Quick Install

On a fresh supported server, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alokgame2009-bot/nexyoncloud-pterodactyl-installer/main/install.sh)
```

Or, if you already downloaded the ZIP, extract it and run the included installer directly.

