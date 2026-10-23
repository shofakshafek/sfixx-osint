#!/usr/bin/env bash
# modules/github.sh — GitHub OSINT (API publik)

mod_github() {
  local u="${1:-}" H=() emails real n keys
  u="${u##*github.com/}"; u="${u%%[/?#]*}"; u="${u#@}"
  [[ $u =~ ^[A-Za-z0-9-]{1,39}$ ]] || { err "Username GitHub tidak valid: ${1:-<kosong>}"; return 1; }
  [[ -n ${GITHUB_TOKEN:-} ]] && H=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

  section "GITHUB OSINT » $u"
  fetch "https://api.github.com/users/${u}" "${H[@]}" -H "Accept: application/vnd.github+json"
  case $HTTP_CODE in
    200) ;;
    404) err "User GitHub tidak ditemukan"; return 1 ;;
    403|429) err "Rate-limit API GitHub (60 req/jam tanpa token) — isi GITHUB_TOKEN di config"; return 1 ;;
    *) err "GitHub tidak merespons (HTTP $HTTP_CODE)"; return 1 ;;
  esac
  jq_fields '.login,.id,.name,.type,.company,.blog,.location,.email,.bio,.twitter_username,.public_repos,.public_gists,.followers,.following,.created_at,.updated_at,.hireable,.html_url,.avatar_url' "$HTTP_BODY"
  kv "Username" "${JF[0]:-}"
  kv "ID akun" "${JF[1]:-}"
  kv "Nama" "${JF[2]:-}"
  kv "Tipe" "${JF[3]:-}"
  kv "Perusahaan" "${JF[4]:-}"
  kv "Website / blog" "${JF[5]:-}"
  kv "Lokasi" "${JF[6]:-}"
  kv "Email profil" "${JF[7]:-}"
  kv "Bio" "${JF[8]:-}"
  kv "X / Twitter" "${JF[9]:-}"
  kv "Repo publik" "${JF[10]:-}"
  kv "Gist publik" "${JF[11]:-}"
  kv "Followers" "${JF[12]:-} / mengikuti ${JF[13]:-}"
  kv "Akun dibuat" "$(date_fmt "${JF[14]:-}")"
  kv "Aktivitas terakhir" "$(date_fmt "${JF[15]:-}")"
  kv "Profil" "${JF[17]:-}"
  kv "Avatar" "${JF[18]:-}"

  fetch "https://api.github.com/users/${u}/orgs" "${H[@]}"
  [[ $HTTP_CODE == 200 ]] && kv "Organisasi" "$(jq -r 'map(.login) | join(", ")' <<<"$HTTP_BODY" 2>/dev/null)"

  fetch "https://api.github.com/users/${u}/repos?per_page=100&sort=pushed" "${H[@]}"
  if [[ $HTTP_CODE == 200 ]] && is_json "$HTTP_BODY"; then
    section "Repositori (terbaru di-push)"
    kv "Bahasa dominan" "$(jq -r '[.[].language | select(. != null)] | group_by(.) | map({l: .[0], n: length}) | sort_by(-.n) | .[0:5] | map("\(.l) (\(.n))") | join(", ")' <<<"$HTTP_BODY" 2>/dev/null)"
    kvl "Repo" "$(jq -r '.[0:15][] | "\(.name)  ★\(.stargazers_count)  [\(.language // "-")]\(if .fork then "  (fork)" else "" end)"' <<<"$HTTP_BODY" 2>/dev/null)"
  fi

  fetch "https://api.github.com/users/${u}/events/public?per_page=100" "${H[@]}"
  if [[ $HTTP_CODE == 200 ]] && is_json "$HTTP_BODY"; then
    section "Jejak Commit Publik"
    emails="$(jq -r '[.[] | select(.type == "PushEvent") | .payload.commits[]? | .author | "\(.name) <\(.email)>"] | unique | .[]' <<<"$HTTP_BODY" 2>/dev/null)"
    real="$(grep -v 'noreply' <<<"$emails")"
    n="$(grep -c 'noreply' <<<"$emails")"
    kvl "Email di commit" "$real"
    if [[ -z $real ]]; then kv "Email di commit" "tidak ada yang terlihat (${n} alamat noreply)"
    elif (( n > 0 )); then kv "Alamat noreply" "${n} (disembunyikan)"; fi
  fi

  fetch "https://github.com/${u}.keys"
  if [[ $HTTP_CODE == 200 && -n $HTTP_BODY ]]; then
    keys="$(grep -c . <<<"$HTTP_BODY")"
    kv "SSH public key" "${keys} kunci → https://github.com/${u}.keys"
  fi
  fetch "https://github.com/${u}.gpg"
  [[ $HTTP_CODE == 200 && $HTTP_BODY == *"BEGIN PGP"* ]] && kv "GPG public key" "ada → https://github.com/${u}.gpg"

  kv "Cek username lain" "sfixx user ${u}"
  return 0
}
