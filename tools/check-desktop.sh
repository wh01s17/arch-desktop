#!/usr/bin/env bash
# Pruebas del escritorio en el equipo real. Ejecútalo desde una terminal de la
# sesión gráfica (deja de usar el equipo mientras corre):
#
#   tools/check-desktop.sh                 paneles, bloqueo, brillo, volumen, monitores y apps
#   tools/check-desktop.sh --keys          además pide pulsar las teclas de brillo y volumen
#   tools/check-desktop.sh --suspend       además suspende y despierta solo (sudo)
#   tools/check-desktop.sh --hibernate     además hiberna y despierta solo (sudo; escribe la clave de LUKS)
#   tools/check-desktop.sh --only "panels lock"     sólo esas pruebas
#   tools/check-desktop.sh --apps "firefox typora"  apps a abrir (ids de los .desktop)
#
# Pruebas: panels lock brightness volume monitors apps keys suspend hibernate.
# Informe en ~/check-desktop.txt y capturas en ~/check-desktop/.
set -uo pipefail

APPS="firefox com.microsoft.VSCode obsidian spotify"
ONLY="panels lock brightness volume monitors apps"
EXTRA=""
while (($#)); do
  case $1 in
    --keys) EXTRA+=" keys" ;;
    --suspend) EXTRA+=" suspend" ;;
    --hibernate) EXTRA+=" hibernate" ;;
    --only) ONLY=$2; shift ;;
    --apps) APPS=$2; shift ;;
    -h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done
TESTS="$ONLY$EXTRA"

SHOTS="$HOME/check-desktop"
MARKER="$HOME/.local/state/wh01s17/check-desktop-hibernate"
mkdir -p "$SHOTS" "${MARKER%/*}"
exec > >(tee "$HOME/check-desktop.txt") 2>&1

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)}
export WH01S17_PATH=${WH01S17_PATH:-$HOME/.local/share/wh01s17}
export PATH="$WH01S17_PATH/bin:$PATH"

passed=0 failed=0
ok() { printf '  ok    %s\n' "$*"; ((passed++)); }
bad() { printf '  FALLA %s\n' "$*"; ((failed++)); }
info() { printf '        %s\n' "$*"; }
wants() { [[ " $TESTS " == *" $1 "* ]]; }

hyprctl version >/dev/null 2>&1 || { echo "Ejecútalo dentro de la sesión de Hyprland."; exit 1; }

