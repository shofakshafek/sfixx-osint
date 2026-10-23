#!/usr/bin/env bash
# modules/email.sh — Email OSINT (DNS, reputasi, gravatar, breach, pivot)

_FREE_PROVIDERS=" gmail.com googlemail.com yahoo.com yahoo.co.id ymail.com outlook.com hotmail.com live.com msn.com icloud.com me.com proton.me protonmail.com pm.me aol.com gmx.com gmx.net mail.com zoho.com yandex.com yandex.ru mail.ru "
_ROLE_ACCOUNTS=" admin administrator info support sales contact help billing hello office postmaster webmaster abuse security noreply no-reply hr jobs career press marketing team cs "

_mx_provider() {
  local mx="${1,,}"
  case $mx in
    *google.com*|*googlemail.com*)          echo "Google (Gmail / Workspace)" ;;
    *outlook.com*|*protection.outlook*|*hotmail.com*) echo "Microsoft (Outlook / 365)" ;;
    *yahoodns*|*yahoo.com*)                 echo "Yahoo Mail" ;;
    *zoho.*)                                echo "Zoho Mail" ;;
    *protonmail*|*proton.ch*)               echo "Proton Mail" ;;
    *icloud.com*|*apple.com*)               echo "Apple iCloud" ;;
    *yandex*)                               echo "Yandex" ;;
    *mimecast*)                             echo "Mimecast (gateway)" ;;
    *pphosted*)                             echo "Proofpoint (gateway)" ;;
    *secureserver*)                         echo "GoDaddy" ;;
    *registrar-servers*|*privateemail*)     echo "Namecheap" ;;
    *mailgun*)                              echo "Mailgun" ;;
    *ovh.net*)                              echo "OVH" ;;
    *qq.com*)                               echo "Tencent QQ Mail" ;;
    *)                                      echo "" ;;
  esac
}

_is_disposable() { grep -qixF "$1" "$SFIXX_HOME/data/disposable_domains.txt" 2>/dev/null; }

