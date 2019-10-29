#!/bin/bash
set -euo pipefail

########################
### SCRIPT VARIABLES ###
########################

## USED FOR:
# Traefik dashboard password
ADMIN_PASSWD=***ADMIN_PASSWD***

## USED FOR:
# Traefik acme dns challenge
DO_AUTH_TOKEN=***DO_AUTH_TOKEN***

####################
### SCRIPT LOGIC ###
####################

USERNAME=$(whoami)
home_directory="$(eval echo ~${USERNAME})"

# Clone & install antigen and fzf
git clone https://github.com/zsh-users/antigen.git "${home_directory}/antigen"
git clone --depth 1 https://github.com/junegunn/fzf.git "${home_directory}/.fzf"
echo 'source $HOME/.antigenrc' > "${home_directory}/.zshrc"
"${home_directory}/.fzf/install" --all

# personal bootstrap
git clone https://github.com/rabidpug/bootstrap.git "${home_directory}/bootstrap"

# Move antigen config
mv "${home_directory}/bootstrap/.antigenrc" "${home_directory}/.antigenrc"

# Move docker config
mv "${home_directory}/bootstrap/docker" "${home_directory}/docker"

# remove personal bootstrap
rm -rf "${home_directory}/bootstrap"

# Add digital ocean auth token to traefik .env
echo "DO_AUTH_TOKEN=${DO_AUTH_TOKEN}" > "${home_directory}/docker/services/traefik/.env"

# Add user and password for access to traefik dashboard
echo "${USERNAME}:$(openssl passwd -apr1 "${ADMIN_PASSWD}")" > "${home_directory}/docker/services/traefik/config/users.pw"

# Download config file for Sentry
curl https://raw.githubusercontent.com/getsentry/sentry/master/docker/sentry.conf.py -o "${home_directory}/docker/services/sentry/config/sentry.conf.py"

# Generate secret key for Sentry
SENTRY_SECRET_KEY=$(docker run --rm sentry config generate-secret-key)
echo "system.secret-key: '${SENTRY_SECRET_KEY}'" >> "${home_directory}/docker/services/sentry/config/config.yml"
echo "SENTRY_SECRET_KEY=${SENTRY_SECRET_KEY}" >> "${home_directory}/docker/services/sentry/.env"

# initiate docker
cd "${home_directory}/docker"
docker network create web
docker-compose run --rm sentry upgrade --noinput
docker-compose run --rm sentry createuser --email m@jcuneo.com --password "${ADMIN_PASSWD}" --superuser --no-input
docker-compose up -d
