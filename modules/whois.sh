#!/usr/bin/env bash
# modules/whois.sh — WHOIS / RDAP untuk domain & IP

age_days() {   # ISO8601 → jumlah hari sejak tanggal tsb
  local e; e="$(date -d "$1" +%s 2>/dev/null)" || return 1
  [[ -n $e ]] && echo $(( ( $(date +%s) - e ) / 86400 ))
}

# rdap_domain_load <domain> → set RD_* ; return 1 bila gagal
rdap_domain_load() {
  local d="$1"
  RD_JSON=""; RD_CREATED=""; RD_EXPIRES=""; RD_UPDATED=""; RD_REGISTRAR=""
  RD_NS=""; RD_STATUS=""; RD_ABUSE=""; RD_DNSSEC=""
  fetch "https://rdap.org/domain/${d}" && is_json "$HTTP_BODY" || return 1
  RD_JSON="$HTTP_BODY"
  jq_fields '((.events // []) | map(select(.eventAction == "registration")) | .[0].eventDate),((.events // []) | map(select(.eventAction == "expiration")) | .[0].eventDate),((.events // []) | map(select(.eventAction == "last changed")) | .[0].eventDate),([.. | objects | select(has("roles")) | select(.roles | index("registrar")) | .vcardArray[1][]? | select(.[0] == "fn") | .[3]] | .[0]),((.nameservers // []) | map(.ldhName // empty | ascii_downcase) | join(", ")),((.status // []) | join(", ")),([.. | objects | select(has("roles")) | select(.roles | index("abuse")) | .vcardArray[1][]? | select(.[0] == "email") | .[3]] | unique | join(", ")),(.secureDNS.delegationSigned | if . == null then "" else tostring end)' "$RD_JSON"
  RD_CREATED="${JF[0]:-}"; RD_EXPIRES="${JF[1]:-}"; RD_UPDATED="${JF[2]:-}"
  RD_REGISTRAR="${JF[3]:-}"; RD_NS="${JF[4]:-}"; RD_STATUS="${JF[5]:-}"
  RD_ABUSE="${JF[6]:-}"; RD_DNSSEC="${JF[7]:-}"
  return 0
}

mod_whois() {
  local t="${1:-}" d days
  [[ -z $t ]] && { err "Masukkan domain atau IP"; return 1; }
  if is_ipv4 "$t" || is_ipv6 "$t"; then _ip_rdap "$t"; return; fi
  d="$(apex_domain "$(host_of "$t")")"
  is_domain "$d" || { err "Domain tidak valid: $t"; return 1; }
  section "WHOIS / RDAP » $d"
  if rdap_domain_load "$d"; then
    kv "Domain" "$d"
    kv "Registrar" "$RD_REGISTRAR"
    kv "Dibuat" "$(date_fmt "$RD_CREATED")"
    kv "Diperbarui" "$(date_fmt "$RD_UPDATED")"
    kv "Kedaluwarsa" "$(date_fmt "$RD_EXPIRES")"
    kv "Status" "$RD_STATUS"
    kv "Nameserver" "$RD_NS"
    [[ -n $RD_DNSSEC ]] && kv "DNSSEC" "$([[ $RD_DNSSEC == true ]] && echo aktif || echo tidak aktif)"
    kv "Kontak abuse" "$RD_ABUSE"
    if [[ -n $RD_CREATED ]] && days="$(age_days "$RD_CREATED")" && [[ -n $days ]] && (( days < 90 )); then
      warn "Domain sangat baru (${days} hari) — waspadai bila dipakai untuk penawaran/phishing."
    fi
  elif have whois; then
    warn "RDAP tidak tersedia untuk TLD ini — memakai whois"
    whois "$d" 2>/dev/null | grep -Ei '^(domain name|registrar|creation date|created|updated date|registry expiry|expir|name server|status|registrant (organization|country))' | sort -u | head -n 30
  else
    warn "RDAP gagal dan perintah 'whois' belum terpasang (pkg install whois)"
    return 1
  fi
}