mod_email() {
  local email user domain hash sha mx prov norm names n days
  email="$(lower "$(trim "${1:-}")")"
  is_email "$email" || { err "Format email tidak valid: ${1:-<kosong>}"; return 1; }
  user="${email%@*}"; domain="${email#*@}"
  hash="$(md5_of "$email")"; sha="$(sha256_of "$email")"

  section "EMAIL OSINT » $email"
  kv "Username (local)" "$user"
  kv "Domain" "$domain"
  [[ $user == *+* ]] && kv "Alias +tag" "alamat dasar: ${user%%+*}@${domain}"
  if [[ $domain == gmail.com || $domain == googlemail.com ]]; then
    norm="${user%%+*}"; norm="${norm//./}"
    kv "Normalisasi Gmail" "${norm}@gmail.com (titik & +tag diabaikan Gmail)"
  fi
  [[ $_ROLE_ACCOUNTS == *" ${user%%+*} "* ]] && kv "Jenis akun" "role / fungsional (bukan perorangan)"
  [[ $_FREE_PROVIDERS == *" $domain "* ]] && kv "Penyedia" "email gratis publik"

  section "Domain & Penerimaan Email"
  mx="$(dns_query "$domain" MX | sort -n)"
  if [[ -n $mx ]]; then
    kvl "MX" "$mx"
    prov="$(_mx_provider "$(head -n1 <<<"$mx")")"
    kv "Penyedia (tebakan)" "$prov"
    kv "Terima email" "${C_GREEN}Ya${C_RESET} (record MX ada)"
  elif [[ -n "$(dns_query "$domain" A | head -n1)" ]]; then
    kv "Terima email" "${C_YELLOW}Mungkin${C_RESET} (tanpa MX, fallback ke record A)"
  else
    kv "Terima email" "${C_RED}Tidak${C_RESET} — domain tanpa MX/A (alamat hampir pasti tidak valid)"
  fi

  if _is_disposable "$domain"; then
    kv "Email sementara" "${C_RED}Ya${C_RESET} — domain ada di daftar disposable"
  elif fetch "https://open.kickbox.com/v1/disposable/${domain}" && is_json "$HTTP_BODY"; then
    if [[ "$(jq -r '.disposable' <<<"$HTTP_BODY" 2>/dev/null)" == true ]]; then kv "Email sementara" "${C_RED}Ya${C_RESET} (kickbox)"
    else kv "Email sementara" "Tidak (daftar lokal + kickbox)"; fi
  else
    kv "Email sementara" "Tidak (daftar lokal saja)"
  fi

  if [[ $_FREE_PROVIDERS != *" $domain "* ]]; then
    if rdap_domain_load "$(apex_domain "$domain")"; then
      kv "Domain dibuat" "$(date_fmt "$RD_CREATED")"
      kv "Registrar" "$RD_REGISTRAR"
      if [[ -n $RD_CREATED ]] && days="$(age_days "$RD_CREATED")" && [[ -n $days ]] && (( days < 90 )); then
        warn "Domain email sangat baru (${days} hari) — hati-hati."
      fi
    fi
    dns_mailsec "$domain"
  fi

  section "Gravatar"
  fetch "https://api.gravatar.com/v3/profiles/${sha}"
  if [[ $HTTP_CODE == 200 ]] && is_json "$HTTP_BODY"; then
    jq_fields '.display_name,.profile_url,.avatar_url,.location,.job_title,.company,.description,((.verified_accounts // []) | map("\(.service_label): \(.url)") | join(" | ")),((.links // []) | map(.url) | join(", "))' "$HTTP_BODY"
    kv "Nama tampilan" "${JF[0]:-}"
    kv "Profil" "${JF[1]:-}"
    kv "Lokasi" "${JF[3]:-}"
    kv "Pekerjaan" "${JF[4]:-}${JF[5]:+ @ ${JF[5]}}"
    kv "Bio" "${JF[6]:-}"
    kv "Akun terverifikasi" "${JF[7]:-}"
    kv "Tautan" "${JF[8]:-}"
    kv "Avatar" "${JF[2]:-}"
  else
    fetch "https://en.gravatar.com/${hash}.json"
    if [[ $HTTP_CODE == 200 ]] && is_json "$HTTP_BODY"; then
      jq_fields '.entry[0].displayName,.entry[0].profileUrl,.entry[0].currentLocation,.entry[0].aboutMe,((.entry[0].accounts // []) | map("\(.name): \(.url)") | join(" | ")),.entry[0].thumbnailUrl' "$HTTP_BODY"
      kv "Nama tampilan" "${JF[0]:-}"
      kv "Profil" "${JF[1]:-}"
      kv "Lokasi" "${JF[2]:-}"
      kv "Bio" "${JF[3]:-}"
      kv "Akun tertaut" "${JF[4]:-}"
      kv "Avatar" "${JF[5]:-}"
    else
      fetch "https://www.gravatar.com/avatar/${hash}?d=404" -I
      if [[ $HTTP_CODE == 200 ]]; then kv "Gravatar" "avatar ada (profil tidak publik): https://www.gravatar.com/avatar/${hash}"
      else kv "Gravatar" "tidak ditemukan"; fi
    fi
  fi

  section "Reputasi (EmailRep)"
  fetch "https://emailrep.io/$(urlenc "$email")" -H "Accept: application/json"
  if is_json "$HTTP_BODY" && [[ -n "$(jq -r '.email // empty' <<<"$HTTP_BODY" 2>/dev/null)" ]]; then
    jq_fields '.reputation,.suspicious,.references,.details.blacklisted,.details.malicious_activity,.details.credentials_leaked,.details.data_breach,.details.first_seen,.details.last_seen,.details.spam,.details.free_provider,.details.deliverable,.details.valid_mx,((.details.profiles // []) | join(", "))' "$HTTP_BODY"
    kv "Reputasi" "${JF[0]:-}"
    kv "Mencurigakan" "$(tf "${JF[1]:-}")"
    kv "Referensi web" "${JF[2]:-}"
    kv "Blacklist" "$(tf "${JF[3]:-}")"
    kv "Aktivitas berbahaya" "$(tf "${JF[4]:-}")"
    kv "Kredensial bocor" "$(tf "${JF[5]:-}")"
    kv "Terlibat breach" "$(tf "${JF[6]:-}")"
    kv "Spam" "$(tf "${JF[9]:-}")"
    kv "Pertama terlihat" "${JF[7]:-}"
    kv "Terakhir terlihat" "${JF[8]:-}"
    kv "Profil terdeteksi" "${JF[13]:-}"
  elif is_json "$HTTP_BODY" && [[ -n "$(jq -r '.reason // empty' <<<"$HTTP_BODY" 2>/dev/null)" ]]; then
    warn "EmailRep: $(jq -r '.reason' <<<"$HTTP_BODY")"
  else
    info "EmailRep tidak merespons (HTTP $HTTP_CODE)"
  fi

  section "Paparan Kebocoran Data (nama breach saja)"
  fetch "https://api.xposedornot.com/v1/check-email/$(urlenc "$email")"
  if [[ $HTTP_CODE == 200 ]] && is_json "$HTTP_BODY"; then
    names="$(jq -r '[.breaches[]?[]?] | unique | .[]' <<<"$HTTP_BODY" 2>/dev/null)"
    n="$(grep -c . <<<"$names")"
    if (( n > 0 )); then
      kv "XposedOrNot" "${C_RED}ditemukan di ${n} kebocoran${C_RESET}"
      kvl "Nama breach" "$(head -n 30 <<<"$names")"
      (( n > 30 )) && info "…dan $(( n - 30 )) lainnya"
      info "Saran: ganti password di layanan terkait & aktifkan 2FA."
    else
      kv "XposedOrNot" "tidak ditemukan"
    fi
  elif [[ $HTTP_CODE == 404 ]]; then
    kv "XposedOrNot" "tidak ditemukan di basis data breach"
  elif [[ $HTTP_CODE == 429 ]]; then
    warn "XposedOrNot: rate-limit, coba lagi beberapa saat"
  else
    warn "XposedOrNot tidak merespons (HTTP $HTTP_CODE)"
  fi
  if [[ -n ${HIBP_KEY:-} ]]; then
    fetch "https://haveibeenpwned.com/api/v3/breachedaccount/$(urlenc "$email")?truncateResponse=false" \
          -H "hibp-api-key: ${HIBP_KEY}" -H "user-agent: sfixx-osint"
    case $HTTP_CODE in
      200) kvl "HIBP" "$(jq -r '.[] | "\(.Name) (\(.BreachDate)) — \(.PwnCount) akun"' <<<"$HTTP_BODY" 2>/dev/null | head -n 25)" ;;
      404) kv "HIBP" "tidak ditemukan" ;;
      401) warn "HIBP_KEY tidak valid" ;;
      429) warn "HIBP rate-limit" ;;
      *)   warn "HIBP gagal (HTTP $HTTP_CODE)" ;;
    esac
  fi

  section "Pivot & Pencarian Lanjutan"
  dork_line "Exact match"   "\"${email}\""
  dork_line "Paste / kode"  "\"${email}\" (site:pastebin.com OR site:github.com OR site:gitlab.com OR site:gist.github.com)"
  dork_line "Dokumen"       "\"${email}\" (filetype:pdf OR filetype:doc OR filetype:docx OR filetype:xls OR filetype:xlsx OR filetype:txt)"
  dork_line "Profil sosial" "\"${email}\" (site:linkedin.com OR site:facebook.com OR site:x.com OR site:instagram.com)"
  kv "Cek username" "sfixx user ${user%%+*}"
  return 0
}

mod_emailgen() {
  local first last domain f l
  first="$(lower "${1:-}")"; last="$(lower "${2:-}")"; domain="$(lower "${3:-}")"
  [[ -z $first || -z $last || -z $domain ]] && { err "Pakai: sfixx emailgen <nama-depan> <nama-belakang> <domain>"; return 1; }
  is_domain "$domain" || { err "Domain tidak valid: $domain"; return 1; }
  f="${first:0:1}"; l="${last:0:1}"
  section "Pola Email » $first $last @ $domain"
  printf '%s\n' "${first}.${last}" "${first}${last}" "${f}${last}" "${f}.${last}" "${first}${l}" \
    "${first}.${l}" "${first}_${last}" "${last}.${first}" "${last}${first}" "${last}${f}" \
    "${first}" "${last}" "${f}_${last}" | awk -v d="$domain" '{printf "  ◆ %s@%s\n", $0, d}'
  info "Ini hanya pola umum — bukan bukti bahwa alamat tersebut benar-benar ada."
}
