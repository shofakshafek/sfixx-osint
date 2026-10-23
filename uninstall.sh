#!/usr/bin/env bash
# Uninstaller Sfixx OSINT — menghapus tautan perintah (folder sumber tidak dihapus)
G=$'\e[1;32m'; Y=$'\e[1;33m'; N=$'\e[0m'
IS_TERMUX=0
[[ -n ${TERMUX_VERSION:-} || -d /data/data/com.termux/files/usr ]] && IS_TERMUX=1

for BIN in "${PREFIX:-/data/data/com.termux/files/usr}/bin" /usr/local/bin "$HOME/.local/bin"; do
  for n in sfixx sfixx-osint; do
    if [[ -L $BIN/$n ]]; then
      rm -f "$BIN/$n" 2>/dev/null || sudo rm -f "$BIN/$n"
      printf '%s[+]%s dihapus: %s/%s\n' "$G" "$N" "$BIN" "$n"
    fi
  done
done

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/sfixx-osint"
if [[ -d $CONF ]]; then
  read -rp "Hapus config & API key pribadi ($CONF)? [y/N] " a
  [[ $a =~ ^[yY]$ ]] && rm -rf "$CONF" && printf '%s[+]%s config dihapus\n' "$G" "$N"
fi
if [[ -d $HOME/sfixx-reports ]]; then
  read -rp "Hapus folder laporan ($HOME/sfixx-reports)? [y/N] " a
  [[ $a =~ ^[yY]$ ]] && rm -rf "$HOME/sfixx-reports" && printf '%s[+]%s laporan dihapus\n' "$G" "$N"
fi
printf '%s[!]%s Folder sumber tidak dihapus. Hapus manual bila perlu: rm -rf <folder sfixx-osint>\n' "$Y" "$N"
