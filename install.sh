#!/usr/bin/env bash
# Instala el escritorio wh01s17 (runtime congelado + tus dotfiles) en
# un Arch Linux recién instalado. Ver README.md y PLAN.md.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$script_dir/lib/detect.sh"

readonly DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/wh01s17/dotfiles.git}"
readonly DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
readonly BLACKARCH_STRAP_SHA1="${BLACKARCH_STRAP_SHA1:-d338a4bb95d9e09f97508da68ac9e17d963b85f6}"
readonly PACKAGES_DIR="$script_dir/packages"
readonly MACHINES_TSV="$script_dir/profiles/machines.tsv"
readonly MACHINE_ENV="$HOME/.config/wh01s17/machine.env"
readonly PLATFORM_DIR="$HOME/.local/share/wh01s17"
readonly ARCH_BUILD_DIR="$DOTFILES_DIR/.arch-build"
# DIR:PACKAGE. desktop and terminal keep Omarchy's names in ~/dotfiles (your
# Omarchy machine uses them); tools/arch-dotfiles.py builds the wh01s17 version.
readonly STOW_PACKAGES=("$DOTFILES_DIR:platform" "$DOTFILES_DIR:maintenance" "$ARCH_BUILD_DIR:desktop" "$ARCH_BUILD_DIR:terminal")
readonly STOW_NO_FOLDING_PACKAGES=("$DOTFILES_DIR:apps")
readonly SOURCE_PACKAGES=(platform maintenance apps desktop terminal)
readonly OPTIONAL_GROUPS=(dev apps gaming virtualization pentest)
readonly ALL_STAGES=(preflight bootstrap dotfiles decide packages aur stow seed machine system user hibernate shell services validate)
readonly EXTERNAL_SHELL_PLUGIN_ID=io.github.sirjul1337.lock-explorer
readonly EXTERNAL_SHELL_PLUGIN_URL=https://github.com/SirJul1337/omarchy-lock-explorer.git
# Web apps the runtime installs that you do not use (PLAN.md, D7).
readonly DROPPED_DESKTOP_FILES=(
  HEY X YouTube Zoom "Google Contacts" "Google Maps" "Google Messages" "Google Photos"
)
# Command launchers in ~/.local/bin for the tools in apps/.config/mise/config.toml
# ("PACKAGE" or "PACKAGE COMMAND"). Your .zshrc drops mise's shims from PATH, so
# these are what make `claude` and the rest work; each installs on first run.
readonly MISE_LAUNCHERS=(claude codex copilot gemini gh opencode "npm:@xai-official/grok grok")

DRY_RUN=false
ASSUME_YES=false
RECONFIGURE=false
ONLY_STAGES=""
SKIP_STAGES=""
OPT_PROFILE=""
OPT_GPU=""
OPT_GROUPS=""
OPT_AUTOLOGIN=""
OPT_HIBERNATE=""
BACKUP_DIR=""
declare -a TEMP_FILES=()
declare -a WARNINGS=()

WH_PROFILE="" WH_KITTY_FONT_SIZE="" WH_GPU="" WH_GROUPS="" WH_HIBERNATE="" WH_AUTOLOGIN=""
WH_USER_NAME="" WH_USER_EMAIL=""

usage() {
  cat <<EOF
Uso: ./install.sh [opciones]

Instala en Arch Linux el escritorio wh01s17: Hyprland, su shell (paquete Stow
«platform»), tus dotfiles con los nombres de wh01s17, tus apps y la
configuración de sistema. Detecta el equipo y pregunta lo necesario; guarda las
respuestas en ~/.config/wh01s17/machine.env para no repetirlas.

Opciones:
  --dry-run               Muestra lo que haría, sin cambiar nada
  --yes                   Acepta los valores propuestos sin preguntar
  --reconfigure           Vuelve a preguntar aunque exista machine.env
  --profile NOMBRE        Perfil de equipo (omen, hp-gray, auto…)
  --gpu FAMILIA           nvidia-legacy, nvidia, amd, intel, vm o none
  --groups "A B"          Grupos opcionales: ${OPTIONAL_GROUPS[*]}
  --autologin|--no-autologin
  --hibernate|--no-hibernate
  --only "ETAPA …"        Ejecuta sólo esas etapas
  --skip "ETAPA …"        Omite esas etapas
  -h, --help

Etapas: ${ALL_STAGES[*]}

Variables: DOTFILES_REPO, DOTFILES_DIR (~/dotfiles), BLACKARCH_STRAP_SHA1.
EOF
}

