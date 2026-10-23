#!/usr/bin/env bash
# modules/ip.sh — IP OSINT (geolokasi, ASN, RDAP, eksposur, reputasi)

DNSBL_LIST=(bl.spamcop.net psbl.surriel.com dnsbl.dronebl.org all.s5h.net ix.dnsbl.manitu.net dnsbl-1.uceprotect.net)

_is_private_ip() {
  local ip="${1,,}"
  local re='^(10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)'
  [[ $ip =~ $re ]] && return 0
  [[ $ip == ::1 || $ip == fc* || $ip == fd* || $ip == fe80:* ]] && return 0
  return 1
}

_ip_geo() {
  local ip="$1" lat="" lon="" ptr
  local fields="status,message,continent,country,countryCode,regionName,city,district,zip,lat,lon,timezone,currency,isp,org,as,asname,reverse,mobile,proxy,hosting"
  section "Geolokasi & Jaringan"
  if fetch "http://ip-api.com/json/${ip}?fields=${fields}" && [[ "$(jq -r '.status' <<<"$HTTP_BODY" 2>/dev/null)" == success ]]; then
    jq_fields '.country,.countryCode,.regionName,.city,.district,.zip,.lat,.lon,.timezone,.currency,.isp,.org,.["as"],.asname,.reverse,.mobile,.proxy,.hosting,.continent' "$HTTP_BODY"
    kv "Benua" "${JF[18]:-}"
    [[ -n ${JF[0]:-} ]] && kv "Negara" "${JF[0]} (${JF[1]:-?})"
    kv "Provinsi / Region" "${JF[2]:-}"
    kv "Kota" "${JF[3]:-}"
    kv "Distrik" "${JF[4]:-}"
    kv "Kode pos" "${JF[5]:-}"
    kv "Zona waktu" "${JF[8]:-}"
    kv "Mata uang" "${JF[9]:-}"
    kv "ISP" "${JF[10]:-}"
    kv "Organisasi" "${JF[11]:-}"
    kv "ASN" "${JF[12]:-}"
    kv "AS name" "${JF[13]:-}"
    kv "Reverse DNS" "${JF[14]:-}"
    kv "Jaringan seluler" "$(tf "${JF[15]:-}")"
    kv "Proxy / VPN" "$(tf "${JF[16]:-}")"
    kv "Hosting / DC" "$(tf "${JF[17]:-}")"
    lat="${JF[6]:-}"; lon="${JF[7]:-}"
  elif fetch "https://ipwho.is/${ip}" && [[ "$(jq -r '.success' <<<"$HTTP_BODY" 2>/dev/null)" == true ]]; then
    jq_fields '.country,.country_code,.region,.city,.postal,.latitude,.longitude,.timezone.id,.currency.code,.connection.isp,.connection.org,.connection.asn,.connection.domain,.continent' "$HTTP_BODY"
    kv "Benua" "${JF[13]:-}"
    [[ -n ${JF[0]:-} ]] && kv "Negara" "${JF[0]} (${JF[1]:-?})"
    kv "Provinsi / Region" "${JF[2]:-}"
    kv "Kota" "${JF[3]:-}"
    kv "Kode pos" "${JF[4]:-}"
    kv "Zona waktu" "${JF[7]:-}"
    kv "Mata uang" "${JF[8]:-}"
    kv "ISP" "${JF[9]:-}"
    kv "Organisasi" "${JF[10]:-}"
    [[ -n ${JF[11]:-} ]] && kv "ASN" "AS${JF[11]}"
    kv "Domain" "${JF[12]:-}"
    lat="${JF[5]:-}"; lon="${JF[6]:-}"
    info "(sumber cadangan: ipwho.is)"
  else
    warn "Layanan geolokasi tidak merespons (cek koneksi internet)"
  fi

  if is_ipv4 "$ip"; then
    ptr="$(dns_query "$(awk -F. '{print $4"."$3"."$2"."$1}' <<<"$ip").in-addr.arpa" PTR | head -n1)"
    kv "PTR (DNS balik)" "${ptr%.}"
  fi

  local u="https://ipinfo.io/${ip}/json"
  [[ -n ${IPINFO_TOKEN:-} ]] && u+="?token=${IPINFO_TOKEN}"
  if fetch "$u" && is_json "$HTTP_BODY"; then
    jq_fields '.hostname,.city,.region,.country,.org,.timezone' "$HTTP_BODY"
    [[ -n ${JF[4]:-} ]] && kv "ipinfo.io (silang)" "${JF[4]} — ${JF[1]:-}, ${JF[2]:-}, ${JF[3]:-}"
    kv "Hostname (ipinfo)" "${JF[0]:-}"
  fi

  if [[ -n $lat && -n $lon ]]; then
    kv "Koordinat" "${lat}, ${lon}  (akurasi kota/ISP, bukan alamat rumah)"
    kv "Google Maps" "https://www.google.com/maps?q=${lat},${lon}"
    kv "OpenStreetMap" "https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=11/${lat}/${lon}"
  fi
}

