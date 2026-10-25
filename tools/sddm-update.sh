#!/usr/bin/env bash
# Trae la última versión de ~/dotfiles y reinstala la pantalla de login (tema de
# SDDM y su configuración de Hyprland), como hace lib/system-setup.sh.
# Ejecútalo desde una TTY (Ctrl+Alt+F3):  tools/sddm-update.sh
# Desbloquea además el usuario si los intentos fallidos lo dejaron bloqueado,
# y reinicia SDDM, lo que cierra la sesión gráfica.
set -Eeuo pipefail

die() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }
log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }

readonly DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
platform="$DOTFILES_DIR/platform/.local/share/wh01s17"
[[ -d $platform/default/sddm/wh01s17 ]] || die "No encuentro el tema en $platform."

log 'Actualizando ~/dotfiles'
git -C "$DOTFILES_DIR" pull --ff-only || die 'git pull falló; revisa ~/dotfiles (¿cambios sin guardar?).'

log 'Instalando el tema de login (pide tu contraseña)'
sudo rm -rf /usr/share/sddm/themes/wh01s17
sudo install -d /usr/share/sddm/themes
sudo cp -r "$platform/default/sddm/wh01s17" /usr/share/sddm/themes/wh01s17
sudo install -m 0644 "$platform/system/usr/share/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua
sudo faillock --user "$USER" --reset

log 'Reiniciando SDDM'
sudo systemctl restart sddm
