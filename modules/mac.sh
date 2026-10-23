#!/usr/bin/env bash
# modules/mac.sh — vendor MAC address

mod_mac() {
  local m="${1:-}" c oui b0 fmt
  is_mac "$m" || { err "Format MAC tidak valid (contoh: 44:38:39:ff:ef:57)"; return 1; }
  c="${m//[:.-]/}"; c="${c^^}"
  oui="${c:0:6}"; b0=$(( 16#${c:0:2} ))
  fmt="${c:0:2}:${c:2:2}:${c:4:2}:${c:6:2}:${c:8:2}:${c:10:2}"
  section "MAC » $fmt"
  kv "OUI (prefix)" "${c:0:2}:${c:2:2}:${c:4:2}"
  if (( b0 & 2 )); then kv "Jenis alamat" "Locally administered (acak/privat — mis. MAC randomization ponsel)"
  else kv "Jenis alamat" "Universally administered (ditetapkan pabrikan)"; fi
  if (( b0 & 1 )); then kv "Tipe" "Multicast"; else kv "Tipe" "Unicast"; fi
  if fetch "https://api.macvendors.com/${oui}"; then
    kv "Vendor" "$HTTP_BODY"
    (( b0 & 2 )) && info "MAC acak: vendor di atas tidak bermakna (alamat dibuat perangkat, bukan pabrikan)."
  elif [[ $HTTP_CODE == 404 ]]; then
    kv "Vendor" "tidak terdaftar di basis OUI"
  elif [[ $HTTP_CODE == 429 ]]; then
    warn "macvendors.com rate-limit (maks 1 request/detik) — coba lagi sebentar"
  else
    warn "Lookup vendor gagal (HTTP $HTTP_CODE)"
  fi
  return 0
}
