#!/usr/bin/env bash
# ==============================================================================
# ENTRYPOINT - ProtonMail Bridge Docker Container
# ==============================================================================
# Description: Handles setup of directories, GPG, Pass keyring and launches bridge
# Version: 2.1.0
# ==============================================================================
# Dependencies:
#   - proton-bridge binary
#   - gpg, pass, socat
#   - gpg-setup.sh, mailutils-setup.sh scripts
# Notes:
#   - Starts socat port forwarding AFTER bridge is ready (fixed race condition)
#   - Only starts socat in --noninteractive mode
#   - For initial setup, use --cli mode without socat
#   - Cache directory uses tmpfs mount to avoid permission issues
# ==============================================================================

# For debugging (uncomment if needed)
# set -x

setup_dir() {
    local DIR="$1"
    echo "DIR: $1"
    mkdir -p "${DIR}"
    chown -R "${PUID}:${PGID}" "${DIR}"
    chmod 700 "${DIR}"
}

shutdown() {
    echo "Shutdown signal received"
    pkill proton-bridge || true
    pkill socat || true
    kill -15 1
}

# Trap shutdown signals
trap shutdown SIGTERM SIGINT SIGQUIT

wait_for_bridge_port() {
    local port=$1
    local max_attempts=30
    local attempt=0

    echo "Waiting for proton-bridge to listen on port ${port}..."

    while [ $attempt -lt $max_attempts ]; do
        if nc -z 127.0.0.1 "${port}" 2>/dev/null; then
            echo "Port ${port} is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "  Attempt ${attempt}/${max_attempts}..."
        sleep 2
    done

    echo "ERROR: Port ${port} did not become available"
    return 1
}

echo "============================INITIALIZING============================="
echo "Proton Bridge ${PROTON_BRIDGE_VERSION}"
echo "PROTONMAIL_BRIDGE_NO_AUTOUPDATE=${PROTONMAIL_BRIDGE_NO_AUTOUPDATE}"
echo "PROTONMAIL_BRIDGE_LOG_LEVEL=${PROTONMAIL_BRIDGE_LOG_LEVEL}"
echo "PROTONMAIL_BRIDGE_DISABLE_TELEMETRY=${PROTONMAIL_BRIDGE_DISABLE_TELEMETRY}"
echo "....................................................................."
sleep 1
echo "User variables: PUID=${PUID}, PGID=${PGID}, USER=${USER}, HOME=${HOME}"
echo "                PROTONMAIL_HOST...${PROTONMAIL_HOST}"
echo "                PROTONMAIL_URI....${PROTONMAIL_URI}"
echo "....................................................................."
echo "Environment:"
env
echo "....................................................................."
sleep 1
echo "Mounted Docker secrets:"
ls -la /run/secrets/
sleep 1
echo "GPG variables:  GPG_NAME.......${GPG_NAME}"
echo "                GPG_EMAIL......${GPG_EMAIL}"
echo "                GPG_COMMENT....${GPG_COMMENT}"
export GPG_ID="${GPG_NAME} (${GPG_COMMENT}) <${GPG_EMAIL}>"
echo "....................................................................."
echo ""
echo "...starting setup..."
echo ""
sleep 1
echo "............................ENTRYPOINT..............................."

# Create a dummy notify-send if it doesn't exist
if ! command -v notify-send &> /dev/null; then
    echo "Creating dummy notify-send script..."
    cat > "/tmp/notify-send" << 'EOF'
#!/bin/sh
# Dummy notify-send that logs messages instead of displaying them
echo "NOTIFICATION: $*" >> "${HOME}/.local/share/protonmail/bridge-v3/notifications.log"
exit 0
EOF
    chmod +x "/tmp/notify-send"
    export PATH="/tmp:${PATH}"
fi

# Set up essential directories
echo "Setting up essential directories..."
echo "#####"
setup_dir "${HOME}/.gnupg"
setup_dir "${HOME}/.config/protonmail/bridge"
setup_dir "${HOME}/.config/protonmail/bridge-v3"
setup_dir "${HOME}/.local/share"
setup_dir "${HOME}/.local/share/protonmail/bridge-v3"
# Note: .cache is tmpfs mount in compose file
echo "#####"
echo "Directories created:"
ls -la "${HOME}"
echo ""

