# Instalación de Arch con el escritorio wh01s17

Pasos para pasar de un disco con Windows (o vacío) a tu escritorio actual
sobre Arch puro. El instalador (`install.sh`) hace casi todo; esta guía
cubre lo que va antes: el sistema base con btrfs y Limine. A diferencia de
tu Omarchy, el btrfs usa subvolúmenes `@` para que los snapshots sólo cubran el
sistema y la restauración desde Limine funcione.

## Índice

1. [Antes de formatear](#1-antes-de-formatear)
2. [Sistema base desde el ISO de Arch](#2-sistema-base-desde-el-iso-de-arch)
3. [Primer arranque y escritorio](#3-primer-arranque-y-escritorio)
4. [Comprobaciones](#4-comprobaciones)
5. [Volver a ejecutar o cambiar decisiones](#5-volver-a-ejecutar-o-cambiar-decisiones)

## 1. Antes de formatear

En el equipo con Omarchy:

```bash
cd ~/workspace/arch-desktop
tools/capture-reference.sh        # pide sudo para btrfs y limine.conf
git -C ~/dotfiles status               # sin cambios pendientes
git add reference && git commit -m "Capture Omarchy reference" && git push
git -C ~/dotfiles push
```

Respalda fuera del equipo: `~/.ssh`, `~/.gnupg`, perfiles de navegador,
bóvedas de Obsidian, `~/workspace`, `~/VirtualBox VMs` y cualquier `.env` o
licencia.

Para el arranque dual con Windows, sigue `omarchy/dual-boot.md` (repo privado post-install-linux) §1–3
(preparar Windows, la USB y el firmware): no cambia en Arch.

## 2. Sistema base desde el ISO de Arch

Arranca el ISO oficial de Arch Linux. Los nombres de disco son ejemplos;
compruébalos con `lsblk`.

```bash
iwctl station wlan0 connect "MiRed"     # o cable
timedatectl set-ntp true
lsblk -f
```

### Particiones

Si hay Windows, **reutiliza su ESP** (FAT32, ~1 GB en tu Omen) y crea sólo la
partición de Linux en el espacio libre:

```bash
cfdisk /dev/nvme0n1                     # nueva partición «Linux filesystem»
mkfs.btrfs -L arch /dev/nvme0n1p4       # la nueva; NO formatees la ESP de Windows
```

Sin Windows: crea una ESP de 1 GB (`mkfs.fat -F32`) y el resto btrfs.

### btrfs con subvolúmenes `@`

Tu Omarchy usa el **nivel superior** del btrfs como raíz (`subvolid=5`), sin
subvolúmenes `@` (ver `reference/btrfs.txt`). Ese esquema tiene dos problemas:

- Cada snapshot congela el disco completo, incluidos `/home`, las VMs, Docker y
  las cachés, así que borrar archivos no libera espacio mientras existan
  snapshots que los contengan.
- `limine-snapper-sync` restaura con `RESTORE_METHOD=replace`, que no puede
  restaurar un sistema sin subvolumen raíz: los snapshots arrancan, pero
  «Restaurar» no funciona.

Este esquema separa lo que no es sistema. Es el que `limine-snapper-sync`
espera por defecto (`/@` y `/@/.snapshots`):

| Subvolumen | Se monta en | Por qué |
| --- | --- | --- |
| `@` | `/` | Lo único que cubren los snapshots |
| `@home` | `/home` | Home, VMs, Steam y `~/.cache` fuera de los snapshots |
| `@log` | `/var/log` | Los logs sobreviven a una restauración |
| `@pkg` | `/var/cache/pacman/pkg` | La caché de pacman fuera de los snapshots |
| `@docker` | `/var/lib/docker` | Contenedores y volúmenes de Docker fuera de los snapshots |
| `@containerd` | `/var/lib/containerd` | Las capas de las imágenes: Docker 29 las guarda en containerd |
| `@swap` | `/swap` | Swapfile de hibernación, sin copy-on-write |

`/.snapshots` no se crea aquí: el instalador ejecuta `snapper create-config /`,
que lo crea dentro de `@`.

```bash
mount /dev/nvme0n1p4 /mnt
for sv in @ @home @log @pkg @docker @containerd @swap; do btrfs subvolume create "/mnt/$sv"; done
chattr +C /mnt/@swap
umount /mnt

opts=relatime,ssd,discard=async,space_cache=v2,compress=zstd:1
mount -o "$opts,subvol=@" /dev/nvme0n1p4 /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,var/lib/docker,var/lib/containerd,swap,boot}
mount -o "$opts,subvol=@home"       /dev/nvme0n1p4 /mnt/home
mount -o "$opts,subvol=@log"        /dev/nvme0n1p4 /mnt/var/log
mount -o "$opts,subvol=@pkg"        /dev/nvme0n1p4 /mnt/var/cache/pacman/pkg
mount -o "$opts,subvol=@docker"     /dev/nvme0n1p4 /mnt/var/lib/docker
mount -o "$opts,subvol=@containerd" /dev/nvme0n1p4 /mnt/var/lib/containerd
mount -o "$opts,subvol=@swap"       /dev/nvme0n1p4 /mnt/swap
mount /dev/nvme0n1p1 /mnt/boot          # la ESP (Omarchy la monta en /boot)
```

`compress=zstd:1` sólo comprime lo que se escribe a partir de ahora; el
swapfile y los archivos con `chattr +C` no se comprimen.

Tu fstab actual también monta Windows en `/mnt/windows` (`ntfs3`, con
`x-systemd.automount` y `nofail`). Si lo quieres igual, añade esa línea a
`/etc/fstab` tras el primer arranque.

### Paquetes mínimos e idioma

```bash
pacstrap -K /mnt base linux linux-firmware btrfs-progs limine efibootmgr \
  networkmanager sudo git zsh neovim intel-ucode   # amd-ucode en CPU AMD
genfstab -U /mnt >> /mnt/etc/fstab
# Restaurar con «replace» cambia el ID de @: monta por nombre, no por ID.
sed -i 's/subvolid=[0-9]*,//' /mnt/etc/fstab
arch-chroot /mnt
```

Revisa `/mnt/etc/fstab`: debe tener una línea por subvolumen, todas con
`subvol=` y ninguna con `subvolid=`.

Dentro del chroot:

```bash
ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime   # tu zona
hwclock --systohc
sed -i 's/^#\(es_CL.UTF-8\|en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
echo 'LANG=es_CL.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf
echo 'omen' > /etc/hostname                 # nombre del equipo

useradd -m -G wheel -s /bin/zsh wh01s17 && passwd wh01s17
passwd                                      # root
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
systemctl enable NetworkManager
```

### Limine

El instalador añadirá después `limine-mkinitcpio-hook` y
`limine-snapper-sync`, que mantienen las entradas (kernels, snapshots y
Windows). Ahora basta con que el sistema arranque:

```bash
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
efibootmgr --create --disk /dev/nvme0n1 --part 1 \
  --label "Arch Linux" --loader '\EFI\limine\BOOTX64.EFI' --unicode

root_uuid=$(blkid -s PARTUUID -o value /dev/nvme0n1p4)
cat > /etc/default/limine <<EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]+="root=PARTUUID=$root_uuid rootflags=subvol=@ zswap.enabled=0 rw rootfstype=btrfs"
EOF

cat > /boot/limine.conf <<EOF
timeout: 3

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: root=PARTUUID=$root_uuid rootflags=subvol=@ zswap.enabled=0 rw rootfstype=btrfs
    module_path: boot():/initramfs-linux.img
EOF
exit
umount -R /mnt && reboot
```

Con `FIND_BOOTLOADERS=yes` (lo configura el instalador), Limine añade
Windows solo. Si no aparece, sigue `omarchy/dual-boot.md` (repo privado post-install-linux) §6.

## 3. Primer arranque y escritorio

Entra en la TTY con tu usuario y conéctate a la red (`nmtui`). Después:

```bash
git clone https://github.com/wh01s17/arch-desktop.git ~/workspace/arch-desktop
cd ~/workspace/arch-desktop
./install.sh --dry-run      # revisa el plan sin tocar nada
./install.sh
```

El instalador detecta el equipo y pregunta:

| Pregunta | Propuesta |
| --- | --- |
| Perfil de monitores y fuente | El del modelo en `profiles/machines.tsv` (`omen`), o `auto` en un equipo nuevo |
| Tamaño de fuente de Kitty | Sólo con `auto`: 11, o 12 si hay una pantalla 4K |
| Driver de GPU | Detectado: `nvidia-legacy` (GTX 10xx), `nvidia`, `amd`, `intel`, `vm` o `none` |
| Grupos opcionales | `dev`, `apps`, `gaming`, `virtualization` sí; `pentest` no |
| Hibernación | Sí en portátiles con btrfs y Limine |
| Autologin | Sí, como hoy |
| Nombre y correo de git | Los de `git config` si existen |

Las respuestas quedan en `~/.config/wh01s17/machine.env`. Al terminar,
reinicia: SDDM abre la sesión «wh01s17 (Hyprland uwsm)» y el primer inicio
completa los servicios de usuario, el tema GTK y los avisos.

Antes de traer las VMs del respaldo, crea su carpeta vacía sin
copy-on-write; los archivos que copies ahí heredan el atributo:

```bash
mkdir -p ~/"VirtualBox VMs" && chattr +C ~/"VirtualBox VMs"
```

En un equipo con perfil `auto`, coloca las pantallas en el panel Monitor de
la barra: la escala, la resolución y la disposición se guardan solas. Para
convertirlo en un perfil con nombre, copia `profiles/hp-gray.lua` como base,
añade su nombre al mapa de `monitors.lua` y su modelo a
`profiles/machines.tsv`.

## 4. Comprobaciones

```bash
tools/compare-binds.sh          # atajos frente a Omarchy (sin los descartados)
hyprctl configerrors                 # vacío
systemctl --failed; systemctl --user --failed
nvidia-smi                           # con GPU NVIDIA
cat /sys/module/nvidia_drm/parameters/modeset   # Y
snapper list                         # snapshots de pacman (snap-pac)
sudo btrfs subvolume list /          # @, @home, @log, @pkg, @docker, @containerd, @swap y @/.snapshots
findmnt -t btrfs -o TARGET,OPTIONS   # / con subvol=/@ y compress=zstd:1
lsattr -d ~/"VirtualBox VMs"         # con la C de no copy-on-write
```

Prueba también: suspender y reanudar, hibernar, cerrar la tapa, conectar y
desconectar monitores, compartir pantalla en Chrome, la ñ y las tildes en
Chrome, VS Code y Obsidian, y arrancar un snapshot y Windows desde Limine.
Prueba también una restauración real: arranca un snapshot, pulsa «Restaurar»
y comprueba que el sistema vuelve a ese estado y que `/home` sigue intacto.

## 5. Volver a ejecutar o cambiar decisiones

```bash
./install.sh                       # idempotente; reutiliza machine.env
./install.sh --reconfigure         # vuelve a preguntar
./install.sh --only "stow seed"    # sólo algunas etapas
./install.sh --groups "dev apps" --gpu nvidia --yes   # sin preguntas
```

Etapas: `preflight bootstrap dotfiles decide packages aur fixes stow seed machine
system user hibernate shell services validate`.

Para actualizar una instalación que ya estás probando, sigue [UPDATE.md](UPDATE.md).
