#!/usr/bin/env bash
# Captura el estado de referencia del escritorio Omarchy actual (Fase 0 de
# PLAN.md): atajos, opciones de Hyprland, paquetes, servicios, arranque y
# btrfs. Ejecutar dentro de la sesión de Hyprland, antes de reinstalar.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
out_dir="$script_dir/../reference"
dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
use_sudo=true
keep_uuids=false

usage() {
  cat <<'EOF'
Uso: tools/capture-reference.sh [--out DIR] [--no-sudo] [--keep-uuids]

Escribe en reference/ (o DIR) la referencia del escritorio actual:
  binds.json            atajos efectivos (hyprctl binds -j)
  binds.tsv             atajos legibles: combinación, opciones y descripción
  options.tsv           valores efectivos de opciones de Hyprland
  animations.json       animaciones efectivas
  packages.tsv          paquetes explícitos con su repositorio de origen
  services.txt          unidades habilitadas del sistema y del usuario
  config-unmanaged.txt  entradas de ~/.config que no enlazan a ~/dotfiles
  omarchy-commands.txt  comandos omarchy usados por ~/dotfiles
  shell-layout.json     barra, idle y plugins de shell.json
  system.txt            versiones, modelo, GPU, pantallas y entrada
  boot.txt              cmdline, mkinitcpio, modprobe y limine.conf (sudo)
  btrfs.txt             subvolúmenes, montajes, fstab y swap (sudo)

--no-sudo     omite lo que requiere sudo (btrfs.txt y limine.conf)
--keep-uuids  no oculta UUID/PARTUUID (por defecto se reemplazan)

Variables: DOTFILES_DIR (por defecto ~/dotfiles).
EOF
}

while (($#)); do
  case "$1" in
    --out)
      (($# >= 2)) || { echo '--out requiere un directorio' >&2; exit 2; }
      out_dir=$2
      shift
      ;;
    --no-sudo) use_sudo=false ;;
    --keep-uuids) keep_uuids=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '==> %s\n' "$1"; }
warn() { printf '[!] %s\n' "$1" >&2; }

[[ $EUID -ne 0 ]] || { echo 'Ejecuta el script como usuario normal.' >&2; exit 1; }
for tool in hyprctl jq pacman systemctl; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'Falta %s\n' "$tool" >&2; exit 1; }
done
hyprctl version -j >/dev/null 2>&1 ||
  { echo 'No hay una sesión de Hyprland activa; ejecuta el script dentro de ella.' >&2; exit 1; }
if [[ $use_sudo == true ]] && ! sudo -v; then
  warn 'Sin sudo: se omiten btrfs.txt y limine.conf.'
  use_sudo=false
fi

mkdir -p "$out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"

# UUIDs are not secrets, but this repository is public: hide them by default.
redact() {
  if [[ $keep_uuids == true ]]; then
    cat
  else
    sed -E -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g' \
      -e 's/(UUID=)[0-9A-Fa-f-]+/\1<UUID>/g'
  fi
}

section() { printf '\n## %s\n' "$1"; }

capture_binds() {
  log 'Atajos de Hyprland'
  hyprctl binds -j | jq 'sort_by(.modmask, .key, .keycode)' >"$out_dir/binds.json"
  # modmask: SHIFT=1 CAPS=2 CTRL=4 ALT=8 MOD2=16 MOD3=32 SUPER=64 MOD5=128.
  jq -r '
    def mods: [ (if (.modmask / 64 | floor) % 2 == 1 then "SUPER" else empty end),
                (if (.modmask / 4  | floor) % 2 == 1 then "CTRL"  else empty end),
                (if (.modmask / 8  | floor) % 2 == 1 then "ALT"   else empty end),
                (if .modmask % 2 == 1 then "SHIFT" else empty end) ];
    def flags: [ (if .locked then "locked" else empty end),
                 (if .release then "release" else empty end),
                 (if .repeat then "repeat" else empty end),
                 (if .mouse then "mouse" else empty end) ] | join(",");
    ["combinacion", "opciones", "descripcion"],
    (.[] | [ (mods + [ if .key != "" then .key else "code:\(.keycode)" end ] | join(" + ")),
             flags, .description ])
    | @tsv' "$out_dir/binds.json" >"$out_dir/binds.tsv"
  printf '    %s atajos\n' "$(jq length "$out_dir/binds.json")"
}

