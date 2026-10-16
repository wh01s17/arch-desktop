# Escritorio wh01s17 en Arch puro

Reproduce en Arch Linux, sin el repositorio ni los paquetes de Omarchy, el
escritorio que usas en Omarchy 4: Hyprland en Lua, Omarchy Shell con tus
plugins `wh01s17.*`, el tema `wh01s17`, Kitty, Zsh con Oh My Posh, tus atajos
y tus aplicaciones.

La idea es **congelar** Omarchy 4.0.4, que tiene licencia MIT, en lugar de
reescribirlo. Esa copia vive en tus dotfiles como el paquete Stow `platform`,
y tus paquetes `desktop`, `terminal` y `maintenance` funcionan sobre ella sin
cambios.

- Instalación paso a paso: [INSTALL.md](INSTALL.md)
- Decisiones y fases: [PLAN.md](PLAN.md)
- Atajos: [KEYBINDINGS.md](KEYBINDINGS.md) (generado)

## Cómo encaja

```text
arch-desktop/                       instalador (este repositorio)
├── install.sh                      etapas: paquetes, AUR, Stow, sistema, usuario…
├── lib/                            common, detección de hardware, pasos de root
├── packages/*.txt                  listas oficiales (*.txt) y del AUR (*.aur.txt)
├── profiles/machines.tsv           modelo DMI → perfil de monitores y fuente
├── reference/                      captura de tu Omarchy (atajos, opciones…)
└── tools/                          capture-reference, vendor-omarchy, compare-binds…

~/dotfiles/                         configuración (Stow)
├── platform/   (sólo Arch)         copia congelada de Omarchy → ~/.local/share/omarchy
├── apps/       (sólo Arch)         mise, apps predeterminadas, webapps propias
├── desktop/                        Hyprland, Omarchy Shell, plugins, tema
├── terminal/                       Zsh, Kitty, Oh My Posh
└── maintenance/                    timers de usuario
```

Con `OMARCHY_PATH=~/.local/share/omarchy` (lo define
`~/.config/uwsm/env.d/10-omarchy`, del paquete `platform`), Hyprland, el
shell y los comandos `omarchy-*` usan la copia en lugar de
`/usr/share/omarchy`.

## Uso

En un Arch recién instalado (ver [INSTALL.md](INSTALL.md)):

```bash
git clone https://github.com/wh01s17/arch-desktop.git ~/workspace/arch-desktop
cd ~/workspace/arch-desktop
./install.sh --dry-run
./install.sh
```

El instalador detecta el modelo, la GPU, las pantallas, la batería, el
arranque y el receptor Logitech, y pregunta por:

- el perfil de monitores (`omen`, `hp-gray` o `auto` para cualquier equipo);
- el driver de la GPU;
- los grupos opcionales (`dev`, `apps`, `gaming`, `virtualization`,
  `pentest`);
- la hibernación y el autologin.

Guarda las respuestas en `~/.config/wh01s17/machine.env`, así que volver a
ejecutarlo no repite las preguntas. `./install.sh --help` muestra todas
las opciones.

| Etapa | Qué hace |
| --- | --- |
| `preflight` | Arch, usuario normal, sin Omarchy, red, sudo |
| `bootstrap` | git, stow, base-devel |
| `dotfiles` | Clona o actualiza `~/dotfiles` |
| `decide` | Detecta el hardware y pregunta (o lee `machine.env`) |
| `packages` | Paquetes oficiales: `base`, `desktop`, `fonts`, `terminal`, grupos y GPU |
| `aur` | yay, los sustitutos de lo que venía del repositorio de Omarchy, grupos, Limine/Snapper y BlackArch |
| `stow` | `platform desktop terminal maintenance` y `apps` (sin plegar), con respaldo de conflictos |
| `seed` | Configuración por defecto de Omarchy donde no hay una tuya; Neovim (LazyVim) |
| `machine` | `machine-profile.lua` de Hyprland y `machine-profile.conf` de Kitty |
| `system` | `lib/system-setup.sh` como root: archivos de sistema y pasos de configuración de Omarchy, firewall, hardware, SDDM con autologin, servicios, initramfs y Limine |
| `user` | `omarchy-provision-user`: tema wh01s17, llavero, git, mise, skills, directorios XDG; Firefox como navegador; plugin lock-explorer |
| `hibernate` | `omarchy-hibernation-setup` |
| `shell` | Oh My Zsh, plugins, NVM y `chsh` a Zsh |
| `services` | Timers de `maintenance` |
| `validate` | `Hyprland --verify-config`, `zsh -n`, Oh My Posh, tema y `~/dotfiles/test.sh` |

## Diferencias con Omarchy

- Sin los temas de serie ni las migraciones: sólo existe `wh01s17`.
- `omarchy update` actualiza Arch (pacman, AUR, mise) con un snapshot previo.
  No toca el repositorio de Omarchy ni hace `git pull` en `OMARCHY_PATH`, que
  aquí está dentro de `~/dotfiles`.
- Desactivados: canales, reinstalación, `omarchy dev link`, restablecimiento
  de fábrica y los `sudoers` sin contraseña de Omarchy.
- Sin fcitx5 ni Plymouth.
- Se quitan los atajos de las apps y webapps que no usas: ver
  `reference/binds-dropped.tsv`.
- Kernels `linux` y `linux-lts` en lugar de `linux-omarchy`. Los paquetes que
  venían del repositorio de Omarchy salen del AUR (`packages/*.aur.txt`).

## Mantenimiento de la copia congelada

La copia se regenera desde un equipo con Omarchy:

```bash
tools/vendor-omarchy.py --force      # escribe ~/dotfiles/platform
git -C ~/dotfiles diff --stat platform    # revisa antes de hacer commit
```

Cada adaptación a Arch está dentro de `tools/vendor-omarchy.py` y comprueba
el texto original que sustituye. Si una versión nueva de Omarchy lo cambia,
la herramienta falla en lugar de dejar la copia a medias. Los cambios hechos
a mano dentro de `platform/` se pierden al regenerarla.

## Verificación

```bash
bash -n install.sh lib/*.sh tools/*.sh
python3 -m py_compile tools/vendor-omarchy.py
./install.sh --dry-run --yes
tools/compare-binds.sh               # dentro de la sesión nueva
```
