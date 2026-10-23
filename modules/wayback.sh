#!/usr/bin/env bash
# modules/wayback.sh — arsip Wayback Machine (pasif)

_wb_date() { local t="$1"; printf '%s-%s-%s %s:%s' "${t:0:4}" "${t:4:2}" "${t:6:2}" "${t:8:2}" "${t:10:2}"; }

mod_wayback() {
  local t="${1:-}" first last ts code urls n
  [[ -z $t ]] && { err "Masukkan domain atau URL"; return 1; }
  t="${t#*://}"; t="${t%%\?*}"; t="${t%/}"
  section "Wayback Machine » $t"

  if fetch "https://web.archive.org/cdx/search/cdx?url=$(urlenc "$t")&output=json&limit=1&fl=timestamp,statuscode" && is_json "$HTTP_BODY"; then
    first="$(jq -r '.[1] // empty | "\(.[0]) \(.[1])"' <<<"$HTTP_BODY" 2>/dev/null)"
    ts="${first%% *}"; code="${first##* }"
    if [[ -n $ts ]]; then
      kv "Snapshot pertama" "$(_wb_date "$ts") (HTTP $code)"
      kv "  ↳ tautan" "https://web.archive.org/web/${ts}/${t}"
    else
      info "Belum ada snapshot untuk target ini"
      return 0
    fi
  else
    warn "CDX Wayback tidak merespons"; return 1
  fi

  if fetch "https://web.archive.org/cdx/search/cdx?url=$(urlenc "$t")&output=json&limit=-1&fl=timestamp,statuscode" && is_json "$HTTP_BODY"; then
    last="$(jq -r '.[1] // empty | "\(.[0]) \(.[1])"' <<<"$HTTP_BODY" 2>/dev/null)"
    ts="${last%% *}"; code="${last##* }"
    [[ -n $ts ]] && { kv "Snapshot terakhir" "$(_wb_date "$ts") (HTTP $code)"; kv "  ↳ tautan" "https://web.archive.org/web/${ts}/${t}"; }
  fi
  kv "Kalender snapshot" "https://web.archive.org/web/*/${t}"

  if [[ $t != */* ]]; then
    info "Mencari URL arsip menarik (dokumen, backup, konfigurasi)…"
    if fetch "https://web.archive.org/cdx/search/cdx?url=$(urlenc "$t")&matchType=domain&output=text&fl=original&collapse=urlkey&limit=3000" --max-time 45; then
      n="$(wc -l <<<"$HTTP_BODY")"
      kv "URL unik (maks 3000)" "$n"
      urls="$(grep -Ei '\.(sql|bak|old|zip|tar|gz|7z|rar|env|log|conf|config|ini|xml|json|ya?ml|pdf|xlsx?|csv|docx?|txt)(\?|$)' <<<"$HTTP_BODY" | head -n 25)"
      kvl "File menarik" "$urls"
    else
      warn "Daftar URL arsip tidak tersedia (timeout / terlalu besar)"
    fi
  fi
  return 0
}
