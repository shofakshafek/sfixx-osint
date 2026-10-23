#!/usr/bin/env bash
# modules/whatsapp.sh — WhatsApp OSINT (pasif: tautan, varian, dork, pratinjau grup publik)

_wa_group() {
  local in="$1" code name img desc
  code="${in##*chat.whatsapp.com/}"; code="${code%%[?#/]*}"
  [[ $code =~ ^[A-Za-z0-9]{10,30}$ ]] || { err "Kode undangan grup tidak valid"; return 1; }
  section "WhatsApp Grup » chat.whatsapp.com/${code}"
  if fetch "https://chat.whatsapp.com/${code}" -H "Accept-Language: id,en;q=0.8"; then
    name="$(html_meta 'og:title' <<<"$HTTP_BODY")"
    img="$(html_meta 'og:image' <<<"$HTTP_BODY")"
    desc="$(html_meta 'og:description' <<<"$HTTP_BODY")"
    [[ $desc == "WhatsApp Group Invite" ]] && desc=""
    if [[ -z $name || $name == "WhatsApp Group Invite" || $name == "WhatsApp Group" ]]; then
      warn "Link tidak valid, sudah dicabut (revoked), atau kedaluwarsa"
    else
      kv "Nama grup" "$name"
      kv "Deskripsi" "$desc"
      kv "Ikon grup" "$img"
      kv "Kode undangan" "$code"
      kv "Status link" "${C_GREEN}aktif${C_RESET}"
    fi
  else
    warn "Tidak bisa membuka halaman undangan (HTTP $HTTP_CODE)"
  fi
  info "Data di atas adalah pratinjau publik yang tampil ke siapa pun pemegang link."
}

_wa_groupsearch() {
  local kw="$*" q
  [[ -z $kw ]] && { err "Masukkan kata kunci grup"; return 1; }
  q="site:chat.whatsapp.com \"${kw}\""
  section "Cari Grup WhatsApp Publik » $kw"
  dork_line "Google" "$q"
  kv "Bing" "https://www.bing.com/search?q=$(urlenc "$q")"
  kv "DuckDuckGo" "https://duckduckgo.com/?q=$(urlenc "$q")"
  info "Inspeksi link yang ketemu: sfixx wa https://chat.whatsapp.com/<kode>"
}

_wa_number() {
  local raw="$1" all
  is_phone "$raw" || { err "Format nomor tidak valid: $raw"; return 1; }
  phone_parse "$raw" || { err "Kode negara tidak dikenali — pakai format internasional, mis. +62812…"; return 1; }
  all="$(phone_or_query)"
  section "WHATSAPP OSINT » +${PH_E164}"
  kv "Nomor (E.164)" "+${PH_E164}"
  kv "Negara" "${PH_COUNTRY} (${PH_ISO})"
  if [[ $PH_CC == 62 ]] && _id_carrier "$PH_NSN"; then kv "Operator (prefix)" "${ID_OP} — ${ID_BRAND}"; fi

  section "Tautan WhatsApp"
  kv "Chat (wa.me)" "https://wa.me/${PH_E164}"
  kv "Chat (api)" "https://api.whatsapp.com/send?phone=${PH_E164}"

  section "Varian Nomor (untuk pencarian)"
  kvl "Varian" "$(phone_variants)"

  section "Jejak Publik (dork)"
  dork_line "wa.me terindeks" "\"wa.me/${PH_E164}\" OR inurl:\"wa.me/${PH_E164}\""
  dork_line "Nomor + kontak"       "(${all}) (whatsapp OR wa OR hubungi OR kontak OR chat)"
  dork_line "Marketplace/iklan"    "(${all}) (site:olx.co.id OR site:tokopedia.com OR site:shopee.co.id OR site:facebook.com/marketplace)"
  dork_line "Media sosial"           "(${all}) (site:facebook.com OR site:instagram.com OR site:linkedin.com OR site:x.com OR site:tiktok.com)"
  dork_line "Laporan penipuan"       "(${all}) (penipuan OR scam OR spam)"

  info "Status akun WhatsApp tidak bisa dicek secara pasif; modul ini hanya memakai sumber publik."
  info "Cek manual: simpan nomor di kontak, lihat info yang memang dibuka oleh privasi pemiliknya."
}

mod_wa() {
  local a="${1:-}"
  [[ -z $a ]] && { err "Pakai: sfixx wa <nomor> | wa <link grup> | wa group <kata kunci>"; return 1; }
  case $a in
    group|grup|search) shift; _wa_groupsearch "$@"; return ;;
  esac
  if [[ $a == *chat.whatsapp.com/* ]]; then _wa_group "$a"; return; fi
  if [[ $a == *wa.me/* ]]; then a="${a##*wa.me/}"; a="${a%%[?/]*}"; fi
  _wa_number "$a"
}
