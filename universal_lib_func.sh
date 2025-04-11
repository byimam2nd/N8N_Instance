# -------------------------------
# Universal Function
# -------------------------------

log() {
  if [ -n "$2" ]; then
    echo -e "$1$2${RESET}"
  else
    echo -e "$1"
  fi
}
