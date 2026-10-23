#!/usr/bin/env bash
# lib/utils.sh — fungsi bantu umum (HTTP, JSON, DNS, validasi, dork)

SFIXX_VERSION="1.0.0"
UA_DEFAULT="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

have() { command -v "$1" >/dev/null 2>&1; }

need_cmd() {
  local c missing=()
  for c in "$@"; do have "$c" || missing+=("$c"); done
  (( ${#missing[@]} == 0 )) && return 0
  err "Dependensi belum terpasang: ${missing[*]}"
  info "Termux : pkg install ${missing[*]}"
  info "Debian : sudo apt install ${missing[*]}"
  return 1
}

# ── string ────────────────────────────────────────────────────
lower()     { printf '%s' "${1,,}"; }
trim()      { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
safe_name() { local s="${1//[^A-Za-z0-9._@+-]/_}"; printf '%s' "${s:0:60}"; }
md5_of()    { printf '%s' "$1" | md5sum | cut -d' ' -f1; }
sha256_of() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
host_of()   { local h="$1"; h="${h#*://}"; h="${h%%[/?#]*}"; h="${h##*@}"; h="${h%%:*}"; printf '%s' "${h,,}"; }

urlenc() {
  local LC_ALL=C s="$1" i c out=""
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case $c in
      [A-Za-z0-9.~_-]) out+="$c" ;;
      *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

html_unescape() {
  sed -e 's/&amp;/\&/g' -e 's/&quot;/"/g' -e "s/&#39;/'/g" -e "s/&#x27;/'/g" -e 's/&lt;/</g' -e 's/&gt;/>/g'
}
# html_meta <property|name>  (baca HTML dari stdin)
html_meta() {
  grep -oiE "<meta[^>]+(property|name)=[\"']$1[\"'][^>]*>" | head -n1 \
    | sed -E "s/.*content=[\"']([^\"']*)[\"'].*/\1/" | html_unescape
}

# ── HTTP ──────────────────────────────────────────────────────
# fetch URL [opsi curl…] → set HTTP_CODE & HTTP_BODY; status 0 bila 2xx
fetch() {
  local url="$1"; shift
  local tmp; tmp="$(mktemp "${SFIXX_TMP:-/tmp}/f.XXXXXX")"
  HTTP_CODE="$(curl -sL --connect-timeout 10 --max-time "${TIMEOUT:-20}" \
      -A "${UA:-$UA_DEFAULT}" "$@" -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null)"
  [[ -z $HTTP_CODE ]] && HTTP_CODE=000
  HTTP_BODY="$(tr -d '\0' <"$tmp")"
  rm -f "$tmp"
  [[ $HTTP_CODE == 2* ]]
}

# ── JSON (jq) ─────────────────────────────────────────────────
is_json() { [[ -n $1 ]] && jq empty >/dev/null 2>&1 <<<"$1"; }

# jq_fields '<ekspresi, ekspresi…>' "$json" → array global JF (null → kosong)
jq_fields() {
  local expr="$1" json="$2" out
  local prog='map(if . == null then "" else (tostring | gsub("\n";" ") | gsub("\r";" ") | gsub("\t";" ")) end) | join("\u001f")'
  JF=()
  out="$(jq -r "[${expr}] | ${prog}" <<<"$json" 2>/dev/null)" || return 1
  IFS=$'\x1f' read -r -a JF <<<"$out"
}

# ── DNS over HTTPS (tanpa dig) ────────────────────────────────
dns_type_code() {
  case "${1^^}" in
    A) echo 1;; NS) echo 2;; CNAME) echo 5;; SOA) echo 6;; PTR) echo 12;;
    MX) echo 15;; TXT) echo 16;; AAAA) echo 28;; SRV) echo 33;; CAA) echo 257;;
    *) echo 0;;
  esac
}

# dns_query <nama> [TIPE] → data per baris
dns_query() {
  local name="$1" type="${2:-A}" code body
  code="$(dns_type_code "$type")"
  body="$(curl -s --max-time 10 -H 'accept: application/dns-json' \
      "https://dns.google/resolve?name=$(urlenc "$name")&type=${type}" 2>/dev/null)"
  [[ -z $body ]] && body="$(curl -s --max-time 10 -H 'accept: application/dns-json' \
      "https://cloudflare-dns.com/dns-query?name=$(urlenc "$name")&type=${type}" 2>/dev/null)"
  if [[ -n $body ]]; then
    jq -r --argjson t "$code" '.Answer[]? | select(.type == $t) | .data' <<<"$body" 2>/dev/null \
      | sed -e 's/^"//' -e 's/"$//' -e 's/" "//g'
  elif have dig; then
    dig +short +time=5 "$name" "$type" 2>/dev/null | sed -e 's/^"//' -e 's/"$//' -e 's/" "//g'
  fi
}

