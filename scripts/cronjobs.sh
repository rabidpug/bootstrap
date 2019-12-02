#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

lg '##CRONJOBS##'
find "$BS_PATH/cronjobs" -type f | while read job; do
  lg "Create/update symlink for $job"
  ln -sf "$job" /etc/cron.daily
done
