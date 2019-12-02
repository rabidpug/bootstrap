#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

lg '##USER SHELL##'
if [ -z "${USERNAME:-}" ]; then
  lg 'Skipping configuring user shell - No user'
else
  home_directory="$(eval echo ~$USERNAME)"

  lg 'Changing user shell to zsh'
  usermod -s "$(command -v zsh)" "$USERNAME"

  lg 'sourcing /etc/profile in .zshrc'
  su "$USERNAME" -c "echo 'source /etc/profile' >> $home_directory/.zshrc"

  lg 'Configuring git identity'
  su "$USERNAME" -c "git config --global user.email $GIT_EMAIL"
  su "$USERNAME" -c "git config --global user.name $GIT_NAME"

  lg 'Installing FZF'
  su "$USERNAME" -c "git clone -q --depth 1 https://github.com/junegunn/fzf.git $home_directory/.fzf && $home_directory/.fzf/install --all"

  lg 'Installing Antigen'
  su "$USERNAME" -c "git clone -q https://github.com/zsh-users/antigen.git $home_directory/antigen"
  ln -sf "$BS_PATH/.antigenrc" "$home_directory"
  echo 'source $HOME/.antigenrc' >>"$home_directory/.zshrc"
fi
