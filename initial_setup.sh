#!/bin/bash
set -euo pipefail

########################
### SCRIPT VARIABLES ###
########################

# Name of the user to create and grant sudo privileges
USERNAME=$1

OTHER_PUBLIC_KEYS_TO_ADD=(
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDxvSWFu4ljGMFdtmbZWKjc+NZxjW74RENIeFqCXQRJZb/VS3wXh/dHev973/fdO73Ma4vv1bkLBtmornKeu7kjTet6o+Dpup7sVoBqZ1ilvBTHVIlOHKpmDJ5sxU22AnMEXwBQPRvK10mKFkQ7m/l/KxGEy84+oiZeTiamAPXYFsZrKJ68mSKUZCBhGgjEPc0l4hS8QHuZeqX/aIVwapfNADuMSYKJTHV90mcMCuj4C5CY3CnSwQba9WE6yg3D/HdzqR6/NAs/X9VQWOvp8wk92Sqjk0Bn6gCvCdxQDdnz4t5dMa823d4Wy3S4imUtVKKvJz8DsYJgKltuPx+ZNKiZ matt@Matts-MacBook-Pro.local"
)

# Whether to copy over the root user's `authorized_keys` file to the new sudo
# user.
COPY_AUTHORIZED_KEYS_FROM_ROOT=true

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

# Expire the sudo user's password immediately to force a change
chage --lastday 0 "${USERNAME}"

# Create SSH directory for sudo user
home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

# Copy `authorized_keys` file from root if requested
if [ "${COPY_AUTHORIZED_KEYS_FROM_ROOT}" = true ]; then
    cp /root/.ssh/authorized_keys "${home_directory}/.ssh"
fi

# Add additional provided public keys
for pub_key in "${OTHER_PUBLIC_KEYS_TO_ADD[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

# Adjust SSH configuration ownership and permissions
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

# Disable root SSH login with password
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed --in-place 's/^PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

# Add exception for SSH and then enable UFW firewall
ufw allow OpenSSH
ufw --force enable

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"

apt update
apt --assume-yes upgrade
apt --assume-yes install zsh python docker-ce docker-compose
usermod -aG docker "${USERNAME}"

git clone https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
git clone --depth 1 https://github.com/junegunn/fzf.git "${home_directory}/.fzf"
echo 'source $HOME/.antigenrc' > "${home_directory}/.zshrc"

"${home_directory}/.fzf/install" --all
chown -R "${USERNAME}":"${USERNAME}" "${home_directory}"
usermod -s $(which zsh) ${USERNAME}
