#!/bin/bash
set -euo pipefail

########################
### SCRIPT VARIABLES ###
########################

## USED FOR:
# Linux sudo user
# traefik dashboard user
export USERNAME=***USERNAME***

## USED FOR:
# ssh
export PUBLIC_KEYS=(
    ***PUBLIC_KEYS***
)

## USED FOR:
# Traefik dashboard password
export ADMIN_PASSWD=***ADMIN_PASSWD***

## USED FOR:
# Traefik acme dns challenge
export DO_AUTH_TOKEN=***DO_AUTH_TOKEN***

## USED FOR:
# Docker data backup and restore
export GITHUB_AUTH_TOKEN=***GITHUB_AUTH_TOKEN***

####################
### SCRIPT LOGIC ###
####################

# Add sudo user and grant privileges
useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

# Check whether the root account has a real password set
encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

if [ "${encrypted_root_pw}" != "*" ]; then
    # Transfer auto-generated root password to user if present
    # and lock the root account to password-based access
    echo "${USERNAME}:${encrypted_root_pw}" | chpasswd --encrypted
    passwd --lock root
else
    # Delete invalid password for user if using keys so that a new password
    # can be set without providing a previous value
    passwd --delete "${USERNAME}"
fi

# Expire the sudo user's password to force a change
chage --lastday 0 "${USERNAME}"

# Create SSH directory for sudo user
export home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

# Copy root account public keys
cp /root/.ssh/authorized_keys "${home_directory}/.ssh"

# Add additional provided public keys
for pub_key in "${PUBLIC_KEYS[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

# Adjust SSH configuration ownership and permissions
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

# Disable root SSH login with password
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
# Disable all SSH login with password
sed --in-place 's/^PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

# Add firewall exception for SSH and then enable UFW firewall
ufw allow OpenSSH
ufw --force enable

# Create swapfile to avoid docker OOM
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

# Add docker and digital ocean agent repos
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
curl https://repos.insights.digitalocean.com/sonar-agent.asc | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
add-apt-repository "deb https://repos.insights.digitalocean.com/apt/do-agent/ main main"


# update and install apps
apt update
apt --assume-yes upgrade
apt --assume-yes install zsh python docker-ce docker-compose do-agent

# Add user to docker group
usermod -aG docker "${USERNAME}"

# Change default shell to ZSH
usermod -s $(which zsh) ${USERNAME}

# Personal bootstrap as new sudo user
su ${USERNAME} -c "git clone https://github.com/rabidpug/bootstrap.git ${home_directory}/bootstrap && bash ${home_directory}/bootstrap/bootstrap.sh"

 