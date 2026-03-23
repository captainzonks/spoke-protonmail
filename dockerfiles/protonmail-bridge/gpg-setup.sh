#!/usr/bin/env bash
# ==============================================================================
# GPG-SETUP - Generate ECC GPG key for Proton Mail Bridge
# ==============================================================================
# Description: Generates an ECC GPG key pair for use with pass credential store
# Version: 1.0.0
# ==============================================================================
# Designed to work with GnuPG v2.1 and later, unattended
# ==============================================================================

# For debugging
# set -x

return_message() {
    echo "Returning to entrypoint..."
    sleep 2
    echo "....................................................................."
    echo "....................................................................."
}

echo "............................GPG-SETUP................................"
# Environment variables, or default assignments, and local variables
GPG_NAME="${GPG_NAME:-"Proton Mail User"}"
GPG_EMAIL="${GPG_EMAIL:-"user@example.com"}"
GPG_COMMENT="${GPG_COMMENT:-"Proton Mail Bridge Key"}"
GNUPGHOME="${GNUPGHOME:-"/home/proton/.gnupg"}"
GPG_PARAMS_FILE="/tmp/gpg_params.txt"

# Ensure existence of .gnupg directory with proper permissions
if [ ! -d "${GNUPGHOME}" ]; then
    mkdir -p "${GNUPGHOME}"
fi
chmod 700 "${GNUPGHOME}"

# Check if we already have keys generated
if gpg --list-secret-keys "${GPG_EMAIL}" &>/dev/null; then
    echo "GPG keys for ${GPG_EMAIL} already exist, skipping generation."
    return_message
    exit 0
fi

# Generate the params file for primary key and encryption subkey
cat > "${GPG_PARAMS_FILE}" << EOF
# ECC key setup for Proton Mail Bridge
Key-Type: eddsa
Key-Curve: Ed25519
Key-Usage: cert
# Encryption subkey using Curve25519
Subkey-Type: ecdh
Subkey-Curve: Curve25519
Subkey-Usage: encrypt
# User identity information
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Name-Comment: ${GPG_COMMENT}
# No expiration date (required by Proton Mail)
Expire-Date: 0
# No password protection (required for unattended generation)
%no-protection
%commit
EOF

# Generate the key
echo "Generating GPG keys for ${GPG_EMAIL}..."
gpg --batch --generate-key "${GPG_PARAMS_FILE}"

# Verify key generation and add signing subkey
if gpg --list-secret-keys "${GPG_EMAIL}" &>/dev/null; then
    echo "GPG primary key and encryption subkey generation successful."

    # Add a signing subkey with explicit error checking
    echo "Adding signing subkey..."
    GPG_RETURN=$(gpg --list-secret-keys --with-colons "${GPG_EMAIL}")
    KEY_FPR="$(echo "${GPG_RETURN}" | grep "fpr" | head -n1 | cut -d: -f10)"
    # Get the fingerprint (not just the key ID)
    if [ -z "${KEY_FPR}" ]; then
        echo "ERROR: Could not retrieve key fingerprint: ${GPG_RETURN}"
        exit 1
    fi
    echo "Generated key with fingerprint:"
    echo "${KEY_FPR}"

    if ! gpg --batch --passphrase "" --quick-add-key "${KEY_FPR}" ed25519 sign 0; then
        GPG_RETURN=$?
        echo "WARNING: Failed to add signing subkey: ${GPG_RETURN}"
    else
        echo "Signing subkey added successfully."
    fi

    # Verify the key again to ensure everything is set up
    echo "Secret Keys:"
    gpg --list-secret-keys "${GPG_EMAIL}"
else
    GPG_RETURN=$?
    echo "ERROR: Key generation failed: ${GPG_RETURN}"
    exit 1
fi

# Clean up
echo "Cleaning up temporary files..."
rm -f "${GPG_PARAMS_FILE}"

echo "GPG setup complete."
return_message
