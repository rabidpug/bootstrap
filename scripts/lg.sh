BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"

if [ -z "$DEBUG" ]; then
  exec 3>&1
else
  exec 3>&1 &>/dev/null
fi
lg() {
  echo ">> [$(date '+%Y-%m-%d %H:%M:%S')]: $@" >&3
}
