#!/bin/bash
set -euo pipefail

########################
### SCRIPT VARIABLES ###
########################

USERNAME=

PUBLIC_KEYS=(
    
)

GITHUB_AUTH_TOKEN=

####################
### SCRIPT LOGIC ###
####################

echo ">> Adding sudo user and granting privileges"
useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

echo ">> Checking whether the root account has a real password set"
encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

if [ "${encrypted_root_pw}" != "*" ]; then
    echo ">> Transfering auto-generated root password to user if present and locking the root account to password-based access"
    echo "${USERNAME}:${encrypted_root_pw}" | chpasswd --encrypted
    passwd --lock root
else
    echo ">> Deleting invalid password for user if using keys so that a new password can be set without providing a previous value"
    passwd --delete "${USERNAME}" > /dev/null
fi

echo ">> Expiring the sudo user's password to force a change"
chage --lastday 0 "${USERNAME}"

echo ">> Creating SSH directory for sudo user"
home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

echo ">> Copying root account public keys"
cp /root/.ssh/authorized_keys "${home_directory}/.ssh"

echo ">> Adding additional provided public keys"
for pub_key in "${PUBLIC_KEYS[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

echo ">> Adjusting SSH configuration ownership and permissions"
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

echo ">> Disabling root SSH login with password"
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

echo ">> Disabling all SSH login with password"
sed --in-place 's/^PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

echo ">> Adding firewall exception for SSH and then enabling UFW firewall"
{
ufw allow OpenSSH
ufw allow 23
ufw allow 24
ufw --force enable
} > /dev/null

echo ">> Creating swapfile to avoid docker OOM"
{
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
} > /dev/null

echo ">> Disabling password requirement for sudo"
echo "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/${USERNAME}" > /dev/null

echo ">> Setting timezone"
timedatectl set-timezone Australia/Sydney

echo ">> Installing required packages"
{
apt update
apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
curl -fsSL https://repos.insights.digitalocean.com/sonar-agent.asc | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
add-apt-repository "deb https://repos.insights.digitalocean.com/apt/do-agent/ main main"
apt update
apt -y install zsh python docker-ce do-agent jq
curl -fsSL "https://github.com/docker/compose/releases/download/$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
} &> /dev/null

echo ">> Adding user to docker group"
usermod -aG docker "${USERNAME}"

echo ">> Changing default shell to ZSH"
chsh --shell $(which zsh)
usermod -s $(which zsh) ${USERNAME}

echo ">> Installing FZF"

su ${USERNAME} -c "git clone -q --depth 1 https://github.com/junegunn/fzf.git ${home_directory}/.fzf && ${home_directory}/.fzf/install --all" &> /dev/null

echo ">> Installing Antigen and add source command to .zshrc"
git clone -q https://github.com/rabidpug/bootstrap.git "${home_directory}/bootstrap"
git clone -q https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
echo 'source $HOME/bootstrap/.antigenrc' >> "${home_directory}/.zshrc"

echo ">> Downloading and extracting docker assets"
RELEASE_ID=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

ASSETS=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | jq -c '.[] | {name: .name, id: .id}')

for asset in $ASSETS;
do
name=$(echo $asset | jq -r .name)
id=$(echo $asset | jq -r .id)
case "$name" in
  *docker* )
    curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}" | tar --same-owner -xzp -C "${home_directory}"
    ;;
esac;
done

echo ">> Creating docker Web network"
docker network create web > /dev/null

echo ">> Spinning up docker services"
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d &> /dev/null

echo ">> setting up update backup cron job"
sed --in-place "s|^GITHUB_AUTH_TOKEN=.*|GITHUB_AUTH_TOKEN=${GITHUB_AUTH_TOKEN}|g" "${home_directory}/bootstrap/update_backup"

sed --in-place "s|^home_directory=.*|home_directory=${home_directory}|g" "${home_directory}/bootstrap/update_backup"

ln -s "${home_directory}/bootstrap/update_backup" /etc/cron.daily
