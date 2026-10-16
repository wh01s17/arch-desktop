# shellcheck shell=bash
# Funciones compartidas por install.sh. Se cargan con `source`.

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
warn() { printf '\n\033[1;33m[!]\033[0m %s\n' "$1" >&2; }
die() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

# run CMD...: ejecuta, o sólo lo muestra con --dry-run.
run() {
  if [[ ${DRY_RUN:-false} == true ]]; then
    printf '    [dry-run] %s\n' "$(printf '%q ' "$@")"
    return 0
  fi
  "$@"
}

# ask PREGUNTA [s|n]: sí/no. Sin terminal o con --yes usa el valor por defecto.
ask() {
  local prompt=$1 default=${2:-n} answer hint
  [[ $default == s ]] && hint='[S/n]' || hint='[s/N]'
  if [[ ${ASSUME_YES:-false} == true || ! -t 0 ]]; then
    [[ $default == s ]]
    return
  fi
  read -r -p "$prompt $hint " answer || answer=""
  answer=${answer,,}
  [[ -z $answer ]] && answer=$default
  [[ $answer == s || $answer == si || $answer == sí || $answer == y || $answer == yes ]]
}

# choose VAR PREGUNTA DEFECTO OPCIÓN...: menú numerado; guarda la opción en VAR.
choose() {
  local -n _result=$1
  local prompt=$2 default=$3 answer index
  shift 3
  local -a options=("$@")
  if [[ ${ASSUME_YES:-false} == true || ! -t 0 ]]; then
    _result=$default
    return
  fi
  printf '\n%s\n' "$prompt" >&2
  for index in "${!options[@]}"; do
    if [[ ${options[$index]} == "$default" ]]; then
      printf '  %d) %s  (propuesto)\n' "$((index + 1))" "${options[$index]}" >&2
    else
      printf '  %d) %s\n' "$((index + 1))" "${options[$index]}" >&2
    fi
  done
  while true; do
    read -r -p "Elige [Enter = $default]: " answer || answer=""
    if [[ -z $answer ]]; then
      _result=$default
      return
    fi
    if [[ $answer =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#options[@]})); then
      _result=${options[$((answer - 1))]}
      return
    fi
    printf 'Opción no válida.\n' >&2
  done
}

# prompt_value VAR PREGUNTA DEFECTO
prompt_value() {
  local -n _value=$1
  local prompt=$2 default=$3 answer
  if [[ ${ASSUME_YES:-false} == true || ! -t 0 ]]; then
    _value=$default
    return
  fi
  read -r -p "$prompt [$default]: " answer || answer=""
  _value=${answer:-$default}
}

# read_list ARCHIVO...: nombres de paquete sin comentarios ni líneas vacías.
read_list() {
  local file
  for file in "$@"; do
    [[ -f $file ]] || die "Falta la lista de paquetes $file"
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$file" | grep -v '^[[:space:]]*$' || true
  done
}

clone_or_pull() {
  local repo=$1 destination=$2
  shift 2
  if [[ -d $destination/.git ]]; then
    if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
      warn "Hay cambios locales en $destination; se usa el checkout tal como está."
      return 0
    fi
    run git -C "$destination" pull --ff-only ||
      warn "No se pudo actualizar $destination; se usa el checkout existente."
  elif [[ -e $destination || -L $destination ]]; then
    die "$destination existe, pero no es un repositorio Git."
  else
    run git clone "$@" "$repo" "$destination"
  fi
}

# machine.env guarda las respuestas para que volver a ejecutar no pregunte.
load_machine_env() {
  [[ -f $MACHINE_ENV ]] || return 1
  # shellcheck disable=SC1090
  source "$MACHINE_ENV"
}

save_machine_env() {
  local content
  content=$(cat <<EOF
# Respuestas de install.sh para este equipo. Bórralo o usa
# --reconfigure para que vuelva a preguntar.
WH_PROFILE=$(printf '%q' "$WH_PROFILE")
WH_KITTY_FONT_SIZE=$(printf '%q' "$WH_KITTY_FONT_SIZE")
WH_GPU=$(printf '%q' "$WH_GPU")
WH_GROUPS=$(printf '%q' "$WH_GROUPS")
WH_HIBERNATE=$(printf '%q' "$WH_HIBERNATE")
WH_AUTOLOGIN=$(printf '%q' "$WH_AUTOLOGIN")
WH_USER_NAME=$(printf '%q' "$WH_USER_NAME")
WH_USER_EMAIL=$(printf '%q' "$WH_USER_EMAIL")
EOF
)
  if [[ ${DRY_RUN:-false} == true ]]; then
    printf '    [dry-run] escribiría %s:\n%s\n' "$MACHINE_ENV" "$content" | sed 's/^/    /'
    return
  fi
  mkdir -p "$(dirname "$MACHINE_ENV")"
  printf '%s\n' "$content" >"$MACHINE_ENV"
}

has_group() {
  [[ " $WH_GROUPS " == *" $1 "* ]]
}