cleanup() {
  local path
  for path in "${TEMP_FILES[@]}"; do
    [[ -n $path && -e $path ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT
trap 'warn "Falló la línea $LINENO (código $?)."' ERR

note() { WARNINGS+=("$1"); warn "$1"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --yes) ASSUME_YES=true ;;
      --reconfigure) RECONFIGURE=true ;;
      --profile|--gpu|--groups|--only|--skip)
        (($# >= 2)) || die "$1 requiere un valor."
        case "$1" in
          --profile) OPT_PROFILE=$2 ;;
          --gpu) OPT_GPU=$2 ;;
          --groups) OPT_GROUPS=$2 ;;
          --only) ONLY_STAGES=$2 ;;
          --skip) SKIP_STAGES=$2 ;;
        esac
        shift
        ;;
      --autologin) OPT_AUTOLOGIN=1 ;;
      --no-autologin) OPT_AUTOLOGIN=0 ;;
      --hibernate) OPT_HIBERNATE=1 ;;
      --no-hibernate) OPT_HIBERNATE=0 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "Opción desconocida: $1" ;;
    esac
    shift
  done
  local stage
  for stage in $ONLY_STAGES $SKIP_STAGES; do
    [[ " ${ALL_STAGES[*]} " == *" $stage "* ]] || die "Etapa desconocida: $stage"
  done
}

wanted() {
  local stage=$1
  [[ -z $ONLY_STAGES || " $ONLY_STAGES " == *" $stage "* ]] || return 1
  [[ " $SKIP_STAGES " != *" $stage "* ]]
}

as_root() { run sudo "$@"; }

# ---------------------------------------------------------------- preflight

stage_preflight() {
  log 'Comprobaciones previas'
  ((EUID != 0)) || die 'Ejecuta el instalador como usuario normal; usará sudo cuando haga falta.'
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == arch || " ${ID_LIKE:-} " == *" arch "* ]] || die 'Este instalador es para Arch Linux.'
  if pacman -Q omarchy >/dev/null 2>&1 || [[ -d /usr/share/omarchy ]]; then
    if [[ $DRY_RUN == true ]]; then
      warn 'Este equipo tiene Omarchy; el --dry-run continúa sólo para mostrar el plan.'
    else
      die 'Este equipo tiene Omarchy instalado. El instalador es para Arch puro.'
    fi
  fi
  if [[ $DRY_RUN != true ]]; then
    curl -fsI --max-time 10 https://archlinux.org >/dev/null ||
      die 'Sin acceso a internet (https://archlinux.org).'
    sudo -v || die 'Se necesita sudo.'
  fi
}

