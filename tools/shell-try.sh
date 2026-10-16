#!/usr/bin/env bash
# Relanza el shell en la sesión abierta con variables de entorno extra y
# cuenta los errores de color. Ejemplos:
#   tools/shell-try.sh                          # tal cual
#   tools/shell-try.sh QML_DISABLE_DISK_CACHE=1
set -uo pipefail

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
export WH01S17_PATH=$HOME/.local/share/wh01s17 PATH="$HOME/.local/share/wh01s17/bin:$PATH"
[[ -n $HYPRLAND_INSTANCE_SIGNATURE ]] || { echo "No hay sesión de Hyprland abierta"; exit 1; }
hypr_env=$(tr '\0' '\n' <"/proc/$(pgrep -xo Hyprland)/environ" | grep -E '^(LIBGL_ALWAYS_SOFTWARE|QT_QPA_PLATFORMTHEME|DBUS_SESSION_BUS_ADDRESS)=' | tr '\n' ' ')

echo "== Equipo: $(nproc) CPU, $(free -m | awk '/Mem/{print $2}') MB · quickshell $(pacman -Q quickshell | cut -d' ' -f2) · qt $(pacman -Q qt6-declarative | cut -d' ' -f2)"
echo "== Caché QML: $(du -sh "$HOME/.cache/quickshell" 2>/dev/null | cut -f1)"
pkill -x quickshell 2>/dev/null
pkill -f wh01s17-launch-shell 2>/dev/null
sleep 1
# shellcheck disable=SC2086
env $hypr_env "$@" setsid wh01s17-launch-shell >/dev/null 2>&1 &
sleep 12
log=$(ls -t "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.log | head -1)
echo "== Con «${*:-nada extra}»: $(grep -c 'of undefined' "$log") errores de color"
grep -m3 -E 'of undefined|Color|Commons' "$log" | sed -E 's/^[0-9-]+ [0-9:.]+ +//' | cut -c1-150
