#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

lg '## BEGINNING CRONJOBS ##'
find "$BS_PATH/cronjobs" -type d | while read folder; do
  interval=$(basename "$folder")
  find "$folder" -type f | while read job; do
    lg "Create/update symlink for $(basename $job) in cron.$interval"
    chmod +x "$job"
    ln -sf "$job" "/etc/cron.$interval"
  done
done

lg '## CRONJOBS COMPLETED ##'
