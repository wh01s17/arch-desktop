#!/usr/bin/env bash
# Configuración del sistema como root. La llama install.sh con:
#   sudo env WH01S17_PATH=… TARGET_USER=… WH_GPU=… WH_GROUPS=… \
#     WH_AUTOLOGIN=… bash lib/system-setup.sh
# Reutiliza los pasos de instalación que trae el runtime congelado
# (WH01S17_PATH/install) y sus archivos de sistema
# (WH01S17_PATH/system).
set -Eeuo pipefail

die() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
step() { printf '\n--> %s\n' "$1"; }

((EUID == 0)) || die 'system-setup.sh debe ejecutarse como root.'
: "${WH01S17_PATH:?falta WH01S17_PATH}" "${TARGET_USER:?falta TARGET_USER}"
: "${WH_GPU:=none}" "${WH_GROUPS:=}" "${WH_AUTOLOGIN:=1}"
[[ -d $WH01S17_PATH/install && -d $WH01S17_PATH/system ]] ||
  die "$WH01S17_PATH no contiene el runtime (paquete Stow platform)."
getent passwd "$TARGET_USER" >/dev/null || die "No existe el usuario $TARGET_USER."

export WH01S17_PATH TARGET_USER
export WH01S17_INSTALL="$WH01S17_PATH/install"
export WH01S17_INSTALL_USER="$TARGET_USER"
export WH01S17_LOG_TO_STDOUT=1
# Root never runs anything from a user-writable PATH entry except the copy.
export PATH="$WH01S17_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"

system_files="$WH01S17_PATH/system"
failed=()

has_group() { [[ " $WH_GROUPS " == *" $1 "* ]]; }
installed() { pacman -Q "$1" >/dev/null 2>&1; }

put() { # put RUTA [MODO]: copia WH01S17_PATH/system/RUTA a /RUTA
  [[ -f $system_files/$1 ]] || die "Falta $system_files/$1"
  install -D -m "${2:-0644}" "$system_files/$1" "/$1"
}

# shellcheck disable=SC1091
source "$WH01S17_INSTALL/helpers/logging.sh"
leaf() { # leaf RUTA: un paso de instalación del runtime; los fallos se resumen al final
  if ! run_logged "$WH01S17_INSTALL/$1"; then
    failed+=("$1")
  fi
}

step 'Archivos de sistema'
for path in \
  etc/gnupg/dirmngr.conf \
  etc/modprobe.d/wh01s17-usb-autosuspend.conf \
  etc/NetworkManager/conf.d/wh01s17-wifi-powersave.conf \
  etc/sysctl.d/90-wh01s17-file-watchers.conf \
  etc/sysctl.d/99-wh01s17-sysctl.conf \
  etc/systemd/logind.conf.d/10-ignore-power-button.conf \
  etc/systemd/logind.conf.d/20-inhibit-delay.conf \
  etc/systemd/logind.conf.d/30-ignore-lid-switch.conf \
  etc/systemd/oomd.conf.d/10-wh01s17.conf \
  etc/systemd/resolved.conf.d/10-disable-multicast.conf \
  etc/systemd/system.conf.d/10-faster-shutdown.conf \
  etc/systemd/system.conf.d/20-wh01s17-nofile.conf \
  etc/systemd/system/cups-browsed.service.d/10-wh01s17.conf \
  etc/systemd/system/plocate-updatedb.service.d/ac-only.conf \
  etc/systemd/system/user@.service.d/10-faster-shutdown.conf \
  etc/systemd/user.conf.d/20-wh01s17-nofile.conf \
  etc/sysusers.d/wh01s17-cups-browsed.conf \
  etc/tmpfiles.d/wh01s17-zswap.conf \
  usr/lib/systemd/system/plocate-updatedb.service.d/10-wh01s17.conf \
  usr/lib/systemd/zram-generator.conf.d/90-wh01s17.conf \
  usr/local/share/wayland-sessions/wh01s17.desktop \
  usr/share/fontconfig/conf.avail/50-wh01s17.conf \
  usr/share/fonts/wh01s17/wh01s17.ttf \
  usr/share/pixmaps/wh01s17.png \
  usr/share/sddm/hyprland.lua; do
  put "$path"
