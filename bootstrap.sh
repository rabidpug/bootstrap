#!/bin/bash
set -euo pipefail

#############################
### INSTALL ANTIGEN & FZF ###
#############################

echo "Clone Antigen and add source command to .zshrc"
git clone https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
echo 'source $HOME/.antigenrc' > "${home_directory}/.zshrc"

echo "Copy .antigenrc"
cp "${home_directory}/bootstrap/.antigenrc" "${home_directory}/.antigenrc"

echo "Clone and install FZF"
git clone --depth 1 https://github.com/junegunn/fzf.git "${home_directory}/.fzf"
"${home_directory}/.fzf/install" --all

#########################
### GET BACKUP ASSETS ###
#########################

echo "Get artifacts repo release ID"
RELEASE_ID=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

echo "Get all asset IDs from release"
ASSETS=$(curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | jq -c '.[] | {name: .name, id: .id}')

echo "Download assets and extract or place"
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
    curl -fsSL -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}"  | tar xvz -C "${home_directory}/docker/services/${service_name}/config"
    ;;
esac;
done

#####################
### SET UP DOCKER ###
#####################

echo "Merge Docker folder with backup assets"
rsync -av "${home_directory}/bootstrap/docker/" "${home_directory}/docker/"

echo "Creat Web network and pull images"
docker network create web

######################
### SET UP TRAEFIK ###
######################

echo "Add Digital Ocean Auth Token to Traefik .env"
echo "DO_AUTH_TOKEN=${DO_AUTH_TOKEN}" > "${home_directory}/docker/services/traefik/.env"

echo "Add Username and Password to users.pw file"
echo "${USERNAME}:$(openssl passwd -apr1 "${ADMIN_PASSWD}")" > "${home_directory}/docker/services/traefik/config/users.pw"

#####################
### SET UP SENTRY ###
#####################

echo "Get current sentry.conf.py file from source"
curl -fsSL --create-dirs https://raw.githubusercontent.com/getsentry/sentry/master/docker/sentry.conf.py -o "${home_directory}/docker/services/sentry/config/sentry.conf.py"

echo "Generate Sentry secret key and add to Sentry .env and config file"
SENTRY_SECRET_KEY=$(docker run --rm sentry config generate-secret-key)
echo "system.secret-key: '${SENTRY_SECRET_KEY}'" >> "${home_directory}/docker/services/sentry/config/config.yml"
echo "SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY}" >> "${home_directory}/docker/services/sentry/.env"

echo "Run sentry upgrade and create user"
docker-compose -f "${home_directory}/docker/docker-compose.yml" run -T --rm sentry upgrade --noinput
docker-compose -f "${home_directory}/docker/docker-compose.yml" run -T --rm sentry createuser --email m@jcuneo.com --password "${ADMIN_PASSWD}" --superuser --no-input

echo "import backed up metadata"
docker-compose -f "${home_directory}/docker/docker-compose.yml" run -T --rm sentry sentry import /etc/sentry/backups/1_sentry_backup.tar

#####################
### SET UP GITLAB ###
#####################

echo "Spin up Gitlab"
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d gitlab
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-ctl reconfigure
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-ctl start

echo "Stop services necessary for backup restore"
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-ctl stop unicorn
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-ctl stop sidekiq

echo "Restore backup"
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-backup restore force=yes

echo "Reconfigure. restart and check Gitlab"
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-ctl reconfigure
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-ctl restart
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec -T gitlab gitlab-rake gitlab:check SANITIZE=true
docker-compose -f "${home_directory}/docker/docker-compose.yml" restart gitlab

####################
### START DOCKER ###
####################

echo "Spin up remaining services"
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d

echo "Remove personal bootstrap"
rm -rf "${home_directory}/bootstrap"
