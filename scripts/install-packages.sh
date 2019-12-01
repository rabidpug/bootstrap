#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

export DEBIAN_FRONTEND=noninteractive

lg 'Updating & installing common packages'
{
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
  apt update
  apt -y upgrade
  apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common tzdata ntp zsh python jq docker-ce
} &>/dev/null

if [ -z "$USERNAME" ]; then
  lg 'Skipping adding user to docker group - No user'
else
  lg 'Adding user to docker group'
  usermod -aG docker "${USERNAME}"
fi

if [ -z "$TZ" ]; then
  lg 'Skipping setting timezone - no timezone'
else
  lg 'Setting timezone'
  ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime
  dpkg-reconfigure --frontend noninteractive tzdata
fi

lg 'Installing docker-compose'
{
  curl -fsSL "https://github.com/docker/compose/releases/download/$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
} &>/dev/null

if grep -Eq '/(lxc|docker|kubepods)/[[:xdigit:]]{64}' /proc/1/cgroup; then
  lg 'Installing code server packages'
  curl -fsSL https://deb.nodesource.com/setup_13.x | sudo -E bash -
  {
    apt update
    apt -y install nodejs build-essential fonts-firacode
  }
else
  lg 'Installing dev server packages'
  {
    curl -fsSL https://repos.insights.digitalocean.com/sonar-agent.asc | apt-key add -
    add-apt-repository "deb https://repos.insights.digitalocean.com/apt/do-agent/ main main"
    apt update
    apt -y install do-agent
  } &>/dev/null

  lg 'Setting max watches'
  echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
  sysctl -p

  lg 'Adding firewall exception for SSH and then enabling UFW firewall'
  {
    ufw allow OpenSSH
    ufw allow 23
    ufw allow 24
    ufw --force enable
  } >/dev/null

  lg 'Creating swapfile'
  {
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile swap swap defaults 0 0' >>/etc/fstab
  } >/dev/null

  lg 'Install canonical live patches'
  snap install canonical-livepatch >/dev/null
  canonical-livepatch enable "$LIVEPATCH_KEY" >/dev/null
fi
