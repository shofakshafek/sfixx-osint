#!/usr/bin/env bash
# modules/username.sh — pencarian username lintas situs (HTTP biasa, tanpa login)

# _us_has <file> <teks> → sukses bila body memuat teks (abaikan beda spasi/newline pada JSON)
_us_has() {
  local a
  grep -qF -- "$2" "$1" && return 0
  a="$(tr -d '[:space:]' <<<"$2")"
  tr -d '[:space:]' < "$1" | grep -qF -- "$a"
}

# _us_check <nama> <url> <tipe> <argumen> <username> → "STATUS|nama|url|kode"
_us_check() {
  local name="$1" url="$2" type="$3" arg="$4" q="$5" tmp code r body
  url="${url//\{\}/$q}"
  if [[ $type == L ]]; then printf 'L|%s|%s|-\n' "$name" "$url"; return; fi
  tmp="$(mktemp "$SFIXX_TMP/u.XXXXXX")"
  code="$(curl -sL --connect-timeout 8 --max-time "${US_TIMEOUT:-12}" -A "${UA:-$UA_DEFAULT}" \
      -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null)"
  [[ -z $code ]] && code=000
  r=E
  case $type in
    S) case $code in 200) r=F ;; 404|410) r=N ;; esac ;;
    M) case $code in 200) if _us_has "$tmp" "$arg"; then r=N; else r=F; fi ;; 404|410) r=N ;; esac ;;
    P) case $code in 200) if _us_has "$tmp" "$arg"; then r=F; else r=N; fi ;; 404|410) r=N ;; esac ;;
    E) case $code in
         200) body="$(tr -d '[:space:]' < "$tmp")"; if [[ $body == "$arg" ]]; then r=N; else r=F; fi ;;
         404|410) r=N ;;
       esac ;;
  esac
  rm -f "$tmp"
  printf '%s|%s|%s|%s\n' "$r" "$name" "$url" "$code"
}

mod_username() {
  local u="${1:-}" sites="$SFIXX_HOME/data/sites.psv" res="$SFIXX_TMP/us.$$" total n=0
  local name url type arg st code nf nl ne nn
  [[ -z $u ]] && { err "Masukkan username"; return 1; }
  u="${u#@}"
  [[ $u =~ ^[A-Za-z0-9._-]{2,40}$ ]] || { err "Username hanya boleh huruf, angka, titik, underscore, strip (2–40 karakter)"; return 1; }
  total="$(grep -vcE '^(#|$)' "$sites")"
  section "USERNAME OSINT » $u"
  info "Memeriksa ${total} situs (paralel ${THREADS:-12}) — biasanya 10–30 detik…"
  : > "$res"
  while IFS='|' read -r name url type arg; do
    [[ -z $name || $name == \#* ]] && continue
    throttle "${THREADS:-12}"
    _us_check "$name" "$url" "$type" "$arg" "$u" >> "$res" &
    n=$((n+1))
    (( n % 4 == 0 )) && progress "[~] $(wc -l < "$res")/${total}"
  done < "$sites"
  while (( $(jobs -rp | wc -l) > 0 )); do progress "[~] $(wc -l < "$res")/${total}"; sleep 0.3; done
  wait
  progress_clear

  nf="$(grep -c '^F|' "$res")"; nl="$(grep -c '^L|' "$res")"
  ne="$(grep -c '^E|' "$res")"; nn="$(grep -c '^N|' "$res")"
  echo
  kv "Akun ditemukan" "${C_GREEN}${nf}${C_RESET}"
  while IFS='|' read -r st name url code; do
    printf '  %s[+]%s %-18s %s\n' "$C_GREEN" "$C_RESET" "$name" "$url"
  done < <(grep '^F|' "$res" | sort -t'|' -k2,2 -f)
  if (( nl > 0 )); then
    echo; info "Cek manual (situs ini memblokir pengecekan otomatis):"
    while IFS='|' read -r st name url code; do
      printf '  %s[?]%s %-18s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$url"
    done < <(grep '^L|' "$res" | sort -t'|' -k2,2 -f)
  fi
  echo
  kv "Tidak ditemukan" "$nn"
  kv "Tidak pasti" "$ne (diblokir / timeout)"
  if (( ${VERBOSE:-0} && ne > 0 )); then
    while IFS='|' read -r st name url code; do
      printf '  %s[~]%s %-18s HTTP %s  %s\n' "$C_GRAY" "$C_RESET" "$name" "$code" "$url"
    done < <(grep '^E|' "$res" | sort -t'|' -k2,2 -f)
  fi
  info "Hasil bersifat indikatif — verifikasi manual sebelum menyimpulkan apa pun."
  return 0
}
