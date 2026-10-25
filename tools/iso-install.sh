#!/usr/bin/env bash
# Sistema base desde el ISO de Arch (INSTALL.md §2): btrfs con subvolúmenes @,
# LUKS opcional, Limine, usuario y el repo clonado. Desde el ISO, con red:
#   git clone https://github.com/wh01s17/arch-desktop
#   bash arch-desktop/tools/iso-install.sh
# Si falla después de preparar el disco, se vuelve a ejecutar y continúa desde
# los paquetes sin tocar el disco.
set -Eeuo pipefail

readonly REPO=wh01s17/arch-desktop
readonly TIMEZONE=America/Santiago
readonly SUBVOLS=(@ @home @log @pkg @docker @containerd @swap)

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

# The disk is ready once stage is "system"; from then on a rerun resumes.
stage=disk
on_error() {
  # A failure inside $(…) also reaches here; only the main shell reports it.
  [[ $BASHPID == "$$" ]] || exit 1
  if [[ $stage == system ]]; then
    die "Falló en la línea $1. El disco ya está listo y montado en /mnt: corrige lo que indique la salida y vuelve a ejecutar el script; continúa desde los paquetes."
  fi
  die "Falló en la línea $1; revisa la salida anterior."
}
trap 'on_error $LINENO' ERR

# prompt VAR PREGUNTA [DEFECTO]
prompt() {
  local -n _var=$1
  local answer
  read -r -p "$2${3:+ [$3]}: " answer
  _var=${answer:-${3:-}}
}
# is_yes RESPUESTA
is_yes() {
  case ${1,,} in
    s | si | sí | y | yes) return 0 ;;
    n | no) return 1 ;;
    *) die "Respuesta no válida: $1" ;;
  esac
}
# device NAME: accepts nvme0n1 as well as /dev/nvme0n1
device() { [[ -z $1 || $1 == /* ]] && echo "$1" || echo "/dev/$1"; }

[[ -d /run/archiso ]] || die 'Ejecútalo desde el ISO de Arch.'
((EUID == 0)) || die 'Ejecútalo como root (el ISO ya entra como root).'
[[ -d /sys/firmware/efi ]] || die 'Arranca el ISO en modo UEFI.'

resume=false
if mountpoint -q /mnt; then
  [[ $(findmnt -no FSROOT /mnt) == /@ ]] && mountpoint -q /mnt/boot ||
    die '/mnt ya está montado y no es una instalación a medias de este script: umount -R /mnt'
  log 'Instalación a medias en /mnt'
  findmnt -R -o TARGET,SOURCE /mnt | sed 's/^/    /'
  prompt again '¿Continuar desde los paquetes, sin tocar el disco? n empieza de cero (s/n)' s
  if is_yes "$again"; then
    resume=true
  else
    umount -R /mnt
  fi
fi
# A fresh install reformats the partition, so an open container can go.
if ! $resume && [[ -e /dev/mapper/root ]]; then
  cryptsetup close root
fi

if $resume; then
  root=$(findmnt -no SOURCE /mnt | sed 's/\[.*//')
  esp=$(findmnt -no SOURCE /mnt/boot)
  if [[ $(lsblk -dno TYPE "$root") == crypt ]]; then
    encrypt=true
    part=$(cryptsetup status "$(basename "$root")" | awk '$1 == "device:" {print $2}')
    [[ -b $part ]] || die "No se encontró la partición cifrada bajo $root."
  else
    encrypt=false
    part=$root
  fi
else
  log 'Discos'
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME
  echo '    1) Disco entero: lo borra y crea una ESP de 1 GB y el resto btrfs (sin Windows)'
  echo '    2) Particiones: elige la de Linux y reutiliza la ESP (con Windows)'
  prompt mode 'Modo' 1
  whole_disk=false
  case $mode in
    1)
      whole_disk=true
      prompt disk 'Disco que se BORRA ENTERO (p. ej. nvme0n1)'
      disk=$(device "$disk")
      [[ -b $disk && $(lsblk -dno TYPE "$disk") == disk ]] || die "$disk no es un disco."
      ! lsblk -no MOUNTPOINTS "$disk" | grep -q . || die "$disk tiene particiones montadas."
      format_esp=true
      ;;
    2)
      prompt part_disk '¿Crear o cambiar particiones con cfdisk? Escribe el disco o Enter para seguir'
      part_disk=$(device "$part_disk")
      if [[ -n $part_disk ]]; then
        [[ -b $part_disk ]] || die "$part_disk no existe."
        cfdisk "$part_disk"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME
      fi
      prompt root 'Partición de Linux (SE BORRA)'
      root=$(device "$root")
      prompt esp 'ESP, la partición FAT32 de arranque (la de Windows)'
      esp=$(device "$esp")
      [[ -b $root && $(lsblk -dno TYPE "$root") == part ]] || die "$root no es una partición."
      [[ -b $esp && $(lsblk -dno TYPE "$esp") == part ]] || die "$esp no es una partición."
      [[ $root != "$esp" ]] || die 'La partición de Linux y la ESP no pueden ser la misma.'
      [[ $(lsblk -dno PARTTYPENAME "$esp") == 'EFI System' ]] ||
        die "$esp no es de tipo «EFI System»; cámbialo con cfdisk o elige otra."
      # An empty ESP is formatted; one with a file system (Windows') is reused as is.
      format_esp=false
      case $(blkid -o value -s TYPE "$esp" || true) in
        vfat) ;;
        '') format_esp=true ;;
        *) die "$esp no es FAT32." ;;
      esac
      ;;
    *) die "Modo no válido: $mode" ;;
  esac
