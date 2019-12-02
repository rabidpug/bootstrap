#!/bin/bash
set -euo pipefail

BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"
source "$BS_PATH/scripts/lg.sh"
lg '##DNS RECORDS##'
if grep -Eq '/(lxc|docker|kubepods)/[[:xdigit:]]{64}' /proc/1/cgroup; then
  lg 'Skipping dns record setup - Code server'
elif [ -z "${DO_AUTH_TOKEN:-}" ]; then
  lg 'Skipping dns record setup - No auth token'
elif [ -z "${DOMAINS:-}" ]; then
  lg 'Skipping dns record setup - No domains'
else
  lg 'Getting public IP'
  public_ip=$(curl -fsSL http://icanhazip.com)
  lg 'Getting existing domains'
  mapfile -t existing_domains < <(curl -fsSL -X GET -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" "https://api.digitalocean.com/v2/domains" | jq -r '.domains[].name')
  lg 'Creating required records for domains'
  for domain in "${DOMAINS[@]}"; do
    unset exits
    case "${existing_domains[@]}" in
    *$domain*) exists=true ;;
    esac
    if [ -z $exists ]; then
      lg "adding $domain to dns"
      curl -fsSL -X POST -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"name\":\"$domain\"}" "https://api.digitalocean.com/v2/domains"
    fi
    domain_records=$(curl -fsSL -X GET -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" "https://api.digitalocean.com/v2/domains/$domain/records" | jq -c '.domain_records')
    host_record=$(echo "$domain_records" | jq -c '.[] | select(.type=="A" and .name=="@")')
    wildcard_record=$(echo "$domain_records" | jq -c '.[] | select(.type=="A" and .name=="*")')
    host_id=$(echo "$host_record" | jq -r .id)
    host_data=$(echo "$host_record" | jq -r .data)
    wildcard_id=$(echo "$wildcard_record" | jq -r .id)
    wildcard_data=$(echo "$wildcard_record" | jq -r .data)
    if [ "$host_data" != "$public_ip" ]; then
      if [ -z "$host_id" ]; then
        lg "creating host record for $domain > $public_ip"
        curl -fsSL -X POST -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"type\":\"A\",\"name\":\"@\",\"data\":\"$public_ip\"}" "https://api.digitalocean.com/v2/domains/$domain/records"
      else
        lg "updating host record for $domain > $public_ip (was $host_data)"
        curl -fsSL -X PUT -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"data\":\"$public_ip\"}" "https://api.digitalocean.com/v2/domains/$domain/records/$host_id"
      fi
    else
      lg "host record for $domain up to date"
    fi
    if [ "$wildcard_data" != "$public_ip" ]; then
      if [ -z "$wildcard_id" ]; then
        lg "creating wildcard record for $domain > $public_ip"
        curl -fsSL -X POST -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"type\":\"A\",\"name\":\"*\",\"data\":\"$public_ip\"}" "https://api.digitalocean.com/v2/domains/$domain/records"
      else
        lg "updating wildcard record for $domain > $public_ip (was $wildcard_data)"
        curl -fsSL -X PUT -H "Authorization: Bearer $DO_AUTH_TOKEN" -H "Content-Type: application/json" -d "{\"data\":\"$public_ip\"}" "https://api.digitalocean.com/v2/domains/$domain/records/$wildcard_id"
      fi
    else
      lg "wildcard record for $domain up to date"
    fi
  done
fi
