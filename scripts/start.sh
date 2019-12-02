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

bash "$BS_PATH/scripts/create-user.sh"
bash "$BS_PATH/scripts/install-packages.sh"
bash "$BS_PATH/scripts/user-shell.sh"
bash "$BS_PATH/scripts/docker-project.sh"
bash "$BS_PATH/scripts/dns-records.sh"
bash "$BS_PATH/scripts/cronjobs.sh"