capture_options() {
  log 'Opciones efectivas de Hyprland'
  local option value
  local -a options=(
    general:gaps_in general:gaps_out general:border_size general:layout
    general:col.active_border general:col.inactive_border general:resize_on_border
    general:allow_tearing general:snap:enabled
    decoration:rounding decoration:rounding_power decoration:active_opacity
    decoration:inactive_opacity decoration:dim_inactive
    decoration:blur:enabled decoration:blur:size decoration:blur:passes
    decoration:blur:ignore_opacity decoration:blur:new_optimizations decoration:blur:xray
    decoration:blur:special decoration:blur:popups
    decoration:shadow:enabled decoration:shadow:range decoration:shadow:render_power
    decoration:shadow:color decoration:shadow:color_inactive
    group:col.border_active group:col.border_inactive
    group:groupbar:enabled group:groupbar:font_size group:groupbar:height
    animations:enabled
    input:kb_layout input:kb_variant input:kb_model input:kb_options input:kb_rules
    input:numlock_by_default input:repeat_rate input:repeat_delay input:sensitivity
    input:accel_profile input:follow_mouse input:natural_scroll
    input:touchpad:natural_scroll input:touchpad:scroll_factor
    input:touchpad:disable_while_typing input:touchpad:tap-to-click
    input:touchpad:clickfinger_behavior input:tablet:output
    gestures:workspace_swipe_distance
    dwindle:preserve_split dwindle:force_split dwindle:smart_split
    master:new_status master:mfact
    layout:single_window_aspect_ratio
    misc:disable_hyprland_logo misc:disable_splash_rendering misc:force_default_wallpaper
    misc:focus_on_activate misc:mouse_move_enables_dpms misc:key_press_enables_dpms
    misc:anr_missed_pings misc:vrr
    cursor:no_hardware_cursors cursor:hide_on_key_press cursor:inactive_timeout
    cursor:zoom_factor cursor:warp_on_change_workspace
    xwayland:enabled xwayland:force_zero_scaling
    binds:workspace_back_and_forth binds:allow_workspace_cycles
    ecosystem:no_update_news ecosystem:no_donation_nag
    render:direct_scanout
  )
  {
    printf 'opcion\tvalor\n'
    for option in "${options[@]}"; do
      if value="$(hyprctl getoption "$option" -j 2>/dev/null |
        jq -r 'del(.option, .set) | to_entries[0].value | tostring' 2>/dev/null)"; then
        printf '%s\t%s\n' "$option" "$value"
      else
        printf '%s\t<no existe>\n' "$option"
      fi
    done
  } >"$out_dir/options.tsv"
  hyprctl animations -j >"$out_dir/animations.json"
  local missing
  missing="$(grep -c $'\t<no existe>$' "$out_dir/options.tsv" || true)"
  [[ $missing == 0 ]] || warn "$missing opciones no existen en esta versión; revisa options.tsv."
}

capture_packages() {
  log 'Paquetes explícitos y su origen'
  local -A repo_of=()
  local repo name _
  while read -r repo name _; do
    [[ -n ${repo_of[$name]:-} ]] || repo_of[$name]=$repo
  done < <(pacman -Sl 2>/dev/null)

  local -A explicit_deps=()
  while read -r name; do explicit_deps[$name]=1; done < <(pacman -Qqe)

  {
    printf 'paquete\tversion\torigen\n'
    while read -r name version; do
      [[ -n ${explicit_deps[$name]:-} ]] || continue
      printf '%s\t%s\t%s\n' "$name" "$version" "${repo_of[$name]:-aur/local}"
    done < <(pacman -Q)
  } >"$out_dir/packages.tsv"
  awk -F'\t' 'NR > 1 { n[$3]++ } END { for (r in n) printf "    %-10s %d\n", r, n[r] }' \
    "$out_dir/packages.tsv" | sort
}

capture_services() {
  log 'Servicios habilitados'
  {
    section 'Sistema'
    systemctl list-unit-files --state=enabled --no-legend --no-pager | awk '{print $1}'
    section 'Usuario'
    systemctl --user list-unit-files --state=enabled --no-legend --no-pager | awk '{print $1}'
    section 'Timers activos del usuario'
    systemctl --user list-timers --all --no-legend --no-pager | awk '{print $(NF-1)}'
  } >"$out_dir/services.txt"
}

