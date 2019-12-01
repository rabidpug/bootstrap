#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

if [ -z "$USERNAME" ]; then
  lg 'Skipping configuring user shell - No user'
else
  home_directory="$(eval echo ~$USERNAME)"

  lg 'Changing user shell to zsh'
  usermod -s "$(command -v zsh)" "$USERNAME"

  lg 'sourcing /etc/profile in .zshrc'
  su "$USERNAME" -c "echo 'source /etc/profile' >> $home_directory/.zshrc" &>/dev/null

  lg 'Installing FZF'
  su "$USERNAME" -c "git clone -q --depth 1 https://github.com/junegunn/fzf.git $home_directory/.fzf && $home_directory/.fzf/install --all" &>/dev/null

  lg 'Installing Antigen'
  su "$USERNAME" -c "git clone -q https://github.com/zsh-users/antigen.git $home_directory/antigen" &>/dev/null
  echo "source $BS_PATH/.antigenrc" >>"$home_directory/.zshrc"
fi