_ip_rdap() {
  local ip="$1" json org abuse
  section "Registrasi Jaringan (RDAP) » $ip"
  if   fetch "https://rdap.org/ip/${ip}" && is_json "$HTTP_BODY"; then :
  elif fetch "https://rdap.arin.net/registry/ip/${ip}" && is_json "$HTTP_BODY"; then :
  else warn "RDAP tidak tersedia untuk IP ini"; return 1; fi
  json="$HTTP_BODY"
  jq_fields '.name,.handle,.type,.country,.startAddress,.endAddress,((.cidr0_cidrs // []) | map("\(.v4prefix // .v6prefix)/\(.length)") | join(", ")),((.events // []) | map(select(.eventAction == "registration")) | .[0].eventDate),((.events // []) | map(select(.eventAction == "last changed")) | .[0].eventDate)' "$json"
  kv "Nama jaringan" "${JF[0]:-}"
  kv "Handle" "${JF[1]:-}"
  kv "Tipe alokasi" "${JF[2]:-}"
  kv "Negara" "${JF[3]:-}"
  [[ -n ${JF[4]:-} ]] && kv "Rentang IP" "${JF[4]} – ${JF[5]:-}"
  kv "CIDR" "${JF[6]:-}"
  kv "Terdaftar" "$(date_fmt "${JF[7]:-}")"
  kv "Terakhir diubah" "$(date_fmt "${JF[8]:-}")"
  org="$(jq -r '[.. | objects | select(has("roles")) | select(.roles | index("registrant")) | .vcardArray[1][]? | select(.[0] == "fn") | .[3]] | first // empty' <<<"$json" 2>/dev/null)"
  abuse="$(jq -r '[.. | objects | select(has("roles")) | select(.roles | index("abuse")) | .vcardArray[1][]? | select(.[0] == "email") | .[3]] | unique | join(", ")' <<<"$json" 2>/dev/null)"
  kv "Pemilik" "$org"
  kv "Kontak abuse" "$abuse"
}

_ip_exposure() {
  local ip="$1"
  section "Eksposur Publik (Shodan InternetDB)"
  if fetch "https://internetdb.shodan.io/${ip}" && is_json "$HTTP_BODY"; then
    jq_fields '((.ports // []) | join(", ")),((.hostnames // []) | join(", ")),((.tags // []) | join(", ")),((.cpes // []) | .[0:8] | join(", ")),((.vulns // []) | length),((.vulns // []) | .[0:15] | join(", "))' "$HTTP_BODY"
    kv "Port terbuka" "${JF[0]:-}"
    kv "Hostname" "${JF[1]:-}"
    kv "Tag" "${JF[2]:-}"
    kv "CPE" "${JF[3]:-}"
    if (( ${JF[4]:-0} > 0 )); then kv "CVE terindeks" "${C_RED}${JF[4]}${C_RESET} → ${JF[5]:-}"; fi
  else
    info "Tidak ada data pada InternetDB (IP belum terindeks)"
  fi
}