fi

# Proposes the profile name from profiles/machines.tsv as the hostname.
model=$(</sys/class/dmi/id/product_name)
profile=$(curl -fsSL "https://raw.githubusercontent.com/$REPO/main/profiles/machines.tsv" 2>/dev/null |
  awk -F'\t' -v m="$model" '$1 == m {print $2}') || true
prompt host 'Nombre del equipo' "${profile:-archlinux}"
prompt user 'Usuario' wh01s17
[[ $host =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Nombre de equipo no válido: $host"
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Usuario no válido: $user"

case $(awk '/^vendor_id/ {print $3; exit}' /proc/cpuinfo) in
  GenuineIntel) ucode=intel-ucode ;;
  AuthenticAMD) ucode=amd-ucode ;;
  *) die 'CPU no reconocida (ni Intel ni AMD).' ;;
esac

if ! $resume; then
  prompt encrypt '¿Cifrar la partición de Linux con LUKS? (s/n)' s
  if is_yes "$encrypt"; then encrypt=true; else encrypt=false; fi
  if $encrypt; then
    # The initramfs asks for it with the US keymap, the same as this ISO.
    while :; do
      read -rs -p 'Contraseña del cifrado (se pide en cada arranque): ' luks_pass && echo
      read -rs -p 'Repítela: ' luks_again && echo
      [[ -n $luks_pass && $luks_pass == "$luks_again" ]] && break
      echo '    Vacía o no coinciden; otra vez.'
    done
  fi

  log 'Resumen'
  if $whole_disk; then
    printf '    Se BORRA ENTERO: %s\n' "$(lsblk -dno NAME,SIZE,MODEL "$disk")"
    lsblk -no NAME,SIZE,FSTYPE,LABEL "$disk" | tail -n +2 | sed 's/^/      /'
    printf '    ESP:       nueva, 1 GB\n'
  else
    printf '    Se BORRA:  %s\n' "$(lsblk -dno NAME,SIZE,FSTYPE,LABEL "$root")"
    if $format_esp; then
      printf '    ESP:       %s (vacía: se formatea en FAT32)\n' "$esp"
    else
      printf '    ESP:       %s (se reutiliza, no se formatea)\n' "$esp"
    fi
  fi
  printf '    Cifrado:   %s\n' "$($encrypt && echo 'LUKS2, con TRIM' || echo 'no')"
  printf '    Equipo:    %s · usuario %s · %s\n' "$host" "$user" "$ucode"
  prompt confirm 'Escribe BORRAR para continuar'
  [[ $confirm == BORRAR ]] || die 'Cancelado; no se cambió nada.'

  if $whole_disk; then
    log 'Particiones'
    wipefs -a "$disk" >/dev/null
    sgdisk --zap-all "$disk" >/dev/null
    sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -n2:0:0 -t2:8300 -c2:arch "$disk" >/dev/null
    partprobe "$disk"
    udevadm settle
    mapfile -t parts < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "part" {print $1}')
    ((${#parts[@]} == 2)) || die "No aparecieron las dos particiones nuevas en $disk."
    esp=${parts[0]} root=${parts[1]}
  fi

  # root is what btrfs goes on; part stays the partition, for the boot entry.
  part=$root
  if $encrypt; then
    log 'Cifrado LUKS'
    printf %s "$luks_pass" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$part"
    # --persistent stores allow-discards in the header, so discard=async reaches the SSD.
    printf %s "$luks_pass" | cryptsetup open --allow-discards --persistent --key-file=- "$part" root
    unset luks_pass luks_again
    root=/dev/mapper/root
  fi

  log 'btrfs y subvolúmenes'
  mkfs.btrfs -f -L arch "$root"
  mount "$root" /mnt
  for sv in "${SUBVOLS[@]}"; do btrfs subvolume create "/mnt/$sv"; done
  chattr +C /mnt/@swap
  umount /mnt

  opts=relatime,ssd,discard=async,space_cache=v2,compress=zstd:1
  mount -o "$opts,subvol=@" "$root" /mnt
  mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,var/lib/docker,var/lib/containerd,swap,boot}
  mount -o "$opts,subvol=@home" "$root" /mnt/home
  mount -o "$opts,subvol=@log" "$root" /mnt/var/log
  mount -o "$opts,subvol=@pkg" "$root" /mnt/var/cache/pacman/pkg
  mount -o "$opts,subvol=@docker" "$root" /mnt/var/lib/docker
  mount -o "$opts,subvol=@containerd" "$root" /mnt/var/lib/containerd
  mount -o "$opts,subvol=@swap" "$root" /mnt/swap
  if $format_esp; then mkfs.fat -F32 "$esp"; fi
  mount "$esp" /mnt/boot
fi
stage=system

log 'Paquetes base'
# Downloaded packages stay in /mnt/var/cache/pacman/pkg, so a retry only
# fetches what is missing.
until pacstrap -K /mnt base linux linux-firmware btrfs-progs limine efibootmgr \
  networkmanager sudo git zsh neovim "$ucode"; do
  prompt again 'Falló la instalación de paquetes. ¿Buscar otros mirrors y reintentar? (s/n)' s
  is_yes "$again" || die 'Cancelado. Vuelve a ejecutar el script para continuar desde los paquetes.'
  reflector --protocol https --age 12 --latest 20 --sort rate --save /etc/pacman.d/mirrorlist ||
    echo '    reflector falló; se reintenta con los mirrors actuales.'
done
genfstab -U /mnt >/mnt/etc/fstab
# A replace restore gives @ a new ID; mount by name, not by ID.
sed -i 's/subvolid=[0-9]*,//' /mnt/etc/fstab

log 'Idioma, equipo y usuario'
arch-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#\(es_CL.UTF-8\|en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=es_CL.UTF-8' >/etc/locale.conf
echo 'KEYMAP=us' >/etc/vconsole.conf
echo '$host' >/etc/hostname
id -u '$user' >/dev/null 2>&1 || useradd -m -G wheel -s /bin/zsh '$user'
install -m 0440 /dev/stdin /etc/sudoers.d/10-wheel <<<'%wheel ALL=(ALL:ALL) ALL'
systemctl enable NetworkManager
EOF
echo "Contraseña de $user:"
until arch-chroot /mnt passwd "$user"; do :; done
echo 'Contraseña de root:'
until arch-chroot /mnt passwd; do :; done

if $encrypt; then
  log 'initramfs con desbloqueo LUKS'
  # The same hooks lib/system-setup.sh writes later for an encrypted root.
  install -D -m 0644 /dev/stdin /mnt/etc/mkinitcpio.conf.d/wh01s17_hooks.conf <<'EOF'
# Escrito por arch-desktop (wh01s17).
HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck)
FILES+=(/etc/vconsole.conf)
EOF
  arch-chroot /mnt mkinitcpio -P
fi

log 'Limine'
mkdir -p /mnt/boot/EFI/limine
cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/limine/
# Some firmware (HP among them) ignores new boot entries and only starts the
# fallback path. Leave it alone if something, such as Windows, already uses it.
if [[ ! -e /mnt/boot/EFI/BOOT/BOOTX64.EFI ]]; then
  install -D -m 0644 /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/BOOT/BOOTX64.EFI
fi
# Entries from an earlier install or run point at partitions that may be gone.
efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)[* ] Arch Linux\(\t.*\)\{0,1\}$/\1/p' |
  while read -r num; do efibootmgr -q -b "$num" -B; done
