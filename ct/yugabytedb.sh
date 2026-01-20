#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bandogora
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.yugabyte.com/yugabytedb/

# shellcheck source=misc/build.func
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# App Default Values
APP="YugabyteDB"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Select most recent series
export YB_SERIES="v2025.2"

# Set yugabyte's home directory
export YB_HOME="/opt/yugabyte"

# Make available to install script
export NSAPP

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d $YB_HOME ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "Currently we don't provide an update function for this ${APP}."
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:15433${CL}"
echo -e "${BOLD}${INFO}${YWB}You must restart proxmox to fix the shmem mount permissions preventing YugabyteDB from starting${CL}"