# apex_domain sub.example.co.id → example.co.id
apex_domain() {
  local d="$1" IFS=.
  local -a p=($d)
  local n=${#p[@]}
  (( n <= 2 )) && { printf '%s' "$d"; return; }
  local last2="${p[n-2]}.${p[n-1]}"
  case " co.id or.id go.id ac.id sch.id web.id my.id biz.id net.id mil.id desa.id co.uk org.uk ac.uk gov.uk com.au net.au org.au edu.au gov.au co.jp or.jp co.nz com.br com.sg com.my com.cn com.hk com.tw co.in co.kr com.tr co.za com.ph com.vn com.mx com.ar com.co " in
    *" $last2 "*) printf '%s.%s' "${p[n-3]}" "$last2" ;;
    *)            printf '%s' "$last2" ;;
  esac
}

# ── validasi & deteksi tipe target ───────────────────────────
is_ipv4() {
  local re='^([0-9]{1,3}\.){3}[0-9]{1,3}$' o
  [[ $1 =~ $re ]] || return 1
  local IFS=.
  for o in $1; do (( 10#$o <= 255 )) || return 1; done
}
is_ipv6() {
  [[ $1 == *:*:* && $1 =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
  [[ $1 == *::* ]] && return 0
  local IFS=:; local -a g=($1)
  (( ${#g[@]} == 8 ))
}
is_email()  { local re='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; [[ $1 =~ $re ]]; }
is_domain() { local re='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$'; [[ $1 =~ $re ]]; }
is_url()    { [[ $1 =~ ^https?:// ]]; }
is_mac() {
  local a='^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$' b='^[0-9A-Fa-f]{12}$' c='^([0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}$'
  [[ $1 =~ $a || $1 =~ $c ]] && return 0
  [[ $1 =~ $b && $1 =~ [A-Fa-f] ]]
}
is_phone() {
  local re='^\+?[0-9][0-9 ()./-]{6,22}$' d="${1//[^0-9]/}"
  [[ $1 =~ $re ]] && (( ${#d} >= 8 && ${#d} <= 15 ))
}
is_btc()    { local re='^(bc1[a-z0-9]{25,62}|[13][a-km-zA-HJ-NP-Z1-9]{25,34})$'; [[ $1 =~ $re ]]; }
is_eth()    { local re='^0x[0-9a-fA-F]{40}$'; [[ $1 =~ $re ]]; }
is_coord()  { local re='^-?[0-9]{1,3}(\.[0-9]+)?, ?-?[0-9]{1,3}(\.[0-9]+)?$'; [[ $1 =~ $re ]]; }

detect_type() {
  local t="$1"
  if   [[ -f $t ]];                          then echo file
  elif is_email "$t";                        then echo email
  elif is_ipv4 "$t" || is_ipv6 "$t";         then echo ip
  elif [[ $t == *chat.whatsapp.com/* ]];     then echo wa
  elif is_url "$t";                          then echo url
  elif is_mac "$t";                          then echo mac
  elif is_coord "$t";                        then echo geo
  elif is_eth "$t";                          then echo eth
  elif is_btc "$t";                          then echo btc
  elif is_phone "$t";                        then echo phone
  elif is_domain "$t";                       then echo domain
  elif [[ $t == *" "* ]];                    then echo person
  else                                            echo username
  fi
}

# ── tanggal ───────────────────────────────────────────────────
date_rel() {   # ISO8601 → "N tahun M bulan lalu" / "dalam N hari"
  local e now d y m
  e="$(date -d "$1" +%s 2>/dev/null)" || return 1
  [[ -z $e ]] && return 1
  now="$(date +%s)"; d=$(( (now - e) / 86400 ))
  if   (( d < 0 ));  then printf 'dalam %d hari' $(( -d ))
  elif (( d < 60 )); then printf '%d hari lalu' "$d"
  else
    y=$(( d / 365 )); m=$(( (d % 365) / 30 ))
    if (( y > 0 )); then printf '%d tahun %d bulan lalu' "$y" "$m"; else printf '%d bulan lalu' "$m"; fi
  fi
}
date_fmt() {   # 2020-01-01T00:00:00Z → "2020-01-01  (6 tahun 9 bulan lalu)"
  [[ -z ${1:-} ]] && return 0
  local r; r="$(date_rel "$1")"
  printf '%s%s' "${1%%T*}" "${r:+  ($r)}"
}

# ── UI / proses ───────────────────────────────────────────────
progress()       { [[ ${SFIXX_TTY:-0} == 1 ]] && { printf '\r%s' "$1" >/dev/tty; } 2>/dev/null; return 0; }
progress_clear() { [[ ${SFIXX_TTY:-0} == 1 ]] && { printf '\r\033[K' >/dev/tty; } 2>/dev/null; return 0; }
throttle()       { while (( $(jobs -rp | wc -l) >= ${1:-10} )); do sleep 0.1; done; }
ask()            { local __v; read -rp "$1" __v; printf -v "$2" '%s' "$__v"; }

open_url() {
  if   have termux-open-url; then termux-open-url "$1" >/dev/null 2>&1
  elif have xdg-open;        then xdg-open "$1" >/dev/null 2>&1 &
  fi
  return 0
}

# ── dork helper ───────────────────────────────────────────────
gsearch_url() { printf 'https://www.google.com/search?q=%s' "$(urlenc "$1")"; }
dork_line() {   # dork_line "Label" "query"
  local u; u="$(gsearch_url "$2")"
  kv "$1" "$u"
  (( ${OPEN_BROWSER:-0} )) && open_url "$u"
  return 0
}
