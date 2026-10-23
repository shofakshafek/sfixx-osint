#!/usr/bin/env bash
# modules/auto.sh — deteksi otomatis tipe target & jalankan modul yang sesuai

mod_auto() {
  local t="${1:-}" type u
  [[ -z $t ]] && { err "Masukkan target (email, IP, domain, URL, nomor, username, …)"; return 1; }
  type="$(detect_type "$t")"
  info "Tipe target terdeteksi: ${C_WHITE}${type}${C_RESET}"
  case $type in
    email)
      mod_email "$t"
      u="${t%@*}"; u="${u%%+*}"
      [[ $u =~ ^[A-Za-z0-9._-]{2,40}$ ]] && mod_username "$u"
      ;;
    ip)       mod_ip "$t" ;;
    url)      mod_url "$t"; mod_domain "$t" ;;
    domain)   mod_domain "$t" ;;
    phone)    mod_phone "$t"; mod_wa "$t" ;;
    wa)       mod_wa "$t" ;;
    mac)      mod_mac "$t" ;;
    btc|eth)  mod_crypto "$t" ;;
    geo)      mod_geo "$t" ;;
    file)     mod_exif "$t" ;;
    person)   mod_dork person "$t" ;;
    username) mod_username "$t"; info "Cek juga: sfixx github $t" ;;
  esac
}