############# GPG-SETUP.SH #################
# Run and wait for gpg-setup.sh to check for a GPG key or generate one
echo ""
echo "Running GPG setup..."
export GNUPGHOME="${HOME}/.gnupg"

if [ -x /usr/local/bin/gpg-setup.sh ]; then
    /usr/local/bin/gpg-setup.sh &
    GPG_PID=$!
    echo "(waiting for gpg-setup.sh child process. PID: ${GPG_PID})"
    wait ${GPG_PID}
    GPG_RETURN_CODE=$?
    sleep 2

    if [ ${GPG_RETURN_CODE} -ne 0 ]; then
        echo "ERROR: GPG setup failed with exit code ${GPG_RETURN_CODE}"
        shutdown
    fi
fi

############################################

echo ""
echo "Resuming entrypoint.sh..."
echo ""
sleep 2
echo "....................................................................."

echo "Initializing password store..."
echo "Checking for existing Pass store..."

# look for .gpg-id with matching name, email and comment
if [ -s "${HOME}"/.password-store/.gpg-id ] && [ "$(cat "${HOME}"/.password-store/.gpg-id)" == "${GPG_ID}" ]; then
    echo "Existing Pass store found."
    pass
    sleep 1
else
    echo "No existing Pass store found."
    echo "Initializing Pass password store..."
    pass init "${GPG_ID}"
    PASS_INIT_RETURN=$?
    sleep 1

    if [ -s "${HOME}"/.password-store/.gpg-id ] && [ "$(cat "${HOME}"/.password-store/.gpg-id)" == "${GPG_ID}" ]; then
        echo "Pass store successfully initialized."
    else
        echo "ERROR: Pass store failed to initialize: ${PASS_INIT_RETURN}"
        shutdown
    fi
fi

if gpg --list-secret-keys "${GPG_EMAIL}" &>/dev/null; then
    echo "Found GPG key pair for ${GPG_EMAIL}."
    echo "Exporting GPG keys for backup/persistence..."

    if ! gpg --armor --export "${GPG_EMAIL}" > "${HOME}/.gnupg/public.asc"; then
        echo "ERROR: Export failed: $?"
        exit 1
    fi
    if ! gpg --armor --export-secret-keys "${GPG_EMAIL}" > "${HOME}/.gnupg/private.asc"; then
        echo "ERROR: Export failed: $?"
        exit 1
    fi

    echo "GPG keys exported successfully."
fi

SETTINGS_DIR="${HOME}/.config/protonmail/bridge"
SETTINGS_JSON_PATH="${SETTINGS_DIR}/settings.json"
if [ ! -d "${SETTINGS_DIR}" ]; then
    echo "No settings directory found."
    echo "Creating settings directory..."
    setup_dir "${SETTINGS_DIR}"
fi

echo "Checking Pass keychain configuration..."
if [ ! -f "${SETTINGS_JSON_PATH}" ]; then
    cat > "${SETTINGS_JSON_PATH}" << EOF
{
  "Keychain": "pass",
  "PasswordManagerDir": "${HOME}/.password-store",
  "Telemetry": false,
  "UpdateChecks": false,
  "UserSettings": {
    "AllowProxy": true,
    "AutoStart": false,
    "AutoUpdate": false,
    "DoHEnabled": true,
    "ShowAllMail": true,
    "StartMinimized": false,
    "UseSystemSettings": false,
    "ColorScheme": "system",
    "NetworkTimeoutSeconds": 5
  }
}
EOF
    echo "Configuration written to ${SETTINGS_JSON_PATH}:"
    cat "${SETTINGS_JSON_PATH}"
else
    echo "Existing file found: ${SETTINGS_JSON_PATH}"
    echo "Using existing Pass keychain configuration:"
    cat "${SETTINGS_JSON_PATH}"
fi

############# MAILUTILS-SETUP.SH ###########
# Run and wait for mailutils-setup.sh to handle its setup
echo ""
echo "Running mailutils setup..."

