#!/usr/bin/env bash
# modules/sysinfo.sh — info perangkat, jaringan lokal & dependensi

mod_sysinfo() {
  local ips dns ip t tt tc c target
  section "SISTEM » Perangkat"
  kv "OS / Kernel" "$(uname -sr)"
  kv "Arsitektur" "$(uname -m)"
  kv "Hostname" "$(uname -n)"
  if have getprop; then
    kv "Android" "$(getprop ro.build.version.release)"
    kv "Perangkat" "$(getprop ro.product.manufacturer) $(getprop ro.product.model)"
  fi
  [[ -n ${TERMUX_VERSION:-} ]] && kv "Termux" "$TERMUX_VERSION"
  kv "Bash" "$BASH_VERSION"
  kv "Sfixx" "v${SFIXX_VERSION} (${SFIXX_HOME})"
  kv "Uptime" "$(uptime -p 2>/dev/null)"

  section "SISTEM » Jaringan Lokal"
  ips="$(ip -4 -o addr show 2>/dev/null | awk '{print $2": "$4}')"
  [[ -z $ips ]] && ips="$(ifconfig 2>/dev/null | awk '/^[a-z]/{i=$1} /inet /{print i" "$2}')"
  kvl "Alamat IP lokal" "$ips"
  if have getprop; then dns="$(getprop net.dns1) $(getprop net.dns2)"
  else dns="$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd' ' -)"; fi
  kv "DNS resolver" "$(tr -s ' ' <<<"$dns" | sed 's/^ //; s/ $//')"

  section "SISTEM » Internet"
  if fetch "https://api.ipify.org"; then
    ip="$HTTP_BODY"
    kv "IP publik" "$ip"
    if fetch "http://ip-api.com/json/${ip}?fields=status,country,regionName,city,isp,proxy,hosting" \
       && [[ "$(jq -r '.status' <<<"$HTTP_BODY" 2>/dev/null)" == success ]]; then
      jq_fields '.city,.regionName,.country,.isp,.proxy,.hosting' "$HTTP_BODY"
      kv "Lokasi (perkiraan)" "${JF[0]:-}, ${JF[1]:-}, ${JF[2]:-}"
      kv "ISP" "${JF[3]:-}"
      kv "Proxy / VPN" "$(tf "${JF[4]:-}")"
      kv "Hosting / DC" "$(tf "${JF[5]:-}")"
    fi
  else
    warn "Tidak ada koneksi internet"
  fi
  for target in https://1.1.1.1 https://www.google.com; do
    t="$(curl -s -o /dev/null --max-time 8 -w '%{time_connect}|%{time_total}' "$target" 2>/dev/null)"
    IFS='|' read -r tc tt <<<"$t"
    c="${target#https://}"; c="${c#www.}"
    [[ -n $tt && $tt != 0.000000 ]] && kv "Latensi $c" "$(awk -v a="$tc" -v b="$tt" 'BEGIN{printf "connect %.0f ms · total %.0f ms", a*1000, b*1000}')"
  done

  section "SISTEM » Dependensi"
  for c in curl jq awk sed grep openssl dig whois exiftool file termux-open-url; do
    if have "$c"; then kv "$c" "${C_GREEN}terpasang${C_RESET}"; else kv "$c" "${C_YELLOW}tidak ada${C_RESET}"; fi
  done
  return 0
}
