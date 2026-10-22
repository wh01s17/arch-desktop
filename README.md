# arch-desktop

Instala en Arch Linux el escritorio **wh01s17**: Hyprland en Lua, su shell
(barra, menú, paneles, notificaciones, bloqueo) con tus plugins `wh01s17.*`,
el tema `wh01s17`, Kitty, Zsh con Starship, tus atajos y tus aplicaciones.

Todo se llama wh01s17: los comandos son `wh01s17-*`, las variables
`WH01S17_*`, la configuración vive en `~/.config/wh01s17`, la sesión se llama
«wh01s17» y los plugins internos del shell son `core.*`.

- Instalación paso a paso: [INSTALL.md](INSTALL.md)
- Historia y decisiones: [PLAN.md](PLAN.md)
- Atajos: [KEYBINDINGS.md](KEYBINDINGS.md) (generado)
- Actualizar una instalación existente: [UPDATE.md](UPDATE.md)

## Cómo encaja

```text
arch-desktop/                       este repositorio
├── install.sh                      etapas: paquetes, AUR, Stow, sistema, usuario…
├── lib/                            utilidades, detección de hardware, pasos de root
├── packages/*.txt                  listas oficiales (*.txt) y del AUR (*.aur.txt)
├── profiles/machines.tsv           modelo DMI → perfil de monitores y fuente
├── reference/                      captura del escritorio de origen (atajos, opciones…)
└── tools/
    ├── rename.py                   reglas de nombres (wh01s17, core.*)
    ├── vendor-omarchy.py           genera el runtime (paquete platform)
    ├── arch-dotfiles.py            genera desktop y terminal renombrados
    └── capture-reference.sh, compare-binds.sh, keybindings-md.sh

~/dotfiles/                         configuración (Stow)
├── platform/   (sólo Arch)         runtime → ~/.local/share/wh01s17
├── apps/       (sólo Arch)         mise, apps predeterminadas, webapps
├── desktop/ terminal/              tu configuración, con los nombres originales
├── .arch-build/ (generado)         desktop y terminal renombrados; es lo que se enlaza
└── maintenance/                    timers de usuario
```

`~/.config/uwsm/env.d/10-wh01s17` (paquete `platform`) define
`WH01S17_PATH=~/.local/share/wh01s17` y pone sus comandos en el `PATH`.

**Mientras sigas usando el equipo de origen**, edita `~/dotfiles/desktop` y
`~/dotfiles/terminal`. En Arch, `./install.sh --only stow` regenera
`.arch-build/` a partir de ellos y vuelve a enlazar. No edites `.arch-build/`:
se reescribe cada vez.

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
ejecutarlo no repite las preguntas. `./install.sh --help` muestra todas las
opciones.

| Etapa | Qué hace |
| --- | --- |
| `preflight` | Arch, usuario normal, red, sudo; se niega a ejecutarse sobre Omarchy |
| `bootstrap` | git, stow, base-devel |
| `dotfiles` | Clona o actualiza `~/dotfiles` |
| `decide` | Detecta el hardware y pregunta (o lee `machine.env`); avisa si la raíz btrfs no usa los subvolúmenes de `INSTALL.md` |
| `packages` | Paquetes oficiales: `base`, `desktop`, `fonts`, `terminal`, grupos y GPU |
| `aur` | yay y los paquetes del AUR de uno en uno, sin tests ni paquetes `-debug`; Limine/Snapper y BlackArch |
| `fixes` | Correcciones revisadas del runtime y plugins; retira la configuración insegura de mise de instalaciones anteriores |
| `stow` | Genera `.arch-build/`; enlaza `platform`, `maintenance`, `desktop`, `terminal` y `apps` (sin plegar), con respaldo de conflictos |
| `seed` | Configuración por defecto del runtime donde no hay una tuya; Neovim (LazyVim) |
| `machine` | `machine-profile.lua` de Hyprland y `machine-profile.conf` de Kitty |
| `system` | `lib/system-setup.sh` como root: archivos y pasos de sistema, firewall, hardware, SDDM con autologin, servicios (incluido `paccache.timer`), initramfs y Limine |
| `user` | `wh01s17-provision-user`: tema, llavero, git, mise, directorios XDG; Firefox como navegador; plugin lock-explorer; `~/VirtualBox VMs` sin copy-on-write |
| `hibernate` | `wh01s17-hibernation-setup` |
| `shell` | Oh My Zsh, plugins, NVM y `chsh` a Zsh |
| `services` | Timers de `maintenance` |
| `validate` | `Hyprland --verify-config`, `zsh -n`, Starship, `fstab` sin `subvolid=`, tema y `~/dotfiles/test.sh` |

## Origen y licencia

El runtime es una copia congelada de [Omarchy](https://github.com/basecamp/omarchy)
4.0.4 con correcciones seleccionadas de 4.0.5/4.0.6 (licencia MIT), adaptada a Arch puro y renombrada por
`tools/vendor-omarchy.py`:

- todos los nombres pasan a wh01s17 (`tools/rename.py`); las URLs se conservan;
- sin repositorio de paquetes, migraciones, temas de serie, subida de
  registros, enlaces a su comunidad ni skills de IA que reportan a su GitHub;
- logos y fuente de iconos con la marca wh01s17;
- `wh01s17 update` actualiza Arch (pacman, AUR, mise) con un snapshot previo;
- atajos de apps que no usas eliminados (`reference/binds-dropped.tsv`).

La versión propia es **1.0.1**. La base sigue siendo 4.0.4; los parches
aplicados están identificados en `UPSTREAM` y [patches/README.md](patches/README.md).
Para recibirlos en otro equipo, actualiza este repo con `git pull --ff-only` y
aplica las etapas indicadas en [UPDATE.md](UPDATE.md).
La etapa `fixes` los conserva al instalar, y el generador los vuelve a aplicar
al regenerar. Actualizar paquetes con `wh01s17 update` no actualiza este código.

El aviso de copyright de la licencia MIT se conserva en
`~/.local/share/wh01s17/LICENSE` y `UPSTREAM`, como exige la licencia.

Para regenerar el runtime hace falta un equipo con Omarchy y fontTools:

```bash
python -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools
/tmp/ft/bin/python tools/vendor-omarchy.py --force   # escribe ~/dotfiles/platform
git -C ~/dotfiles diff --stat platform
```

## Verificación

```bash
bash -n install.sh lib/*.sh tools/*.sh
python3 -m py_compile tools/*.py
./install.sh --dry-run --yes
tools/compare-binds.sh               # dentro de la sesión nueva
```
