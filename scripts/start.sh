#!/bin/bash
set -euo pipefail

S_PATH=/usr/local/bootstrap/scripts

source "$S_PATH/lg.sh"

lg "##Create User##"
bash "$S_PATH/create-user.sh"
lg "##Install Packages##"
bash "$S_PATH/install-packages.sh"
lg "##User Shell##"
bash "$S_PATH/user-shell.sh"
lg "##Docker Project##"
bash "$S_PATH/docker-project.sh"
lg "##DNS Records##"
bash "$S_PATH/dns-records.sh"
lg "##Cronjobs##"
bash "$S_PATH/cronjobs.sh"
