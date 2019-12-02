#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/utilities/lg.sh"

lg '## BEGINNING CREATE USER ##'
if [ -z "${USERNAME:-}" ]; then
  lg 'Skipping - no username provided'
elif [ -z "$(id -u "$USERNAME" 2>&1 >/dev/null)" ]; then
  lg "Skipping - user $USERNAME already exists"
else
  lg "Adding $USERNAME as sudo user and granting privileges"
  useradd --create-home --shell "/bin/bash" --groups sudo "$USERNAME"

  lg 'Checking root account password'
  encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

  if [ "$encrypted_root_pw" != "*" ]; then
    lg 'Transfering root password to user'
    echo "$USERNAME:$encrypted_root_pw" | chpasswd --encrypted
    lg 'Locking root account password access'
    passwd --lock root
  else
    lg 'Deleting invalid password for sudo user'
    passwd --delete "$USERNAME"
  fi

  lg 'Expiring sudo user password'
  chage --lastday 0 "$USERNAME"

  lg 'Creating SSH directory for sudo user'
  home_directory="$(eval echo ~$USERNAME)"
  mkdir --parents "$home_directory/.ssh"

  lg 'Copying root account public keys'
  cp /root/.ssh/authorized_keys "$home_directory/.ssh"
  if [ -z "${PUBLIC_KEYS:-}" ]; then
    lg 'No additional public keys provided'
  else
    lg 'Adding additional provided public keys'
    for pub_key in "${PUBLIC_KEYS[@]}"; do
      echo "$pub_key" >>"$home_directory/.ssh/authorized_keys"
    done
  fi
  lg 'Adjusting SSH configuration ownership and permissions'
  chmod 0700 "$home_directory/.ssh"
  chmod 0600 "$home_directory/.ssh/authorized_keys"
  chown --recursive "$USERNAME":"$USERNAME" "$home_directory/.ssh"

  lg 'Disabling root SSH login with password'
  sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

  lg 'Disabling all SSH login with password'
  sed --in-place 's/^PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
  if sshd -t -q; then
    systemctl restart sshd
  fi

  lg 'Disabling sudo password requirement for user'
  echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USERNAME"
fi

lg '## CREATE USER COMPLETED ##'