done
put usr/lib/systemd/system-sleep/unmount-fuse 0755
# The runtime's sudoers drop-ins are not installed: they grant NOPASSWD to
# /usr/bin/wh01s17-* paths, which here would be user-writable scripts.
ln -sfn /usr/share/fontconfig/conf.avail/50-wh01s17.conf /etc/fonts/conf.d/50-wh01s17.conf
cp -r "$system_files/usr/share/icons/hicolor/." /usr/share/icons/hicolor/
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fc-cache -f >/dev/null 2>&1 || true
systemd-sysusers >/dev/null 2>&1 || true

if has_group dev && installed docker; then
  put etc/docker/daemon.json
  put etc/systemd/system/docker.service.d/no-block-boot.conf
  put etc/systemd/resolved.conf.d/20-docker-dns.conf
  usermod -aG docker "$TARGET_USER"
fi
if has_group virtualization && getent group vboxusers >/dev/null; then
  usermod -aG vboxusers "$TARGET_USER"
fi

step 'Pasos de configuración'
leaf config/theme-system.sh
leaf config/browser-policy.sh
leaf config/increase-lockout-limit.sh
leaf config/lockscreen-pam.sh
leaf config/fix-powerprofilesctl-shebang.sh
leaf config/ssh-command-path.sh
leaf config/ssh-keepalive.sh
if [[ $(findmnt -no FSTYPE /) == btrfs ]] && installed snapper; then
  leaf config/snapper.sh
fi

step 'Firewall (UFW)'
if command -v ufw-docker >/dev/null 2>&1; then
  leaf config/firewall.sh
else
  # Same rules as config/firewall.sh, without the ufw-docker block.
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 53317/udp comment 'localsend'
  ufw allow 53317/tcp comment 'localsend'
  sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
  systemctl enable ufw.service
fi

