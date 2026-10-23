#!/usr/bin/env bash
# modules/domain.sh — ringkasan lengkap domain/website (orkestrasi modul lain)

mod_domain() {
  local input="${1:-}" d apex ip
  [[ -z $input ]] && { err "Masukkan domain / URL"; return 1; }
  d="$(host_of "$input")"
  is_domain "$d" || { err "Domain tidak valid: $input"; return 1; }
  apex="$(apex_domain "$d")"
  section "DOMAIN OSINT » $d"

  mod_whois "$apex"
  mod_dns "$d"

  ip="$(dns_query "$d" A | head -n1)"
  if [[ -n $ip ]]; then
    section "Hosting » $ip"
    if fetch "http://ip-api.com/json/${ip}?fields=status,country,regionName,city,isp,org,as,hosting" \
       && [[ "$(jq -r '.status' <<<"$HTTP_BODY" 2>/dev/null)" == success ]]; then
      jq_fields '.country,.regionName,.city,.isp,.org,.["as"],.hosting' "$HTTP_BODY"
      kv "Lokasi server" "${JF[2]:-}, ${JF[1]:-}, ${JF[0]:-}"
      kv "ISP" "${JF[3]:-}"
      kv "Organisasi" "${JF[4]:-}"
      kv "ASN" "${JF[5]:-}"
      kv "Hosting / DC" "$(tf "${JF[6]:-}")"
    fi
  fi

  mod_headers "$d"
  web_files "https://$d"
  mod_ssl "$d"
  mod_subdomain "$apex"
  mod_wayback "$apex"
  return 0
}
