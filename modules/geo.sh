#!/usr/bin/env bash
# modules/geo.sh — geocoding (OpenStreetMap Nominatim)

_geo_links() {
  local lat="$1" lon="$2"
  kv "Google Maps" "https://www.google.com/maps?q=${lat},${lon}"
  kv "OpenStreetMap" "https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=17/${lat}/${lon}"
  kv "Street View" "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${lat},${lon}"
  kv "Google Earth" "https://earth.google.com/web/@${lat},${lon},0a,1500d,35y,0h,0t,0r"
}

mod_geo() {
  local q="${1:-}" ua="sfixx-osint/${SFIXX_VERSION} (OSINT toolkit)" lat lon name n i
  [[ -z $q ]] && { err "Masukkan koordinat 'lat,lon' atau nama tempat"; return 1; }
  if is_coord "$q"; then
    lat="${q%%,*}"; lon="${q##*,}"; lat="${lat// /}"; lon="${lon// /}"
    section "GEO » reverse geocode ${lat}, ${lon}"
    if fetch "https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&accept-language=id&lat=${lat}&lon=${lon}" -A "$ua" && is_json "$HTTP_BODY"; then
      jq_fields '.display_name,.category,.type,.address.road,.address.suburb,.address.village,.address.city,.address.town,.address.county,.address.state,.address.postcode,.address.country' "$HTTP_BODY"
      if [[ -z ${JF[0]:-} ]]; then warn "Tidak ada hasil untuk koordinat ini"
      else
        kv "Alamat" "${JF[0]}"
        kv "Kategori" "${JF[1]:-}${JF[2]:+ / ${JF[2]}}"
        kv "Jalan" "${JF[3]:-}"
        kv "Kelurahan / desa" "${JF[4]:-}${JF[5]:-}"
        kv "Kota / kabupaten" "${JF[6]:-}${JF[7]:-}${JF[8]:+ (${JF[8]})}"
        kv "Provinsi" "${JF[9]:-}"
        kv "Kode pos" "${JF[10]:-}"
        kv "Negara" "${JF[11]:-}"
      fi
    else
      warn "Nominatim tidak merespons (HTTP $HTTP_CODE)"
    fi
    _geo_links "$lat" "$lon"
    return 0
  fi
  section "GEO » cari lokasi: $q"
  if fetch "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=3&accept-language=id&q=$(urlenc "$q")" -A "$ua" && is_json "$HTTP_BODY"; then
    n="$(jq 'length' <<<"$HTTP_BODY" 2>/dev/null)"
    (( ${n:-0} == 0 )) && { warn "Lokasi tidak ditemukan"; return 0; }
    i=0
    while IFS='|' read -r lat lon name; do
      i=$((i+1))
      kv "Hasil $i" "$name"
      kv "  ↳ koordinat" "${lat}, ${lon}"
      _geo_links "$lat" "$lon"
    done < <(jq -r '.[] | "\(.lat)|\(.lon)|\(.display_name)"' <<<"$HTTP_BODY" 2>/dev/null)
  else
    warn "Nominatim tidak merespons (HTTP $HTTP_CODE)"
  fi
  return 0
}
