#!/usr/bin/env bash
# Installer Sfixx OSINT — Termux / Debian / Ubuntu / Arch / Fedora / macOS (brew)
# Pakai: bash install.sh [--no-deps]

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_DEPS=0; [[ ${1:-} == --no-deps ]] && NO_DEPS=1

G=$'\e[1;32m'; Y=$'\e[1;33m'; R=$'\e[1;31m'; C=$'\e[1;36m'; N=$'\e[0m'
say()  { printf '%s[*]%s %s\n' "$C" "$N" "$*"; }
good() { printf '%s[+]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$N" "$*"; }
bad()  { printf '%s[x]%s %s\n' "$R" "$N" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

IS_TERMUX=0
[[ -n ${TERMUX_VERSION:-} || -d /data/data/com.termux/files/usr ]] && IS_TERMUX=1
SUDO=""
if (( ! IS_TERMUX )) && [[ $EUID -ne 0 ]] && have sudo; then SUDO="sudo"; fi

pm_install() {
  if   (( IS_TERMUX )); then pkg install -y "$@"
  elif have apt-get;    then $SUDO apt-get install -y "$@"
  elif have pacman;     then $SUDO pacman -S --noconfirm --needed "$@"
  elif have dnf;        then $SUDO dnf install -y "$@"
  elif have brew;       then brew install "$@"
  else return 1; fi
}

optional_pkgs() {
  if   (( IS_TERMUX )); then echo "dnsutils openssl-tool whois exiftool file"
  elif have apt-get;    then echo "dnsutils openssl whois libimage-exiftool-perl file"
  elif have pacman;     then echo "bind openssl whois perl-image-exiftool file"
  elif have dnf;        then echo "bind-utils openssl whois perl-Image-ExifTool file"
  elif have brew;       then echo "bind openssl whois exiftool"
  fi
}

printf '%s\n' "${C}== Sfixx OSINT installer ==${N}"

if (( ! NO_DEPS )); then
  say "Memasang dependensi wajib (curl, jq, git)…"
  (( IS_TERMUX )) && pkg update -y >/dev/null 2>&1
  have apt-get && ! (( IS_TERMUX )) && $SUDO apt-get update -y >/dev/null 2>&1
  for p in curl jq git; do
    have "$p" || pm_install "$p" >/dev/null 2>&1 || true
    if have "$p"; then good "$p siap"; else bad "$p gagal dipasang — pasang manual lalu jalankan ulang"; fi
  done
  say "Memasang paket opsional (dig, openssl, whois, exiftool, file)…"
  for p in $(optional_pkgs); do
    pm_install "$p" >/dev/null 2>&1 && good "$p" || warn "$p dilewati (opsional)"
  done
fi

have curl && have jq || { bad "curl & jq wajib ada. Pasang dulu, lalu ulangi."; exit 1; }

chmod +x "$DIR/sfixx" "$DIR"/*.sh 2>/dev/null

# ── tautan perintah global ──
if (( IS_TERMUX )); then BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"; LN="ln"
elif [[ -w /usr/local/bin ]]; then BIN="/usr/local/bin"; LN="ln"
elif [[ -n $SUDO ]]; then BIN="/usr/local/bin"; LN="$SUDO ln"
else mkdir -p "$HOME/.local/bin"; BIN="$HOME/.local/bin"; LN="ln"; fi

$LN -sf "$DIR/sfixx" "$BIN/sfixx"
$LN -sf "$DIR/sfixx" "$BIN/sfixx-osint"
good "Perintah terpasang: sfixx  (alias: sfixx-osint) → $BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) warn "Tambahkan ke PATH: export PATH=\"$BIN:\$PATH\"";; esac

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/sfixx-osint"
mkdir -p "$CONF"
[[ -f $CONF/sfixx.conf ]] || cp "$DIR/config/sfixx.conf" "$CONF/sfixx.conf"
good "Config pribadi: $CONF/sfixx.conf"

printf '\n%s\n' "${G}Selesai!${N} Coba:  ${C}sfixx${N}   |   ${C}sfixx help${N}   |   ${C}sfixx ip 8.8.8.8${N}"
