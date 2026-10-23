#!/usr/bin/env bash
# Perbarui Sfixx OSINT dari GitHub (config pribadi di ~/.config/sfixx-osint tidak tersentuh)
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/sfixx" update
