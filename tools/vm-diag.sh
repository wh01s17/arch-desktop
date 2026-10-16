#!/usr/bin/env bash
# Diagnóstico cuando Hyprland arranca pero el shell (barra, fondo) no aparece
# o la terminal se cierra sola. Ejecútalo desde una TTY (Ctrl derecho + F3 en
# VirtualBox) con la sesión gráfica abierta:  tools/vm-diag.sh
# Prueba varias formas de dibujar, deja funcionando la mejor y guarda el
# detalle en ~/vm-diag.txt.
set -uo pipefail

report="$HOME/vm-diag.txt"
exec > >(tee "$report") 2>&1

runtime=""
for name in wh01s17 omarchy; do
  [[ -d $HOME/.local/share/$name/bin ]] && { runtime=$name; break; }
done
[[ -n $runtime ]] || { echo "No encuentro ~/.local/share/{wh01s17,omarchy}"; exit 1; }
upper=${runtime^^}

echo "== Runtime: $runtime"
echo "== GPU y driver"
lspci -k 2>/dev/null | grep -A2 -iE 'vga|3d|display' | grep -E 'VGA|3D|driver' | sed 's/^/   /'

export XDG_RUNTIME_DIR=/run/user/$(id -u)
signature=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
if [[ -z $signature ]]; then
  echo "== No hay una sesión de Hyprland abierta; inicia sesión gráfica y vuelve a probar."
  exit 1
fi
export HYPRLAND_INSTANCE_SIGNATURE=$signature
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
export "${upper}_PATH=$HOME/.local/share/$runtime" PATH="$HOME/.local/share/$runtime/bin:$PATH"
unset QT_QUICK_BACKEND LIBGL_ALWAYS_SOFTWARE

declare -A score=()
try_shell() { # try_shell ETIQUETA VAR=VALOR…
  local label=$1 log errors
  shift
  pkill -x quickshell 2>/dev/null
  pkill -f "$runtime-launch-shell" 2>/dev/null
  sleep 1
  env "$@" setsid "$runtime-launch-shell" >/dev/null 2>&1 &
  sleep 10
  if ! { pgrep -x quickshell >/dev/null && hyprctl layers 2>/dev/null | grep -q "$runtime-bar"; }; then
    echo "== Shell «$label»: falla"
    return
  fi
  log=$(ls -t "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.log 2>/dev/null | head -1)
  errors=$(grep -c 'TypeError: Cannot read property' "$log" 2>/dev/null)
  echo "== Shell «$label»: arranca, $errors errores de QML"
  score[$label]=$errors
}

try_shell "normal" DUMMY=1
try_shell "OpenGL por CPU" LIBGL_ALWAYS_SOFTWARE=1
try_shell "Qt por software" QT_QUICK_BACKEND=software

best="" best_errors=""
for label in "${!score[@]}"; do
  value=${score[$label]}
  if [[ -z $best_errors ]] || ((value < best_errors)); then
    best=$label best_errors=$value
  fi
done

for mode in normal cpu; do
  if [[ $mode == cpu ]]; then flags=(LIBGL_ALWAYS_SOFTWARE=1); else flags=(DUMMY=1); fi
  if timeout 6 env "${flags[@]}" kitty sh -c 'sleep 2' >/dev/null 2>&1 || [[ $? == 124 ]]; then
    echo "== Kitty ($mode): abre"
  else
    echo "== Kitty ($mode): se cierra con error"
  fi
done

case $best in
  "normal") args=(DUMMY=1) ;;
  "OpenGL por CPU") args=(LIBGL_ALWAYS_SOFTWARE=1) ;;
  "Qt por software") args=(QT_QUICK_BACKEND=software) ;;
  *) echo "== Ninguna forma funcionó. Detalle: $report"; exit 1 ;;
esac
pkill -x quickshell 2>/dev/null
pkill -f "$runtime-launch-shell" 2>/dev/null
sleep 1
env "${args[@]}" setsid "$runtime-launch-shell" >/dev/null 2>&1 &
echo "== Mejor: «$best» (queda funcionando). Ctrl derecho + F1 para verlo. Detalle: $report"