shell_log() { ls -t "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.log 2>/dev/null | head -1; }
# Errores QML del registro del shell (se comparan antes y después de cada acción).
qml_errors() {
  local log; log=$(shell_log)
  [[ -n $log ]] || { echo 0; return; }
  grep -cE 'TypeError|ReferenceError|of undefined|Unable to assign|is not a function' "$log"
}
shell_alive() { pgrep -x quickshell >/dev/null && wh01s17-shell shell ping >/dev/null 2>&1; }
shot() { grim "$SHOTS/$1.png" 2>/dev/null; }
since_errors() { # since_errors ANTES DESCRIPCIÓN
  local now; now=$(qml_errors)
  if ((now > $1)); then bad "$2: $((now - $1)) errores QML nuevos (tools/shell-log.sh)"; else ok "$2"; fi
}
lock_field() { wh01s17-shell lock status 2>/dev/null | jq -r ".$1" 2>/dev/null; }
journal_since() { journalctl --since "@$1" --no-pager -o cat -q 2>/dev/null; }

echo "== Pruebas: $TESTS"
info "$(date '+%F %T') · $(cat /sys/class/dmi/id/product_name 2>/dev/null)"

# Una hibernación anterior que no volvió deja la marca con otro arranque.
if [[ -f $MARKER ]]; then
  if [[ $(cat "$MARKER") != "$(cat /proc/sys/kernel/random/boot_id)" ]]; then
    echo "== Hibernación anterior"
    bad "el equipo arrancó de cero en vez de restaurar la sesión"
    journalctl -b -1 --no-pager -o cat 2>/dev/null | grep -iE 'hibernat|PM: |resume' | tail -8 | cut -c1-150 | sed 's/^/        /'
  fi
  rm -f "$MARKER"
fi

if wants panels; then
  echo "== Shell y paneles"
  if shell_alive; then ok "el shell responde"; else bad "el shell no responde"; fi
  plugins=$(wh01s17-shell shell listPlugins 2>/dev/null)
  for id in core.menu core.clock core.audio core.network core.bluetooth core.power core.monitor core.clipboard; do
    if [[ -n $plugins && $plugins != *"\"$id\""* ]]; then info "$id no está activo; se omite"; continue; fi
    before=$(qml_errors)
    payload='{}'; [[ $id == core.menu ]] && payload='{"menu":"root"}'
    wh01s17-shell shell toggle "$id" "$payload" >/dev/null 2>&1
    sleep 1.5
    shot "panel-${id#core.}"
    wh01s17-shell shell hide "$id" >/dev/null 2>&1
    sleep 0.5
    since_errors "$before" "panel ${id#core.}"
  done
  shell_alive || bad "el shell se cayó al abrir los paneles"
fi

if wants lock; then
  echo "== Bloqueo de pantalla"
  before=$(qml_errors)
  wh01s17-system-lock >/dev/null 2>&1
  for _ in $(seq 20); do [[ $(lock_field locked) == true ]] && break; sleep 0.5; done
  if [[ $(lock_field locked) == true ]]; then
    ok "la pantalla se bloqueó"
    # `locked` se marca al pedirlo; `secure`, cuando Hyprland confirma que cubrió todas las pantallas.
    for _ in $(seq 20); do [[ $(lock_field secure) == true ]] && break; sleep 0.5; done
    [[ $(lock_field secure) == true ]] && ok "bloqueo seguro (ext-session-lock)" || bad "el bloqueo no es seguro tras 10 s"
    [[ $(lock_field passwordPam) == true ]] && ok "PAM configurado para la contraseña" || bad "PAM sin configurar"
    echo "        >>> Desbloquea con tu contraseña (tienes 2 minutos)"
    for _ in $(seq 240); do [[ $(lock_field locked) == false ]] && break; sleep 0.5; done
    [[ $(lock_field locked) == false ]] && ok "se desbloqueó con la contraseña" || bad "no se desbloqueó en 2 minutos"
  else
    bad "la pantalla no se bloqueó ($(wh01s17-shell lock status 2>&1 | cut -c1-120))"
  fi
  since_errors "$before" "pantalla de bloqueo sin errores"
fi

if wants brightness; then
  echo "== Brillo"
  if dev=$(brightnessctl -l -c backlight -m 2>/dev/null | head -1 | cut -d, -f1) && [[ -n $dev ]]; then
    start=$(brightnessctl -d "$dev" get)
    brightnessctl -d "$dev" -q set 10%-
    sleep 0.3
    after=$(brightnessctl -d "$dev" get)
    brightnessctl -d "$dev" -q set "$start"
    ((after != start)) && ok "el brillo cambia ($dev: $start → $after, restaurado)" || bad "el brillo no cambia ($dev)"
  else
    info "sin control de brillo (pantalla externa o equipo de escritorio)"
  fi
fi

volume() { pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d %; }
muted() { pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}'; }
if wants volume; then
  echo "== Volumen"
  start=$(volume)
  if [[ -n $start ]]; then
    wh01s17-audio-output-volume -5 >/dev/null 2>&1
    sleep 0.3
    after=$(volume)
    pactl set-sink-volume @DEFAULT_SINK@ "$start%"
    [[ $after != "$start" ]] && ok "el volumen cambia ($start% → $after%, restaurado)" || bad "el volumen no cambia"
    info "salida: $(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -m1 'node.description' | sed 's/.*= //')"
  else
    bad "no hay salida de audio por defecto"
  fi
fi

if wants keys; then
  echo "== Teclas (pulsa cada una cuando se pida; 10 s por tecla)"
  wait_change() { # wait_change COMANDO_LECTURA DESCRIPCIÓN up|down|yes
    local first now
    sleep 1 # que termine de aplicarse la tecla anterior
    first=$($1)
    echo "        >>> Pulsa una vez: $2"
    for _ in $(seq 40); do
      now=$($1)
      if [[ $now != "$first" ]]; then
        case $3 in
          up) ((now > first)) ;;
          down) ((now < first)) ;;
          *) [[ $now == "$3" ]] ;;
        esac && ok "$2 ($first → $now)" || bad "$2: cambió al revés ($first → $now)"
        return
      fi
      sleep 0.25
    done
    bad "$2: no hubo cambio"
  }
  dev=$(brightnessctl -l -c backlight -m 2>/dev/null | head -1 | cut -d, -f1)
  if [[ -n $dev ]]; then
    bright() { brightnessctl -d "$dev" get; }
    start=$(bright)
    wait_change bright "BAJAR brillo" down
    wait_change bright "SUBIR brillo" up
    brightnessctl -d "$dev" -q set "$start"
  fi
  start=$(volume)
  wait_change volume "BAJAR volumen" down
  wait_change volume "SUBIR volumen" up
  wait_change muted "SILENCIAR" yes
  [[ $(muted) == yes ]] && pactl set-sink-mute @DEFAULT_SINK@ 0
  pactl set-sink-volume @DEFAULT_SINK@ "$start%"
fi

