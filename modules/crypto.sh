#!/usr/bin/env bash
# modules/crypto.sh — alamat Bitcoin / Ethereum (data blockchain publik)

_sat2btc() { awk -v s="${1:-0}" 'BEGIN{printf "%.8f", s/100000000}'; }

mod_crypto() {
  local a="${1:-}" t h r
  [[ -z $a ]] && { err "Masukkan alamat Bitcoin (bc1…/1…/3…) atau Ethereum (0x…)"; return 1; }
  if is_eth "$a"; then
    section "ETHEREUM » $a"
    kv "Etherscan" "https://etherscan.io/address/${a}"
    kv "Blockchair" "https://blockchair.com/ethereum/address/${a}"
    kv "Arkham Intel" "https://intel.arkm.com/explorer/address/${a}"
    info "Detail saldo ETH butuh API key explorer — tautan di atas membuka data publiknya."
    return 0
  fi
  is_btc "$a" || { err "Format alamat tidak dikenali: $a"; return 1; }
  section "BITCOIN » $a"
  if fetch "https://blockchain.info/rawaddr/${a}?limit=5" && is_json "$HTTP_BODY"; then
    jq_fields '.n_tx,.total_received,.total_sent,.final_balance' "$HTTP_BODY"
    kv "Jumlah transaksi" "${JF[0]:-}"
    kv "Total diterima" "$(_sat2btc "${JF[1]:-0}") BTC"
    kv "Total terkirim" "$(_sat2btc "${JF[2]:-0}") BTC"
    kv "Saldo akhir" "$(_sat2btc "${JF[3]:-0}") BTC"
    echo
    info "5 transaksi terbaru:"
    while IFS='|' read -r t h r; do
      printf '  %s◆%s %s  %s…  %s%s BTC%s\n' "$C_CYAN" "$C_RESET" "$t" "$h" "$C_GRAY" "$(_sat2btc "$r")" "$C_RESET"
    done < <(jq -r '.txs[]? | "\(.time | todate)|\(.hash[0:16])|\(.result // 0)"' <<<"$HTTP_BODY" 2>/dev/null)
  else
    warn "blockchain.info tidak merespons (HTTP $HTTP_CODE)"
  fi
  kv "Blockchain.com" "https://www.blockchain.com/explorer/addresses/btc/${a}"
  kv "Blockchair" "https://blockchair.com/bitcoin/address/${a}"
  return 0
}
