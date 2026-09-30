#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
dry_run=false
backup_dir=""
profile="auto"

usage() {
  cat <<'EOF'
Uso: ./arch/install.sh [--dry-run] [--profile auto|omen|hp-gray]

Reproduce la apariencia wh01s17 en Arch con Hyprland, Quickshell, Kitty y
Oh My Posh. Respaldará cada configuración que reemplace en
~/.config-backup/arch-look/<fecha>/.

Variables: DOTFILES_DIR (por defecto ~/dotfiles).
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --profile)
      (($# >= 2)) || { echo '--profile requiere un nombre' >&2; exit 2; }
      profile=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
case "$profile" in auto|omen|hp-gray) ;; *) echo "Perfil desconocido: $profile" >&2; exit 2 ;; esac

for source_file in \
  "$script_dir/config/hyprland.lua" "$script_dir/config/bindings.lua" \
  "$script_dir/config/monitors-$profile.lua" "$script_dir/config/shell.qml" \
  "$script_dir/config/kitty.conf" "$script_dir/config/colors.conf" \
  "$script_dir/config/kitty-$profile.conf" "$script_dir/config/wofi.css" \
  "$script_dir/config/swaync.css" "$script_dir/config/hyprlock.conf" \
  "$script_dir/config/hypridle.conf" "$script_dir/config/zshrc" \
  "$script_dir/config/arch-look-action" "$script_dir/KEYBINDINGS.md"; do
  [[ -f "$source_file" ]] || { printf 'Falta archivo del instalador: %s\n' "$source_file" >&2; exit 1; }
done

packages=(
  hyprland xorg-xwayland quickshell kitty swaybg swaync wofi hyprlock hypridle hyprpicker
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk polkit-kde-agent
  grim slurp wf-recorder wl-clipboard cliphist tesseract ffmpeg zenity util-linux hyprsunset
  networkmanager network-manager-applet nm-connection-editor
  pipewire pipewire-pulse wireplumber pavucontrol playerctl brightnessctl
  bluez blueman wdisplays
  git curl unzip jq python lua qt6-declarative fzf zsh neovim tmux btop nautilus firefox libqalculate
  xdg-utils libnotify procps-ng
  ttf-jetbrains-mono-nerd ttf-meslo-nerd noto-fonts noto-fonts-emoji
)

if [[ $dry_run == true ]]; then
  printf 'Instalaría %s paquetes con sudo pacman -Syu --needed.\n' "${#packages[@]}"
  printf 'Clonaría/leerá dotfiles en: %s\n' "$dotfiles_dir"
  printf 'Perfil de monitores y fuente: %s\n' "$profile"
  printf 'Copiaría Hyprland, Quickshell, Kitty, Zsh y tema wh01s17 a ~/.config.\n'
  printf 'Respaldaría archivos existentes antes de reemplazarlos.\n'
  exit 0
fi

[[ $EUID -ne 0 ]] || { echo 'Ejecuta el script como usuario normal.' >&2; exit 1; }
source /etc/os-release
[[ ${ID:-} == arch ]] || { echo 'Este instalador requiere Arch Linux.' >&2; exit 1; }
if command -v omarchy >/dev/null 2>&1; then
  echo 'Este instalador es para Arch sin Omarchy. Se canceló para proteger la sesión actual.' >&2
  exit 1
fi

[[ ! -e "$dotfiles_dir" || -e "$dotfiles_dir/.git" ]] ||
  { echo "$dotfiles_dir existe y no es un repositorio Git" >&2; exit 1; }

# Never copy through a directory symlink: Stow may own ~/.config/kitty, etc.
check_target_path() {
  local parent
  if [[ -L "$1" ]]; then
    printf 'Conflicto con Stow/enlace simbólico: %s\n' "$1" >&2
    return 1
  fi
  parent="$(dirname "$1")"
  while [[ "$parent" != "$HOME" && "$parent" != / ]]; do
    if [[ -L "$parent" ]]; then
      printf 'Conflicto con Stow/enlace simbólico: %s (destino: %s)\n' "$parent" "$1" >&2
      return 1
    fi
    parent="$(dirname "$parent")"
  done
}
for target in \
  "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprlock.conf" \
  "$HOME/.config/hypr/hypridle.conf" "$HOME/.config/arch-look/bindings.lua" \
  "$HOME/.config/arch-look/monitors.lua" "$HOME/.config/arch-look/shell.qml" \
  "$HOME/.config/arch-look/KEYBINDINGS.md" "$HOME/.config/arch-look/wallpaper-1.png" \
  "$HOME/.config/arch-look/wallpaper-2.png" "$HOME/.config/arch-look/wallpaper.png" \
  "$HOME/.config/arch-look/logo.svg" "$HOME/.config/kitty/kitty.conf" \
  "$HOME/.config/kitty/colors.conf" "$HOME/.config/kitty/machine-profile.conf" \
  "$HOME/.config/wofi/style.css" "$HOME/.config/swaync/style.css" \
  "$HOME/.config/oh-my-posh" "$HOME/.zshrc" \
  "$HOME/.local/bin/arch-look-action" \
  "$HOME/.local/state/omarchy/current/theme/kitty.conf"; do
  check_target_path "$target" || exit 1
done

verify_dotfiles_assets() {
  local asset
  for asset in \
    desktop/.config/omarchy/themes/wh01s17/backgrounds/01-solid-mark.png \
    desktop/.config/omarchy/themes/wh01s17/backgrounds/02-outline-mark.png \
    desktop/.config/omarchy/themes/wh01s17/brand/logo.svg \
    terminal/.config/oh-my-posh/active.omp.json \
    terminal/.config/oh-my-posh/theme-picker.zsh; do
    [[ -f "$dotfiles_dir/$asset" ]] || { printf 'Falta en dotfiles: %s\n' "$asset" >&2; return 1; }
  done
}
if [[ -e "$dotfiles_dir/.git" ]]; then verify_dotfiles_assets || exit 1; fi

