#!/usr/bin/env bash
# ==============================================================================
# PROTONMAIL MODULE - TEST MAIL SCRIPT
# ==============================================================================
# Description: Validates SMTP connectivity and sends test emails
# Author: Matt Barham
# Created: 2025-06-12
# Modified: 2026-04-21
# Version: 1.0.1
# Host: Your Server
# ==============================================================================
# Type: Shell Script
# Component: module: protonmail / service: protonmail-bridge
# Usage: test-mail.sh [recipient_email]
#   If no recipient specified, sends to PROTON_EMAIL
# ==============================================================================

set -e

echo "========== Testing Mail Configuration =========="
echo "Date: $(date)"
echo "Mail Server: 127.0.0.1:${SMTP_INSIDE_PORT:-1025}"
echo "From: ${PROTON_EMAIL?"PROTON_EMAIL not set"}"
echo "Hostname: ${HOSTNAME:-"Server"}"

# Show current SSMTP configuration (with password redacted)
echo -e "\nSSMTP Configuration:"
sed 's/AuthPass=.*/AuthPass=******/g' < /etc/ssmtp/ssmtp.conf

# Check if bridge is running
echo -e "\nChecking if Proton Bridge is running:"
if pgrep -x "proton-bridge" > /dev/null; then
    echo "Proton Bridge is running"
else
    echo "ERROR: Proton Bridge is not running!"
    exit 1
fi

# Check network connectivity to the bridge
echo -e "\nChecking network connectivity to 127.0.0.1:${SMTP_INSIDE_PORT}:"
if nc -z -w5 127.0.0.1 "${SMTP_INSIDE_PORT}"; then
    echo "Port ${SMTP_INSIDE_PORT} is open"
else
    echo "ERROR: Port ${SMTP_INSIDE_PORT} is not accessible!"
    exit 1
fi

# Try a direct SMTP connection
echo -e "\nTrying direct SMTP connection:"
{
    sleep 1
    echo "EHLO mail.${DOMAIN}"
    sleep 1
    echo "QUIT"
    sleep 1
} | nc -v 127.0.0.1 "${SMTP_INSIDE_PORT}"

# Now try to send a test mail with ssmtp
echo -e "\nSending test mail with ssmtp:"
echo -e "To: ${1:-$PROTON_EMAIL}\nFrom: ${PROTON_EMAIL}\nSubject: Test from ${HOSTNAME} Server\n\nThis is a test email sent at $(date)" | ssmtp -v "${1:-$PROTON_EMAIL}"
SSMTP_RESULT=$?

if [ $SSMTP_RESULT -eq 0 ]; then
    echo "Mail sent successfully with ssmtp"
else
    echo "ERROR: ssmtp failed with exit code ${SSMTP_RESULT}"
fi

# Now try with mail command
echo -e "\nSending test mail with mail command:"
echo "This is a test email sent at $(date)" | mail -s "Test from ${HOSTNAME} Server" "${1:-$PROTON_EMAIL}"
MAIL_RESULT=$?

if [ ${MAIL_RESULT} -eq 0 ]; then
    echo "Mail sent successfully with mail command"
else
    echo "ERROR: mail command failed with exit code ${MAIL_RESULT}"
fi

echo -e "\nMail testing complete"