capture_unmanaged_config() {
  log 'Configuración fuera de ~/dotfiles'
  local entry target
  {
    printf '# Entradas de ~/.config que no son enlaces a %s.\n' "$dotfiles_dir"
    printf '# "*" indica un directorio que contiene enlaces a dotfiles (Stow desplegado).\n'
    for entry in "$HOME"/.config/* "$HOME"/.config/.[!.]*; do
      [[ -e $entry || -L $entry ]] || continue
      case "$entry" in *.bak|*.bak.*|*.omarchy-upgrade-*|*.pacnew) continue ;; esac
      if [[ -L $entry ]]; then
        target="$(readlink -f -- "$entry")"
        [[ $target == "$dotfiles_dir"/* ]] && continue
      fi
      if [[ -d $entry ]] && find "$entry" -maxdepth 2 -type l -lname "*dotfiles*" -print -quit | grep -q .; then
        printf '%s*\n' "${entry#"$HOME"/}"
      else
        printf '%s\n' "${entry#"$HOME"/}"
      fi
    done
  } >"$out_dir/config-unmanaged.txt"
}

capture_omarchy_commands() {
  log 'Comandos omarchy usados por los dotfiles'
  if [[ ! -d $dotfiles_dir ]]; then
    warn "No existe $dotfiles_dir; se omite omarchy-commands.txt."
    return
  fi
  {
    printf 'usos\tcomando\n'
    # Only your own config: platform/ is the frozen Omarchy copy itself.
    grep -rhoIE --exclude-dir=.git --exclude-dir=platform \
      'omarchy(-[a-z0-9]+)+|omarchy [a-z]+( [a-z-]+)?' "$dotfiles_dir" |
      sort | uniq -c | sort -rn | awk '{c=$1; $1=""; sub(/^ /, ""); printf "%s\t%s\n", c, $0}'
  } >"$out_dir/omarchy-commands.txt"
  printf '    %s comandos distintos\n' "$(($(wc -l <"$out_dir/omarchy-commands.txt") - 1))"
}

capture_shell_layout() {
  local shell_json="$HOME/.config/omarchy/shell.json"
  [[ -f $shell_json ]] || { warn 'No existe shell.json; se omite shell-layout.json.'; return; }
  log 'Distribución de Omarchy Shell'
  jq '{bar, idle, plugins, disabledPlugins}' "$shell_json" >"$out_dir/shell-layout.json"
}

capture_system() {
  log 'Sistema y hardware'
  local file
  {
    section 'Versiones'
    printf 'omarchy: %s\n' "$(omarchy version 2>/dev/null || echo 'no disponible')"
    hyprctl version -j | jq -r '"hyprland: \(.tag) (\(.commit[0:12]))"'
    printf 'quickshell: %s\n' "$(pacman -Q quickshell 2>/dev/null | cut -d' ' -f2)"
    printf 'kernel: %s\n' "$(uname -r)"
    section 'Equipo'
    for file in sys_vendor product_name product_version board_name chassis_type; do
      printf '%s: %s\n' "$file" "$(cat "/sys/class/dmi/id/$file" 2>/dev/null || echo '?')"
    done
    printf 'virtualizacion: %s\n' "$(systemd-detect-virt 2>/dev/null || true)"
    printf 'bateria: %s\n' "$(compgen -G '/sys/class/power_supply/BAT*' >/dev/null && echo si || echo no)"
    printf 'retroiluminacion: %s\n' "$(ls /sys/class/backlight 2>/dev/null | tr '\n' ' ')"
    section 'GPU'
    lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || echo 'lspci no disponible'
    section 'Pantallas (Hyprland)'
    hyprctl monitors all -j | jq -r '.[] |
      "\(.name)\t\(.width)x\(.height)@\(.refreshRate)\tpos=\(.x)x\(.y)\tscale=\(.scale)\tdisabled=\(.disabled)\t\(.make) \(.model)"'
    section 'Dispositivos de entrada'
    hyprctl devices -j | jq -r '
      (.keyboards[] | "teclado\t\(.name)\t\(.layout)/\(.variant)\t\(.options)"),
      (.mice[] | "puntero\t\(.name)"),
      (.tablets[]? | "tableta\t\(.name // .type // "?")")'
    # Layout, arrangement and modes chosen in the Display panel override the profile.
    for file in "$HOME"/.local/state/omarchy/monitor-*.conf; do
      [[ -f $file ]] || continue
      section "${file#"$HOME"/}"
      cat "$file"
    done
    file="$HOME/.local/state/omarchy/monitor-scaling.log"
    if [[ -f $file ]]; then
      section 'Última escala pedida por salida (monitor-scaling.log)'
      awk -F'\t' '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
                    last[f["monitor"]] = f["requested"] }
                  END { for (m in last) printf "%s\t%s\n", m, last[m] }' "$file" | sort
    fi
  } >"$out_dir/system.txt"
}

capture_boot() {
  log 'Arranque'
  local file
  {
    section 'cmdline'
    cat /proc/cmdline
    for file in /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf /etc/modprobe.d/*.conf; do
      [[ -f $file ]] || continue
      section "$file"
      grep -vE '^\s*(#|$)' "$file" || true
    done
    section '/boot/limine.conf'
    if [[ $use_sudo == true ]]; then
      sudo cat /boot/limine.conf 2>/dev/null || echo 'no encontrado'
    else
      echo 'omitido (--no-sudo)'
    fi
  } | redact >"$out_dir/boot.txt"
}

capture_btrfs() {
  [[ $use_sudo == true ]] || return 0
  log 'btrfs, montajes y swap'
  {
    section 'Subvolúmenes'
    sudo btrfs subvolume list / 2>/dev/null || echo 'no disponible'
    section 'Montajes btrfs'
    findmnt -t btrfs -o TARGET,SOURCE,OPTIONS
    section '/etc/fstab'
    grep -vE '^\s*(#|$)' /etc/fstab
    section 'Swap'
    swapon --show
    section 'Snapper'
    ls /etc/snapper/configs 2>/dev/null || echo 'sin configuraciones'
  } | redact >"$out_dir/btrfs.txt"
}

capture_binds
capture_options
capture_packages
capture_services
capture_unmanaged_config
capture_omarchy_commands
capture_shell_layout
capture_system
capture_boot
capture_btrfs

printf '\nReferencia guardada en %s\n' "$out_dir"
echo 'Pendiente manual: capturas de pantalla (barra, paneles, menú, bloqueo) con grim.'
