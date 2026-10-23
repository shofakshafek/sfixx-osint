#!/usr/bin/env bash
# modules/url.sh — URL analyzer, redirect chain, reverse image search

_SHORTENERS=" bit.ly tinyurl.com t.co goo.gl is.gd cutt.ly s.id rebrand.ly ow.ly shorturl.at bit.do tiny.cc lnkd.in buff.ly t.ly rb.gy shope.ee tokopedia.link tinyurl.id v.gd 1url.com "
_SUSP_TLDS=" zip mov top xyz tk ml ga cf gq click country work live support rest fit cam icu monster buzz "
_PHISH_WORDS="login signin verify verification secure account update confirm banking wallet password suspended unlock giveaway claim hadiah undian"

_strip_trackers() {   # URL → URL tanpa parameter pelacak (utm_*, fbclid, gclid, …)
  local u="${1%%#*}" base q clean
  [[ $u == *\?* ]] || { printf '%s' "$u"; return; }
  base="${u%%\?*}"; q="${u#*\?}"
  clean="$(tr '&' '\n' <<<"$q" | grep -viE '^(utm_[a-z]+|fbclid|gclid|igshid|mc_eid|mc_cid|ref_src|yclid|msclkid|_ga)=' | paste -sd'&' -)"
  printf '%s%s' "$base" "${clean:+?$clean}"
}