step 'Hardware (detección automática)'
# Each script checks its own hardware; GPU packages are already installed by
# install.sh, so wh01s17-pkg-add finds them and only writes the config.
while read -r line; do
  [[ $line =~ run_logged\ \"\$WH01S17_INSTALL/([^\"]+)\" ]] || continue
  leaf "${BASH_REMATCH[1]}"
done <"$WH01S17_INSTALL/hardware/all.sh"

step 'Inicio de sesión (SDDM)'
leaf login/sddm.sh
install -d /usr/share/sddm/themes
rm -rf /usr/share/sddm/themes/wh01s17
cp -r "$WH01S17_PATH/default/sddm/wh01s17" /usr/share/sddm/themes/wh01s17
put etc/sddm.conf.d/10-theme.conf
install -D -m 0644 /dev/stdin /etc/sddm.conf.d/10-wayland.conf <<'EOF'
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.lua
EOF
if [[ $WH_AUTOLOGIN == 1 ]]; then
  install -D -m 0644 /dev/stdin /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=$TARGET_USER
Session=wh01s17.desktop
EOF
else
  rm -f /etc/sddm.conf.d/autologin.conf
fi

step 'Pasos finales'
leaf post-install/pacman.sh
leaf post-install/udev.sh
leaf post-install/localdb.sh

step 'Servicios'
services=(
  NetworkManager.service bluetooth.service cups.service avahi-daemon.service
  power-profiles-daemon.service sddm.service systemd-resolved.service
  systemd-oomd.service linux-modules-cleanup.service
)
installed docker && services+=(docker.socket)
for service in "${services[@]}"; do
  systemctl enable "$service" || failed+=("systemctl enable $service")
done
systemctl mask NetworkManager-wait-online.service
# systemd-resolved needs the stub resolv.conf to serve NetworkManager's DNS.
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# The original setup only enables resolved and reboots; the installer keeps going (AUR,
# mise, git clones), so start it now and let NetworkManager hand it the DNS.
systemctl start systemd-resolved.service || failed+=('systemctl start systemd-resolved')
systemctl try-restart NetworkManager.service || true
for _ in {1..30}; do
  getent hosts archlinux.org >/dev/null 2>&1 && break
  sleep 1
done
getent hosts archlinux.org >/dev/null 2>&1 || failed+=('DNS tras activar systemd-resolved')
if [[ $WH_GPU == nvidia || $WH_GPU == nvidia-legacy ]]; then
  for service in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
    systemctl enable "$service" || failed+=("systemctl enable $service")
  done
fi
if [[ $WH_GPU == vm ]] && installed virtualbox-guest-utils; then
  systemctl enable vboxservice.service || failed+=('systemctl enable vboxservice.service')
fi
if installed snapper; then
  systemctl enable snapper-cleanup.timer || failed+=('systemctl enable snapper-cleanup.timer')
fi

step 'initramfs y arranque'
# These hooks unlock LUKS with `encrypt` (cryptdevice=), like archinstall with a
# password. A FIDO2/HSM install boots with rd.luks= and sd-encrypt instead;
# rewriting its hooks would leave it unable to unlock the disk.
if grep -qw 'rd\.luks\.[a-z]*' /proc/cmdline && ! grep -qw 'cryptdevice=[^ ]*' /proc/cmdline; then
  printf '[!] El disco se desbloquea con rd.luks (FIDO2/HSM); no se cambia el initramfs.\n' >&2
  printf '    Reinstala con cifrado por contraseña (cryptdevice=) o ajusta los hooks a mano.\n' >&2
  exit 3
fi
hooks=(base udev keyboard autodetect microcode modconf kms keymap consolefont block)
root_source=$(findmnt -no SOURCE / | sed 's/\[.*//')
if lsblk -no TYPE "$root_source" 2>/dev/null | grep -qx crypt ||
  lsblk -s -no TYPE "$root_source" 2>/dev/null | grep -qx crypt; then
  hooks+=(encrypt)
fi
hooks+=(filesystems fsck)
if installed limine-mkinitcpio-hook && [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
  hooks+=(btrfs-overlayfs)
fi
{
  echo '# Escrito por arch-desktop (wh01s17).'
  echo "HOOKS=(${hooks[*]})"
  [[ -f /etc/vconsole.conf ]] && echo 'FILES+=(/etc/vconsole.conf)'
} >/etc/mkinitcpio.conf.d/wh01s17_hooks.conf

if installed limine-mkinitcpio-hook; then
  if [[ ! -f /etc/default/limine ]]; then
    # Keep booting with today's command line; drop boot-loader-only words.
    cmdline=$(tr ' ' '\n' </proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | paste -sd' ')
    esp=$(bootctl --print-esp-path 2>/dev/null || echo /boot)
    install -D -m 0644 /dev/stdin /etc/default/limine <<EOF
ESP_PATH="$esp"
KERNEL_CMDLINE[default]+="$cmdline"
EOF
  fi
  install -D -m 0644 /dev/stdin /etc/limine-entry-tool.d/wh01s17.conf <<'EOF'
# Escrito por arch-desktop (wh01s17), a partir de los valores por defecto del runtime.
TARGET_OS_NAME="Arch Linux"
ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=yes
BOOT_ORDER="linux, linux-lts, *, *fallback, Snapshots"
MAX_SNAPSHOT_ENTRIES=5
EOF
  if installed limine-snapper-sync; then
    systemctl enable limine-snapper-sync.service || failed+=('systemctl enable limine-snapper-sync.service')
  fi
  limine-mkinitcpio || failed+=('limine-mkinitcpio')
else
  mkinitcpio -P || failed+=('mkinitcpio -P')
fi

if ((${#failed[@]})); then
  printf '\n[!] Pasos con errores (revisa la salida anterior):\n' >&2
  printf '    - %s\n' "${failed[@]}" >&2
  exit 3
fi
printf '\nConfiguración del sistema completada.\n'