if wants monitors; then
  echo "== Monitores"
  active=$(hyprctl monitors -j | jq -r '.[].name')
  for status in /sys/class/drm/card*-*/status; do
    [[ $(cat "$status") == connected ]] || continue
    name=${status%/status}; name=${name##*/}; name=${name#card*-}
    if grep -qx "$name" <<<"$active"; then
      ok "$name conectado y en uso ($(hyprctl monitors -j | jq -r ".[] | select(.name==\"$name\") | \"\(.width)x\(.height)@\(.refreshRate|floor) escala \(.scale)\""))"
    else
      bad "$name conectado pero Hyprland no lo usa"
    fi
  done
  [[ $active == *HDMI* || $active == *DP-* ]] || info "conecta el proyector o un monitor y vuelve a ejecutar «--only monitors»"
  shot monitores
fi

if wants apps; then
  echo "== Aplicaciones"
  addresses() { hyprctl clients -j | jq -r '.[].address' | sort; }
  class_of() { hyprctl clients -j | jq -r ".[] | select(.address==\"$1\") | .class"; }
  for app in $APPS; do
    desktop=""
    for dir in "$HOME/.local/share/applications" /usr/share/applications; do
      [[ -f $dir/$app.desktop ]] && { desktop=$dir/$app.desktop; break; }
    done
    [[ -n $desktop ]] || { info "$app: no hay $app.desktop; se omite"; continue; }
    before=$(addresses)
    setsid gtk-launch "$app" >/dev/null 2>&1 &
    new=""
    for _ in $(seq 60); do
      new=$(comm -13 <(echo "$before") <(addresses) | head -1)
      [[ -n $new ]] && break
      sleep 0.5
    done
    if [[ -n $new ]]; then
      sleep 2
      shot "app-$app"
      ok "$app abrió una ventana ($(class_of "$new"))"
      hyprctl dispatch closewindow "address:$new" >/dev/null 2>&1
    else
      bad "$app no abrió ninguna ventana en 30 s"
    fi
  done
fi

sleep_test() { # sleep_test suspend|hibernate SEGUNDOS PATRÓN_DEL_KERNEL
  local mode=$1 delay=$2 pattern=$3 start
  sudo -v || { bad "$mode: hace falta sudo para programar el despertador"; return; }
  echo "        >>> No toques el teclado ni el touchpad hasta que vuelva (los Ryzen despiertan con ellos)"
  sleep 5
  sync
  start=$(date +%s)
  sudo rtcwake -m no -s "$delay" >/dev/null || { bad "$mode: no se pudo programar el despertador (rtcwake)"; return; }
  info "el equipo despertará solo en ${delay}s"
  systemctl "$mode" || { bad "$mode: systemctl $mode falló"; return; }
  for _ in $(seq 600); do
    journal_since "$start" | grep -qE "$pattern" && break
    sleep 1
  done
  local elapsed=$(( $(date +%s) - start )) locked_now
  locked_now=$(lock_field locked)
  if journal_since "$start" | grep -qE "$pattern"; then
    if ((elapsed + 3 < delay)); then
      bad "$mode: despertó antes del despertador (${elapsed}s de ${delay}s; IRQ de despertar: $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo '?'))"
    else
      ok "$mode y vuelta (${elapsed}s)"
    fi
  else
    bad "$mode: no se ve la vuelta en el journal"
  fi
  [[ $mode == suspend ]] && info "modo de suspensión: $(cat /sys/power/mem_sleep)"
  sleep 8
  shell_alive && ok "el shell sigue vivo" || bad "el shell no responde tras $mode"
  [[ $(nmcli -t -f STATE general 2>/dev/null) == connected* ]] && ok "red reconectada" || bad "sin red tras $mode ($(nmcli -t -f STATE general))"
  [[ $locked_now == true ]] && ok "pantalla bloqueada al volver (desbloquéala)" || bad "la pantalla no estaba bloqueada al volver"
  journal_since "$start" | grep -iE 'error|fail' | grep -viE 'ACPI|firmware bug|IPv4 forwarding|dbus-monitor|pam message|ring init command' | awk '!seen[$0]++' | head -6 | cut -c1-150 | sed 's/^/        /'
}

if wants suspend; then
  echo "== Suspender"
  sleep_test suspend 25 'PM: suspend exit'
fi

if wants hibernate; then
  echo "== Hibernar"
  if ! grep -qw disk /sys/power/state || ! grep -q 'resume=' /proc/cmdline; then
    bad "la hibernación no está configurada (resume= o /sys/power/state)"
  else
    echo "        >>> Al volver, Limine pedirá la clave de LUKS: escríbela y la sesión debe restaurarse"
    cat /proc/sys/kernel/random/boot_id >"$MARKER"
    sleep_test hibernate 45 'PM: hibernation: hibernation exit|PM: Image restored|Restarting tasks'
    rm -f "$MARKER"
  fi
fi

echo
echo "== Resultado: $passed ok, $failed fallas"
echo "Informe en ~/check-desktop.txt · capturas en ~/check-desktop/"
