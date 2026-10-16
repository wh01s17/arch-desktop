#!/usr/bin/env bash
# Arranque del shell en bruto (sin el ruido repetido) y estado del tema.
#   tools/shell-log.sh [LÍNEAS]       (registro completo en ~/shell-log.txt)
set -uo pipefail

lines=${1:-40}
log=$(ls -t /run/user/$(id -u)/quickshell/by-id/*/log.log 2>/dev/null | head -1)
[[ -n $log ]] || { echo "No hay registro de Quickshell"; exit 1; }
cp "$log" "$HOME/shell-log.txt"

theme="$HOME/.local/state/wh01s17/current"
echo "== Tema: $(cat "$theme/theme.name" 2>/dev/null || echo 'SIN theme.name')"
echo "   $(ls "$theme/theme" 2>/dev/null | grep -cE '\.toml$') archivos .toml en current/theme; shell.toml: $(test -s "$theme/theme/shell.toml" && echo sí || echo NO)"
echo "== Primeras $lines líneas del shell (sin repeticiones)"
grep -vE 'pluginBarApiFor|QQmlVMEMetaObject|Failed to open channel' "$log" |
  sed -E -e 's/0x[0-9a-f]+//g' -e 's#file://[^ ]*/(plugins|shell|Ui|Commons)/#\1/#g' -e 's#/home/[^/]+/#~/#g' |
  awk '!seen[$0]++' | head -n "$lines" | cut -c1-165
