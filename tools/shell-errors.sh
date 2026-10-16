#!/usr/bin/env bash
# Resumen de los avisos del shell en este arranque (plugins que no cargan,
# errores de QML). Cabe en una pantalla:  tools/shell-errors.sh
# El registro completo queda en ~/shell-errors.txt.
set -uo pipefail

tag=wh01s17-shell
journalctl --user -b -t "$tag" --no-pager -o cat >"$HOME/shell-errors.txt" 2>&1

echo "== Plugins rechazados o que no cargan"
grep -iE 'rejected|failed to load|plugin .*(error|fail)|not found|is not installed|no such' "$HOME/shell-errors.txt" |
  sed -E 's/0x[0-9a-f]+//g' | sort | uniq -c | sort -rn | head -12 | cut -c1-170

echo "== Errores de QML (los más frecuentes)"
grep -E 'TypeError|ReferenceError|SyntaxError|Cannot assign|is not a type|module .* not installed|Unable to' "$HOME/shell-errors.txt" |
  grep -v pluginBarApiFor |
  sed -E -e 's/0x[0-9a-f]+//g' -e 's#file://[^ ]*/(plugins|shell)/#\1/#' | sort | uniq -c | sort -rn | head -12 | cut -c1-170

echo "== Arranques del shell: $(grep -c 'Starting\|Launching' "$HOME/shell-errors.txt") · reinicios: $(grep -c 'relaunching' "$HOME/shell-errors.txt")"
