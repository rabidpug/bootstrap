#!/bin/bash
set -euo pipefail
{
########################
### SCRIPT VARIABLES ###
########################

GITHUB_AUTH_TOKEN=

DO_AUTH_TOKEN=

USERNAME=m

DOMAINS=(
  re.fyi
  repo.fyi
  debug.fyi
  staged.run
  jcuneo.com
  mybws.win
)

PUBLIC_KEYS=(
    
)

TZ=Australia/Sydney

#################
### FUNCTIONS ###
#################

lg () {
echo ">>[$(date '+%Y-%m-%d %H:%M:%S')]: $@"
}

###################
### USER CONFIG ###
###################

lg '//USER CONFIG'
lg "Adding ${USERNAME} as sudo user and granting privileges"
useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

lg 'Checking root account password'
encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

if [ "${encrypted_root_pw}" != "*" ]; then
    lg 'Transfering root password to user'
    echo "${USERNAME}:${encrypted_root_pw}" | chpasswd --encrypted
    lg 'Locking root account password access'
    passwd --lock root
else
    lg 'Deleting invalid password for sudo user'
    passwd --delete "${USERNAME}" > /dev/null
fi

lg 'Expiring sudo user password'
chage --lastday 0 "${USERNAME}"

lg 'Creating SSH directory for sudo user'
home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

lg 'Copying root account public keys'
cp /root/.ssh/authorized_keys "${home_directory}/.ssh"

lg 'Adding additional provided public keys'
for pub_key in "${PUBLIC_KEYS[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

lg 'Adjusting SSH configuration ownership and permissions'
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

lg 'Disabling root SSH login with password'
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

lg 'Disabling all SSH login with password'
sed --in-place 's/^PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

lg 'Disabling sudo password requirement for user'
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/${USERNAME}" > /dev/null

#####################
### SYSTEM CONFIG ###
#####################

lg '//SYSTEM CONFIG'
lg "Setting timezone to ${TZ}"
timedatectl set-timezone "${TZ}"

lg 'Adding firewall exception for SSH and then enabling UFW firewall'
{
ufw allow OpenSSH
ufw allow 23
ufw allow 24
ufw --force enable
} > /dev/null

lg 'Creating swapfile'
{
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
} > /dev/null

lg 'Installing common packages'
{
apt update
apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
} &> /dev/null
lg 'Adding package repositories'
{
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
curl -fsSL https://repos.insights.digitalocean.com/sonar-agent.asc | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
add-apt-repository "deb https://repos.insights.digitalocean.com/apt/do-agent/ main main"
} &> /dev/null
lg 'Installing advanced packages'
{
apt update
apt -y install zsh python docker-ce do-agent jq
} &> /dev/null
lg 'Installing docker-compose'
{
curl -fsSL "https://github.com/docker/compose/releases/download/$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
} &> /dev/null

#################
### USER APPS ###
#################

lg '//USER APPS'
lg 'Adding user to docker group'
usermod -aG docker "${USERNAME}"

lg 'Changing default shell to ZSH'
chsh --shell "$(command -v zsh)"
usermod -s "$(command -v zsh)" "${USERNAME}"

lg 'Installing FZF'
su ${USERNAME} -c "git clone -q --depth 1 https://github.com/junegunn/fzf.git ${home_directory}/.fzf && ${home_directory}/.fzf/install --all" &> /dev/null

lg 'Installing Antigen'
su ${USERNAME} -c "git clone -q https://github.com/rabidpug/bootstrap.git ${home_directory}/bootstrap"
su ${USERNAME} -c "git clone -q https://github.com/zsh-users/antigen.git ${home_directory}/antigen"
echo 'source $HOME/bootstrap/.antigenrc' >> "${home_directory}/.zshrc"

#####################
### DOCKER CONFIG ###
#####################

lg '//DOCKER CONFIG'
lg 'Getting asset release id'
RELEASE_ID=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

lg 'Getting asset IDs'
mapfile -t ASSETS < <(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | jq -c '.[] | {name: .name, id: .id}')

for asset in "${ASSETS[@]}"; do
  name=$(echo "$asset" | jq -r .name)
  id=$(echo "$asset" | jq -r .id)
  case "$name" in
    *docker* )
      lg 'Extracting Docker assets'
      curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}" | tar --same-owner -xzp -C "${home_directory}"
    ;;
  esac
