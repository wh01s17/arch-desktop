#!/usr/bin/env bash
# Diagnóstico cuando Hyprland arranca pero el shell (barra, fondo) no aparece.
# Ejecútalo desde una TTY (Ctrl derecho + F3 en VirtualBox) con la sesión
# gráfica abierta:  tools/vm-diag.sh
# Deja el detalle completo en ~/vm-diag.txt.
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
ls /dev/dri 2>/dev/null | tr '\n' ' ' | sed 's/^/   \/dev\/dri: /'; echo
journalctl -b -k 2>/dev/null | grep -iE 'vmwgfx.*(3d|opengl|gl )|vmwgfx.*disabl' | tail -3 | sed 's/^/   /'

echo "== Errores del shell en este arranque"
journalctl --user -b -t "$runtime-shell" 2>/dev/null |
  grep -iE 'fatal|egl|opengl|rhi|vulkan|dmabuf|giving up|failed to create' | head -8 | cut -c1-160 | sed 's/^/   /'

export XDG_RUNTIME_DIR=/run/user/$(id -u)
signature=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
if [[ -z $signature ]]; then
  echo "== No hay una sesión de Hyprland abierta; inicia sesión gráfica y vuelve a probar."
  exit 1
fi
export HYPRLAND_INSTANCE_SIGNATURE=$signature
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
export "${upper}_PATH=$HOME/.local/share/$runtime" PATH="$HOME/.local/share/$runtime/bin:$PATH"

try_shell() { # try_shell ETIQUETA VAR=VALOR…
  local label=$1
  shift
  pkill -x quickshell 2>/dev/null
  pkill -f "$runtime-launch-shell" 2>/dev/null
  sleep 1
  env "$@" setsid "$runtime-launch-shell" >/dev/null 2>&1 &
  sleep 8
  if pgrep -x quickshell >/dev/null && hyprctl layers 2>/dev/null | grep -q "$runtime-bar"; then
    echo "== Prueba «$label»: FUNCIONA (barra visible)"
    return 0
  fi
  echo "== Prueba «$label»: falla"
  return 1
}

try_shell "normal" DUMMY=1 ||
  try_shell "renderizado por software" QT_QUICK_BACKEND=software ||
  try_shell "software sin dmabuf" QT_QUICK_BACKEND=software QT_WAYLAND_DISABLE_DMABUF=1

echo "== Vuelve a la pantalla gráfica con Ctrl derecho + F1 (o F2). Detalle: $report"
