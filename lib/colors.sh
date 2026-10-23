#!/usr/bin/env bash
# lib/colors.sh — warna, helper tampilan, banner

_use_color=1
[[ -n ${NO_COLOR:-} || ${SFIXX_NO_COLOR:-0} == 1 ]] && _use_color=0
[[ ${SFIXX_TTY:-0} != 1 && ${SFIXX_FORCE_COLOR:-0} != 1 ]] && _use_color=0

if (( _use_color )); then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[1;31m'; C_GREEN=$'\e[1;32m'; C_YELLOW=$'\e[1;33m'
  C_BLUE=$'\e[1;34m'; C_MAGENTA=$'\e[1;35m'; C_CYAN=$'\e[1;36m'
  C_WHITE=$'\e[1;37m'; C_GRAY=$'\e[0;90m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_WHITE=""; C_GRAY=""
fi

info() { printf '%s[*]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

section() { printf '\n%s╭─[ %s%s%s%s ]%s\n' "$C_CYAN" "$C_WHITE" "$1" "$C_RESET" "$C_CYAN" "$C_RESET"; }

# kv "Label" "nilai" — kosong/null dilewati
kv() {
  [[ -z ${2:-} || ${2:-} == null ]] && return 0
  printf '  %s◆%s %-19s%s:%s %s\n' "$C_CYAN" "$C_RESET" "$1" "$C_GRAY" "$C_RESET" "$2"
}

# kvl "Label" "baris1\nbaris2" — daftar multi-baris
kvl() {
  local label="$1" line n=0
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if (( n++ == 0 )); then kv "$label" "$line"
    else printf '    %-19s  %s\n' "" "$line"; fi
  done <<<"${2:-}"
}

# tf true|false → Ya/Tidak berwarna
tf() {
  case "${1:-}" in
    true|1|yes)  printf '%sYa%s' "$C_YELLOW" "$C_RESET" ;;
    false|0|no)  printf '%sTidak%s' "$C_GREEN" "$C_RESET" ;;
    *)           printf '%s' "${1:-}" ;;
  esac
}

banner() {
  local f="$SFIXX_HOME/assets/banner.txt"
  printf '%s' "$C_CYAN"; [[ -f $f ]] && cat "$f"; printf '%s' "$C_RESET"
  printf '  %sOSINT Toolkit%s · v%s · %sgunakan secara legal & bertanggung jawab%s\n' \
    "$C_WHITE" "$C_RESET" "${SFIXX_VERSION:-1.0.0}" "$C_GRAY" "$C_RESET"
}
