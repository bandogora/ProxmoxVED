#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# Import Functions und Setup
# shellcheck source=/dev/null
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  diffutils \
  gettext \
  iotop \
  less \
  libncurses-dev \
  net-tools \
  openssl \
  libssl-dev \
  rsync \
  procps \
  sysstat \
  tcpdump \
  binutils \
  chrony \
  locales-all
msg_ok "Installed Dependencies"

# yugabyted expects cmd `chronyc sources` to succeed
msg_info "Restarting chronyd in container mode"
# Start chronyd with the -x option to disable control of the system clock
sed -i 's|^ExecStart=!/usr/sbin/chronyd|ExecStart=!/usr/sbin/chronyd -x|' \
  /usr/lib/systemd/system/chrony.service

systemctl daemon-reload
if systemctl restart chronyd; then
  msg_ok "chronyd running correctly"
else
  msg_error "Failed to restart chronyd"
  journalctl -xeu chronyd.service
  exit 1
fi

msg_info "Configuring environment"
DATA_DIR="$YB_HOME/var/data"
TEMP_DIR="$YB_HOME/var/tmp"

# Save environment for users and update
cat >/etc/environment <<EOF
YB_SERIES=$YB_SERIES
YB_HOME=$YB_HOME
DATA_DIR=$DATA_DIR
TEMP_DIR=$TEMP_DIR
EOF

# Create data dirs from ENV vars, required before creating venv
mkdir -p "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
# Set working dir
cd "$YB_HOME" || exit
msg_ok "Configured environment"

# Create unprivileged user to run DB, required before creating venv
msg_info "Creating yugabyte user"
useradd --home-dir "$YB_HOME" \
  --uid 10001 \
  --no-create-home \
  --no-user-group \
  --shell /sbin/nologin \
  yugabyte
# Make sure user has permission to create venv
chown -R yugabyte "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
msg_ok "Created yugabyte user"

msg_info "Setting up Python virtual environment"
PYTHON_VERSION=3.11 setup_uv
# Create venv as yugabyte user to ensure correct permissions when sourcing later
$STD sudo -u yugabyte uv venv --python 3.11 "$YB_HOME/.venv"
source "$YB_HOME/.venv/bin/activate"
# Install required packages
$STD uv pip install --upgrade pip
$STD uv pip install --upgrade lxml
$STD uv pip install --upgrade s3cmd
$STD uv pip install --upgrade psutil
msg_ok "Setup Python virtual environment"

msg_info "Setup ${APPLICATION}"
# Get latest version and build number for our series
read -r VERSION RELEASE < <(
  curl -fsSL https://github.com/yugabyte/yugabyte-db/raw/refs/heads/master/docs/data/currentVersions.json |
    jq -r ".dbVersions[] | select(.series == \"${YB_SERIES}\") | [.version, .appVersion] | @tsv"
)
# Download the corresponding tarball
curl -OfsSL "https://software.yugabyte.com/releases/${VERSION}/yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"
tar -xzf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz" --strip 1
rm -rf "yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"

# Extract share/ybc-*.tar.gz to get bins required for ysql_conn_mgr
tar -xzf share/ybc-*.tar.gz
rm -rf ybc-*/conf/
# yugabyted expects yb-controller-server file in ybc/bin
mv ybc-* ybc

# Strip unneeded symbols from object files in $YB_HOME
# This is a step taken from the official Dockerfile
for a in $(find . -exec file {} \; | grep -i elf | cut -f1 -d:); do
  $STD strip --strip-unneeded "$a" || true
done

# Link yugabyte bins to /usr/local/bin/
for a in ysqlsh ycqlsh yugabyted yb-admin yb-ts-cli; do
  ln -s "$YB_HOME/bin/$a" "/usr/local/bin/$a"
done
msg_ok "Setup ${APPLICATION}"

msg_info "Setting permissions"
chown -R yugabyte "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
chmod -R 755 "$YB_HOME" "$DATA_DIR" "$TEMP_DIR"
msg_ok "Permissions set"

# Create service file with user selected options, correct limits, ENV vars, etc.
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"${NSAPP}.service"
[Unit]
Description=${APPLICATION} Service
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
RestartForceExitStatus=SIGPIPE
StartLimitInterval=0
ExecStart=/usr/local/bin/yugabyted start --secure \
--advertise_address=$(hostname -I | awk '{print $1}') \
--tserver_flags="tmp_dir=$TEMP_DIR" \
--data_dir=$DATA_DIR \
--callhome=false

Environment="PATH=$YB_HOME/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="YB_HOME=$YB_HOME"
WorkingDirectory=$YB_HOME
TimeoutStartSec=30
RestartSec=5
PermissionsStartOnly=True
User=yugabyte
TimeoutStopSec=300
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --quiet --now "${NSAPP}".service
msg_ok "Created Service"

motd_ssh
customize

# Cleanup
$STD uv cache clean
cleanup_lxc