_ip_reputation() {
  local ip="$1" bl rev r checked=0 listed=()
  section "Reputasi"
  if fetch "https://check.torproject.org/torbulkexitlist"; then
    if grep -qxF "$ip" <<<"$HTTP_BODY"; then kv "Tor exit node" "$(tf true)"; else kv "Tor exit node" "$(tf false)"; fi
  fi
  if is_ipv4 "$ip"; then
    rev="$(awk -F. '{print $4"."$3"."$2"."$1}' <<<"$ip")"
    for bl in "${DNSBL_LIST[@]}"; do
      r="$(dns_query "${rev}.${bl}" A | head -n1)"
      checked=$((checked+1))
      if [[ $r == 127.* && $r != 127.255.255.* ]]; then listed+=("$bl"); fi
    done
    if (( ${#listed[@]} )); then kv "DNSBL" "${C_RED}TERDAFTAR${C_RESET} di: ${listed[*]}"
    else kv "DNSBL" "tidak ditemukan di ${checked} daftar hitam"; fi
  fi
  if [[ -n ${ABUSEIPDB_KEY:-} ]]; then
    if fetch "https://api.abuseipdb.com/api/v2/check?ipAddress=${ip}&maxAgeInDays=90" -H "Key: ${ABUSEIPDB_KEY}" -H "Accept: application/json"; then
      jq_fields '.data.abuseConfidenceScore,.data.totalReports,.data.numDistinctUsers,.data.lastReportedAt,.data.usageType' "$HTTP_BODY"
      kv "AbuseIPDB" "skor ${JF[0]:-?}% · ${JF[1]:-0} laporan / ${JF[2]:-0} pelapor (90 hari)"
      kv "Terakhir dilaporkan" "${JF[3]:-}"
      kv "Tipe penggunaan" "${JF[4]:-}"
    else warn "AbuseIPDB gagal (HTTP $HTTP_CODE)"; fi
  fi
  if [[ -n ${VIRUSTOTAL_KEY:-} ]]; then
    if fetch "https://www.virustotal.com/api/v3/ip_addresses/${ip}" -H "x-apikey: ${VIRUSTOTAL_KEY}"; then
      jq_fields '.data.attributes.last_analysis_stats.malicious,.data.attributes.last_analysis_stats.suspicious,.data.attributes.last_analysis_stats.harmless,.data.attributes.last_analysis_stats.undetected,.data.attributes.reputation' "$HTTP_BODY"
      kv "VirusTotal" "malicious ${JF[0]:-0} · suspicious ${JF[1]:-0} · harmless ${JF[2]:-0} · undetected ${JF[3]:-0}"
      kv "VT reputasi" "${JF[4]:-}"
    else warn "VirusTotal gagal (HTTP $HTTP_CODE)"; fi
  fi
  [[ -z ${ABUSEIPDB_KEY:-}${VIRUSTOTAL_KEY:-} ]] && info "Isi ABUSEIPDB_KEY / VIRUSTOTAL_KEY di config untuk reputasi tambahan (opsional)"
  return 0
}

_ip_reverse() {
  local ip="$1" n
  section "Domain pada IP yang sama (reverse IP)"
  if fetch "https://api.hackertarget.com/reverseiplookup/?q=${ip}"; then
    case $HTTP_BODY in
      "API count"*|error*|"No DNS"*) info "Tidak ada hasil / kuota publik habis" ;;
      *)
        kvl "Domain" "$(head -n 25 <<<"$HTTP_BODY")"
        n="$(wc -l <<<"$HTTP_BODY")"
        (( n > 25 )) && info "…dan $(( n - 25 )) domain lainnya"
        ;;
    esac
  else
    info "Layanan reverse-IP tidak merespons"
  fi
}

mod_ip() {
  local input="${1:-}" ip h
  if [[ -z $input ]]; then
    info "Tanpa target → memakai IP publik kamu"
    fetch "https://api.ipify.org" || { err "Gagal mengambil IP publik (cek koneksi)"; return 1; }
    ip="$HTTP_BODY"
  elif is_ipv4 "$input" || is_ipv6 "$input"; then
    ip="$input"
  else
    h="$(host_of "$input")"
    is_domain "$h" || { err "Bukan IP / domain yang valid: $input"; return 1; }
    ip="$(dns_query "$h" A | head -n1)"
    [[ -z $ip ]] && ip="$(dns_query "$h" AAAA | head -n1)"
    [[ -z $ip ]] && { err "Domain tidak bisa di-resolve: $h"; return 1; }
    info "Resolve: $h → $ip"
  fi

  section "IP OSINT » $ip"
  if _is_private_ip "$ip"; then
    warn "Alamat privat/lokal — tidak ada data publik untuk ditelusuri."
    return 0
  fi
  _ip_geo "$ip"
  _ip_rdap "$ip"
  _ip_exposure "$ip"
  _ip_reputation "$ip"
  _ip_reverse "$ip"
}
