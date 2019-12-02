#!/bin/bash
set -eou pipefail

BS_PATH=/usr/local/bootstrap

# Clone bootstrap repo to /usr/local/bootstrap and set up
mkdir -p "$BS_PATH"
git clone -q https://github.com/rabidpug/bootstrap.git "$BS_PATH"
touch "$BS_PATH/.env"

chmod +x "$BS_PATH/bootstrap"
find "$BS_PATH/scripts" -type f | while read script; do
  chmod +x $script
done
echo "export PATH=\$PATH:$BS_PATH" >>/etc/profile

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
"$BS_PATH/bootstrap" -a &>>/var/log/bs.log
