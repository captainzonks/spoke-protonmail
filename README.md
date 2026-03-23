# spoke-protonmail

Spoke module for [Proton Mail Bridge](https://proton.me/support/bridge) — a custom Docker image providing SMTP/IMAP email service via ProtonMail.

## Services

| Service           | Description                    | Ports                       | Network |
|-------------------|--------------------------------|-----------------------------|---------|
| protonmail-bridge | ProtonMail Bridge SMTP/IMAP    | 25, 143, 465, 587, 993     | troxy   |

## Prerequisites

- Spoke hub deployed with `troxy` network
- ProtonMail account with Bridge-compatible plan (Mail Plus or higher)
- Docker with BuildKit support (builds from source)

## Quick Start

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your GPG identity and network settings

# Create secrets
mkdir -p ${SECRETS_DIR}/proton/
echo "your-bridge-password" > ${SECRETS_DIR}/proton/proton_bridge_password

# Build and deploy
docker compose build
docker compose up -d
```

## First-Time Setup

The bridge requires manual login on first run:

```bash
# Start without --noninteractive (uses default CMD: tail -f /dev/null)
docker compose up -d

# Enter the container
docker exec -it protonmail-bridge bash

# Run the CLI login
proton-bridge --cli
# Use 'login' command, authenticate with ProtonMail credentials
# Use 'info' to verify setup and note the generated bridge password
# Use 'exit' to quit

# Update secrets with the generated password
# Then restart with noninteractive mode (already set in docker-compose.yml)
docker compose restart
```

## Module Environment Variables

| Variable                         | Default                    | Description                        |
|----------------------------------|----------------------------|------------------------------------|
| `PROTONMAIL_BRIDGE_GIT_VERSION`  | `v3.22.0`                 | ProtonMail Bridge source version   |
| `PROTONMAIL_BRIDGE_TAG`          | `1.0_v3.22.0-custom`      | Docker image tag                   |
| `PROTONMAIL_BRIDGE_IMAGE`        | `spoke/protonmail-bridge:...` | Full image reference            |
| `PROTONMAIL_IP`                  | `192.168.35.20`            | Static IP on troxy network         |
| `PROTONMAIL_HOST`                | `mail.${DOMAIN}`           | Bridge hostname                    |
| `PROTONMAIL_URI`                 | `https://mail.${DOMAIN}`   | Bridge URI                         |
| `PROTONMAIL_SMTP_PORT`           | `1026`                     | Internal SMTP port                 |
| `PROTONMAIL_IMAP_PORT`           | `1144`                     | Internal IMAP port                 |
| `GPG_NAME`                       | `proton-user`              | GPG key identity name              |
| `GPG_EMAIL`                      | `proton@fake.me`           | GPG key identity email             |

## Secrets

| Secret Name              | Required | Description                                    |
|--------------------------|----------|------------------------------------------------|
| `proton_bridge_password` | Yes      | Bridge-generated password for SMTP/IMAP auth   |

## Custom Docker Image

This module builds ProtonMail Bridge from source with:

- **Multi-stage build**: Go builder + Debian slim runtime
- **GPG integration**: Automated key generation for pass credential store
- **mailutils + ssmtp**: Built-in email testing tools
- **Socat port forwarding**: Maps internal bridge ports to standard SMTP/IMAP ports
- **Non-root execution**: Configurable UID/GID via build args

### Build Scripts

| Script               | Purpose                                          |
|----------------------|--------------------------------------------------|
| `entrypoint.sh`      | Container init: dirs, GPG, pass, bridge launch   |
| `gpg-setup.sh`       | ECC GPG key generation (Ed25519 + Curve25519)    |
| `mailutils-setup.sh` | Configures /etc/mail.rc and /etc/ssmtp/ssmtp.conf |
| `test-mail.sh`       | Validates SMTP connectivity and sends test emails |

## Architecture

```
External Services (other modules)
    |
    | SMTP (port 25/465/587) or IMAP (port 143/993)
    v
[socat port forwarding]
    |
    | Internal ports (1026/1144)
    v
[proton-bridge --noninteractive]
    |
    | ProtonMail API
    v
[ProtonMail Servers]
```

## References

- [ProtonMail Bridge](https://proton.me/support/bridge)
- [ProtonMail Bridge Source](https://github.com/ProtonMail/proton-bridge)