echo '==> Instalando componentes visuales desde repositorios de Arch'
sudo pacman -Syu --needed "${packages[@]}"

if [[ ! -e "$dotfiles_dir/.git" ]]; then
  git clone https://github.com/wh01s17/dotfiles.git "$dotfiles_dir"
fi
verify_dotfiles_assets

export PATH="$HOME/.local/bin:$PATH"
if ! command -v oh-my-posh >/dev/null 2>&1; then
  echo '==> Instalando Oh My Posh en ~/.local/bin'
  mkdir -p "$HOME/.local/bin"
  installer="$(mktemp)"
  trap 'rm -f -- "${installer:-}"' EXIT
  curl --fail --location --silent --show-error https://ohmyposh.dev/install.sh -o "$installer"
  bash "$installer" -d "$HOME/.local/bin"
fi

mkdir -p "$HOME/.config-backup/arch-look"
backup_dir="$(mktemp -d "$HOME/.config-backup/arch-look/$(date +%Y-%m-%d_%H-%M-%S)-XXXXXX")"
install_file() {
  local source=$1 target=$2 relative
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then return; fi
    relative="${target#"$HOME"/}"
    mkdir -p "$backup_dir/$(dirname "$relative")"
    mv -- "$target" "$backup_dir/$relative"
  fi
  cp -- "$source" "$target"
}

echo '==> Instalando la apariencia y respaldando conflictos'
install_file "$script_dir/config/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
install_file "$script_dir/config/bindings.lua" "$HOME/.config/arch-look/bindings.lua"
install_file "$script_dir/config/monitors-$profile.lua" "$HOME/.config/arch-look/monitors.lua"
install_file "$script_dir/config/shell.qml" "$HOME/.config/arch-look/shell.qml"
install_file "$script_dir/config/kitty.conf" "$HOME/.config/kitty/kitty.conf"
install_file "$script_dir/config/colors.conf" "$HOME/.config/kitty/colors.conf"
install_file "$script_dir/config/kitty-$profile.conf" "$HOME/.config/kitty/machine-profile.conf"
install_file "$script_dir/config/wofi.css" "$HOME/.config/wofi/style.css"
install_file "$script_dir/config/swaync.css" "$HOME/.config/swaync/style.css"
install_file "$script_dir/config/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf"
install_file "$script_dir/config/hypridle.conf" "$HOME/.config/hypr/hypridle.conf"
install_file "$script_dir/config/zshrc" "$HOME/.zshrc"
install_file "$script_dir/config/arch-look-action" "$HOME/.local/bin/arch-look-action"
chmod +x "$HOME/.local/bin/arch-look-action"
install_file "$script_dir/KEYBINDINGS.md" "$HOME/.config/arch-look/KEYBINDINGS.md"
install_file "$dotfiles_dir/desktop/.config/omarchy/themes/wh01s17/backgrounds/01-solid-mark.png" "$HOME/.config/arch-look/wallpaper-1.png"
install_file "$dotfiles_dir/desktop/.config/omarchy/themes/wh01s17/backgrounds/02-outline-mark.png" "$HOME/.config/arch-look/wallpaper-2.png"
install_file "$dotfiles_dir/desktop/.config/omarchy/themes/wh01s17/brand/logo.svg" "$HOME/.config/arch-look/logo.svg"
install_file "$HOME/.config/arch-look/wallpaper-1.png" "$HOME/.config/arch-look/wallpaper.png"

if [[ -e "$HOME/.config/oh-my-posh" || -L "$HOME/.config/oh-my-posh" ]]; then
  mkdir -p "$backup_dir/.config"
  mv -- "$HOME/.config/oh-my-posh" "$backup_dir/.config/oh-my-posh"
fi
mkdir -p "$HOME/.config/oh-my-posh"
cp -a "$dotfiles_dir/terminal/.config/oh-my-posh/." "$HOME/.config/oh-my-posh/"

# Compatibility palette for the existing omp-theme compositor; no Omarchy runtime.
mkdir -p "$HOME/.local/state/omarchy/current/theme"
install_file "$script_dir/config/colors.conf" "$HOME/.local/state/omarchy/current/theme/kitty.conf"

echo '==> Activando red y Bluetooth (sudo puede pedir contraseña)'
sudo systemctl enable --now NetworkManager.service bluetooth.service
systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service ||
  echo 'Aviso: revisa los servicios de audio del usuario al iniciar sesión.' >&2

echo '==> Validando archivos'
zsh -n "$HOME/.zshrc"
zsh -n "$HOME/.config/oh-my-posh/theme-picker.zsh"
jq empty "$HOME/.config/oh-my-posh/active.omp.json"
oh-my-posh print primary --config "$HOME/.config/oh-my-posh/active.omp.json" --shell zsh --plain >/dev/null
if command -v luac >/dev/null 2>&1; then luac -p "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/arch-look/bindings.lua"; fi
if command -v qmllint >/dev/null 2>&1; then qmllint "$HOME/.config/arch-look/shell.qml"; fi
Hyprland --verify-config --config "$HOME/.config/hypr/hyprland.lua"

printf '\nListo. Respaldos: %s\n' "$backup_dir"
echo 'Cierra sesión e inicia Hyprland. Consulta arch/README.md para diferencias con Omarchy.'
