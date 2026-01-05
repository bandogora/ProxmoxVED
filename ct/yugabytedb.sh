#!/usr/bin/env bash

# Copyright (c) 2021-2025 bandogora
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# shellcheck source=misc/build.func
source <(curl -fsSL https://raw.githubusercontent.com/bandogora/ProxmoxVED/yugabytedb/misc/build.func)
# source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# App Default Values
APP="YugabyteDB"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-almalinux}"
var_version="${var_version:-10}"
var_unprivileged="${var_unprivileged:-1}"

YB_SERIES=v2025.2
YB_HOME=/home/yugabyte

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present
  if [[ ! -d $YB_HOME ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  read -r VERSION RELEASE < <(
    curl -fsSL https://github.com/yugabyte/yugabyte-db/raw/refs/heads/master/docs/data/currentVersions.json |
      jq -r ".dbVersions[] | select(.series == \"${YB_SERIES}\") | [.version, .appVersion] | @tsv"
  )
  # Get version_number and build_number then concat with '-' to match .appVersion style stored in RELEASE
  if [[ "${RELEASE}" != "$(sed -rn 's/.*"version_number"[[:space:]]*:[[:space:]]*"([^"]*)".*"build_number"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1-\2/p' ${YB_HOME}/version_metadata.json)" ]]; then
    # Stopping Services
    msg_info "Stopping $APP"
    systemctl stop ${NSAPP}.service
    pkill yb-master
    msg_ok "Stopped $APP"

    # Creating Backup
    # msg_info "Creating Backup"
    # tar -czf "/opt/${NSAPP}_backup_$(date +%F).tar.gz" [IMPORTANT_PATHS]
    # msg_ok "Backup Created"

    msg_info "Updating Dependencies"
    $STD dnf -y upgrade
    alternatives --install /usr/bin/python python /usr/bin/python3.11 99
    alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 99
    $STD python3 -m pip install --upgrade pip
    $STD python3 -m pip install --upgrade lxml
    $STD python3 -m pip install --upgrade s3cmd
    $STD python3 -m pip install --upgrade psutil
    msg_ok "Updated Dependencies"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"

    curl -fsSL "https://software.yugabyte.com/releases/${VERSION}/yugabyte-${RELEASE}-linux-$(uname -m).tar.gz"

    tar -xvf "/tmp/yugabyte*$(uname -m)*.tar.gz" --strip 1
    rm -rf /tmp/yuabyte*
    # Run post install
    ./bin/post_install.sh
    tar -xvf share/ybc-*.tar.gz
    rm -rf ybc-*/conf/
    msg_ok "Updated $APP to v${RELEASE}"

    # Starting Services
    msg_info "Starting $APP"
    systemctl start ${NSAPP}.service
    # Verify service is running
    if systemctl is-active --quiet "${NSAPP}".service; then
      msg_ok "Service running successfully"
    else
      msg_error "Service failed to start"
      journalctl -u "${NSAPP}".service -n 20
      exit 1
    fi
    msg_ok "Started $APP"

    # Cleaning up
    msg_info "Cleaning Up"
    rm -rf ~/.cache
    $STD dnf autoremove -y 2>/dev/null
    $STD dnf clean all 2>/dev/null
    rm -rf /var/cache/yum /var/cache/dnf
    msg_ok "Cleanup Completed"

    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:15433${CL}"
