#!/usr/bin/env bash
# modules/dns.sh — DNS lookup & keamanan email (SPF/DMARC/DKIM)

dns_mailsec() {
  local d="$1" spf dmarc sel found tmp="$SFIXX_TMP/dkim.$$"
  section "Keamanan Email (SPF / DMARC / DKIM) » $d"
  spf="$(dns_query "$d" TXT | grep -i '^v=spf1' | head -n1)"
  dmarc="$(dns_query "_dmarc.${d}" TXT | grep -i '^v=DMARC1' | head -n1)"
  kv "SPF" "${spf:-${C_YELLOW}tidak ada${C_RESET}}"
  kv "DMARC" "${dmarc:-${C_YELLOW}tidak ada${C_RESET}}"
  if   [[ -z $dmarc ]];            then kv "Risiko spoofing" "${C_RED}tinggi${C_RESET} — tidak ada DMARC"
  elif [[ $dmarc == *"p=none"* ]]; then kv "Risiko spoofing" "${C_YELLOW}sedang${C_RESET} — DMARC p=none (hanya monitor)"
  else                                  kv "Risiko spoofing" "${C_GREEN}rendah${C_RESET} — DMARC ditegakkan"; fi
  : > "$tmp"
  for sel in default google selector1 selector2 k1 s1 s2 mail dkim smtp mandrill; do
    throttle 8
    { [[ -n "$(dns_query "${sel}._domainkey.${d}" TXT | head -n1)" ]] && echo "$sel" >> "$tmp"; } &
  done
  wait
  found="$(sort "$tmp" | paste -sd' ' -)"
  kv "DKIM selector" "${found:-tidak terdeteksi (hanya selector umum yang dicek)}"
}

mod_dns() {
  local d types t base="$SFIXX_TMP/dns.$$" found=0 r
  d="$(host_of "${1:-}")"
  is_domain "$d" || { err "Domain tidak valid: ${1:-<kosong>}"; return 1; }
  shift
  types="${*:-A AAAA CNAME NS MX TXT SOA CAA}"; types="${types//,/ }"
  section "DNS Records » $d"
  for t in ${types^^}; do
    throttle 8
    dns_query "$d" "$t" > "${base}.${t}" &
  done
  wait
  for t in ${types^^}; do
    r="$(cat "${base}.${t}" 2>/dev/null)"
    [[ -n $r ]] && { kvl "$t" "$r"; found=1; }
  done
  (( found )) || warn "Tidak ada record ditemukan (domain tidak ada / DoH tidak terjangkau)"
  r="$(dns_query "www.${d}" CNAME | head -n1)"
  kv "www CNAME" "${r%.}"
  [[ $types == *MX* || -z ${1:-} ]] && dns_mailsec "$d"
  return 0
}
