## 🚀 Quick Install

Run the following command on a fresh supported server:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alokgame2009-bot/nexyoncloud-pterodactyl-installer/main/install.sh)
```

### Requirements

* Ubuntu 22.04 / 24.04
* Debian 11 / 12 / 13
* Root access
* Domain pointing to the server
* Ports `80` and `443` accessible

### Installer Menu

```text
╔══════════════════════════════════════════════╗
║     NEXYONCLOUD PTERODACTYL MANAGER         ║
╚══════════════════════════════════════════════╝

1) Install Panel
2) Update Panel
3) Status / Health Check
4) Uninstall Panel
5) Exit

Select an option [1-5]:
```

Select **1) Install Panel** to start the Pterodactyl installation.

The installer configures the panel, database, Redis, NGINX, HTTPS, timezone, administrator account, queue worker and scheduler.
