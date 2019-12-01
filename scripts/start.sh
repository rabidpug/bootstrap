#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

if [ -z "${DEBUG:-}" ]; then
  exec 3>&1 &>/dev/null
else
  exec 3>&1
fi

lg "##Create User##"
bash "$BS_PATH/scripts/create-user.sh"
lg "##Install Packages##"
bash "$BS_PATH/scripts/install-packages.sh"
lg "##User Shell##"
bash "$BS_PATH/scripts/user-shell.sh"
lg "##Docker Project##"
bash "$BS_PATH/scripts/docker-project.sh"
lg "##DNS Records##"
bash "$BS_PATH/scripts/dns-records.sh"
lg "##Cronjobs##"
bash "$BS_PATH/scripts/cronjobs.sh"
