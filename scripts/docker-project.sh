#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"

if grep -Eq '/(lxc|docker|kubepods)/[[:xdigit:]]{64}' /proc/1/cgroup; then
  lg 'Skipping docker project setup - Code server'
elif [ -z "$USERNAME" ]; then
  lg 'Skipping docker project setup - No user'
elif [ -z "$GITHUB_AUTH_TOKEN" ]; then
  lg 'Skipping docker project setup - No auth token'
else
  home_directory="$(eval echo ~$USERNAME)"
  lg 'Getting asset release id'
  release_id=$(curl -fsSL -H "Authorization: token $GITHUB_AUTH_TOKEN" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

  lg 'Getting asset IDs'
  mapfile -t assets < <(curl -fsSL -H "Authorization: token $GITHUB_AUTH_TOKEN" "https://api.github.com/repos/rabidpug/artifacts/releases/$release_id/assets" | jq -c '.[] | {name: .name, id: .id}')

  for asset in "${assets[@]}"; do
    name=$(echo "$asset" | jq -r .name)
    id=$(echo "$asset" | jq -r .id)
    case "$name" in
    *docker*)
      lg 'Extracting Docker assets'
      curl -fsSL -H "Authorization: token $GITHUB_AUTH_TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/$id" | tar --same-owner -xzp -C "$home_directory"
      ;;
    esac
  done

  lg 'Creating docker Web network'
  docker network create web

  lg 'Spinning up docker services'
  docker-compose -f "$home_directory/docker/docker-compose.yml" up -d
fi
