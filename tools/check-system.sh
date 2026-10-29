#!/usr/bin/env bash
# Revisión del sistema instalado (sólo lectura). Ejecútalo dentro de la sesión
# gráfica y pega la salida:  tools/check-system.sh   (copia en ~/check-system.txt)
set -uo pipefail

exec > >(tee "$HOME/check-system.txt") 2>&1
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
echo "Pide tu contraseña una vez para leer snapper y el firewall (Ctrl+C para omitir)."
sudo -v 2>/dev/null || true
export HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)}

ok() { printf '  ok    %s\n' "$*"; }
bad() { printf '  FALLA %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }
check() { # check DESCRIPCIÓN COMANDO…
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}

echo "== Equipo"
info "$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null | paste -sd' ')"
info "kernel $(uname -r) · $(nproc) CPU · $(free -h | awk '/Mem/{print $2}') RAM"
info "perfil: $(grep -o '"[^"]*"' ~/.config/hypr/machine-profile.lua 2>/dev/null | tr -d '"')"
grep -E '^WH_' ~/.config/wh01s17/machine.env 2>/dev/null | sed 's/^/        /'

echo "== Instalación"
WH_GROUPS='' WH_GPU=''
# shellcheck disable=SC1090
[[ -f ~/.config/wh01s17/machine.env ]] && source ~/.config/wh01s17/machine.env
[[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]] && ok "shell de $USER: zsh" ||
  bad "la shell de $USER no es zsh: chsh -s /usr/bin/zsh"
lists=("$repo"/packages/{base,desktop,fonts,terminal}.txt "$repo/packages/core.aur.txt")
for group in $WH_GROUPS; do
  [[ $group == pentest ]] && continue # BlackArch drops packages; install.sh already reports them
  lists+=("$repo/packages/$group.txt" "$repo/packages/$group.aur.txt")
done
lists+=("$repo/packages/gpu-$WH_GPU.txt" "$repo/packages/gpu-$WH_GPU.aur.txt")
mapfile -t wanted < <(cat "${lists[@]}" 2>/dev/null | sed -e 's/#.*//' -e 's/[[:space:]]*$//' | grep -v '^$' | sort -u)
# pacman -T counts providers too: nvidia-580xx-utils satisfies nvidia-utils.
missing=$(pacman -T "${wanted[@]}" 2>/dev/null | paste -sd' ')
[[ -z $missing ]] && ok "los ${#wanted[@]} paquetes de las listas están instalados" ||
  bad "faltan paquetes (./install.sh --only packages o --only aur): $missing"
check "repositorio multilib activo" grep -qE '^\[multilib\]' /etc/pacman.conf

echo "== Arranque y disco"
root_src=$(findmnt -no SOURCE / | sed 's/\[.*//')
if lsblk -s -no TYPE "$root_src" 2>/dev/null | grep -qx crypt; then
  ok "raíz cifrada con LUKS ($root_src)"
  crypt_name=$(lsblk -rs -no NAME,TYPE "$root_src" | awk '$2 == "crypt" {print $1; exit}')
  if [[ $(lsblk -dno DISC-MAX "/dev/mapper/$crypt_name" 2>/dev/null | tr -d ' ') == 0B ]]; then
    bad "LUKS sin allow-discards: discard=async no llega al SSD"
  else
    ok "TRIM atraviesa LUKS"
  fi
else
  info "raíz sin cifrar ($root_src)"
fi
info "cmdline: $(tr ' ' '\n' </proc/cmdline | grep -E '^(cryptdevice|root|rootflags|resume|resume_offset|rd\.luks[^=]*)=' | paste -sd' ')"
info "hooks: $(grep -h '^HOOKS' /etc/mkinitcpio.conf.d/*.conf 2>/dev/null | paste -sd' ')"
check "Limine instalado" pacman -Q limine
check "limine-snapper-sync activo" systemctl is-enabled limine-snapper-sync.service
# CSV: the table output keeps translated headers and box drawing even with --no-headers.
if configs=$(sudo -n snapper --csvout --no-headers list-configs 2>/dev/null | cut -d, -f1 | paste -sd' '); then
  info "snapper: ${configs:-sin configuraciones} · instantáneas de root: $(sudo -n snapper --csvout --no-headers -c root list --columns number 2>/dev/null | grep -cvx 0)"
else
  info "snapper: sin permisos para leerlo"
fi
if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
  root_subvol=$(findmnt -no FSROOT /)
  if [[ $root_subvol == / ]]; then
    bad "raíz en el nivel superior del btrfs: snapshots con /home y sin restauración (INSTALL.md §2)"
  else
    ok "raíz en el subvolumen $root_subvol"
  fi
  if grep -qE '^[^#]*[[:space:]]btrfs[[:space:]].*subvolid=' /etc/fstab; then
    bad "fstab monta btrfs con subvolid= (rompe la restauración)"
  fi
  info "btrfs: $(findmnt -no OPTIONS / | grep -o 'compress=[^,]*' || echo 'sin compresión')"
  usage=$(sudo -n btrfs filesystem usage / 2>/dev/null |
    awk '/Free \(estimated\)/ {f = $3} /Device unallocated/ {u = $3} END {if (u) print "libre " f " · sin asignar " u}')
  info "btrfs: ${usage:-espacio sin permisos para leerlo}"
  check "balance semanal (btrfs-balance-auto.timer)" systemctl is-enabled btrfs-balance-auto.timer
  check "aviso de espacio (btrfs-space-check.timer)" systemctl --user is-enabled btrfs-space-check.timer
  check "reclamo dinámico de chunks de datos" grep -qx 1 "/sys/fs/btrfs/$(findmnt -no UUID /)/allocation/data/dynamic_reclaim"
  if [[ $root_subvol != / ]] && pacman -Q docker >/dev/null 2>&1; then
    check "/var/lib/containerd en su propio subvolumen (UPDATE.md)" mountpoint -q /var/lib/containerd
  fi
fi
check "paccache.timer activo" systemctl is-enabled paccache.timer
info "zram: $(zramctl --noheadings -o NAME,DISKSIZE,ALGORITHM 2>/dev/null | paste -sd' ')"
if [[ -f /swap/swapfile ]] || swapon --show=NAME --noheadings | grep -qv zram; then
  ok "swap para hibernar: $(swapon --show=NAME,SIZE --noheadings | grep -v zram | paste -sd' ')"
else
  info "sin swap en disco (no hay hibernación)"
fi

echo "== Servicios"
failed=$(systemctl --failed --no-legend --plain | awk '{print $1}' | paste -sd' ')
[[ -z $failed ]] && ok "ningún servicio del sistema falló" || bad "fallaron: $failed"
ufailed=$(systemctl --user --failed --no-legend --plain | awk '{print $1}' | paste -sd' ')
[[ -z $ufailed ]] && ok "ningún servicio de usuario falló" || bad "fallaron (usuario): $ufailed"
for s in NetworkManager bluetooth sddm systemd-resolved systemd-timesyncd ufw cups power-profiles-daemon; do
  systemctl list-unit-files "$s.service" >/dev/null 2>&1 || continue
  state=$(systemctl is-active "$s" 2>/dev/null)
  [[ $state == active ]] && ok "$s" || bad "$s: $state"
done
check "hora sincronizada (NTP)" sh -c "timedatectl show -p NTPSynchronized --value | grep -qx yes"
check "firewall activo" sh -c "sudo -n ufw status 2>/dev/null | grep -q 'Status: active' || systemctl is-active -q ufw"

echo "== Gráficos y sonido"
lspci -nnk | grep -A3 -E 'VGA|3D|Display' | grep -E 'VGA|3D|Display|driver in use' | sed 's/^\s*/        /'
if [[ $WH_GPU == nvidia* ]]; then
  check "nvidia-smi ve la GPU" nvidia-smi -L
  check "módulo nvidia cargado (no nouveau)" sh -c "lsmod | grep -q '^nvidia ' && ! lsmod | grep -q '^nouveau '"
  # The parameter is root-only (0400) on the 580xx branch.
  check "nvidia_drm con modeset=Y" sh -c "sudo -n cat /sys/module/nvidia_drm/parameters/modeset | grep -qx Y"
  check "módulo DKMS compilado para $(uname -r)" sh -c "dkms status -k '$(uname -r)' | grep -q installed"
fi
info "Vulkan: $(vulkaninfo --summary 2>/dev/null | grep -m1 deviceName | sed 's/.*= //' || echo '-')"
check "PipeWire activo" systemctl --user is-active pipewire wireplumber
info "salida de audio: $(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -m1 'node.description' | sed 's/.*= //')"
for b in /sys/class/backlight/*; do [[ -e $b ]] && info "brillo $(basename "$b"): $(cat "$b/brightness")/$(cat "$b/max_brightness")"; done
for b in /sys/class/power_supply/BAT*; do [[ -e $b ]] && info "batería $(basename "$b"): $(cat "$b/capacity")% $(cat "$b/status")"; done

echo "== Escritorio"
if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]] && hyprctl version >/dev/null 2>&1; then
  errors=$(hyprctl configerrors 2>/dev/null | grep -v '^$')
  [[ -z $errors || $errors == *"no errors"* ]] && ok "Hyprland sin errores de configuración" || bad "Hyprland: $errors"
  hyprctl monitors -j 2>/dev/null |
    jq -r '.[] | "        monitor \(.name): \(.width)x\(.height)@\(.refreshRate | floor) escala \(.scale)"'
else
  bad "no hay sesión de Hyprland (ejecútalo desde la terminal del escritorio)"
fi
log=$(ls -t "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.log 2>/dev/null | head -1)
if [[ -n $log ]]; then
  n=$(grep -cE 'of undefined|Unable to assign|ReferenceError|is not defined' "$log")
  ((n == 0)) && ok "shell sin errores QML" || bad "shell: $n errores QML (tools/shell-log.sh)"
  pgrep -x quickshell >/dev/null && ok "shell corriendo" || bad "el shell no está corriendo"
else
  bad "no hay registro del shell"
fi
for cmd in kitty firefox claude yay mise stow nvim; do
  command -v "$cmd" >/dev/null && ok "$cmd" || bad "$cmd no está en el PATH"
done

echo "== Errores de este arranque (sin repetir; se omiten los avisos de la BIOS: ACPI, SGX, TDX)"
journalctl -b -p err --no-pager -o cat 2>/dev/null |
  grep -vE '^ACPI( BIOS)? Error|^ACPI: |SGX disabled|TDX not supported|^\s*$|^\[ *[0-9]+\]' |
  sed -E 's/[0-9a-f]{8,}//g' | awk '!seen[$0]++' | head -20 | cut -c1-150 | sed 's/^/        /'

echo
echo "Copia guardada en ~/check-system.txt"
