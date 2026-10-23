#!/usr/bin/env bash
# modules/ssl.sh — informasi sertifikat SSL/TLS

mod_ssl() {
  need_cmd openssl || return 1
  local in="${1:-}" h port=443 out pem subj iss nb na fp san proto cipher e days
  [[ -z $in ]] && { err "Masukkan host (mis. example.com atau example.com:8443)"; return 1; }
  h="$(host_of "$in")"
  [[ $in == *:* && $in != *://* ]] && port="${in##*:}"
  [[ $in == *://*:* ]] && { local hp="${in#*://}"; hp="${hp%%/*}"; [[ $hp == *:* ]] && port="${hp##*:}"; }
  section "SSL/TLS » ${h}:${port}"
  out="$(echo | timeout 15 openssl s_client -connect "${h}:${port}" -servername "$h" 2>&1)"
  pem="$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' <<<"$out")"
  [[ -z $pem ]] && { err "Tidak bisa mengambil sertifikat dari ${h}:${port}"; return 1; }

  subj="$(openssl x509 -noout -subject -nameopt RFC2253 <<<"$pem" 2>/dev/null | sed 's/^subject=//')"
  iss="$(openssl x509 -noout -issuer  -nameopt RFC2253 <<<"$pem" 2>/dev/null | sed 's/^issuer=//')"
  nb="$(openssl x509 -noout -startdate <<<"$pem" 2>/dev/null | cut -d= -f2)"
  na="$(openssl x509 -noout -enddate   <<<"$pem" 2>/dev/null | cut -d= -f2)"
  fp="$(openssl x509 -noout -fingerprint -sha256 <<<"$pem" 2>/dev/null | cut -d= -f2)"
  san="$(openssl x509 -noout -ext subjectAltName <<<"$pem" 2>/dev/null | tail -n +2 | tr ',' '\n' | sed -e 's/^ *DNS://' -e 's/^ *IP Address://' -e 's/^ *//' | head -n 25)"
  proto="$(grep -m1 -E '^ *Protocol *:' <<<"$out" | sed 's/.*: *//')"
  [[ -z $proto ]] && proto="$(grep -m1 -oE 'TLSv[0-9.]+' <<<"$out")"
  cipher="$(grep -m1 -E '^ *Cipher *: *[A-Za-z]' <<<"$out" | sed 's/.*: *//')"
  [[ -z $cipher ]] && cipher="$(grep -m1 -oE 'Cipher is [A-Za-z0-9_-]+' <<<"$out" | sed 's/Cipher is //')"

  kv "Subjek" "$subj"
  kv "Penerbit (CA)" "$iss"
  kv "Berlaku dari" "$nb"
  kv "Berlaku sampai" "$na"
  e="$(date -d "$na" +%s 2>/dev/null)"
  if [[ -n $e ]]; then
    days=$(( (e - $(date +%s)) / 86400 ))
    if   (( days < 0 ));  then kv "Status" "${C_RED}KEDALUWARSA ${days#-} hari lalu${C_RESET}"
    elif (( days < 15 )); then kv "Status" "${C_YELLOW}segera kedaluwarsa (${days} hari)${C_RESET}"
    else                       kv "Status" "${C_GREEN}valid, sisa ${days} hari${C_RESET}"; fi
  fi
  kv "Protokol" "$proto"
  kv "Cipher" "$cipher"
  kv "SHA-256" "$fp"
  kvl "SAN (nama lain)" "$san"
  return 0
}
