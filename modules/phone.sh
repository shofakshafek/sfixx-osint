#!/usr/bin/env bash
# modules/phone.sh — Number OSINT (offline + sumber publik)

PH_E164=""; PH_CC=""; PH_ISO=""; PH_COUNTRY=""; PH_NSN=""
ID_OP=""; ID_BRAND=""; ID_AREA=""

# calling_code_lookup <digit E.164> → set PH_CC / PH_ISO / PH_COUNTRY
calling_code_lookup() {
  local num="$1" n code line
  PH_CC=""; PH_ISO=""; PH_COUNTRY=""
  for n in 4 3 2 1; do
    (( ${#num} < n )) && continue
    code="${num:0:n}"
    line="$(awk -F'|' -v c="$code" '$1 == c {print; exit}' "$SFIXX_HOME/data/calling_codes.psv")"
    if [[ -n $line ]]; then IFS='|' read -r PH_CC PH_ISO PH_COUNTRY <<<"$line"; return 0; fi
  done
  return 1
}

# phone_parse <input> → set PH_E164 / PH_CC / PH_NSN …
phone_parse() {
  local raw="$1" s e cc="${DEFAULT_CC:-62}"
  s="${raw//[^0-9+]/}"
  if [[ $s == +* ]]; then s="+${s//+/}"; else s="${s//+/}"; fi
  if   [[ $s == +* ]];                  then e="${s#+}"
  elif [[ $s == 00* ]];                 then e="${s#00}"
  elif [[ $s == 0* ]];                  then e="${cc}${s#0}"
  elif [[ $s == ${cc}* ]];              then e="$s"
  elif [[ $cc == 62 && $s == 8* ]];     then e="62${s}"
  else e="$s"; fi
  [[ -z $e ]] && return 1
  calling_code_lookup "$e" || return 1
  PH_NSN="${e:${#PH_CC}}"
  [[ $PH_NSN == 0* ]] && PH_NSN="${PH_NSN#0}"      # buang nol trunk: +62 (0)812…
  [[ -z $PH_NSN ]] && return 1
  PH_E164="${PH_CC}${PH_NSN}"
  return 0
}

_ph_group() {   # 81234567890 → "812 3456 7890" ; NANP 4155550132 → "415 555 0132"
  local s="$1" out="${1:0:3}"
  if [[ ${PH_CC:-} == 1 && ${#s} == 10 ]]; then printf '%s %s %s' "${s:0:3}" "${s:3:3}" "${s:6}"; return; fi
  s="${s:3}"
  while [[ -n $s ]]; do out+=" ${s:0:4}"; s="${s:4}"; done
  printf '%s' "$out"
}

_id_carrier() {   # $1 = NSN → ID_OP / ID_BRAND
  local line
  ID_OP=""; ID_BRAND=""
  line="$(grep -m1 "^0${1:0:3}|" "$SFIXX_HOME/data/id_carriers.psv" 2>/dev/null)"
  [[ -n $line ]] && IFS='|' read -r _ ID_OP ID_BRAND <<<"$line"
  [[ -n $ID_OP ]]
}

_id_area() {      # $1 = NSN → ID_AREA
  local line
  ID_AREA=""
  line="$(grep -m1 "^0${1:0:3}|" "$SFIXX_HOME/data/id_areas.psv" 2>/dev/null)"
  [[ -z $line ]] && line="$(grep -m1 "^0${1:0:2}|" "$SFIXX_HOME/data/id_areas.psv" 2>/dev/null)"
  [[ -n $line ]] && ID_AREA="${line#*|}"
  [[ -n $ID_AREA ]]
}

phone_variants() {
  local g; g="$(_ph_group "$PH_NSN")"
  if [[ $PH_CC == 62 ]]; then
    printf '%s\n' "0${PH_NSN}" "+${PH_E164}" "${PH_E164}" "+${PH_CC} ${g}" "0${g// /-}" "0${g}" "(+${PH_CC}) ${g// /-}" "${PH_NSN}"
  else
    printf '%s\n' "+${PH_E164}" "${PH_E164}" "00${PH_E164}" "+${PH_CC} ${g}" "${PH_CC}-${g// /-}" "(+${PH_CC}) ${g}"
  fi
}

# phone_or_query: gabungan varian dipakai pada dork → "\"a\" OR \"b\" …"
phone_or_query() {
  local x all=""
  while IFS= read -r x; do all+="\"${x}\" OR "; done < <(phone_variants | head -n 6)
  printf '%s' "${all% OR }"
}

phone_dorks() {
  local all; all="$(phone_or_query)"
  dork_line "Semua format"        "${all}"
  dork_line "Media sosial"        "(${all}) (site:facebook.com OR site:instagram.com OR site:linkedin.com OR site:x.com OR site:tiktok.com)"
  dork_line "Marketplace / iklan" "(${all}) (site:olx.co.id OR site:tokopedia.com OR site:shopee.co.id OR site:facebook.com/marketplace)"
  dork_line "Dokumen publik"      "(${all}) (filetype:pdf OR filetype:doc OR filetype:docx OR filetype:xls OR filetype:xlsx)"
  dork_line "Paste / kode"        "(${all}) (site:pastebin.com OR site:github.com OR site:gist.github.com)"
  dork_line "Laporan penipuan"    "(${all}) (penipuan OR scam OR spam OR \"nomor penipu\")"
}

mod_phone() {
  local raw="${1:-}" g len
  [[ -z $raw ]] && { err "Masukkan nomor (mis. 081234567890 atau +14155550132)"; return 1; }
  is_phone "$raw" || { err "Format nomor tidak valid: $raw"; return 1; }
  phone_parse "$raw" || { err "Kode negara tidak dikenali — pakai format internasional, mis. +62812…"; return 1; }
  g="$(_ph_group "$PH_NSN")"; len=${#PH_NSN}

  section "NUMBER OSINT » +${PH_E164}"
  kv "Input" "$raw"
  kv "Format E.164" "+${PH_E164}"
  kv "Internasional" "+${PH_CC} ${g}"
  [[ $PH_CC == 62 ]] && kv "Nasional (ID)" "0${g// /-}"
  kv "Negara" "${PH_COUNTRY} (${PH_ISO}) · kode +${PH_CC}"

  if [[ $PH_CC == 62 ]]; then
    case $PH_NSN in
      800*) kv "Jenis" "Bebas pulsa (toll-free 0800)" ;;
      809*) kv "Jenis" "Tarif premium (0809)" ;;
      8*)
        if _id_carrier "$PH_NSN"; then
          kv "Jenis" "Seluler"
          kv "Operator (prefix)" "$ID_OP"
          kv "Merek / kartu" "$ID_BRAND"
        else
          kv "Jenis" "Seluler (prefix 0${PH_NSN:0:3} tidak ada di tabel)"
        fi
        if (( len >= 9 && len <= 12 )); then kv "Panjang nomor" "lazim (${len} digit tanpa 0)"
        else kv "Panjang nomor" "${C_YELLOW}tidak lazim (${len} digit tanpa 0)${C_RESET}"; fi
        ;;
      [1-9]*)
        if _id_area "$PH_NSN"; then kv "Jenis" "Telepon tetap (fixed line)"; kv "Wilayah" "$ID_AREA"
        else kv "Jenis" "Telepon tetap / layanan lain"; fi
        ;;
    esac
    info "Operator berdasarkan alokasi prefix — nomor bisa saja sudah pindah/merger operator."
  else
    info "Analisis operator hanya tersedia untuk Indonesia (+62)."
  fi

  section "Varian Format (untuk pencarian)"
  kvl "Varian" "$(phone_variants)"

  section "Tautan Aplikasi"
  kv "WhatsApp" "https://wa.me/${PH_E164}"
  kv "Telegram" "https://t.me/+${PH_E164}"
  kv "Signal" "https://signal.me/#p/+${PH_E164}"

  section "Pencarian Publik (dork)"
  phone_dorks

  if [[ -n ${NUMVERIFY_KEY:-} ]]; then
    section "Numverify"
    if fetch "http://apilayer.net/api/validate?access_key=${NUMVERIFY_KEY}&number=${PH_E164}" && is_json "$HTTP_BODY"; then
      jq_fields '.valid,.country_name,.location,.carrier,.line_type,.error.info' "$HTTP_BODY"
      kv "Valid" "${JF[0]:-}"
      kv "Negara" "${JF[1]:-}"
      kv "Lokasi" "${JF[2]:-}"
      kv "Operator" "${JF[3]:-}"
      kv "Tipe line" "${JF[4]:-}"
      kv "Pesan API" "${JF[5]:-}"
    else
      warn "Numverify gagal (HTTP $HTTP_CODE)"
    fi
  fi
  return 0
}
