# -------------------------------
# Universal Function
# -------------------------------

function sudo_controller() {
  while true; do
    read -p "Apakah ingin menggunakan sudo untuk setiap perintah? (y/n): " use_sudo
    if [[ -z "$use_sudo" ]]; then
      SUDO="sudo"
      break
    fi
    case $use_sudo in
      [Yy]*) SUDO="sudo"; break ;;
      [Nn]*) SUDO=""; break ;;
      *) echo "Masukkan y atau n saja!" ;;
    esac
  done
}