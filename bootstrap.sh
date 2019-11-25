#!/bin/bash
set -euo pipefail

#############################
### INSTALL ANTIGEN & FZF ###
#############################

echo ">> Installing Antigen and add source command to .zshrc"
git clone -q https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
echo 'source $HOME/.antigenrc' > "${home_directory}/.zshrc"

echo ">> Copying .antigenrc"
cp "${home_directory}/bootstrap/.antigenrc" "${home_directory}/.antigenrc"

echo ">> Installing FZF"
git clone -q --depth 1 https://github.com/junegunn/fzf.git "${home_directory}/.fzf"
"${home_directory}/.fzf/install" --all

#####################
### SET UP DOCKER ###
#####################

echo ">> Downloading and extracting docker assets"
RELEASE_ID=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

ASSETS=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | jq -c '.[] | {name: .name, id: .id}')

for asset in $ASSETS;
do
name=$(echo $asset | jq -r .name)
id=$(echo $asset | jq -r .id)
case "$name" in
  *docker* )
    curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}"  | tar --same-owner xzp -C "${home_directory}"
    ;;
esac;
done

echo ">> Creating docker Web network"
docker network create web

echo ">> Spinning up docker services"
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d
