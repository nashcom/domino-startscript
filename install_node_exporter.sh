#!/bin/bash

DOWNLOAD_VERSION=1.12.1
DOWNLOAD_URL=https://github.com/prometheus/node_exporter/releases/download/v1.12.1/node_exporter-1.12.1.linux-amd64.tar.gz
DOWNLOAD_HASH=b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63

SYSTEMD_NAME=node_exporter
SYSTEMD_FILE=$SYSTEMD_NAME.service
SYSTEMD_FILEPATH=/etc/systemd/system/$SYSTEMD_FILE
NODE_EXPORTER_BIN=/usr/local/bin/node_exporter


log()
{
  echo
  echo "$@"
  echo
}

log_error()
{
  log "ERROR: $@"
}

print_delim()
{
  echo "--------------------------------------------------------------------------------"
}

header()
{
  echo
  print_delim
  echo "$1"
  print_delim
  echo
}

download()
{
  DOWNLOAD_FILE=$1
  FILES_TO_EXTRACT=$2
  EXPECTED_HASH=$3

  case "$DOWNLOAD_FILE" in
    *.tar.gz)
      TAR_OPT=-xz
      ;;

    *.tgz)
      TAR_OPT=-xz
      ;;

    *.taz)
      TAR_OPT=-xz
      ;;

    *.tar)
      TAR_OPT=-x
      ;;

    *)
      TAR_OPT=""
      ;;
  esac

  HASH=$(curl -sL $DOWNLOAD_FILE | tee >(tar $TAR_OPT --no-anchored --strip-components 1 $FILES_TO_EXTRACT 2>/dev/null) | sha256sum -b | cut -d" " -f1)

  if [ -z "$EXPECTED_HASH" ]; then
    return 0
  fi

  if [ "$HASH" = "$EXPECTED_HASH" ]; then
    return 0
  fi

  log_error "Download Hash does not match!"
  exit 1
}


header "Prometheus Node Exporter $DOWNLOAD_VERSION Installer"

# Check if requested version is already installed
if [ -e "$NODE_EXPORTER_BIN" ]; then

  INSTALL_MODE=update
  NODE_EXPORTER_VERSION=$("$NODE_EXPORTER_BIN" --version 2>&1 | sed -n 's/.*version \([^ ]*\).*/\1/p;q')

  if [ "$DOWNLOAD_VERSION" = "$NODE_EXPORTER_VERSION" ]; then
    log "Node exporter $NODE_EXPORTER_VERSION already installed"
    exit 0
  fi

fi

header "Downloading binary from GitHub"

if [ -e node_exporter ]; then
  log "Info: Node Exporter found"
else
  download "$DOWNLOAD_URL" "node_exporter" "$DOWNLOAD_HASH"
fi

if [ ! -e node_exporter ]; then
  log_error "Cannot download node_exporter. Please download & extract manually from $DOWNLOAD_URL"
  exit 1
fi

if [ -e "$NODE_EXPORTER_BIN" ]; then

  if [ "$(sha256sum -b "$NODE_EXPORTER_BIN" | cut -d' ' -f1)" = "$(sha256sum node_exporter -b | cut -d' ' -f1)" ]; then
    log "Node exporter $NODE_EXPORTER_VERSION already installed"
    exit 0
  fi

fi

# Binary needs to be located in /usr/local/bin because of SELinux permissions
mv -f node_exporter "$NODE_EXPORTER_BIN"
chmod 755 "$NODE_EXPORTER_BIN"

# Relabel binary for SELinux if tool is available
if [ -e /usr/sbin/restorecon ]; then
  /usr/sbin/restorecon -v "$NODE_EXPORTER_BIN"
fi

if [ "$INSTALL_MODE" = "update" ]; then
  log "Restarting Node Exporter service ..."
  systemctl restart "$SYSTEMD_NAME"
  exit 0
fi

cat > "$SYSTEMD_FILEPATH" <<'EOF'
###########################################################################
# Prometheus Node Exporter systemd service
# Version 1.0.3 (2026-07-22)
#
# Copyright (c) 2024-2026 Daniel Nashed / NashCom
# SPDX-License-Identifier: Apache-2.0
###########################################################################

[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=exec
User=notes

# Default directory for textfile collector (.prom files)
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/local/notesdata/domino/stats

StandardOutput=file:/tmp/node_exporter.log
StandardError=file:/tmp/node_exporter_error.log

[Install]
WantedBy=multi-user.target
EOF

chown root:root "$SYSTEMD_FILEPATH"
chmod 0644 "$SYSTEMD_FILEPATH"

systemctl daemon-reload
log "Starting Node Exporter service ..."
systemctl enable --now "$SYSTEMD_NAME"
echo

log "Completed"
