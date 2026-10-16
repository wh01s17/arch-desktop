#!/usr/bin/env bash
# Compara los atajos de la sesión de Hyprland actual con la referencia
# capturada en Omarchy (reference/binds.json).
#
# Uso (dentro de la sesión nueva):
#   tools/compare-binds.sh                  # usa hyprctl binds -j
#   tools/compare-binds.sh otro-binds.json  # compara un archivo
#
# Los atajos descartados a propósito están en reference/binds-dropped.tsv
# (combinación<TAB>descripción) y no cuentan como faltantes.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
reference="$script_dir/../reference/binds.json"
dropped="$script_dir/../reference/binds-dropped.tsv"
[[ -f $reference ]] || { echo "Falta $reference; ejecuta capture-reference.sh en Omarchy." >&2; exit 1; }

current=$(mktemp)
trap 'rm -f "$current"' EXIT
if (($#)); then
  cp -- "$1" "$current"
else
  hyprctl binds -j >"$current"
fi

# One line per bind: modifiers + key, flags and description.
normalize() {
  jq -r '
    def mods: [ (if (.modmask / 64 | floor) % 2 == 1 then "SUPER" else empty end),
                (if (.modmask / 4  | floor) % 2 == 1 then "CTRL"  else empty end),
                (if (.modmask / 8  | floor) % 2 == 1 then "ALT"   else empty end),
                (if .modmask % 2 == 1 then "SHIFT" else empty end) ];
    .[] | [ (mods + [ if .key != "" then .key else "code:\(.keycode)" end ] | join(" + ")),
            .description ] | @tsv' "$1" | sort -u
}

missing=$(comm -23 <(normalize "$reference") <(normalize "$current"))
extra=$(comm -13 <(normalize "$reference") <(normalize "$current"))
if [[ -f $dropped ]]; then
  missing=$(comm -23 <(printf '%s\n' "$missing" | sort -u) <(grep -v '^#' "$dropped" | sort -u))
fi

status=0
if [[ -n ${missing//[[:space:]]/} ]]; then
  echo 'Faltan respecto a Omarchy:'
  printf '%s\n' "$missing" | sed 's/^/  /'
  status=1
fi
if [[ -n ${extra//[[:space:]]/} ]]; then
  echo 'Nuevos o con otra descripción:'
  printf '%s\n' "$extra" | sed 's/^/  /'
fi
((status == 0)) && echo "Atajos completos: $(normalize "$current" | wc -l) (referencia: $(normalize "$reference" | wc -l), descartados: $(grep -vc '^#' "$dropped" 2>/dev/null || echo 0))."
exit "$status"
