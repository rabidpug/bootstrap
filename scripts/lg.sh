BS_PATH=/usr/local/bootstrap

source "$BS_PATH/.env"

if [ "$DEBUG" != "1" ]; then
  exec 3>&1 &>/dev/null
else
  exec 3>&1
fi
lg() {
  echo ">> [$(date '+%Y-%m-%d %H:%M:%S')]: $@" >&3
}
