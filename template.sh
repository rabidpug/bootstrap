#!/bin/bash
set -eou pipefail

BS_PATH=/usr/local/bootstrap

# Clone bootstrap repo to /usr/local/bootstrap
mkdir -p $BS_PATH
git clone -q https://github.com/rabidpug/bootstrap.git $BS_PATH
touch $BS_PATH/.env

# Define required variables for scripts
cat <<EOT >>$BS_PATH/.env
GITHUB_AUTH_TOKEN=
DO_AUTH_TOKEN=
LIVEPATCH_KEY=
USERNAME=
GIT_NAME=
GIT_EMAIL=
DOMAINS=()
PUBLIC_KEYS=()
TZ=
DEBUG=
EOT

touch /var/log/bs.log
bash $BS_PATH/scripts/start.sh &>/var/log/bs.log
