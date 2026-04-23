# ==============================================================================
# PROTONMAIL MODULE - PROTONMAIL-BRIDGE DOCKERFILE
# ==============================================================================
# Description: Multi-stage build for ProtonMail Bridge with GPG and mailutils
# Author: Matt Barham
# Created: 2025-06-12
# Modified: 2026-04-21
# Version: 3.22.1-custom
# Host: Your Server
# ==============================================================================
# Type: Dockerfile
# Base Images: golang:1.24-bookworm (builder), debian:bookworm-slim (runtime)
# Documentation: https://proton.me/support/bridge
# Component: module: protonmail / service: protonmail-bridge
# Target Architecture: amd64
# Security: non-root user (configurable UID/GID), GPG/pass integration
# ==============================================================================
# Build Command:
#   docker build --build-arg PUID=1000 --build-arg PGID=968 \
#     --build-arg PROTON_BRIDGE_VERSION=v3.22.0 \
#     --build-arg GPG_NAME="proton-user" \
#     --build-arg GPG_EMAIL="proton@fake.me" \
#     -t protonmail-bridge:3.22.0-custom .
# ==============================================================================
# Features:
#   - Builds ProtonMail Bridge from source
#   - GPG setup for encrypted password store
#   - mailutils and ssmtp for email testing
#   - Custom entrypoint with Docker secrets support
#   - Non-interactive mode by default
#   - SMTP on port 1025 (internal), IMAP on port 1143 (internal)
#   - Socat port forwarding to standard ports (25, 143, 465, 587, 993)
# ==============================================================================

############################ BUILD PROTON MAIL BRIDGE ##############################
FROM golang:1.24-bookworm AS go-builder
WORKDIR /build/

RUN apt update -y
RUN apt install -y --no-install-recommends \
    libsecret-1-dev \
    libfido2-dev \
    libcbor-dev \
    pkg-config

# Clone Proton Mail Bridge repository (adjust version as needed)
ARG PROTON_BRIDGE_VERSION="v3.22.0" # can be overridden from build file
ADD https://github.com/ProtonMail/proton-bridge.git#${PROTON_BRIDGE_VERSION} /build/

# Build Proton Mail Bridge
RUN make -d build-nogui vault-editor

################################ BUILD FINAL IMAGE #################################
FROM debian:bookworm-slim AS final
LABEL maintainer="captainzonks"

# .......................... ENVIRONMENT ........................... #
# PUID and PGID can be overriden via build file
# set to default system admin and Docker group
ARG PUID
ARG PGID
ENV PUID=${PUID:-1000}
ENV PGID=${PGID:-968}
ENV USER=proton
ENV HOME=/home/${USER}

# Bridge mode set to --noninteractive by default
ENV BRIDGE_MODE=--noninteractive

# Setup needed variables, receive from build to override defaults
ARG GPG_NAME
ARG GPG_EMAIL
ARG GPG_COMMENT
ENV GPG_NAME=${GPG_NAME:-proton-user}
ENV GPG_EMAIL=${GPG_EMAIL:-proton@fake.me}
ENV GPG_COMMENT=${GPG_COMMENT:-}
ENV PROTON_USER=
ENV PROTON_EMAIL=
ENV PROTON_BRIDGE_PASSWORD=
ENV PROTON_BRIDGE_PASSWORD_FILE=

# default inner container ports
ENV SMTP_INSIDE_PORT=1025
ENV IMAP_INSIDE_PORT=1143

# Default as precaution; gpg-setup.sh handles this as well
ENV GPG_ID="${GPG_NAME} (${GPG_COMMENT}) <${GPG_EMAIL}>"

ENV XDG_RUNTIME_DIR=/run/user/${PUID}
ENV XDG_CONFIG_HOME=${HOME}/.config
ENV XDG_CACHE_HOME=${HOME}/.cache
ENV XDG_DATA_HOME=${HOME}/.local/share
ENV TMPDIR=/tmp

# ........................... PACKAGES ............................. #
# Avoid interaction with package installs
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update -y
RUN apt upgrade -y
RUN apt install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        gnupg \
        htop \
        iproute2 \
        libnotify-bin \
        libsecret-1-dev \
        libfido2-1 \
        libcbor0.8 \
        mailutils \
        musl-dev \
        nano \
        netcat-openbsd \
        openssl \
        pass \
        procps \
        rng-tools \
        socat \
        ssmtp \
        tini \
        tzdata
RUN apt clean

# ...................... BINARIES & PERMISSIONS .................... #
# Set working directory
WORKDIR ${HOME}

# Copy binaries
COPY --from=go-builder /build/bridge /usr/bin/bridge
COPY --from=go-builder /build/proton-bridge /usr/bin/proton-bridge
COPY --from=go-builder /build/vault-editor /usr/bin/vault-editor
# Copy local scripts
COPY entrypoint.sh /entrypoint.sh
COPY gpg-setup.sh /usr/local/bin/gpg-setup.sh
COPY mailutils-setup.sh /usr/local/bin/mailutils-setup.sh
COPY test-mail.sh /usr/local/bin/test-mail.sh

# Ensure non-root permissions
RUN chmod 750 \
    /entrypoint.sh \
    /usr/local/bin/gpg-setup.sh \
    /usr/local/bin/mailutils-setup.sh \
    /usr/local/bin/test-mail.sh \
    /usr/bin/bridge \
    /usr/bin/proton-bridge \
    /usr/bin/vault-editor

# ................... CREATE DIRS, USER & GROUP .................... #
RUN mkdir -p ${HOME}/.config/protonmail/bridge/ && \
    mkdir -p ${HOME}/.config/protonmail/bridge-v3/ && \
    mkdir -p ${HOME}/.gnupg/ && \
    mkdir -p ${HOME}/.local/share/protonmail/bridge-v3/logs/ && \
    mkdir -p ${HOME}/.cache/ && \
    mkdir -p ${HOME}/.password-store/ && \
    mkdir -p /etc/ssmtp/

RUN if [ ${PUID:-0} -ne 0 ] && [ ${PGID:-0} -ne 0 ]; then \
        groupadd -g ${PGID} ${USER} && \
        useradd -l -u ${PUID} -g ${USER} ${USER} && \
        install -d -m 0755 -o ${USER} -g ${USER} ${HOME} \
    ;fi

# create config files for mailutils and ssmtp (populated via mailutils-setup.sh)
RUN touch /etc/mail.rc
RUN touch /etc/ssmtp/ssmtp.conf
# set rw-rw-r-- permissions
RUN chmod 664 /etc/mail.rc /etc/ssmtp/ssmtp.conf

# set ownership to user
RUN chown --changes --silent --no-dereference --recursive \
    ${USER}:${USER} \
    ${HOME}/ \
    /entrypoint.sh \
    /usr/local/bin/gpg-setup.sh \
    /usr/local/bin/mailutils-setup.sh \
    /usr/local/bin/test-mail.sh \
    /usr/bin/bridge \
    /usr/bin/proton-bridge \
    /usr/bin/vault-editor \
    /etc/mail.rc \
    /etc/ssmtp/ssmtp.conf

HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD pgrep proton-bridge || exit 1

# Switch to non-root user
USER ${USER}

ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
# Container does not start the bridge by default.
# This is because --cli needs user input for the
# initial login. Manually entering the container
# will be required for the first time it's created.
CMD ["tail", "-f", "/dev/null"]