esp_name=$(basename "$(readlink -f "$esp")")
efibootmgr --create --disk "/dev/$(lsblk -dno PKNAME "$esp")" \
  --part "$(</sys/class/block/"$esp_name"/partition)" \
  --label 'Arch Linux' --loader '\EFI\limine\BOOTX64.EFI' --unicode >/dev/null
if $encrypt; then
  cmdline="cryptdevice=UUID=$(blkid -s UUID -o value "$part"):root root=/dev/mapper/root"
else
  cmdline="root=PARTUUID=$(blkid -s PARTUUID -o value "$part")"
fi
cmdline+=" rootflags=subvol=@ zswap.enabled=0 rw rootfstype=btrfs"
cat >/mnt/etc/default/limine <<EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="$cmdline"
EOF
cat >/mnt/boot/limine.conf <<EOF
timeout: 3

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: $cmdline
    module_path: boot():/initramfs-linux.img
EOF

log 'Repo arch-desktop'
if [[ ! -d /mnt/home/$user/workspace/arch-desktop/.git ]]; then
  arch-chroot /mnt runuser -u "$user" -- \
    git clone "https://github.com/$REPO.git" "/home/$user/workspace/arch-desktop"
fi

sync
# Everything is written; a busy mount (a leftover gpg-agent) only delays
# the unmount until the reboot.
if ! umount -R /mnt; then
  echo '    /mnt sigue ocupado; se desmontará al reiniciar.'
elif $encrypt; then
  cryptsetup close root || true
fi
log 'Listo. Reinicia con: reboot'
cat <<EOF
    En la TTY, como $user:
      nmtui                                   # red
      cd ~/workspace/arch-desktop && ./install.sh
EOF
