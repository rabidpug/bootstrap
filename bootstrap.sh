#!/bin/bash
set -euo pipefail

####################
### SCRIPT LOGIC ###
####################

# Clone & install antigen and fzf
git clone https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
git clone --depth 1 https://github.com/junegunn/fzf.git "${home_directory}/.fzf"
echo 'source $HOME/.antigenrc' > "${home_directory}/.zshrc"
"${home_directory}/.fzf/install" --all
cp "${home_directory}/bootstrap/.antigenrc" "${home_directory}/.antigenrc"

# Get backup assets
RELEASE_ID=$(curl -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | fq -r .id)
ASSETS=($(curl --H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | fq -c '.[] | {name: .name, id: .id}'))
for asset in $ASSETS;
do
name=$(echo $asset | fq -r .name | sed 's/\..*//')
service_name=$(echo $asset | fq -r .name | sed 's/\..*//')
id=$(echo $asset | fq -r .id)
case "$name" in
  *backup* )
    mkdir -p "${home_directory}/docker/services/${service_name}/data/backups"
    curl -L -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}" -o "${home_directory}/docker/services/${service_name}/data/backups/${name}";;
  *config* )
    mkdir -p "${home_directory}/docker/services/${service_name}/config"
    curl -L -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}"  | tar xvz -C "${home_directory}/docker/services/${service_name}/config";;
esac
;
done

# Set up Docker
rsync -av "${home_directory}/bootstrap/docker/" "${home_directory}/docker/"
docker network create web
docker-compose -f "${home_directory}/docker/docker-compose.yml" pull

# Set up Traefik
echo "DO_AUTH_TOKEN=${DO_AUTH_TOKEN}" > "${home_directory}/docker/services/traefik/.env"
echo "${USERNAME}:$(openssl passwd -apr1 "${ADMIN_PASSWD}")" > "${home_directory}/docker/services/traefik/config/users.pw"

# Set up Sentry
curl https://raw.githubusercontent.com/getsentry/sentry/master/docker/sentry.conf.py -o "${home_directory}/docker/services/sentry/config/sentry.conf.py"
SENTRY_SECRET_KEY=$(docker run --rm sentry config generate-secret-key)
echo "system.secret-key: '${SENTRY_SECRET_KEY}'" >> "${home_directory}/docker/services/sentry/config/config.yml"
echo "SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY}" >> "${home_directory}/docker/services/sentry/.env"
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry upgrade --noinput
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry createuser --email m@jcuneo.com --password "${ADMIN_PASSWD}" --superuser --no-input

# Set up Gitlab
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d gitlab
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl reconfigure
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl start
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl stop unicorn
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl stop sidekiq
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-backup restore force=yes
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl reconfigure
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl restart
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-rake gitlab:check SANITIZE=true
docker-compose -f "${home_directory}/docker/docker-compose.yml" restart gitlab

# initiate docker
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d

# remove personal bootstrap
rm -rf "${home_directory}/bootstrap"
