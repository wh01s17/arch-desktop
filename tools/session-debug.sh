#!/usr/bin/env bash
# Primeros errores del shell, entorno real de la sesión y prueba de la
# terminal (Super+Enter). Ejecútalo desde una TTY con la sesión gráfica
# abierta:  tools/session-debug.sh      (detalle en ~/session-debug.txt)
set -uo pipefail

exec > >(tee "$HOME/session-debug.txt") 2>&1
export XDG_RUNTIME_DIR=/run/user/$(id -u)

echo "== Entorno de Hyprland (sesión real)"
hypr_pid=$(pgrep -xo Hyprland || pgrep -o -f 'Hyprland' || true)
if [[ -n $hypr_pid ]]; then
  tr '\0' '\n' <"/proc/$hypr_pid/environ" |
    grep -E '^(WH01S17_PATH|QT_[A-Z_]+|LIBGL[A-Z_]*|XDG_CURRENT_DESKTOP|TERMINAL|XCURSOR_THEME|PATH)=' | cut -c1-150 | sed 's/^/   /'
else
  echo "   Hyprland no está corriendo"
fi

echo "== Primeros avisos del shell (en orden, sin repetir)"
log=$(ls -t "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.log 2>/dev/null | head -1)
if [[ -n $log ]]; then
  grep -E 'WARN|ERROR|CRIT' "$log" | grep -v pluginBarApiFor |
    sed -E -e 's/^.{0,40}(WARN|ERROR|CRIT)/\1/' -e 's/0x[0-9a-f]+//g' -e 's#file://[^ ]*/(plugins|shell|Ui|Commons)/#\1/#g' |
    awk '!seen[$0]++' | head -14 | cut -c1-170 | sed 's/^/   /'
else
  echo "   No hay registro de Quickshell"
fi

echo "== Terminal (lo mismo que Super+Enter)"
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
export WH01S17_PATH=$HOME/.local/share/wh01s17 PATH="$HOME/.local/share/wh01s17/bin:$PATH"
echo "   xdg-terminal-exec: $(command -v xdg-terminal-exec || echo 'NO INSTALADO')"
echo "   xdg-terminals.list: $(grep -v '^#' "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -1)"
timeout 6 xdg-terminal-exec sh -c 'sleep 3' >/tmp/term-test.log 2>&1
echo "   código de salida: $? (124 = se mantuvo abierta, bien)"
head -5 /tmp/term-test.log | cut -c1-160 | sed 's/^/   /'
timeout 6 kitty zsh -ic 'sleep 3' >/tmp/zsh-test.log 2>&1
echo "   kitty + zsh: código $? (124 = bien)"
grep -v '^$' /tmp/zsh-test.log | head -5 | cut -c1-160 | sed 's/^/   /'
