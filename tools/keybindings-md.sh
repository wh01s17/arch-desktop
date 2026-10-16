#!/usr/bin/env bash
# Genera KEYBINDINGS.md a partir de los atajos de Hyprland.
#   arch/tools/keybindings-md.sh [binds.json] > arch/KEYBINDINGS.md
# Sin argumento usa la sesión actual (hyprctl binds -j). Omite los atajos de
# reference/binds-dropped.tsv.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dropped="$script_dir/../reference/binds-dropped.tsv"
source_json=$(mktemp)
trap 'rm -f "$source_json"' EXIT
if (($#)); then cp -- "$1" "$source_json"; else hyprctl binds -j >"$source_json"; fi

rows=$(jq -r '
  def mods: [ (if (.modmask / 64 | floor) % 2 == 1 then "Super" else empty end),
              (if (.modmask / 4  | floor) % 2 == 1 then "Ctrl"  else empty end),
              (if (.modmask / 8  | floor) % 2 == 1 then "Alt"   else empty end),
              (if .modmask % 2 == 1 then "Shift" else empty end) ];
  .[] | select(.description != "")
  | [ (mods + [ if .key != "" then .key else "code:\(.keycode)" end ] | join(" + ")), .description ]
  | @tsv' "$source_json" | sort -u)

if [[ -f $dropped ]]; then
  # Same combination format as compare-binds.sh, upper-case modifiers.
  rows=$(while IFS=$'\t' read -r combo description; do
    upper=$(sed -e 's/Super/SUPER/; s/Ctrl/CTRL/; s/Alt/ALT/; s/Shift/SHIFT/' <<<"$combo")
    grep -qxF "$upper"$'\t'"$description" "$dropped" || printf '%s\t%s\n' "$combo" "$description"
  done <<<"$rows")
fi

cat <<'EOF'
# Atajos del escritorio wh01s17

Generado con `arch/tools/keybindings-md.sh` a partir de los atajos reales de
Hyprland. Son los de Omarchy 4.0.4 más los tuyos de
`~/dotfiles/desktop/.config/hypr/bindings.lua`, sin los descartados en
`arch/reference/binds-dropped.tsv`. En la sesión, Super + K muestra la misma
lista.

`code:10` … `code:19` son las teclas 1 … 0 de la fila superior.

| Atajo | Acción |
| --- | --- |
EOF
while IFS=$'\t' read -r combo description; do
  printf '| %s | %s |\n' "${combo//|/\\|}" "${description//|/\\|}"
done <<<"$rows"