done

lg 'Creating docker Web network'
docker network create web > /dev/null

lg 'Spinning up docker services'
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d &> /dev/null

##################
### DNS CONFIG ###
##################

lg '//DNS CONFIG'
lg 'Getting public IP'
public_ip=$(curl -fsSL http://icanhazip.com)
lg 'Getting existing domains'
mapfile -t existing_domains < <(curl -fsSL -X GET -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" "https://api.digitalocean.com/v2/domains" | jq -r '.domains[].name')
lg 'Creating required records for domains'
for domain in "${DOMAINS[@]}"; do
unset exits
  case "${existing_domains[@]}" in
    *$domain*) exists=true ;;
  esac
  if [ -z $exists ];
    then
      lg "adding ${domain} to dns"
      curl -fsSL -X POST -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" -d "{\"name\":\"${domain}\"}" "https://api.digitalocean.com/v2/domains" > /dev/null
  fi
  domain_records=$(curl -fsSL -X GET -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" "https://api.digitalocean.com/v2/domains/${domain}/records" | jq -c '.domain_records')
  host_record=$(echo "${domain_records}" | jq -c '.[] | select(.type=="A" and .name=="@")')
  wildcard_record=$(echo "${domain_records}" | jq -c '.[] | select(.type=="A" and .name=="*")')
  host_id=$(echo "${host_record}" | jq -r .id)
  host_data=$(echo "${host_record}" | jq -r .data)
  wildcard_id=$(echo "${wildcard_record}" | jq -r .id)
  wildcard_data=$(echo "${wildcard_record}" | jq -r .data)
  if [ "${host_data}" != "${public_ip}" ];
    then
      if [ -z "${host_id}" ];
        then
          lg "creating host record for ${domain} > ${public_ip}"
          curl -fsSL -X POST -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" -d "{\"type\":\"A\",\"name\":\"@\",\"data\":\"${public_ip}\"}" "https://api.digitalocean.com/v2/domains/${domain}/records" > /dev/null
        else
          lg "updating host record for ${domain} > ${public_ip} (was ${host_data})"
          curl -fsSL -X PUT -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" -d "{\"data\":\"${public_ip}\"}" "https://api.digitalocean.com/v2/domains/${domain}/records/${host_id}" > /dev/null
      fi
    else
      lg "host record for ${domain} up to date"
  fi
  if [ "${wildcard_data}" != "${public_ip}" ];
    then
      if [ -z "${wildcard_id}" ];
        then
          lg "creating wildcard record for ${domain} > ${public_ip}"
          curl -fsSL -X POST -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" -d "{\"type\":\"A\",\"name\":\"*\",\"data\":\"${public_ip}\"}" "https://api.digitalocean.com/v2/domains/${domain}/records" > /dev/null
        else
          lg "updating wildcard record for ${domain} > ${public_ip} (was ${wildcard_data})"
          curl -fsSL -X PUT -H "Authorization: Bearer ${DO_AUTH_TOKEN}" -H "Content-Type: application/json" -d "{\"data\":\"${public_ip}\"}" "https://api.digitalocean.com/v2/domains/${domain}/records/${wildcard_id}" > /dev/null
      fi
    else
      lg "wildcard record for ${domain} up to date"
  fi
done

###################
### CRON CONFIG ###
###################

lg '//CRON CONFIG'
lg 'setting up cronjobs'
find "${home_directory}/bootstrap/cronjobs" -type f | while read job; do
  lg "Update variables for ${job}"
  sed --in-place "s|^GITHUB_AUTH_TOKEN=.*|GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN}|g" "${job}"
  sed --in-place "s|^home_directory=.*|home_directory=${home_directory}|g" "${job}"
  lg "Create/update symlink for ${job}"
  ln -sf "${job}" /etc/cron.daily
done

lg 'Setting owner for cronjobs'
chown --recursive root:root "${home_directory}/bootstrap/cronjobs"




} &> /var/log/initial_setup.log
