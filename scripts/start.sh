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
lg '### BEGINNING BOOTSTRAP ###'
bash "$BS_PATH/scripts/1-create-user.sh"
bash "$BS_PATH/scripts/2-install-packages.sh"
bash "$BS_PATH/scripts/3-user-shell.sh"
bash "$BS_PATH/scripts/4-docker-project.sh"
bash "$BS_PATH/scripts/5-dns-records.sh"
bash "$BS_PATH/scripts/6-cronjobs.sh"
lg '### BOOTSTRAP COMPLETED ###'
