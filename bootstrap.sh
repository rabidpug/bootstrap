#!/bin/bash
set -euo pipefail

#############################
### INSTALL ANTIGEN & FZF ###
#############################

# Clone Antigen and add source command to .zshrc
git clone https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
echo 'source $HOME/.antigenrc' > "${home_directory}/.zshrc"

# Copy .antigenrc
cp "${home_directory}/bootstrap/.antigenrc" "${home_directory}/.antigenrc"

# Clone and install FZF
git clone --depth 1 https://github.com/junegunn/fzf.git "${home_directory}/.fzf"
"${home_directory}/.fzf/install" --all

#########################
### GET BACKUP ASSETS ###
#########################

# Get artifacts repo release ID
RELEASE_ID=$(curl -H "Authorization: token ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/rabidpug/artifacts/releases/latest | jq -r .id)

# Get all asset IDs from release
ASSETS=$(curl --H "Authorization: token ${GITHUB_AUTH_TOKEN}" "https://api.github.com/repos/rabidpug/artifacts/releases/${RELEASE_ID}/assets" | jq -c '.[] | {name: .name, id: .id}')

# Download assets and extract or place
for asset in $ASSETS;
do
name=$(echo $asset | jq -r .name | sed 's/\..*//')
id=$(echo $asset | jq -r .id)
case "$name" in
  *backup* )
    service_name=$(echo $asset | jq -r .name | sed 's/1_//' | sed 's/_.*//')
    mkdir -p "${home_directory}/docker/services/${service_name}/data/backups"
    curl -L -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}" -o "${home_directory}/docker/services/${service_name}/data/backups/${name}"
    ;;
  *config* )
    service_name=$(echo $asset | jq -r .name | sed 's/\..*//')
    mkdir -p "${home_directory}/docker/services/${service_name}/config"
    curl -L -H "Authorization: token ${GITHUB_AUTH_TOKEN}" -H "Accept: application/octet-stream" "https://api.github.com/repos/rabidpug/artifacts/releases/assets/${id}"  | tar xvz -C "${home_directory}/docker/services/${service_name}/config"
    ;;
esac
;
done

#####################
### SET UP DOCKER ###
#####################

# Merge Docker folder with backup assets
rsync -av "${home_directory}/bootstrap/docker/" "${home_directory}/docker/"

# Creat Web network and pull images
docker network create web
docker-compose -f "${home_directory}/docker/docker-compose.yml" pull

######################
### SET UP TRAEFIK ###
######################

# Add Digital Ocean Auth Token to Traefik .env
echo "DO_AUTH_TOKEN=${DO_AUTH_TOKEN}" > "${home_directory}/docker/services/traefik/.env"

# Add Username and Password to users.pw file
echo "${USERNAME}:$(openssl passwd -apr1 "${ADMIN_PASSWD}")" > "${home_directory}/docker/services/traefik/config/users.pw"

#####################
### SET UP SENTRY ###
#####################

# Get current sentry.conf.py file from source
curl https://raw.githubusercontent.com/getsentry/sentry/master/docker/sentry.conf.py -o "${home_directory}/docker/services/sentry/config/sentry.conf.py"

# Generate Sentry secret key and add to Sentry .env and config file
SENTRY_SECRET_KEY=$(docker run --rm sentry config generate-secret-key)
echo "system.secret-key: '${SENTRY_SECRET_KEY}'" >> "${home_directory}/docker/services/sentry/config/config.yml"
echo "SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY}" >> "${home_directory}/docker/services/sentry/.env"

# Run sentry upgrade and create user
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry upgrade --noinput
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry createuser --email m@jcuneo.com --password "${ADMIN_PASSWD}" --superuser --no-input

# import backed up metadata
docker-compose -f "${home_directory}/docker/docker-compose.yml" run --rm sentry sentry import /etc/sentry/backups/1_sentry_backup.tar

#####################
### SET UP GITLAB ###
#####################

# Spin up Gitlab
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d gitlab
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl reconfigure
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl start

# Stop services necessary for backup restore
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl stop unicorn
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl stop sidekiq

# Restore backup
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-backup restore force=yes

# Reconfigure. restart and check Gitlab
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl reconfigure
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-ctl restart
docker-compose -f "${home_directory}/docker/docker-compose.yml" exec gitlab gitlab-rake gitlab:check SANITIZE=true
docker-compose -f "${home_directory}/docker/docker-compose.yml" restart gitlab

####################
### START DOCKER ###
####################

# Spin up remaining services
docker-compose -f "${home_directory}/docker/docker-compose.yml" up -d

# remove personal bootstrap
rm -rf "${home_directory}/bootstrap"
