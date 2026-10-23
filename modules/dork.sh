#!/usr/bin/env bash
# modules/dork.sh — generator dork pencarian (hanya membuat tautan pencarian)

_dork_run() {
  local item
  for item in "$@"; do dork_line "${item%%|*}" "${item#*|}"; done
}

_dork_help() {
  err "Pakai: sfixx dork <jenis> <target>"
  info "Jenis: person (nama) | email | user | domain | phone"
}

mod_dork() {
  local kind="${1:-}" t
  [[ -z $kind ]] && { _dork_help; return 1; }
  shift
  t="$*"
  [[ -z $t ]] && { _dork_help; return 1; }
  case $kind in
    person|nama|name)
      section "DORK » nama: $t"
      _dork_run \
        "Nama persis|\"$t\"" \
        "LinkedIn|\"$t\" site:linkedin.com/in" \
        "Facebook|\"$t\" site:facebook.com" \
        "Instagram|\"$t\" site:instagram.com" \
        "X / Twitter|\"$t\" (site:x.com OR site:twitter.com)" \
        "TikTok|\"$t\" site:tiktok.com" \
        "Dokumen|\"$t\" (filetype:pdf OR filetype:doc OR filetype:docx OR filetype:xls OR filetype:xlsx)" \
        "CV / resume|\"$t\" (cv OR resume OR \"curriculum vitae\")"
      ;;
    email)
      section "DORK » email: $t"
      _dork_run \
        "Exact match|\"$t\"" \
        "Paste / kode|\"$t\" (site:pastebin.com OR site:github.com OR site:gitlab.com OR site:gist.github.com)" \
        "Dokumen|\"$t\" (filetype:pdf OR filetype:doc OR filetype:docx OR filetype:xls OR filetype:xlsx OR filetype:txt)" \
        "Profil sosial|\"$t\" (site:linkedin.com OR site:facebook.com OR site:x.com OR site:instagram.com)"
      ;;
    user|username)
      section "DORK » username: $t"
      _dork_run \
        "Exact match|\"$t\"" \
        "Profil|\"$t\" (site:github.com OR site:instagram.com OR site:x.com OR site:tiktok.com OR site:reddit.com)" \
        "Forum / komunitas|\"$t\" (forum OR komunitas OR profile OR profil)" \
        "Paste|\"$t\" (site:pastebin.com OR site:gist.github.com)"
      ;;
    domain|web|site)
      t="$(host_of "$t")"
      section "DORK » domain: $t  (pakai untuk domain milik sendiri / yang diizinkan)"
      _dork_run \
        "Subdomain|site:*.$t -www" \
        "Dokumen publik|site:$t (filetype:pdf OR filetype:doc OR filetype:docx OR filetype:xls OR filetype:xlsx OR filetype:ppt OR filetype:pptx)" \
        "Direktori terbuka|site:$t intitle:\"index of\"" \
        "Halaman login|site:$t (inurl:login OR inurl:admin OR inurl:signin OR inurl:portal)" \
        "Backup / konfigurasi|site:$t (ext:bak OR ext:old OR ext:sql OR ext:log OR ext:conf OR ext:env)" \
        "Disebut di kode|\"$t\" (site:github.com OR site:gitlab.com OR site:bitbucket.org)" \
        "Disebut di paste|\"$t\" (site:pastebin.com OR site:paste.ee)" \
        "Email publik|\"@$t\""
      ;;
    phone|nomor|hp)
      is_phone "$t" && phone_parse "$t" || { err "Nomor tidak valid: $t"; return 1; }
      section "DORK » nomor: +${PH_E164}"
      phone_dorks
      ;;
    *) _dork_help; return 1 ;;
  esac
  return 0
}