mod_url() {
  local u="${1:-}" scheme rest frag="" query="" hostport userinfo="" host port="" path
  local flags=() depth tld w lowu found_w="" clean hdr meta code eff ip redirs i fh apex days vtid
  local -a codes locs
  [[ -z $u ]] && { err "Masukkan URL"; return 1; }
  is_url "$u" || u="https://$u"

  scheme="${u%%://*}"; scheme="${scheme,,}"; rest="${u#*://}"
  [[ $rest == *"#"* ]] && { frag="${rest#*#}"; rest="${rest%%#*}"; }
  [[ $rest == *"?"* ]] && { query="${rest#*\?}"; rest="${rest%%\?*}"; }
  hostport="${rest%%/*}"
  if [[ $rest == */* ]]; then path="/${rest#*/}"; else path="/"; fi
  [[ $hostport == *@* ]] && { userinfo="${hostport%@*}"; hostport="${hostport##*@}"; }
  host="${hostport%%:*}"; host="${host,,}"
  [[ $hostport == *:* ]] && port="${hostport##*:}"

  section "URL ANALYZER » $u"
  kv "Skema" "$scheme"
  kv "Userinfo" "$userinfo"
  kv "Host" "$host"
  kv "Port" "$port"
  kv "Path" "$path"
  kv "Fragment" "$frag"
  if [[ -n $query ]]; then
    kvl "Parameter" "$(tr '&' '\n' <<<"$query" | head -n 20)"
    clean="$(_strip_trackers "$u")"
    [[ $clean != "${u%%#*}" ]] && kv "URL bersih" "$clean"
  fi

  # ── heuristik risiko ──
  tld="${host##*.}"; lowu="${u,,}"
  depth="$(tr -cd '.' <<<"$host" | wc -c)"
  [[ $scheme == http ]]                    && flags+=("Tanpa HTTPS (http://) — data tidak terenkripsi")
  is_ipv4 "$host"                          && flags+=("Host berupa alamat IP, bukan nama domain")
  [[ -n $userinfo ]]                       && flags+=("Ada '@' pada URL — trik penyamaran host yang umum di phishing")
  [[ $host == *xn--* ]]                    && flags+=("Punycode (xn--) — kemungkinan homograph / domain meniru")
  (( depth >= 4 ))                         && flags+=("Subdomain bersarang dalam (${depth} titik)")
  [[ $_SUSP_TLDS == *" $tld "* ]]          && flags+=("TLD yang sering disalahgunakan (.${tld})")
  [[ $_SHORTENERS == *" $host "* ]]        && flags+=("Pemendek URL — tujuan asli disembunyikan")
  (( ${#u} > 120 ))                        && flags+=("URL sangat panjang (${#u} karakter)")
  for w in $_PHISH_WORDS; do [[ $lowu == *"$w"* ]] && found_w+="$w "; done
  [[ -n $found_w ]]                        && flags+=("Kata kunci umum phishing: ${found_w% }")

  # ── redirect chain ──
  section "Redirect Chain"
  hdr="$SFIXX_TMP/u.$$"
  meta="$(curl -sL --connect-timeout 10 --max-time "${TIMEOUT:-20}" --max-redirs 15 --max-filesize 3000000 \
      -A "${UA:-$UA_DEFAULT}" -o /dev/null -D "$hdr" \
      -w '%{http_code}|%{url_effective}|%{remote_ip}|%{num_redirects}' "$u" 2>/dev/null)"
  IFS='|' read -r code eff ip redirs <<<"$meta"
  if [[ -z $code || $code == 000 ]]; then
    warn "Tidak bisa membuka URL (timeout / diblokir / host tidak ada)"
    eff="$u"
  else
    mapfile -t codes < <(tr -d '\r' < "$hdr" | awk '/^HTTP\//{print $2}')
    mapfile -t locs  < <(tr -d '\r' < "$hdr" | awk 'tolower($1)=="location:"{print $2}')
    kv "Mulai" "$u"
    for (( i=0; i<${#locs[@]}; i++ )); do kv "Hop $((i+1)) [${codes[i]:-?}]" "→ ${locs[i]}"; done
    kv "Tujuan akhir" "${eff}  [HTTP ${code}]"
    kv "IP tujuan" "$ip"
    clean="$(_strip_trackers "$eff")"
    [[ $clean != "$eff" ]] && kv "Tujuan bersih" "$clean"
    (( ${redirs:-0} > 2 )) && flags+=("Banyak redirect (${redirs}) sebelum tujuan akhir")
    [[ $(host_of "$eff") != "$host" ]] && flags+=("Domain tujuan akhir berbeda dari domain awal: $(host_of "$eff")")
  fi

  # ── umur domain tujuan ──
  fh="$(host_of "$eff")"
  if is_domain "$fh"; then
    apex="$(apex_domain "$fh")"
    if rdap_domain_load "$apex"; then
      kv "Domain dibuat" "$(date_fmt "$RD_CREATED")"
      kv "Registrar" "$RD_REGISTRAR"
      if [[ -n $RD_CREATED ]] && days="$(age_days "$RD_CREATED")" && [[ -n $days ]] && (( days < 30 )); then
        flags+=("Domain tujuan sangat baru (${days} hari)")
      fi
    fi
  fi

  if [[ -n ${VIRUSTOTAL_KEY:-} ]]; then
    vtid="$(printf '%s' "$u" | base64 | tr -d '\n=' | tr '+/' '-_')"
    if fetch "https://www.virustotal.com/api/v3/urls/${vtid}" -H "x-apikey: ${VIRUSTOTAL_KEY}"; then
      jq_fields '.data.attributes.last_analysis_stats.malicious,.data.attributes.last_analysis_stats.suspicious,.data.attributes.last_analysis_stats.harmless,.data.attributes.last_analysis_stats.undetected' "$HTTP_BODY"
      kv "VirusTotal" "malicious ${JF[0]:-0} · suspicious ${JF[1]:-0} · harmless ${JF[2]:-0} · undetected ${JF[3]:-0}"
    else
      info "URL belum pernah dipindai di VirusTotal (HTTP $HTTP_CODE)"
    fi
  fi

  section "Indikator Risiko (heuristik)"
  if (( ${#flags[@]} )); then
    for w in "${flags[@]}"; do printf '  %s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$w"; done
  else
    kv "Hasil" "${C_GREEN}tidak ada indikator mencurigakan${C_RESET} (bukan jaminan aman)"
  fi
  return 0
}

mod_img() {
  local u="${1:-}" e
  is_url "$u" || { err "Masukkan URL gambar langsung (http/https)"; return 1; }
  e="$(urlenc "$u")"
  section "REVERSE IMAGE SEARCH"
  kv "Google Lens" "https://lens.google.com/uploadbyurl?url=${e}"
  kv "TinEye" "https://tineye.com/search?url=${e}"
  kv "Yandex" "https://yandex.com/images/search?rpt=imageview&url=${e}"
  kv "Bing" "https://www.bing.com/images/search?view=detailv2&iss=sbi&q=imgurl:${e}"
  if (( ${OPEN_BROWSER:-0} )); then
    open_url "https://lens.google.com/uploadbyurl?url=${e}"
  fi
  info "Cocok untuk verifikasi asal gambar (hoaks, foto profil palsu, sumber asli)."
}