if [ -x /usr/local/bin/mailutils-setup.sh ]; then
    /usr/local/bin/mailutils-setup.sh &
    MAILUTILS_PID=$!
    echo "(waiting for mailutils-setup.sh child process. PID: ${MAILUTILS_PID})"
    wait ${MAILUTILS_PID}
    MAILUTILS_RETURN_CODE=$?
    sleep 2

    if [ ${MAILUTILS_RETURN_CODE} -ne 0 ]; then
        echo "ERROR: mailutils setup failed with exit code ${MAILUTILS_RETURN_CODE}"
        shutdown
    fi
fi

# Kill any existing bridge/socat processes
pkill proton-bridge || true
pkill bridge || true
pkill socat || true

echo "....................................................................."
echo "Setup complete. Checking command mode..."
echo "....................................................................."

# Check if we're running in noninteractive mode
# The command is passed as arguments to the entrypoint
if [ "$1" = "proton-bridge" ] && [ "$2" = "--noninteractive" ]; then
    echo ""
    echo "=================== NONINTERACTIVE MODE ========================="
    echo "Starting Proton Bridge in background with socat port forwarding"
    echo "================================================================"
    echo ""

    # Start the bridge in background
    echo "Starting proton-bridge --noninteractive..."
    "$@" &
    BRIDGE_PID=$!
    echo "Bridge started with PID: ${BRIDGE_PID}"

    # Wait for bridge ports to be ready
    if ! wait_for_bridge_port "${SMTP_INSIDE_PORT}"; then
        echo "ERROR: SMTP port ${SMTP_INSIDE_PORT} failed to start"
        shutdown
        exit 1
    fi

    if ! wait_for_bridge_port "${IMAP_INSIDE_PORT}"; then
        echo "ERROR: IMAP port ${IMAP_INSIDE_PORT} failed to start"
        shutdown
        exit 1
    fi

    echo ""
    echo "Proton Bridge is ready!"
    echo ""

    # Now start socat port forwarding
    echo "Starting socat port forwarding for external connections..."
    echo "NOTE: POP3 is not supported by Proton Mail Bridge."
    echo "#####"
    echo "...standard ports..."
    echo "SMTP: socat TCP-LISTEN:25,fork TCP:127.0.0.1:${SMTP_INSIDE_PORT} &"
    echo "IMAP: socat TCP-LISTEN:143,fork TCP:127.0.0.1:${IMAP_INSIDE_PORT} &"
    echo "...secure ports..."
    echo "SMTPS: socat TCP-LISTEN:465,fork TCP:127.0.0.1:${SMTP_INSIDE_PORT} &"
    echo "Submission: socat TCP-LISTEN:587,fork TCP:127.0.0.1:${SMTP_INSIDE_PORT} &"
    echo "IMAPS: socat TCP-LISTEN:993,fork TCP:127.0.0.1:${IMAP_INSIDE_PORT} &"
    echo "#####"

    socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:${SMTP_INSIDE_PORT} &   # SMTP
    socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:${IMAP_INSIDE_PORT} &  # IMAP
    socat TCP-LISTEN:465,fork,reuseaddr TCP:127.0.0.1:${SMTP_INSIDE_PORT} &  # SMTPS
    socat TCP-LISTEN:587,fork,reuseaddr TCP:127.0.0.1:${SMTP_INSIDE_PORT} &  # Submission
    socat TCP-LISTEN:993,fork,reuseaddr TCP:127.0.0.1:${IMAP_INSIDE_PORT} &  # IMAPS

    sleep 2
    echo ""
    echo "Socat port forwarding active"
    echo "================================================================"
    echo ""

    # Wait for bridge process
    wait ${BRIDGE_PID}

else
    echo ""
    echo "===================== CLI/MANUAL MODE ==========================="
    echo "Not starting automatic port forwarding"
    echo "================================================================"
    echo ""
    echo "INITIALIZING THE BRIDGE:"
    echo "For initial setup, the bridge is now ready for manual login."
    echo ""
    echo "Run 'proton-bridge --cli' to login and sync for the first time."
    echo ""
    echo "Use 'help' within the CLI menu for guidance."
    echo "The 'login' command is all you'll need."
    echo "The 'info' command shows account info to confirm setup."
    echo "Then 'exit' to shutdown the bridge processes fully."
    echo ""
    echo "After successful login, restart the container with the"
    echo "'proton-bridge --noninteractive' command to run in background."
    echo "================================================================"
    echo ""

    # Execute whatever command was passed (or default CMD)
    exec "$@"
fi
