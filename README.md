# EV Infrastructure

Automated infrastructure provisioning for Raspberry Pi devices using Ansible and cloud-init. This project automatically configures a Raspberry Pi to run containerized services with secure external access via Cloudflare Tunnel.

## Features

- **Zero-touch deployment**: Insert SD card, power on, and the Pi configures itself
- **Secure remote access**: Cloudflare Tunnel provides HTTPS access without exposing your home IP
- **Infrastructure as Code**: Ansible playbooks for reproducible configurations
- **Secret management**: Secrets injected at build time, never committed to git
- **Auto-updates**: Bootstrap script pulls latest configuration from git on each run

## Prerequisites

- Raspberry Pi (3/4/5 or Zero 2 W)
- MicroSD card (16GB+ recommended)
- Ubuntu Server for Raspberry Pi (22.04 LTS or newer)
- Cloudflare account with a configured tunnel
- SSH key pair
- Git repository (this one, forked/cloned)

## Quick Start

### 1. Generate SSH Keys (if you don't have them)

```powershell
# On Windows PowerShell
ssh-keygen -t ed25519 -C "$env:USERNAME@$env:COMPUTERNAME" -f "$env:USERPROFILE\.ssh\id_ed25519"
```

```bash
# On Linux/macOS
ssh-keygen -t ed25519 -C "$USER@$HOSTNAME" -f ~/.ssh/id_ed25519
```

### 2. Get Cloudflare Tunnel Token

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks** → **Tunnels**
3. Create a new tunnel or use an existing one
4. Copy the tunnel token (starts with `eyJh...`)

### 3. Configure Environment

Copy `.env.public` to `.env` and fill in your values:

```bash
cp .env.public .env
```

Edit `.env`:

```bash
CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoiZ..."
USER_NAME="your-username"
DEVICE_HOSTNAME="ev-rpi"
SSH_PUBLIC_KEY_PATH="~/.ssh/id_ed25519.pub"
REPO_URL="https://github.com/your-username/ev_infra.git"
```

### 4. Generate Boot Configuration

```bash
./generate_boot_config.sh /path/to/sd-card/system-boot
```

This creates configuration files with your secrets injected. **These files are not committed to git.**

### 5. Flash Ubuntu Server

1. Download [Ubuntu Server for Raspberry Pi](https://ubuntu.com/download/raspberry-pi)
2. Flash to SD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or `dd`
3. Copy the generated files from step 4 to the `system-boot` partition on the SD card
   - **Note**: Ubuntu Server uses cloud-init by default, so the files will be automatically detected

### 6. Boot Your Pi

1. Insert SD card into Raspberry Pi
2. Connect to network (Ethernet recommended for first boot)
3. Power on
4. Wait 2-5 minutes for initial setup and package installation

### 7. Connect via SSH

```bash
ssh your-username@ev-rpi.local
# or
ssh your-username@<pi-ip-address>
```

## How It Works

### Boot Sequence

1. **Cloud-init** reads `system-boot/ssh_authorized_keys.yml`:
   - Creates user with sudo privileges
   - Configures SSH authorized keys
   - Installs git and Ansible
   - Writes Cloudflare token to Ansible facts directory
   - Executes `ansible_bootstrap.sh`

2. **Ansible Bootstrap** (`/usr/local/bin/ansible_bootstrap.sh`):
   - Clones this repository to `/etc/ansible/code`
   - Runs `playbooks/site.yml` locally

3. **Ansible Playbook** configures:
   - Docker and Docker Compose
   - Service directory at `/opt/services`
   - `.env` file with secrets
   - Deploys services via Docker Compose

4. **Docker Compose** starts:
   - Demo web service (nginx)
   - Cloudflare Tunnel daemon

### Architecture

```
┌─────────────────────────────────────────┐
│           Raspberry Pi                  │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │      Cloud-init (First Boot)      │ │
│  │  • User creation                  │ │
│  │  • SSH setup                      │ │
│  │  • Package installation           │ │
│  └──────────────┬────────────────────┘ │
│                 │                       │
│  ┌──────────────▼────────────────────┐ │
│  │      Ansible Bootstrap            │ │
│  │  • Git clone repository           │ │
│  │  • Run playbook locally           │ │
│  └──────────────┬────────────────────┘ │
│                 │                       │
│  ┌──────────────▼────────────────────┐ │
│  │      Ansible Playbook             │ │
│  │  • Install Docker                 │ │
│  │  • Configure services             │ │
│  │  • Inject secrets                 │ │
│  └──────────────┬────────────────────┘ │
│                 │                       │
│  ┌──────────────▼────────────────────┐ │
│  │      Docker Compose               │ │
│  │  • Web services                   │ │
│  │  • Cloudflare Tunnel              │ │
│  └───────────────────────────────────┘ │
└─────────────────────────────────────────┘
                  │
                  │ Secure Tunnel
                  ▼
         ┌────────────────┐
         │   Cloudflare   │
         │     Network    │
         └────────────────┘
                  │
                  ▼
            Internet Users
```

## Project Structure

```
.
├── playbooks/
│   └── site.yml              # Main Ansible playbook
├── roles/
│   └── ev_base/
│       ├── tasks/
│       │   └── main.yml      # Ansible tasks
│       ├── handlers/
│       │   └── main.yml      # Service restart handlers
│       └── files/
│           └── docker-compose.yml  # Service definitions
├── system-boot/
│   ├── ssh_authorized_keys.yml     # Cloud-init configuration (template)
│   ├── metadata.yml                # Instance metadata (template)
│   └── network-config.yml          # Network configuration
├── generate_boot_config.sh   # Build script
├── .env.public               # Environment template
└── .env                      # Your secrets (gitignored)
```

## Customization

### Adding Services

Edit `roles/ev_base/files/docker-compose.yml` to add new services:

```yaml
services:
  your-app:
    image: your-image:latest
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      - YOUR_VAR=${YOUR_VAR}
```

Add corresponding secrets to `.env` and update the Ansible task in `roles/ev_base/tasks/main.yml` to include them in `/opt/services/.env`.

### Modifying Configuration

All infrastructure changes should be made in the Ansible playbook:

- `roles/ev_base/tasks/main.yml` - Main configuration tasks
- `roles/ev_base/handlers/main.yml` - Service restart logic

Push changes to git, then SSH into your Pi and run:

```bash
sudo bash /usr/local/bin/ansible_bootstrap.sh
```

## Security Considerations

- **Never commit `.env`** - It contains secrets
- **Cloudflare Tunnel** provides secure access without exposing your home IP
- **SSH keys only** - Password authentication is disabled
- **Automatic updates** - Keep packages updated in the cloud-init configuration
- **Minimal permissions** - Services run as non-root in containers

## Troubleshooting

### Pi doesn't appear on network

- Check Ethernet cable connection
- Verify SD card was flashed correctly
- Check cloud-init logs: `sudo cat /var/log/cloud-init-output.log`

### Can't SSH to Pi

- Verify SSH key is correctly configured in `.env`
- Check hostname resolves: `ping ev-rpi.local`
- Try IP address instead of hostname
- Check SSH service: `sudo systemctl status ssh`

### Services not starting

- Check Ansible logs: `sudo journalctl -u ansible-pull`
- Verify Docker is running: `sudo systemctl status docker`
- Check Docker Compose logs: `sudo docker compose -f /opt/services/docker-compose.yml logs`

### Cloudflare Tunnel not working

- Verify token is correct in `.env`
- Check tunnel status in Cloudflare dashboard
- Check container logs: `sudo docker compose -f /opt/services/docker-compose.yml logs cloudflared`

## License

MIT

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
