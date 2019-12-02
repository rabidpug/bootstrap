#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/utilities/lg.sh"

lg '## BEGINNING CRONJOBS ##'

lg 'Configure log rotation'
cat <<EOT >>/etc/logrotate.d/bs
/var/log/bs.log {
daily
copytruncate
missingok
dateext
rotate 7
compress
}

EOT

find "$BS_PATH/cron" -type d | while read folder; do
  interval=$(basename "$folder")
  find "$folder" -type f | while read job; do
    lg "Create symlink for $(basename $job) in cron.$interval"
    chmod +x "$job"
    ln -sf "$job" "/etc/cron.$interval"
  done
done

lg '## CRONJOBS COMPLETED ##'
