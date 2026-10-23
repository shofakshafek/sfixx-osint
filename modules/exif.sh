#!/usr/bin/env bash
# modules/exif.sh — metadata file/foto (lokal, tanpa upload)

mod_exif() {
  local f="${1:-}" out line lat lon
  [[ -f $f ]] || { err "File tidak ditemukan: ${f:-<kosong>}"; return 1; }
  section "METADATA » $(basename "$f")"
  kv "Ukuran" "$(wc -c < "$f") byte"
  have file && kv "Tipe (file)" "$(file -b "$f" 2>/dev/null)"
  kv "MD5" "$(md5sum "$f" | cut -d' ' -f1)"
  kv "SHA-256" "$(sha256sum "$f" | cut -d' ' -f1)"
  if ! have exiftool; then
    warn "exiftool belum terpasang — metadata detail tidak tersedia (pkg install exiftool)"
    return 0
  fi
  out="$(exiftool -S -Make -Model -LensModel -Software -DateTimeOriginal -CreateDate -ModifyDate \
        -Artist -Author -Creator -Producer -Copyright -OwnerName -SerialNumber -BodySerialNumber \
        -ImageSize -MIMEType -Title -Subject -Keywords -Comment -GPSPosition -- "$f" 2>/dev/null)"
  if [[ -z $out ]]; then info "Tidak ada metadata yang dikenali"
  else
    while IFS= read -r line; do kv "${line%%:*}" "${line#*: }"; done <<<"$out"
  fi
  lat="$(exiftool -n -s3 -GPSLatitude  -- "$f" 2>/dev/null | head -n1)"
  lon="$(exiftool -n -s3 -GPSLongitude -- "$f" 2>/dev/null | head -n1)"
  if [[ -n $lat && -n $lon ]]; then
    section "Lokasi dalam File (GPS)"
    kv "Koordinat" "${lat}, ${lon}"
    _geo_links "$lat" "$lon"
    warn "File ini membawa lokasi. Hapus sebelum dibagikan: exiftool -all= \"$f\""
  fi
  return 0
}