stage_bootstrap() {
  log 'Herramientas mínimas (git, stow, base-devel)'
  local -a missing=()
  local package
  for package in git stow base-devel curl; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done
  ((${#missing[@]})) || { info 'Ya están instaladas.'; return; }
  as_root pacman -Sy --needed --noconfirm "${missing[@]}"
}

stage_dotfiles() {
  log "Dotfiles en $DOTFILES_DIR"
  clone_or_pull "$DOTFILES_REPO" "$DOTFILES_DIR"
  if [[ $DRY_RUN == true && ! -d $DOTFILES_DIR ]]; then
    return
  fi
  local package
  for package in "${SOURCE_PACKAGES[@]}"; do
    [[ -d $DOTFILES_DIR/$package ]] || die "Los dotfiles no tienen el paquete Stow «$package»."
  done
}

# ------------------------------------------------------------------- decide

available_profiles() {
  local path
  for path in "$DOTFILES_DIR"/desktop/.config/hypr/profiles/*.lua; do
    [[ -f $path ]] && basename "$path" .lua
  done
}

suggest_font_size() {
  local display
  for display in "${DETECT_DISPLAYS[@]}"; do
    [[ $display =~ \ ([0-9]+)x ]] && ((BASH_REMATCH[1] >= 3840)) && { echo 12.0; return; }
  done
  echo 11.0
}

stage_decide() {
  detect_hardware
  print_detection

  if [[ $RECONFIGURE != true ]] && load_machine_env; then
    log "Respuestas guardadas en $MACHINE_ENV (usa --reconfigure para cambiarlas)"
  else
    log 'Decisiones para este equipo'
    local -a profiles groups=()
    mapfile -t profiles < <(available_profiles)
    local default_profile=${DETECT_PROFILE:-auto}
    choose WH_PROFILE "Perfil de monitores y fuente (auto = cualquier equipo; ajusta las pantallas luego en el panel Monitor):" \
      "$default_profile" "${profiles[@]}" auto

    if [[ $WH_PROFILE == auto ]]; then
      prompt_value WH_KITTY_FONT_SIZE 'Tamaño de fuente de Kitty' "$(suggest_font_size)"
    else
      WH_KITTY_FONT_SIZE=""
    fi

    local default_gpu=$DETECT_GPU
    if [[ $default_gpu == nvidia-unsupported ]]; then
      warn 'La GPU NVIDIA es anterior a Maxwell: no hay driver propietario en Arch; se propone nouveau (none).'
      default_gpu=none
    fi
    choose WH_GPU 'Driver de GPU:' "$default_gpu" nvidia-legacy nvidia amd intel vm none

    local group default
    for group in "${OPTIONAL_GROUPS[@]}"; do
      default=s
      [[ $group == pentest ]] && default=n
      [[ $DETECT_VIRT != none && ($group == gaming || $group == virtualization) ]] && default=n
      if ask "¿Instalar el grupo «$group» ($(group_summary "$group"))?" "$default"; then
        groups+=("$group")
      fi
    done
    WH_GROUPS="${groups[*]}"

    WH_HIBERNATE=0
    if [[ $DETECT_LAPTOP == yes && $DETECT_ROOT_FS == btrfs && $DETECT_BOOTLOADER == limine ]]; then
      ask '¿Configurar hibernación (swapfile en btrfs del tamaño de la RAM)?' s && WH_HIBERNATE=1
    fi
    WH_AUTOLOGIN=0
    ask '¿Inicio de sesión automático (como hoy, sin contraseña en SDDM)?' s && WH_AUTOLOGIN=1

    prompt_value WH_USER_NAME 'Nombre para git (vacío = no tocar)' "$(git config --global user.name 2>/dev/null || true)"
    prompt_value WH_USER_EMAIL 'Correo para git (vacío = no tocar)' "$(git config --global user.email 2>/dev/null || true)"
  fi

  # Las opciones de la línea de órdenes mandan sobre lo guardado.
  [[ -n $OPT_PROFILE ]] && WH_PROFILE=$OPT_PROFILE
  [[ -n $OPT_GPU ]] && WH_GPU=$OPT_GPU
  [[ -n $OPT_GROUPS ]] && WH_GROUPS=$OPT_GROUPS
  [[ -n $OPT_AUTOLOGIN ]] && WH_AUTOLOGIN=$OPT_AUTOLOGIN
  [[ -n $OPT_HIBERNATE ]] && WH_HIBERNATE=$OPT_HIBERNATE
  [[ $WH_PROFILE == auto && -z $WH_KITTY_FONT_SIZE ]] && WH_KITTY_FONT_SIZE=$(suggest_font_size)

  case $WH_GPU in nvidia-legacy|nvidia|amd|intel|vm|none) ;; *) die "GPU desconocida: $WH_GPU" ;; esac
  local group
  for group in $WH_GROUPS; do
    [[ " ${OPTIONAL_GROUPS[*]} " == *" $group "* ]] || die "Grupo desconocido: $group"
  done
  if [[ $WH_PROFILE != auto && -d $DOTFILES_DIR ]] &&
    [[ ! -f $DOTFILES_DIR/desktop/.config/hypr/profiles/$WH_PROFILE.lua ]]; then
    die "Perfil desconocido: $WH_PROFILE (disponibles: $(available_profiles | tr '\n' ' ')auto)"
  fi

  save_machine_env
  log 'Resumen'
  info "Perfil: $WH_PROFILE${WH_KITTY_FONT_SIZE:+ (Kitty $WH_KITTY_FONT_SIZE)} · GPU: $WH_GPU"
  info "Grupos: ${WH_GROUPS:-ninguno} · hibernación: $WH_HIBERNATE · autologin: $WH_AUTOLOGIN"
}

group_summary() {
  case $1 in
    dev) echo 'Docker, lazydocker, VS Code, toolchains de LazyVim' ;;
    apps) echo 'Obsidian, OBS, Kdenlive, LibreOffice, Chrome, Spotify, Typora…' ;;
    gaming) echo 'Steam' ;;
    virtualization) echo 'VirtualBox' ;;
    pentest) echo 'BlackArch y herramientas de pentesting' ;;
  esac
}

# ----------------------------------------------------------------- packages

official_lists() {
  local group
  printf '%s\n' "$PACKAGES_DIR"/{base,desktop,fonts,terminal}.txt
  for group in $WH_GROUPS; do
    [[ $group == pentest ]] && continue
    [[ -f $PACKAGES_DIR/$group.txt ]] && printf '%s\n' "$PACKAGES_DIR/$group.txt"
  done
  [[ -f $PACKAGES_DIR/gpu-$WH_GPU.txt ]] && printf '%s\n' "$PACKAGES_DIR/gpu-$WH_GPU.txt"
  return 0
}

aur_lists() {
  local group
  printf '%s\n' "$PACKAGES_DIR/core.aur.txt"
  for group in $WH_GROUPS; do
    [[ -f $PACKAGES_DIR/$group.aur.txt ]] && printf '%s\n' "$PACKAGES_DIR/$group.aur.txt"
  done
  [[ -f $PACKAGES_DIR/gpu-$WH_GPU.aur.txt ]] && printf '%s\n' "$PACKAGES_DIR/gpu-$WH_GPU.aur.txt"
  return 0
}

enable_multilib() {
  grep -qE '^\[multilib\]' /etc/pacman.conf && return 0
  log 'Activando el repositorio multilib (Steam, lib32 de la GPU)'
  as_root sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
}

stage_packages() {
  local -a lists packages available=() missing=()
  mapfile -t lists < <(official_lists)
  mapfile -t packages < <(read_list "${lists[@]}" | sort -u)
  enable_multilib
  run sudo pacman -Sy
  local package
  for package in "${packages[@]}"; do
    if pacman -Si "$package" >/dev/null 2>&1 || [[ $DRY_RUN == true ]]; then
      available+=("$package")
    else
      missing+=("$package")
    fi
  done
  ((${#missing[@]})) && note "No están en los repositorios y se omiten: ${missing[*]}"
  log "Instalando ${#available[@]} paquetes oficiales"
  as_root pacman -Su --needed --noconfirm "${available[@]}"
}

install_yay() {
  command -v yay >/dev/null 2>&1 && return 0
  log 'Instalando yay (AUR)'
  local build
  build=$(mktemp -d)
  TEMP_FILES+=("$build")
  run git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$build/yay-bin"
  if [[ $DRY_RUN == true ]]; then
    info '[dry-run] makepkg -si --noconfirm en yay-bin'
  else
    (cd "$build/yay-bin" && makepkg -si --noconfirm)
  fi
}

install_blackarch() {
  local strap
  if ! grep -qE '^\[blackarch\]' /etc/pacman.conf; then
    log 'Configurando BlackArch (strap.sh verificado con SHA-1)'
    strap=$(mktemp)
    TEMP_FILES+=("$strap")
    run curl -fsSL https://blackarch.org/strap.sh -o "$strap"
    if [[ $DRY_RUN != true ]]; then
      printf '%s  %s\n' "$BLACKARCH_STRAP_SHA1" "$strap" | sha1sum -c - ||
        die 'El SHA-1 de strap.sh no coincide; actualiza BLACKARCH_STRAP_SHA1 desde blackarch.org/downloads.html.'
      chmod +x "$strap"
    fi
    as_root "$strap"
    as_root pacman -Syyu --noconfirm
  fi
  local -a wanted_packages available=() missing=()
  mapfile -t wanted_packages < <(read_list "$PACKAGES_DIR/pentest.txt")
  local package
  for package in "${wanted_packages[@]}"; do
    if pacman -Si "$package" >/dev/null 2>&1 || [[ $DRY_RUN == true ]]; then
      available+=("$package")
    else
      missing+=("$package")
    fi
  done
  ((${#missing[@]})) && note "BlackArch ya no publica: ${missing[*]}"
  if ((${#available[@]})); then
    as_root pacman -S --needed --noconfirm "${available[@]}"
  fi
}

# User makepkg.conf: no -debug split packages (slow and noisy for prebuilt
# binaries) and parallel jobs capped by RAM, about 2 GB per compile job.
configure_makepkg() {
  local conf="$HOME/.config/pacman/makepkg.conf" jobs mem_gb
  mem_gb=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 / 1024 }' /proc/meminfo)
  jobs=$((mem_gb / 2))
  ((jobs > $(nproc))) && jobs=$(nproc)
  ((jobs < 1)) && jobs=1
  log "makepkg: sin paquetes -debug y $jobs trabajo(s) en paralelo (${mem_gb} GB de RAM)"
  if [[ $DRY_RUN == true ]]; then
    info "[dry-run] escribiría $conf"
    return
  fi
  mkdir -p "$(dirname "$conf")"
  cat >"$conf" <<EOC
# Escrito por arch-desktop/install.sh (wh01s17). Se lee después de /etc/makepkg.conf.
OPTIONS=("\${OPTIONS[@]/#debug/!debug}")
MAKEFLAGS="-j$jobs"
export CARGO_BUILD_JOBS=$jobs
EOC
}

# AUR packages that verify upstream signatures need the vendor's key first.
# package → "key URL|full fingerprint" (fingerprint from the PKGBUILD's validpgpkeys).
declare -A AUR_SIGNING_KEYS=(
  [spotify]="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg|E1096BCBFF6D418796DE78515384CE82BA52C83A"
)

import_aur_key() {
  local package=$1 url fingerprint
  [[ -n ${AUR_SIGNING_KEYS[$package]:-} ]] || return 0
  url=${AUR_SIGNING_KEYS[$package]%%|*}
  fingerprint=${AUR_SIGNING_KEYS[$package]#*|}
  gpg --list-keys "$fingerprint" >/dev/null 2>&1 && return 0
  info "Importando la clave de firma de $package"
  if [[ $DRY_RUN == true ]]; then
    info "[dry-run] curl -sS $url | gpg --import"
    return 0
  fi
  curl -fsS "$url" | gpg --import 2>/dev/null
  gpg --list-keys "$fingerprint" >/dev/null 2>&1 ||
    { note "La clave importada para $package no tiene la huella $fingerprint."; return 1; }
}

stage_aur() {
  configure_makepkg
  install_yay
  has_group pentest && install_blackarch
  local -a lists packages failed=()
  mapfile -t lists < <(aur_lists)
  mapfile -t packages < <(read_list "${lists[@]}" | sort -u)
  if [[ $DETECT_BOOTLOADER == limine && $DETECT_ROOT_FS == btrfs ]]; then
    packages+=(limine-mkinitcpio-hook limine-snapper-sync)
  fi
  log "Instalando ${#packages[@]} paquetes del AUR (de uno en uno)"
  local package
  for package in "${packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 && continue
    info "→ $package"
    import_aur_key "$package" || { failed+=("$package"); continue; }
    # --nocheck: some packages build their test suite with full LTO, which
    # can exhaust the RAM of a small machine or VM.
    run yay -S --needed --noconfirm --answerdiff None --answerclean None \
      --mflags --nocheck "$package" || failed+=("$package")
  done
  if ((${#failed[@]})); then
    note "Paquetes del AUR que fallaron: ${failed[*]}. Reintenta con: ./install.sh --only aur"
  fi
}

# --------------------------------------------------------------------- stow

# Directories the shell or apps write into at runtime must be real directories,
# or Stow would fold them into links and those writes would land in ~/dotfiles.
prepare_real_dirs() {
  local -a dirs=(
    "$HOME/.config/wh01s17/plugins" "$HOME/.config/wh01s17/themes" "$HOME/.config/wh01s17/branding"
    "$HOME/.config/wh01s17/hooks" "$HOME/.config/wh01s17/extensions" "$HOME/.config/wh01s17/themed"
    "$HOME/.config/systemd/user" "$HOME/.config/uwsm/env.d" "$HOME/.config/mise"
    "$HOME/.config/environment.d" "$HOME/.local/bin" "$HOME/.local/state/wh01s17"
    "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps"
  )
  local entry
  for entry in "$DOTFILES_DIR"/platform/.local/share/wh01s17/config/*/; do
    [[ $(basename "$entry") == fcitx5 ]] && continue
    dirs+=("$HOME/.config/$(basename "$entry")")
  done
  run mkdir -p "${dirs[@]}"
}

find_blocking_ancestor() {
  local target=$1 current=$HOME part
  local relative=${target#"$HOME"/}
  local -a parts
  IFS='/' read -r -a parts <<<"$relative"
  local index
  for ((index = 0; index < ${#parts[@]} - 1; index++)); do
    part=${parts[$index]}
    current="$current/$part"
    if [[ -L $current ]]; then
      # A folded link into this checkout is fine: Stow manages it.
      [[ $(readlink -f -- "$current") == "$(readlink -f -- "$DOTFILES_DIR")"/* ]] && return 1
      printf '%s\n' "$current"
      return 0
    fi
    if [[ -e $current && ! -d $current ]]; then
      printf '%s\n' "$current"
      return 0
    fi
  done
  return 1
}

backup_stow_conflicts() {
  local entry package_dir source relative target blocker
  local -a conflicts=()
  local -A blocked=()
  for entry in "${STOW_PACKAGES[@]}" "${STOW_NO_FOLDING_PACKAGES[@]}"; do
    package_dir="${entry%%:*}/${entry#*:}"
    [[ -d $package_dir ]] || continue
    while IFS= read -r -d '' source; do
      relative=${source#"$package_dir"/}
      target="$HOME/$relative"
      [[ (-e $target || -L $target) && $target -ef $source ]] && continue
      if blocker=$(find_blocking_ancestor "$target"); then
        [[ $DRY_RUN == true ]] || die "No se modificará $target: su ruta atraviesa $blocker. Revísalo a mano."
        blocked["$blocker"]=1
        continue
      fi
      [[ -e $target || -L $target ]] || continue
      [[ -d $target && ! -L $target ]] && continue
      conflicts+=("$target")
    done < <(find "$package_dir" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)
  done
  if ((${#blocked[@]})); then
    warn "[dry-run] Stow se detendría aquí; estas rutas no son directorios propios: ${!blocked[*]}"
  fi
  ((${#conflicts[@]})) || return 0

  warn 'Estas rutas ya existen y no pertenecen a los dotfiles:'
  printf '  - %s\n' "${conflicts[@]}" >&2
  ask '¿Moverlas a ~/.config-backup y continuar?' s || die 'Cancelado sin tocar nada.'
  BACKUP_DIR="$HOME/.config-backup/$(date +%Y-%m-%d_%H-%M-%S)"
  for target in "${conflicts[@]}"; do
    relative=${target#"$HOME"/}
    run mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
    run mv -- "$target" "$BACKUP_DIR/$relative"
  done
}

stage_stow() {
  log 'Enlazando los dotfiles con Stow'
  prepare_real_dirs
  [[ $DRY_RUN == true && ! -d $DOTFILES_DIR ]] && return
  log 'Generando desktop y terminal con los nombres de wh01s17 (.arch-build)'
  run python3 -I "$script_dir/tools/arch-dotfiles.py" --dotfiles "$DOTFILES_DIR"
  backup_stow_conflicts
  local entry
  for entry in "${STOW_PACKAGES[@]}"; do
    run stow --restow -d "${entry%%:*}" -t "$HOME" "${entry#*:}"
  done
  for entry in "${STOW_NO_FOLDING_PACKAGES[@]}"; do
    run stow --restow --no-folding -d "${entry%%:*}" -t "$HOME" "${entry#*:}"
  done
}

# --------------------------------------------------------------------- seed

# Like /etc/skel: copy the stock config only where you have none.
stage_seed() {
  log 'Configuración por defecto donde no hay una tuya'
  local source relative target copied=0
  local defaults="$PLATFORM_DIR/config"
  [[ -d $defaults ]] || defaults="$DOTFILES_DIR/platform/.local/share/wh01s17/config"
  while IFS= read -r -d '' source; do
    relative=${source#"$defaults"/}
    case $relative in
      fcitx5/*|autostart/org.fcitx.Fcitx5.desktop) continue ;; # D8: sin fcitx5
    esac
    target="$HOME/.config/$relative"
    [[ -e $target || -L $target ]] && continue
    run install -D -m 0644 "$source" "$target"
    copied=$((copied + 1))
  done < <(find "$defaults" -type f -print0)
  info "$copied archivos copiados"
  if [[ ! -e $HOME/.config/nvim ]]; then
    run cp -r "$PLATFORM_DIR/nvim/config" "$HOME/.config/nvim"
    info 'Configuración de Neovim (LazyVim) copiada'
  fi
}

# ------------------------------------------------------------------ machine

stage_machine() {
  log "Perfil de equipo: $WH_PROFILE"
  local hypr_selector="$HOME/.config/hypr/machine-profile.lua"
  local kitty_selector="$HOME/.config/kitty/machine-profile.conf"
  # VirtualBox's vmwgfx buffers make Quickshell and Kitty lose their Wayland
  # connection; in VMs the apps Hyprland starts use Mesa's CPU OpenGL
  # (default/hypr/envs.lua). Real GPUs are untouched.
  local vm_env="$HOME/.config/uwsm/env.d/20-vm-rendering"
  if [[ $DRY_RUN == true ]]; then
    if [[ $WH_PROFILE == auto ]]; then
      info "[dry-run] borraría $hypr_selector; $kitty_selector = font_size $WH_KITTY_FONT_SIZE"
    else
      info "[dry-run] $hypr_selector = return \"$WH_PROFILE\"; $kitty_selector = include profiles/$WH_PROFILE.conf"
    fi
    [[ $WH_GPU == vm ]] && info "[dry-run] $vm_env = WH01S17_VM_RENDERING=1"
    return
  fi
  mkdir -p "$(dirname "$hypr_selector")" "$(dirname "$kitty_selector")" "$(dirname "$vm_env")"
  rm -f -- "$hypr_selector" "$kitty_selector" "$vm_env"
  if [[ $WH_GPU == vm ]]; then
    printf '# Escrito por arch-desktop: en máquinas virtuales las apps usan OpenGL por CPU.\nexport WH01S17_VM_RENDERING=1\n' >"$vm_env"
    info 'Máquina virtual: las aplicaciones usarán OpenGL por CPU'
  fi
  if [[ $WH_PROFILE == auto ]]; then
    # monitors.lua uses preferred/auto plus what the Monitor panel saves.
    printf 'font_size %s\n' "$WH_KITTY_FONT_SIZE" >"$kitty_selector"
  else
    printf 'return "%s"\n' "$WH_PROFILE" >"$hypr_selector"
    printf 'include profiles/%s.conf\n' "$WH_PROFILE" >"$kitty_selector"
  fi
}

# ------------------------------------------------------------------- system

stage_system() {
  log 'Configuración del sistema (sudo)'
  local -a env_args=(
    "WH01S17_PATH=$PLATFORM_DIR" "TARGET_USER=$USER" "WH_GPU=$WH_GPU"
    "WH_GROUPS=$WH_GROUPS" "WH_AUTOLOGIN=$WH_AUTOLOGIN"
  )
  local status=0
  run sudo env "${env_args[@]}" bash "$script_dir/lib/system-setup.sh" || status=$?
  case $status in
    0) ;;
    3) note 'Algunos pasos de sistema fallaron (ver arriba); el resto quedó aplicado.' ;;
    *) die "La configuración del sistema falló (código $status)." ;;
  esac
  if [[ -f $DOTFILES_DIR/system/btrfs/install.sh && $DETECT_ROOT_FS == btrfs ]]; then
    log 'Balance semanal de btrfs (dotfiles/system/btrfs)'
    run sudo bash "$DOTFILES_DIR/system/btrfs/install.sh" ||
      note 'No se pudo instalar el balance de btrfs.'
  fi
}

# --------------------------------------------------------------------- user

# Run from $HOME: mise and git look for config in the parent directories.
platform_env() {
  (cd "$HOME" && env WH01S17_PATH="$PLATFORM_DIR" PATH="$PLATFORM_DIR/bin:$PATH" "$@")
}

stage_user() {
  log 'Configuración de usuario (tema wh01s17, llavero, git, mise…)'
  local status=0
  run platform_env WH01S17_USER_NAME="$WH_USER_NAME" WH01S17_USER_EMAIL="$WH_USER_EMAIL" \
    WH01S17_THEME_HEADLESS=1 wh01s17-provision-user --force || status=$?
  ((status == 0)) || note "wh01s17-provision-user terminó con código $status; revisa su salida."

  # Provisioning points the browser to Chromium; you use Firefox.
  run xdg-settings set default-web-browser firefox.desktop || note 'No se pudo fijar Firefox como navegador.'
  local name
  for name in "${DROPPED_DESKTOP_FILES[@]}"; do
    run rm -f -- "$HOME/.local/share/applications/$name.desktop"
  done
  has_group dev || run rm -f -- "$HOME/.local/share/applications/Docker.desktop"

  local launcher
  for launcher in "${MISE_LAUNCHERS[@]}"; do
    # shellcheck disable=SC2086  # "PACKAGE COMMAND" splits into two arguments
    run platform_env wh01s17-mise-install $launcher || note "No se pudo crear el lanzador de ${launcher##* }."
  done

  local plugin_dir="$HOME/.config/wh01s17/plugins/$EXTERNAL_SHELL_PLUGIN_ID"
  if [[ ! -e $plugin_dir ]]; then
    log "Plugin de terceros $EXTERNAL_SHELL_PLUGIN_ID"
    if run git clone --depth=1 "$EXTERNAL_SHELL_PLUGIN_URL" "$plugin_dir"; then
      run rm -rf "$plugin_dir/.git"
      run python3 -I "$script_dir/tools/arch-dotfiles.py" --in-place "$plugin_dir"
    else
      note "No se pudo clonar $EXTERNAL_SHELL_PLUGIN_URL; shell.json lo usa."
    fi
  fi
}

stage_hibernate() {
  [[ $WH_HIBERNATE == 1 ]] || return 0
  log 'Hibernación (swapfile en btrfs, resume y entrada de Limine; usa sudo)'
  run platform_env wh01s17-hibernation-setup --force || note 'No se pudo configurar la hibernación.'
}

# -------------------------------------------------------------------- shell

stage_shell() {
  log 'Zsh: Oh My Zsh, plugins, NVM y shell predeterminada'
  local custom="$HOME/.oh-my-zsh/custom"
  clone_or_pull https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" --depth=1 ||
    note 'No se pudo clonar Oh My Zsh; vuelve a ejecutar con --only shell.'
  clone_or_pull https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions" --depth=1 ||
    note 'No se pudo clonar zsh-autosuggestions.'
  clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting" --depth=1 ||
    note 'No se pudo clonar zsh-syntax-highlighting.'
  # plugins=(… zsh-sudo) needs zsh-sudo/zsh-sudo.plugin.zsh: link Oh My Zsh's sudo plugin.
  run mkdir -p "$custom/plugins/zsh-sudo"
  [[ -e $custom/plugins/zsh-sudo/zsh-sudo.plugin.zsh || ! -d $HOME/.oh-my-zsh/plugins/sudo ]] ||
    run ln -s "$HOME/.oh-my-zsh/plugins/sudo/sudo.plugin.zsh" "$custom/plugins/zsh-sudo/zsh-sudo.plugin.zsh"

  local nvm_dir="$HOME/.config/nvm"
  run mkdir -p "$nvm_dir"
  [[ -e $nvm_dir/nvm.sh ]] || run ln -s /usr/share/nvm/nvm.sh "$nvm_dir/nvm.sh"
  [[ -e $nvm_dir/bash_completion ]] || run ln -s /usr/share/nvm/bash_completion "$nvm_dir/bash_completion"
  if [[ $DRY_RUN != true ]]; then
    (
      set +u
      export NVM_DIR="$nvm_dir"
      # shellcheck disable=SC1091
      source /usr/share/nvm/init-nvm.sh
      if ! nvm version default >/dev/null 2>&1; then
        nvm install --lts && nvm alias default 'lts/*'
      fi
    ) || note 'NVM no pudo instalar Node LTS; ejecuta «nvm install --lts» más tarde.'
  fi

  local zsh_path
  zsh_path=$(command -v zsh || echo /usr/bin/zsh)
  if [[ $(getent passwd "$USER" | cut -d: -f7) != "$zsh_path" ]]; then
    run chsh -s "$zsh_path" || note "No se pudo cambiar la shell; ejecuta: chsh -s $zsh_path"
  fi
}

# ----------------------------------------------------------------- services

stage_services() {
  log 'Servicios de usuario'
  local unit
  for unit in btrfs-space-check.timer codex-staging-clean.timer mise-prune.timer; do
    [[ -f $HOME/.config/systemd/user/$unit ]] || continue
    run systemctl --user enable "$unit" || note "No se pudo habilitar $unit."
  done
  # The runtime's own units (bt-agent, sleep lock, monitor recovery) are
  # enabled at the first graphical login by wh01s17-provision-first-run.
  info 'bt-agent, bloqueo al suspender y recuperación del monitor se activan en el primer inicio de sesión.'
}

# ----------------------------------------------------------------- validate

stage_validate() {
  log 'Validación'
  if [[ $DRY_RUN == true ]]; then
    info '[dry-run] Hyprland --verify-config, zsh -n ~/.zshrc, oh-my-posh y ~/dotfiles/test.sh'
    return
  fi
  local errors=0
  platform_env Hyprland --verify-config --config "$HOME/.config/hypr/hyprland.lua" | tail -n 3 ||
    errors=$((errors + 1))
  zsh -n "$HOME/.zshrc" || errors=$((errors + 1))
  oh-my-posh print primary --config "$HOME/.config/oh-my-posh/active.omp.json" --shell zsh --plain >/dev/null ||
    errors=$((errors + 1))
  [[ -s $HOME/.local/state/wh01s17/current/theme.name ]] || { warn 'No hay tema aplicado.'; errors=$((errors + 1)); }
  if [[ -x $DOTFILES_DIR/test.sh ]]; then
    # Same environment as the session, where uwsm sets WH01S17_PATH.
    (cd "$DOTFILES_DIR" && WH01S17_PATH="$PLATFORM_DIR" PATH="$PLATFORM_DIR/bin:$PATH" ./test.sh) ||
      errors=$((errors + 1))
  fi
  ((errors == 0)) || note "La validación encontró $errors problema(s)."
}

# --------------------------------------------------------------------- main

main() {
  parse_args "$@"
  [[ $DRY_RUN == true ]] && log 'Modo --dry-run: no se cambiará nada'
  local stage
  for stage in "${ALL_STAGES[@]}"; do
    # decide feeds every later stage, so it always runs.
    if [[ $stage == decide ]] || wanted "$stage"; then
      "stage_$stage"
    fi
  done

  log 'Terminado'
  [[ -n $BACKUP_DIR && $DRY_RUN != true ]] && info "Respaldo de lo que había: $BACKUP_DIR"
  if ((${#WARNINGS[@]})); then
    warn 'Avisos:'
    printf '  - %s\n' "${WARNINGS[@]}" >&2
  fi
  info 'Reinicia el equipo. SDDM abrirá la sesión «wh01s17 (Hyprland uwsm)».'
  info 'En el primer inicio se completa la configuración (servicios de usuario, tema GTK, avisos).'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
