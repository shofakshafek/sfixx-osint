#!/usr/bin/env bash
# modules/headers.sh — HTTP header, keamanan header, teknologi, berkas publik

_hdr_val() { grep -i -m1 "^$1:" <<<"$2" | cut -d: -f2- | sed 's/^[[:space:]]*//'; }

# detect_tech "<header final>" <file body>
detect_tech() {
  local h="${1,,}" b="$2" t=() body gen
  [[ $h == *"server: cloudflare"* || $h == *"cf-ray:"* ]]      && t+=("Cloudflare")
  [[ $h == *"x-vercel-id:"* ]]                                  && t+=("Vercel")
  [[ $h == *"x-nf-request-id:"* ]]                              && t+=("Netlify")
  [[ $h == *"x-amz-cf-id:"* ]]                                  && t+=("AWS CloudFront")
  [[ $h == *"server: nginx"* ]]                                 && t+=("Nginx")
  [[ $h == *"server: apache"* ]]                                && t+=("Apache")
  [[ $h == *"server: litespeed"* ]]                             && t+=("LiteSpeed")
  [[ $h == *"x-powered-by: php"* ]]                             && t+=("PHP")
  [[ $h == *"x-powered-by: express"* ]]                         && t+=("Express (Node.js)")
  [[ $h == *"x-aspnet-version"* || $h == *"x-powered-by: asp.net"* ]] && t+=("ASP.NET")
  [[ $h == *"laravel_session"* ]]                               && t+=("Laravel")
  [[ $h == *"x-drupal"* ]]                                      && t+=("Drupal")
  if [[ -s $b ]]; then
    body="$(head -c 250000 "$b" | tr -d '\0' | tr 'A-Z' 'a-z')"
    [[ $body == *"wp-content"* || $body == *"wp-includes"* ]]   && t+=("WordPress")
    [[ $body == *"/media/jui/"* || $body == *"joomla!"* ]]      && t+=("Joomla")
    [[ $body == *"drupal.settings"* || $body == *"sites/default/files"* ]] && t+=("Drupal")
    [[ $body == *"cdn.shopify.com"* ]]                          && t+=("Shopify")
    [[ $body == *"wixstatic.com"* ]]                            && t+=("Wix")
    [[ $body == *"squarespace.com"* ]]                          && t+=("Squarespace")
    [[ $body == *"/_next/"* ]]                                  && t+=("Next.js")
    [[ $body == *"/_nuxt/"* ]]                                  && t+=("Nuxt")
    [[ $body == *"___gatsby"* ]]                                && t+=("Gatsby")
    [[ $body == *"data-reactroot"* || $body == *"react-dom"* ]] && t+=("React")
    [[ $body == *"ng-version"* ]]                               && t+=("Angular")
    [[ $body == *"vue.js"* || $body == *"vue.min.js"* || $body == *"data-v-"* ]] && t+=("Vue.js")
    [[ $body == *"jquery"* ]]                                   && t+=("jQuery")
    [[ $body == *"bootstrap"* ]]                                && t+=("Bootstrap")
    [[ $body == *"tailwind"* ]]                                 && t+=("Tailwind CSS")
    [[ $body == *"google-analytics.com"* || $body == *"gtag/js"* ]] && t+=("Google Analytics")
    [[ $body == *"googletagmanager.com"* ]]                     && t+=("Google Tag Manager")
    [[ $body == *"connect.facebook.net"* ]]                     && t+=("Facebook Pixel")
    [[ $body == *"hotjar"* ]]                                   && t+=("Hotjar")
    [[ $body == *"google.com/recaptcha"* ]]                     && t+=("reCAPTCHA")
    gen="$(html_meta generator < "$b")"
    [[ -n $gen ]] && t+=("generator: $gen")
  fi
  (( ${#t[@]} )) || return 0
  printf '%s\n' "${t[@]}" | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g'
}

mod_headers() {
  local url="${1:-}" hdr="$SFIXX_TMP/h.$$" body="$SFIXX_TMP/b.$$" meta code eff ip redirs t size final v title
  [[ -z $url ]] && { err "Masukkan URL / domain"; return 1; }
  is_url "$url" || url="https://$url"
  section "HTTP Headers » $url"
  meta="$(curl -sL --connect-timeout 10 --max-time "${TIMEOUT:-20}" --max-redirs 10 -A "${UA:-$UA_DEFAULT}" \
      -D "$hdr" -o "$body" \
      -w '%{http_code}|%{url_effective}|%{remote_ip}|%{num_redirects}|%{time_total}|%{size_download}' "$url" 2>/dev/null)"
  IFS='|' read -r code eff ip redirs t size <<<"$meta"
  if [[ -z $code || $code == 000 ]]; then err "Tidak bisa terhubung ke $url"; return 1; fi
  final="$(tr -d '\r' < "$hdr" | awk '/^HTTP\//{blk=""} {blk=blk $0 "\n"} END{printf "%s", blk}')"

  kv "Status HTTP" "$code"
  kv "URL akhir" "$eff"
  kv "IP server" "$ip"
  kv "Jumlah redirect" "${redirs:-0}"
  kv "Waktu respons" "${t}s"
  kv "Ukuran body" "${size} byte"
  if (( ${redirs:-0} > 0 )); then
    kvl "Rantai redirect" "$(tr -d '\r' < "$hdr" | awk 'tolower($1)=="location:"{print "→ " $2}')"
  fi
  title="$(tr -d '\0\r' < "$body" 2>/dev/null | tr '\n' ' ' | grep -oi '<title[^>]*>[^<]*' | head -n1 | sed 's/<title[^>]*>//I')"
  kv "Judul halaman" "$title"

  local -a hk=(server x-powered-by x-generator via content-type last-modified)
  local -a hn=("Server" "X-Powered-By" "X-Generator" "Via" "Content-Type" "Last-Modified")
  for i in "${!hk[@]}"; do
    v="$(_hdr_val "${hk[i]}" "$final")"; kv "${hn[i]}" "$v"
  done
  v="$(grep -ci '^set-cookie:' <<<"$final")"
  if (( v > 0 )); then
    kv "Cookie" "$v cookie dikirim"
    grep -i '^set-cookie:' <<<"$final" | grep -qiv 'httponly' && kv "  ↳ catatan" "ada cookie tanpa HttpOnly"
    grep -i '^set-cookie:' <<<"$final" | grep -qiv 'secure'   && kv "  ↳ catatan" "ada cookie tanpa Secure"
  fi
  kv "Teknologi" "$(detect_tech "$final" "$body")"

  section "Header Keamanan"
  local -a keys=(strict-transport-security content-security-policy x-frame-options x-content-type-options referrer-policy permissions-policy cross-origin-opener-policy)
  local -a names=("HSTS" "CSP" "X-Frame-Options" "X-Content-Type" "Referrer-Policy" "Permissions-Policy" "COOP")
  local i score=0
  for i in "${!keys[@]}"; do
    v="$(_hdr_val "${keys[i]}" "$final")"
    if [[ -n $v ]]; then score=$((score+1)); kv "${names[i]}" "${C_GREEN}✔${C_RESET} ${v:0:70}"
    else kv "${names[i]}" "${C_RED}✘ tidak ada${C_RESET}"; fi
  done
  kv "Skor" "${score} / ${#keys[@]}"
  return 0
}

web_files() {
  local base="${1%/}" f
  section "Berkas Publik » $base"
  for f in robots.txt sitemap.xml .well-known/security.txt; do
    if fetch "${base}/${f}" && [[ $HTTP_BODY != *"<html"* && $HTTP_BODY != *"<!DOCTYPE"* && $HTTP_BODY != *"<!doctype"* ]]; then
      kv "/$f" "ada (${#HTTP_BODY} karakter)"
      case $f in
        robots.txt)  kvl "  Disallow"   "$(grep -i '^disallow:' <<<"$HTTP_BODY" | head -n 12 | sed 's/^[Dd]isallow: *//')" ;;
        sitemap.xml) kvl "  URL contoh" "$(grep -o '<loc>[^<]*' <<<"$HTTP_BODY" | sed 's/<loc>//' | head -n 6)" ;;
        *)           kvl "  Isi"        "$(head -n 6 <<<"$HTTP_BODY")" ;;
      esac
    else
      kv "/$f" "tidak ada"
    fi
  done
  return 0
}
