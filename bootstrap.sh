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
"${home_directory}/.fzf/install" --all &> /dev/null

#########################
### GET BACKUP ASSETS ###
#########################

echo ">> Getting artifacts repo release ID"
RELEASE_ID=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

echo ">> Getting all asset IDs from release"
ASSETS=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | jq -c '.[] | {name: .name, id: .id}')

echo ">> Downloading assets and extracting or placing"
for asset in $ASSETS;
do
name=$(echo $asset | jq -r .name | sed 's/\..*//')
id=$(echo $asset | jq -r .id)
case "$name" in
  *backup* )
    service_name=$(echo $asset | jq -r .name | sed 's/1_//' | sed 's/_.*//')
    mkdir -p "${home_directory}/docker/services/${service_name}/data/backups"
    curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}" -o "${home_directory}/docker/services/${service_name}/data/backups/${name}"
    ;;
  *config* )
    service_name=$(echo $asset | jq -r .name | sed 's/\..*//')
    mkdir -p "${home_directory}/docker/services/${service_name}/config"
    curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}"  | tar xz -C "${home_directory}/docker/services/${service_name}/config"
    ;;
esac;
done

#####################
### SET UP DOCKER ###
#####################

echo ">> Merging Docker folder with backup assets"
rsync -aq "${home_directory}/bootstrap/docker/" "${home_directory}/docker/"

echo ">> Creating Web network"
docker network create web > /dev/null

######################
### SET UP TRAEFIK ###
######################

echo ">> Adding Digital Ocean Auth Token to Traefik .env"
echo "DO_AUTH_TOKEN=${DO_AUTH_TOKEN}" > "${home_directory}/docker/services/traefik/.env"

echo ">> Adding Username and Password to users.pw file"
echo "${USERNAME}:$(openssl passwd -apr1 "${ADMIN_PASSWD}")" > "${home_directory}/docker/services/traefik/config/users.pw"

#####################
### SET UP SENTRY ###
#####################

echo ">> Getting current sentry.conf.py file from source"
curl -fsSL --create-dirs https://raw.githubusercontent.com/getsentry/sentry/master/docker/sentry.conf.py -o "${home_directory}/docker/services/sentry/config/sentry.conf.py"

echo ">> Generating Sentry secret key and adding to Sentry .env and config file"
SENTRY_SECRET_KEY=$(docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry config generate-secret-key 2> /dev/null)
echo "system.secret-key: '${SENTRY_SECRET_KEY}'" >> "${home_directory}/docker/services/sentry/config/config.yml"
echo "SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY}" >> "${home_directory}/docker/services/sentry/.env"

echo ">> Running sentry upgrade and createuser"
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry upgrade --noinput &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry createuser --email m@jcuneo.com --password "${ADMIN_PASSWD}" --superuser --no-input &> /dev/null

echo ">> Importing backed up metadata"
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry sentry import /etc/sentry/backups/1_sentry_backup.tar &> /dev/null

#####################
### SET UP GITLAB ###
#####################

echo ">> Spinning up Gitlab"
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d gitlab &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl reconfigure &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl start &> /dev/null

echo ">> Stopping services necessary for backup restore"
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl stop unicorn &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl stop sidekiq &> /dev/null

echo ">> Restoring backup"
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-backup restore force=yes &> /dev/null

echo ">> Reconfiguring, restating and checking Gitlab"
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl reconfigure &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl restart &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-rake gitlab:check SANITIZE=true &> /dev/null
docker-compose -f "${home_directory}/docker/docker-compose.yml" restart gitlab &> /dev/null

####################
### START DOCKER ###
####################

echo ">> Spinning up remaining services"
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d &> /dev/null

echo ">> Removing personal bootstrap"
rm -rf "${home_directory}/bootstrap"
