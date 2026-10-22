# shellcheck shell=bash
# Detección de hardware de sólo lectura. Rellena variables DETECT_*.
# SYSFS_ROOT permite probarla con un árbol /sys falso.

SYSFS_ROOT=${SYSFS_ROOT:-/sys}

detect_hardware() {
  local dmi=$SYSFS_ROOT/class/dmi/id chassis

  DETECT_VENDOR=$(cat "$dmi/sys_vendor" 2>/dev/null || echo desconocido)
  DETECT_PRODUCT=$(cat "$dmi/product_name" 2>/dev/null || echo desconocido)
  DETECT_VIRT=$(systemd-detect-virt 2>/dev/null || true)
  [[ -n $DETECT_VIRT ]] || DETECT_VIRT=none

  DETECT_BATTERY=no
  compgen -G "$SYSFS_ROOT/class/power_supply/BAT*" >/dev/null && DETECT_BATTERY=yes
  chassis=$(cat "$dmi/chassis_type" 2>/dev/null || echo 0)
  # SMBIOS: 8 portable, 9 laptop, 10 notebook, 14 sub-notebook, 31 convertible, 32 detachable.
  case $chassis in
    8|9|10|14|31|32) DETECT_LAPTOP=yes ;;
    *) DETECT_LAPTOP=$DETECT_BATTERY ;;
  esac

  detect_gpus
  detect_displays

  DETECT_ROOT_FS=$(findmnt -no FSTYPE / 2>/dev/null || echo desconocido)
  # "/" is btrfs's top-level subvolume; INSTALL.md mounts / from "/@".
  DETECT_ROOT_SUBVOL=
  [[ $DETECT_ROOT_FS == btrfs ]] && DETECT_ROOT_SUBVOL=$(findmnt -no FSROOT / 2>/dev/null)
  if [[ -f /boot/limine.conf || -d /boot/EFI/limine ]] || pacman -Q limine >/dev/null 2>&1; then
    DETECT_BOOTLOADER=limine
  elif bootctl is-installed >/dev/null 2>&1; then
    DETECT_BOOTLOADER=systemd-boot
  elif [[ -d /boot/grub ]]; then
    DETECT_BOOTLOADER=grub
  else
    DETECT_BOOTLOADER=desconocido
  fi

  DETECT_LOGITECH=no
  if grep -qsx '046d' "$SYSFS_ROOT"/bus/usb/devices/*/idVendor 2>/dev/null; then
    DETECT_LOGITECH=yes
  fi

  DETECT_PROFILE=$(profile_for_product "$DETECT_PRODUCT")
}

# Same PCI ranges as wh01s17-hw-nvidia-gsp / -without-gsp.
detect_gpus() {
  local device vendor class id
  DETECT_GPUS=()
  shopt -s nullglob
  for device in "$SYSFS_ROOT"/bus/pci/devices/*; do
    class=$(<"$device/class")
    [[ $class == 0x03* ]] || continue
    vendor=$(<"$device/vendor")
    id=$(<"$device/device")
    case $vendor in
      0x10de)
        if ((id >= 0x1e00)); then
          DETECT_GPUS+=(nvidia)
        elif ((id >= 0x1340)); then
          DETECT_GPUS+=(nvidia-legacy)
        else
          DETECT_GPUS+=(nvidia-unsupported)
        fi
        ;;
      0x1002) DETECT_GPUS+=(amd) ;;
      0x8086) DETECT_GPUS+=(intel) ;;
      0x80ee|0x15ad|0x1af4|0x1234) DETECT_GPUS+=(vm) ;;
    esac
  done
  shopt -u nullglob

  # NVIDIA first: it is the one that needs a driver choice.
  DETECT_GPU=none
  local candidate
  for candidate in nvidia-legacy nvidia nvidia-unsupported amd intel vm; do
    if [[ " ${DETECT_GPUS[*]} " == *" $candidate "* ]]; then
      DETECT_GPU=$candidate
      break
    fi
  done
  [[ $DETECT_VIRT == none ]] || DETECT_GPU=vm
}

detect_displays() {
  local connector name mode
  DETECT_DISPLAYS=()
  shopt -s nullglob
  for connector in "$SYSFS_ROOT"/class/drm/card*-*; do
    [[ $(cat "$connector/status" 2>/dev/null) == connected ]] || continue
    name=${connector##*/}
    name=${name#card*-}
    mode=$(head -n1 "$connector/modes" 2>/dev/null || true)
    DETECT_DISPLAYS+=("$name ${mode:-?}")
  done
  shopt -u nullglob
}

profile_for_product() {
  local product=$1 model profile
  [[ -f $MACHINES_TSV ]] || return 0
  while IFS=$'\t' read -r model profile; do
    [[ -z $model || $model == \#* ]] && continue
    if [[ $model == "$product" ]]; then
      printf '%s\n' "$profile"
      return 0
    fi
  done <"$MACHINES_TSV"
}

print_detection() {
  log 'Equipo detectado'
  info "Modelo: $DETECT_VENDOR $DETECT_PRODUCT"
  info "Portátil: $DETECT_LAPTOP · batería: $DETECT_BATTERY · virtualización: $DETECT_VIRT"
  info "GPU: ${DETECT_GPUS[*]:-ninguna} → propuesta: $DETECT_GPU"
  if ((${#DETECT_DISPLAYS[@]})); then
    info "Pantallas: ${DETECT_DISPLAYS[*]}"
  else
    info 'Pantallas: ninguna detectada desde /sys'
  fi
  info "Raíz: $DETECT_ROOT_FS${DETECT_ROOT_SUBVOL:+ ($DETECT_ROOT_SUBVOL)} · arranque: $DETECT_BOOTLOADER · receptor Logitech: $DETECT_LOGITECH"
  info "Perfil conocido para este modelo: ${DETECT_PROFILE:-ninguno}"
}
