#!/usr/bin/env bash
# modules/subdomain.sh — enumerasi subdomain pasif (CT log + passive DNS)

# sub_collect <domain> <file-keluaran>
sub_collect() {
  local d="$1" out="$2" tmp="$SFIXX_TMP/sub.raw.$$" esc
  esc="${d//./\\.}"
  : > "$tmp"

  info "Sumber 1/3: crt.sh (Certificate Transparency)…"
  if fetch "https://crt.sh/?q=%25.${d}&output=json" --max-time 60 && is_json "$HTTP_BODY"; then
    jq -r '.[].name_value' <<<"$HTTP_BODY" 2>/dev/null >> "$tmp"
  else
    warn "crt.sh tidak merespons (HTTP $HTTP_CODE)"
  fi

  info "Sumber 2/3: HackerTarget…"
  if fetch "https://api.hackertarget.com/hostsearch/?q=${d}" && [[ $HTTP_BODY != error* && $HTTP_BODY != "API count"* ]]; then
    cut -d, -f1 <<<"$HTTP_BODY" >> "$tmp"
  else
    warn "HackerTarget tidak tersedia / kuota publik habis"
  fi

  info "Sumber 3/3: AlienVault OTX (passive DNS)…"
  if fetch "https://otx.alienvault.com/api/v1/indicators/domain/${d}/passive_dns" && is_json "$HTTP_BODY"; then
    jq -r '.passive_dns[]?.hostname' <<<"$HTTP_BODY" 2>/dev/null >> "$tmp"
  else
    warn "OTX tidak merespons"
  fi

  tr 'A-Z' 'a-z' < "$tmp" | tr -d '\r' | sed -e 's/^\*\.//' -e 's/\.$//' \
    | grep -E "^([a-z0-9_-]+\.)*${esc}$" | sort -u > "$out"
}

# sub_resolve_print <file>
sub_resolve_print() {
  local f="$1" res="$SFIXX_TMP/subres.$$" h cnt=0 max="${SUB_RESOLVE_MAX:-40}" name ip total
  : > "$res"
  total="$(wc -l < "$f")"
  while IFS= read -r h; do
    (( cnt >= max )) && break
    cnt=$((cnt+1))
    throttle "${THREADS:-12}"
    {
      ip="$(dns_query "$h" A | head -n1)"
      if [[ -z $ip ]]; then
        ip="$(dns_query "$h" CNAME | head -n1)"
        [[ -n $ip ]] && ip="CNAME → ${ip%.}"
      fi
      printf '%s|%s\n' "$h" "${ip:--}" >> "$res"
    } &
  done < "$f"
  wait
  echo
  while IFS='|' read -r name ip; do
    printf '  %s◆%s %-44s %s%s%s\n' "$C_CYAN" "$C_RESET" "$name" "$C_GRAY" "$ip" "$C_RESET"
  done < <(sort -u "$res")
  if (( total > max )); then
    info "Hanya $max pertama yang di-resolve; sisanya (maks 150) hanya nama:"
    tail -n +$((max+1)) "$f" | head -n 150 | sed 's/^/      /'
  fi
}

mod_subdomain() {
  local d out="$SFIXX_TMP/subs.$$" total
  d="$(host_of "${1:-}")"
  is_domain "$d" || { err "Domain tidak valid: ${1:-<kosong>}"; return 1; }
  section "Subdomain » $d"
  sub_collect "$d" "$out"
  total="$(wc -l < "$out")"
  if (( total == 0 )); then warn "Tidak ada subdomain yang ditemukan"; return 0; fi
  kv "Total subdomain unik" "$total"
  sub_resolve_print "$out"
}
