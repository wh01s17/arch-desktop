#!/usr/bin/env bash
# Sistema base desde el ISO de Arch (INSTALL.md §2): btrfs con subvolúmenes @,
# Limine, usuario y el repo clonado. Desde el ISO, con red:
#   curl -LO https://raw.githubusercontent.com/wh01s17/arch-desktop/main/tools/iso-install.sh
#   bash iso-install.sh
set -Eeuo pipefail

readonly REPO=wh01s17/arch-desktop
readonly TIMEZONE=America/Santiago
readonly SUBVOLS=(@ @home @log @pkg @docker @containerd @swap)

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
die() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }
trap 'die "Falló en la línea $LINENO; revisa la salida anterior."' ERR

# prompt VAR PREGUNTA [DEFECTO]
prompt() {
  local -n _var=$1
  local answer
  read -r -p "$2${3:+ [$3]}: " answer
  _var=${answer:-${3:-}}
}

[[ -d /run/archiso ]] || die 'Ejecútalo desde el ISO de Arch.'
((EUID == 0)) || die 'Ejecútalo como root (el ISO ya entra como root).'
[[ -d /sys/firmware/efi ]] || die 'Arranca el ISO en modo UEFI.'
! mountpoint -q /mnt || die '/mnt ya está montado: umount -R /mnt'

log 'Discos'
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME
prompt part_disk '¿Crear o cambiar particiones con cfdisk? Escribe el disco (p. ej. /dev/nvme0n1) o Enter para seguir'
if [[ -n $part_disk ]]; then
  [[ -b $part_disk ]] || die "$part_disk no existe."
  cfdisk "$part_disk"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME
fi

prompt root 'Partición de Linux (SE BORRA)'
prompt esp 'ESP, la partición FAT32 de arranque (la de Windows si la hay)'
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

log 'Resumen'
printf '    Se BORRA:  %s\n' "$(lsblk -dno NAME,SIZE,FSTYPE,LABEL "$root")"
if $format_esp; then
  printf '    ESP:       %s (vacía: se formatea en FAT32)\n' "$esp"
else
  printf '    ESP:       %s (se reutiliza, no se formatea)\n' "$esp"
fi
printf '    Equipo:    %s · usuario %s · %s\n' "$host" "$user" "$ucode"
prompt confirm 'Escribe BORRAR para continuar'
[[ $confirm == BORRAR ]] || die 'Cancelado; no se cambió nada.'

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

log 'Paquetes base'
pacstrap -K /mnt base linux linux-firmware btrfs-progs limine efibootmgr \
  networkmanager sudo git zsh neovim "$ucode"
genfstab -U /mnt >>/mnt/etc/fstab
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
useradd -m -G wheel -s /bin/zsh '$user'
install -m 0440 /dev/stdin /etc/sudoers.d/10-wheel <<<'%wheel ALL=(ALL:ALL) ALL'
systemctl enable NetworkManager
EOF
echo "Contraseña de $user:"
until arch-chroot /mnt passwd "$user"; do :; done
echo 'Contraseña de root:'
until arch-chroot /mnt passwd; do :; done

log 'Limine'
mkdir -p /mnt/boot/EFI/limine
cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/limine/
esp_name=$(basename "$(readlink -f "$esp")")
efibootmgr --create --disk "/dev/$(lsblk -dno PKNAME "$esp")" \
  --part "$(</sys/class/block/"$esp_name"/partition)" \
  --label 'Arch Linux' --loader '\EFI\limine\BOOTX64.EFI' --unicode >/dev/null
cmdline="root=PARTUUID=$(blkid -s PARTUUID -o value "$root") rootflags=subvol=@ zswap.enabled=0 rw rootfstype=btrfs"
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
arch-chroot /mnt runuser -u "$user" -- \
  git clone "https://github.com/$REPO.git" "/home/$user/workspace/arch-desktop"

umount -R /mnt
log 'Listo. Reinicia con: reboot'
cat <<EOF
    En la TTY, como $user:
      nmtui                                   # red
      cd ~/workspace/arch-desktop && ./install.sh
EOF
