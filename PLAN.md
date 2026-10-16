# Plan de implementación: escritorio wh01s17 en Arch puro

> Propuesta del 2026-10-16. Origen analizado en el equipo actual (HP Omen
> 15-ce0xx): Omarchy 4.0.4, Hyprland 0.56.2, Quickshell 0.3.1, `~/dotfiles`
> en `a4a2bd2` (con cambios sin commit) y el prototipo `arch/` de `67d2284`.
>
> **Decisiones tomadas el 2026-10-16:**
> - Shell: fork congelado de Omarchy Shell ([D2](#d2-shell-fork-congelado-de-omarchy-shell-decidido)).
> - Sesión: igual que hoy, autologin y sin LUKS ([D3](#d3-sesión-decidido)).
> - Aplicaciones y webapps: elegidas una por una ([D7](#d7-aplicaciones-y-webapps-decidido)).
> - fcitx5: no se instala ([D8](#d8-fcitx5-decidido)).
> - Tema: sólo `wh01s17` ([D9](#d9-tema-decidido)).
> - Perfiles: compatibles con cualquier equipo, decididos al ejecutar el
>   instalador ([D10](#d10-perfiles-por-equipo-decidido)).

## Estado de la implementación (2026-10-16)

Implementado. Ver [README.md](README.md) e [INSTALL.md](INSTALL.md).

**Dos desviaciones respecto a este plan**, ambas para reducir trabajo y
riesgo:

1. **La copia congelada conserva los nombres de Omarchy** (`omarchy-*`,
   `~/.config/omarchy`, `OMARCHY_PATH`), instalada en
   `~/.local/share/omarchy`. Es el «modo desarrollo» que Omarchy ya soporta.
   El renombrado a `wh-*` de la Fase 4.3 queda descartado: era cosmético y
   habría roto tus plugins y tus scripts. Por lo mismo, ya no hacen falta los
   cambios en `terminal/` de la Fase 2.2.
2. **No hay paquete `desktop-arch`.** Tu paquete `desktop` funciona igual
   sobre la copia, así que Omarchy y Arch comparten la misma configuración. En
   su lugar hay dos paquetes sólo para Arch: `platform` (la copia, generada
   con `tools/vendor-omarchy.py`) y `apps` (mise, apps predeterminadas y
   webapps).

**Estado por fase:**

| Fase | Estado |
| --- | --- |
| 0. Referencia | Completa en `arch/reference/`, incluidos btrfs y Limine. Mostró que la raíz es el nivel superior del btrfs, sin subvolúmenes `@`; `INSTALL.md` replica ese esquema |
| 1. Prueba del fork | Hecha: tu escritorio arranca sobre la copia en una sesión anidada, con barra, plugins, tema, menú y los atajos esperados |
| 2–3. Stow y Hyprland | Hechas con las desviaciones anteriores |
| 4. Shell y comandos | Copia completa, adaptada por `vendor-omarchy.py` (rutas, update, pacman.conf, provisión, atajos descartados) |
| 5. Acciones | Las da el propio shell de Omarchy; los atajos descartados están en `reference/binds-dropped.tsv` |
| 6. Instalador | `install.sh` con 15 etapas, detección de hardware y `machine.env`. Probado con `--dry-run` y con las etapas de usuario en un HOME temporal |
| 7. Validación | `tools/compare-binds.sh` y `INSTALL.md` §4. **Falta**: la instalación completa en una VM y en el hardware real (los pasos de root no se pueden probar en un equipo con Omarchy) |
| 8. Migración | Pendiente: tú decides cuándo |

## Índice

0. [Resumen](#0-resumen)
1. [Hallazgos](#1-hallazgos)
2. [Decisiones de arquitectura](#2-decisiones-de-arquitectura)
3. [Arquitectura objetivo](#3-arquitectura-objetivo)
4. [Fases](#4-fases)
5. [Matriz de paridad funcional](#5-matriz-de-paridad-funcional)
6. [Riesgos](#6-riesgos)
7. [Preguntas abiertas](#7-preguntas-abiertas)
8. [Próximo paso](#8-próximo-paso)

---

## 0. Resumen

**Objetivo.** Reproducir en Arch Linux, sin Omarchy, el escritorio que usas
hoy: atajos, barra, paneles, menú, notificaciones, bloqueo, tema, terminal,
reglas de ventanas y perfiles de monitores. La configuración vivirá en
`~/dotfiles` y se enlazará con Stow, igual que ahora.

**Estado del prototipo `arch/`.** Es una buena prueba de concepto. Pasa
`bash -n`, `luac -p` y `Hyprland --verify-config` (lo comprobé con un HOME
temporal), y declara casi todas las combinaciones de teclas. Sin embargo:

1. **Choca con Stow.** Copia archivos y se detiene si encuentra enlaces de
   Stow (`install.sh:81-109`). Además, duplica `.zshrc`, `kitty.conf` y
   Oh My Posh en versiones reducidas que divergen de `~/dotfiles`.
2. **Sustituye tu shell en lugar de portarlo.** La barra de 174 líneas
   reemplaza unas 15 000 líneas de QML/JS propio repartidas en 9 plugins.
   Ese código depende de `qs.Commons`/`qs.Ui` de Omarchy Shell y de unos
   40 comandos `omarchy-*`.
3. **No cubre el sistema base.** Falta el driver NVIDIA (la GTX 1060 Pascal
   necesita la rama 580xx del AUR), la sesión (uwsm/SDDM), los portales,
   Limine con Snapper y los servicios.
4. **22 acciones son sólo avisos**: zoom, huecos, opacidad, clima, touchpad,
   etc.
5. **Algunos valores no coinciden con los que usas.** Por ejemplo, el
   redondeo efectivo hoy es 3, no 6, y faltan las opciones de teclado,
   touchpad y tableta de tu `input.lua`.

**Enfoque (decidido).** Replicar la arquitectura de Omarchy en pequeño y
bajo tu control:

- un paquete Stow `platform` con la base de Hyprland, tus acciones (`wh-*`)
  y un fork congelado de Omarchy Shell 4.0.4, que tiene licencia MIT;
- un paquete Stow `desktop-arch` con tus ajustes personales, casi idénticos
  a los de hoy;
- los paquetes `terminal` y `maintenance` compartidos, con tres ajustes
  pequeños en `terminal`.

Con este diseño, tus plugins, tu `bindings.lua` (que usa `o.bind`) y tus
perfiles de monitores funcionan casi sin cambios. Además, dejas de depender
del rumbo de Omarchy, porque congelas la versión que te gusta.

---

## 1. Hallazgos

### 1.1 Inventario del prototipo

| Archivo | Función | Estado |
| --- | --- | --- |
| `install.sh` | Paquetes, copia de archivos, respaldo y validación | Funciona, pero usa copias en lugar de Stow |
| `config/hyprland.lua` | Monitores, look, autostart y layouts por espacio | Válido, pero incompleto (envs, reglas de ventanas, NVIDIA) |
| `config/bindings.lua` | ~200 atajos mediante `arch-look-action` | Válido, pero sin `description` |
| `config/arch-look-action` | Despachador de 90 acciones | 22 acciones son sólo avisos |
| `config/shell.qml` | Barra, menú e IPC mínimos | Funcional y básico; 2 avisos de `qmllint` |
| `config/monitors-*.lua` | 3 perfiles fijos | Divergen de `desktop/.config/hypr/profiles` |
| `config/kitty*.conf`, `colors.conf`, `zshrc` | Terminal | Duplican y recortan `terminal/` |
| `config/hypr{idle,lock}.conf`, `swaync.css`, `wofi.css` | Bloqueo, notificaciones y lanzador | Sustitutos de Omarchy Shell |

### 1.2 Problemas y divergencias concretas

**A. Modelo de instalación**

1. Copia en vez de enlazar: `install.sh:157-182`. Rechaza explícitamente los
   destinos que son enlaces de Stow (`install.sh:81-109`).
2. Instala `config/zshrc` (23 líneas) en lugar de `terminal/.zshrc` (430).
   Pierdes Oh My Zsh y sus plugins, aliases, zoxide, NVM y los hooks de Git
   y CTF. Con `kitty.conf` pasa lo mismo: 17 líneas frente a 49.
3. `~/.config/oh-my-posh` se copia con `cp -a` (`install.sh:177-182`), así
   que lo que edites allí ya no vuelve al repositorio.
4. Monitores:
   - `monitors-hp-gray.lua` fuerza el espejo del proyector, mientras que los
     dotfiles usan `auto-right` y el selector de layout del panel Display.
   - Se pierden `monitor_layout.lua`, `monitor_modes.lua` y
     `monitor_scales.lua`: la escala y la resolución por salida, y los modos
     extender, espejo, sólo portátil y sólo externo.
5. Usa sólo 2 de los 5 fondos del tema (faltan `03-pixel-moon`,
   `04-pixel-moon-wordmark` y `05-pixel-gengar-wordmark`).

**B. Hyprland**

6. Aspecto distinto al actual:
   - `hyprctl getoption decoration:rounding` devuelve **3**. Tu
     `hypr/looknfeel.lua` se carga después del tema, que fija 6, y el
     prototipo usa 6.
   - Faltan `group.col.*` del tema, `blur.new_optimizations` y
     `blur.xray = false`.
7. Faltan opciones de entrada de tu `input.lua`:
   - `kb_options = "caps:capslock"`;
   - `repeat_rate = 40` y `repeat_delay = 600`;
   - `numlock_by_default`;
   - `touchpad.scroll_factor = 0.4`;
   - `tablet.output = "DP-1"`.
8. Falta el entorno que define Omarchy en `envs.lua`:
   - `GDK_BACKEND`, `QT_QPA_PLATFORM` y `QT_QPA_PLATFORMTHEME`;
   - `MOZ_ENABLE_WAYLAND`, `ELECTRON_OZONE_PLATFORM_HINT` y `OZONE_PLATFORM`;
   - `XDG_CURRENT_DESKTOP`, `XDG_SESSION_DESKTOP` y `XDG_SESSION_TYPE`;
   - `XCOMPOSEFILE` y `xwayland.force_zero_scaling`.

   Sobre todo, falta ejecutar `systemctl --user import-environment` y
   `dbus-update-activation-environment --systemd --all`. Sin eso, los
   portales y la compartición de pantalla fallan, y algunas aplicaciones
   tardan en abrir.
9. **NVIDIA.** La GPU es una GP106BM (GTX 1060 Mobile, Pascal). Hoy usas
   `nvidia-580xx-dkms` del repositorio `[omarchy]`, junto con
   `MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`,
   `options nvidia_drm modeset=1` y los servicios
   `nvidia-{suspend,resume,hibernate}`. El prototipo no configura nada de
   esto, así que corres el riesgo de quedarte con la pantalla negra o de que
   falle la suspensión.
10. Faltan las reglas de ventanas de Omarchy (`windows.lua` y `apps/*.lua`):
    - `suppress_event = "maximize"`;
    - la opacidad por defecto `0.985 0.96` mediante la etiqueta
      `default-opacity`;
    - la corrección del arrastre en XWayland;
    - las reglas de PiP, diálogos del sistema, overlay de cámara, etc.
11. `run()` (`bindings.lua:3-5`) no pasa `description`. Hoy 235 de tus 237
    atajos la tienen, y de ahí salen el visor de Super+K y la documentación.
12. **F9 queda capturado siempre** (`bindings.lua:99-100`), aunque voxtype
    no esté instalado. En ese caso, ninguna aplicación recibe F9.
13. Sesión:
    - El README propone ejecutar `Hyprland` desde una TTY. Tu sistema
      instala `start-hyprland` y `hyprland-uwsm.desktop`, y Omarchy arranca
      con SDDM y uwsm.
    - Sin `uwsm app --`, las aplicaciones quedan dentro del scope del
      compositor.
14. Faltan, respecto al autostart actual:
    - `solaar`, `udiskie` y la inicialización de perfiles de energía;
    - el vigilante de monitores;
    - `hyprsunset` con tu `hyprsunset.conf`;
    - `xdph.conf`, con el selector `hyprland-preview-share-picker`.

**C. Shell y acciones**

15. Barra:
    - muestra los espacios 1 a 5, aunque los atajos cubren del 1 al 10;
    - el menú no toma el foco de teclado y no se cierra con Escape ni con
      un clic fuera;
    - `qmllint` avisa de accesos no cualificados en
      `shell.qml:166-167`.
16. Las acciones que sólo muestran un aviso están en
    `arch-look-action:11-13, 34, 50, 109, 124, 131-135, 147 y 168`.
17. Idle: hoy usas salvapantallas a los 150 s y bloqueo a los 300 s
    (`shell.json → idle`). El prototipo bloquea a los 300 s, apaga la
    pantalla a los 600 s y no tiene salvapantallas.
18. Servicios de usuario de Omarchy sin equivalente:
    - `omarchy-sleep-lock` y `omarchy-crash-watch`;
    - `omarchy-recover-internal-monitor` y `omarchy-fcitx5`;
    - `bt-agent`;
    - `gnome-keyring-daemon.socket`, el llavero de Chrome y VS Code.

**D. Sistema base (el prototipo no lo cubre)**

19. Paquetes del repositorio `[omarchy]` que usas, y dónde están en Arch
    (comprobado en extra y en el AUR el 2026-10-16):

    | Paquete actual | En Arch puro |
    | --- | --- |
    | `nvidia-580xx-dkms`, `nvidia-580xx-utils`, `lib32-nvidia-580xx-utils` | AUR, con los mismos nombres |
    | `limine-mkinitcpio-hook`, `limine-snapper-sync` | AUR. `btrfs-overlayfs` viene de `limine-mkinitcpio-hook` |
    | `yay` | AUR (`yay` o `yay-bin`); se arranca con `makepkg` |
    | `walker`, `elephant`, `cliamp` | AUR |
    | `wayscriber`, `voxtype` | AUR (también en variante `-bin`) |
    | `oh-my-posh` | AUR `oh-my-posh-bin` (en lugar de `curl \| bash`) |
    | `visual-studio-code-bin`, `1password`, `google-chrome`, `spotify`, `typora`, `localsend-bin` | AUR |
    | `mise-bin` | `mise` en extra |
    | `hyprland-preview-share-picker` | Sólo `hyprland-preview-share-picker-git` en AUR, con 2 votos |
    | `xdg-terminal-exec` | No está en el AUR con ese nombre; hay que empaquetarlo o prescindir de él |
    | `linux-omarchy` | `linux` más `linux-lts` como respaldo |

20. Configuración fuera de `~/dotfiles` que perderías al reinstalar: `nvim`
    (LazyVim de `omarchy-nvim`), `btop`, `tmux`, `git`, `gh`, `lazygit`,
    `mise`, `mpv`, `imv`, `fontconfig`, `gtk-3.0`/`gtk-4.0`, `mimeapps.list`,
    `environment.d`, `uwsm`, `fcitx5`, `solaar`, `starship.toml`, `Code`,
    entre otras.
21. Hay cambios sin commit en `~/dotfiles`: `desktop/.config/hypr/bindings.lua`
    (la sonda del menú) y `desktop/.config/hypr/scripts/`.

### 1.3 Acoplamiento de `~/dotfiles` a Omarchy

| Paquete o ruta | Acoplamiento | Esfuerzo |
| --- | --- | --- |
| `terminal/` | Tres puntos: `kitty.conf` incluye `~/.local/state/omarchy/current/theme/kitty.conf` y usa `listen_on omarchy-kitty-*`; `.zshrc` carga 2 scripts de `~/.config/omarchy/bar/scripts` (de forma condicional); `compose-theme.py` y `theme-picker.zsh --omarchy` leen la paleta de esa misma ruta | S |
| `maintenance/`, `system/` | Ninguno | — |
| `desktop/.config/hypr` | `hyprland.lua` carga el bootstrap de Omarchy; `bindings.lua` usa `o.bind` y `omarchy …`; `monitor_*.lua` guardan su estado en `~/.local/state/omarchy/` y llaman a `omarchy-hyprland-monitor-*` | M |
| `desktop/.config/omarchy/plugins` (9 plugins) | `qs.Commons` (Style con 486 usos, Color con 48, Util con 26), `qs.Ui` (Button, Panel, PanelSeparator, PanelSectionHeader, CursorSurface, BarWidget, KeyboardPanel, …), el host de plugins (`manifest.json`, `PluginBarApi`, `Bar.requestPopout`) y unos 40 comandos `omarchy-*` | L |
| `desktop/.config/omarchy/bar` | `StatusModule.qml` (Commons/Ui) y 9 scripts de bash casi independientes | S |
| `desktop/.config/fastfetch` | 5 módulos llaman a `omarchy-version*` y `omarchy-theme-current` | S |
| `themes/wh01s17` | Formato de tema de Omarchy (`colors.toml`, `shell.*.toml`, `hyprland.lua`) | M |

Omarchy Shell, por su parte, ocupa 2,0 MB y 102 archivos QML. Llama a 98
comandos `omarchy-*` distintos, de los 441 que hay en
`/usr/share/omarchy/bin`.

---

## 2. Decisiones de arquitectura

### D1. La configuración vive en `~/dotfiles` con Stow (decidido)

`post-install-linux/arch` pasa a ser sólo el *bootstrap*: paquetes,
drivers, servicios, clonado y `stow`. Es el mismo patrón que ya usa
`omarchy/post_installation.sh`. Así, cada cambio que hagas en el escritorio
vuelve a Git, y el repositorio `post-install-linux` deja de mantener copias.

Paquetes por plataforma:

| Plataforma | Paquetes Stow |
| --- | --- |
| Omarchy (hoy, sin cambios) | `desktop terminal maintenance` |
| Arch puro | `platform desktop-arch terminal maintenance` |

`desktop` y `desktop-arch` nunca se instalan en el mismo equipo, porque
ambos proporcionan `~/.config/hypr/hyprland.lua`. Al terminar la migración,
`desktop` se elimina y `desktop-arch` pasa a llamarse `desktop`.

### D2. Shell: fork congelado de Omarchy Shell (decidido)

| Opción | Qué es | A favor | En contra |
| --- | --- | --- | --- |
| **A. Fork** de Omarchy Shell 4.0.4 (MIT) | Copias `shell/` (host, Commons, Ui, services y plugins) y sustituyes `omarchy-*` por `wh-*` | Paridad casi total: la barra, el menú, los paneles, las notificaciones, el OSD, el bloqueo, el polkit, el portapapeles, los emojis y los recordatorios son los que usas hoy, y tus 9 plugins funcionan sin reescribirse | Pasas a mantener unas 2 MB de QML ajeno y a seguir los cambios de la API de Quickshell. Debes conservar el aviso de licencia MIT |
| B. Shell propio mínimo (ampliar el prototipo) | Una barra propia más SwayNC, Wofi/Fuzzel, hyprlock y aplicaciones sueltas | Código pequeño y tuyo | Pierdes los paneles; recuperarlos supone reescribir 15 000 líneas |
| C. Híbrido | Un host propio más una reimplementación del subconjunto de Commons/Ui que usan tus plugins; SwayNC y hyprlock para el resto | Menos código ajeno que A | Reimplementar unas 25 piezas de UI y el host de plugins cuesta casi lo mismo que copiarlos, y pierdes el menú y las notificaciones actuales |

**Decisión: opción A.** La Fase 1 ya no decide el enfoque. Sirve para
descubrir pronto qué depende del runtime de Omarchy (rutas fijas, el
*pipeline* de temas y los binarios) y para medir el trabajo de la Fase 4.
La opción C sólo se usaría para piezas concretas que no puedan copiarse.

### D3. Sesión (decidido)

Igual que hoy: SDDM con autologin a la sesión `hyprland-uwsm.desktop`, sin
LUKS. Es una decisión tuya: con este esquema, cualquiera con acceso físico
al equipo entra en tu sesión. Si alguna vez quieres reducir ese riesgo sin
perder el autologin, el instalador puede bloquear la pantalla al iniciar la
sesión. Por defecto queda desactivado.

### D4. Sistema base

Igual que ahora: btrfs, Limine (también para Windows), Snapper con
`limine-snapper-sync`, swapfile con hibernación y `zswap.enabled=0`. El
kernel será `linux`, con `linux-lts` como entrada de respaldo en Limine.
NVIDIA usará la rama 580xx del AUR.

### D5. Red

NetworkManager, que es lo que tienes activo (`iwd` está inactivo).

### D6. Dónde probar

1. Una VM (`notes/arch-linux-virtualbox.md`) para todo lo que no dependa de
   NVIDIA.
2. Después, el HP y el Omen, en el orden que decidas. El instalador no
   depende de ese orden (D10).

### D7. Aplicaciones y webapps (decidido)

Lo que no aparece como «Se conserva» se descarta: no se instala y su atajo
pasa a `reference/binds-dropped.txt`.

**Webapps.** Se abren en una ventana propia (Chromium `--app`), como hoy.
Firefox sigue siendo el navegador predeterminado.

| Webapp | Atajo actual | Decisión |
| --- | --- | --- |
| ChatGPT | Super+Shift+A | Se conserva |
| WhatsApp | Super+Alt+Shift+G | Se conserva |
| YouTube Music | — | Se conserva (en el lanzador) |
| Discord | — | Se conserva (en el lanzador) |
| Basecamp | — | Se conserva (en el lanzador) |
| Grok | Super+Alt+Shift+A | Se descarta |
| HEY Email, nuevo correo y HEY Calendar | Super+Shift+E, Super+Alt+Shift+E, Super+Shift+C | Se descartan |
| Google Messages, Photos y Maps | Super+Ctrl+Shift+G, Super+Shift+P, Super+Shift+S | Se descartan |
| YouTube, X y publicar en X | Super+Shift+Y, Super+Shift+X, Super+Alt+Shift+X | Se descartan |
| Zoom, Figma, GitHub y Google Contacts | — | Se descartan (no marcaste ninguna) |

**Aplicaciones con atajo.**

| Aplicación | Atajo | Decisión y origen |
| --- | --- | --- |
| Obsidian | Super+Shift+O | Se conserva (extra) |
| Spotify | Super+Shift+M | Se conserva (AUR `spotify`) |
| Herdr y su ayuda | Super+Ctrl+Enter, Super+Ctrl+K | Se conserva (AUR `herdr-bin`) |
| Tmux y su ayuda | Super+Alt+Enter, Super+Alt+K | Se conserva (extra) |
| Lazydocker | Super+Shift+D | Se conserva (extra, con `docker`) |
| Cliamp | Super+Alt+Shift+M | Se conserva (AUR) |
| WayScriber | Super+Alt+A/P/D | Se conserva (AUR) |
| Voxtype | F9 mantenido, Super+Ctrl+X | Se conserva (AUR). El atajo F9 sólo se registra si voxtype está instalado |
| Agente IA | Super+Ctrl+Shift+A | Se conserva. Abre **Claude Code** en una terminal (sustituye a `omarchy-agent --pick`) |
| LocalSend | Super+Ctrl+S | Se conserva (AUR `localsend-bin`) |
| Transcodificar | Super+Ctrl+. | Se conserva (`wh-transcode` con ffmpeg) |
| Overlay de webcam | Super+Alt+[ y ] | Se conserva |
| Clima | Super+Ctrl+Alt+W y el módulo de la barra | Se conserva |
| Signal | Super+Shift+G | Se descarta |
| 1Password | Super+Shift+/ | Se descarta |
| Omawrite | Super+Shift+W | Se descarta |
| omacalc | Super+Ctrl+Q, XF86Calculator | Se descarta (no está en el AUR) |
| omacut | — | Se descarta (no está en el AUR) |

**Aplicaciones sin atajo** (sólo afectan a las listas de paquetes):

| Se conservan | Origen |
| --- | --- |
| VS Code, Google Chrome, Typora | AUR (`visual-studio-code-bin`, `google-chrome`, `typora`) |
| Steam | multilib |
| OBS Studio, Kdenlive, LibreOffice (`libreoffice-fresh`) | extra |
| VirtualBox | extra (`virtualbox` y `virtualbox-host-dkms`; no existe `-modules-arch`) |
| qBittorrent, Strawberry, Xournal++, Pinta | extra |
| tensaku | AUR. **Sustituye a satty** como editor de capturas, como en Omarchy |
| aether | AUR. Hay que comprobar dónde escribe los temas que genera, porque está pensado para el formato de Omarchy (Fase 5) |
| try | AUR `try-cli` |
| Solaar | extra; se inicia con la sesión |

Se descarta Dropbox.

Los atajos que quedan libres (por ejemplo, Super+Shift+Y, Super+Shift+X y
Super+Shift+S) pueden reasignarse a YouTube Music, Discord o Basecamp si
quieres; hoy esas webapps no tienen atajo.

### D8. fcitx5 (decidido)

fcitx5 es un método de entrada. Sirve para escribir chino, japonés o
coreano, y Omarchy lo usa (unidad `omarchy-fcitx5`) para que las
secuencias Compose de `~/.XCompose` funcionen en todas las aplicaciones.

En tu equipo sólo tiene `keyboard-us`. Además, tu `input.lua` sustituye la
tecla Compose que define Omarchy (`compose:caps`) por `caps:capslock`, así
que esas secuencias no se pueden escribir. La ñ y las tildes salen de
`altgr-intl`, que es una función de xkb y no depende de fcitx5.

**Decisión: no se instala**, ni se definen `INPUT_METHOD`, `XMODIFIERS`,
`QT_IM_MODULE` ni `SDL_IM_MODULE`. La Fase 7 comprueba la ñ, las tildes y
las teclas muertas en Chrome, VS Code y una aplicación Electron. Si alguna
falla, se activa fcitx5 tal como está hoy.

### D9. Tema (decidido)

Sólo existe el tema `wh01s17`. No hace falta portar el selector de temas de
Omarchy ni sus plantillas (`themed`): Commons lee directamente los archivos
de `themes/wh01s17`. Si el fork necesita archivos generados, como el
`kitty.conf` del tema, `wh-theme-render` los crea a partir de
`colors.toml`. El atajo «Theme menu» (Super+Ctrl+Shift+Espacio) abre aether.

### D10. Perfiles por equipo (decidido)

El instalador debe funcionar en cualquier equipo, no sólo en el HP y el
Omen. Para eso detecta el hardware al ejecutarse, propone valores y te pide
confirmación. El diseño completo está en la
[Fase 6.8](#68-perfiles-por-equipo-y-decisiones-en-ejecución).

---

## 3. Arquitectura objetivo

### 3.1 Repositorios

```text
~/dotfiles/
├── terminal/        compartido: Zsh, Kitty y Oh My Posh (3 ajustes, Fase 2)
├── maintenance/     compartido, sin cambios
├── system/          compartido, sin cambios (balance de btrfs)
├── desktop/         sólo Omarchy; congelado hasta la Fase 8
├── platform/        NUEVO, sólo Arch → ~/.local/share/wh01s17/
│   └── .local/share/wh01s17/
│       ├── UPSTREAM            versión, tag y fecha de Omarchy copiados
│       ├── LICENSE.omarchy     MIT, Basecamp
│       ├── bin/                wh (despachador) y wh-* (reemplazos de omarchy-*)
│       ├── hypr/               bootstrap, helpers (o.*), envs, nvidia, looknfeel,
│       │                       input, windows, apps/, autostart, bindings/, toggles/
│       ├── shell/              fork de Omarchy Shell 4.0.4
│       ├── shell-safe/         barra mínima actual (modo seguro)
│       ├── systemd/user/       wh-shell.service, …
│       └── themes/wh01s17/     tema movido desde desktop/ (enlace en Omarchy)
└── desktop-arch/    NUEVO, sólo Arch → ~/.config/
    └── .config/
        ├── hypr/       hyprland.lua (bootstrap → platform), input.lua, looknfeel.lua,
        │               bindings.lua, autostart.lua, monitors.lua, monitor_*.lua,
        │               profiles/, hyprsunset.conf, xdph.conf
        ├── wh01s17/    shell.json, plugins/wh01s17.*, bar/, branding/
        └── fastfetch/  versión para Arch

post-install-linux/arch/
├── install.sh       bootstrap v2 (Fase 6)
├── INSTALL.md       instalación base de Arch con dual boot
├── PLAN.md          este documento
├── packages/        base.txt, desktop.txt, apps.txt, fonts.txt, aur.txt, pentest.txt
├── reference/       captura de Omarchy (Fase 0): binds, opciones, paquetes y servicios
└── tools/           capture-reference.sh, compare-binds.sh, compare-options.sh
```

El código de terceros (el fork) queda en un subárbol con su licencia, dentro
del mismo repositorio de dotfiles. Así conservas un solo repositorio y un
solo flujo de Stow. Para ver tus cambios respecto al original, basta con
`git diff <commit-vendor> -- platform/.local/share/wh01s17/shell`.

### 3.2 Arranque de la sesión

```text
Limine → linux (+ nvidia-580xx DKMS) → SDDM → uwsm → Hyprland
  └─ ~/.config/hypr/hyprland.lua
       ├─ dofile($WH_PATH/hypr/bootstrap.lua)    package.path y recarga de módulos
       ├─ require("wh.hypr.base")                 helpers, envs, nvidia, looknfeel,
       │                                          input, windows, bindings, autostart
       ├─ require("wh.theme.hyprland")            colores, bordes y sombra del tema
       ├─ require("hypr.monitors"|"input"|"bindings"|"looknfeel"|"autostart")  tus ajustes
       └─ require("wh.hypr.toggles")              gaps, aspecto, touchpad y layouts
  └─ autostart: import-environment → systemctl --user start wh-shell.service,
                udiskie, solaar, perfiles de energía, vigilante de monitores
```

El orden de carga (valores por defecto → tema → ajustes personales) es el
mismo que hoy. Por eso los valores efectivos deben coincidir con
`reference/options.tsv`.

### 3.3 Equivalencias

| Omarchy | Función | En Arch puro |
| --- | --- | --- |
| `default/hypr/bootstrap.lua` | `package.path` y recarga | `platform/hypr/bootstrap.lua` (prefijos `wh.`, `hypr`) |
| `default/hypr/helpers.lua` (`o.*`) | `bind`, `launch`, `window`, `notify` | Se porta con los mismos nombres; `o.launch` → `uwsm app --` |
| `default/hypr/{envs,nvidia,looknfeel,input,windows,apps}` | Base del compositor | Se portan y revisan |
| `default/hypr/bindings/*.lua` | 5 módulos de atajos más voxtype | Se portan cambiando `omarchy-*` por `wh …` |
| `default/hypr/toggles*` | Huecos, aspecto, touchpad y layouts | Se portan con el estado en `~/.local/state/wh01s17/toggles` |
| Omarchy Shell | Barra, menú, paneles, notificaciones, OSD, polkit, bloqueo, portapapeles, emojis, recordatorios e idle | Fork en `platform/shell`, servido por `wh-shell.service` |
| `omarchy-*` (98 en el shell y unos 40 en tus plugins) | Acciones | `wh` y `wh-*`, sólo los que se usan |
| `omarchy theme set` y plantillas `themed` | Paleta | Un único tema (D9), más `wh-theme-render` si hacen falta archivos generados |
| `omarchy-agent --pick` | Agente de código | `wh-agent`: abre `claude` en Kitty, en `~/Work` si existe |
| `omarchy-fcitx5` | Método de entrada para XCompose | No se instala (D8) |
| `omarchy-launch-webapp` | Webapps | `wh-webapp`: `chromium --app=URL` con su archivo `.desktop` |
| `omarchy-crash-watch` | Reiniciar el shell | `Restart=on-failure` en `wh-shell.service` |
| `omarchy-sleep-lock` | Bloquear al suspender | `hypridle before_sleep_cmd` o el manejador de `lock-session` del shell |
| `omarchy-recover-internal-monitor` | Recuperar `eDP-1` | `wh-monitor-recover` (unidad de usuario) |
| `omarchy-update` | Actualizar | `wh-update`: snapshot, `pacman -Syu` y `yay -Sua` |
| `udiskie`, `solaar`, `power-profiles-daemon` | Automontaje, Logitech y energía | Los mismos paquetes, de extra |

---

## 4. Fases

Orden y dependencias:

```text
F0 (Omarchy) ─► F1 spike ─► F2 Stow ─► F3 Hyprland ─► F4 shell ─► F5 acciones ─► F7 validación ─► F8 migración
                                 └──────────► F6 sistema base e instalador ───────┘
```

Tamaño relativo: S (unas horas), M (1–3 sesiones), L (varias sesiones),
XL (el bloque principal).

### Fase 0 — Capturar la referencia en Omarchy (S, obligatoria)

Esta fase sólo puede hacerse mientras Omarchy siga instalado. Si la omites,
no tendrás con qué comparar la paridad.

1. Cierra los cambios pendientes en `~/dotfiles` (la sonda del menú en
   `bindings.lua` y `scripts/`): haz commit o descártalos, y haz push.
   Publica también los temas de Oh My Posh que hayas descargado localmente.
2. Crea `arch/tools/capture-reference.sh`, que escriba en `arch/reference/`:
   - `binds.json` ← `hyprctl binds -j`: los 237 atajos efectivos con su
     descripción. Es la lista que hay que reproducir.
   - `options.tsv` ← `hyprctl getoption <opción> -j` para una lista
     curada: `general:*`, `decoration:*`, `input:*`, `dwindle:*`,
     `misc:*`, `cursor:*` y `xwayland:*`.
   - `animations.txt` ← `hyprctl animations`.
   - `packages.tsv` ← `pacman -Qqe` con el repositorio de origen
     (core/extra/multilib/omarchy/blackarch/AUR).
   - `services.txt` ← unidades habilitadas del sistema y del usuario.
   - `config-unmanaged.txt` ← entradas de `~/.config` que no son enlaces a
     `~/dotfiles`.
   - `omarchy-commands.txt` ← `grep -rhoE 'omarchy[- ][a-z0-9-]+'` sobre
     `~/dotfiles`.
   - `btrfs.txt` ← `sudo btrfs subvolume list /`, `findmnt -t btrfs`,
     `/etc/fstab` y `swapon --show`, para replicar el layout y la
     hibernación.
   - `boot.txt` ← `/proc/cmdline`, `/etc/mkinitcpio.conf.d/*`,
     `/etc/modprobe.d/*` y `/boot/limine.conf` (sin UUID sensibles, si
     prefieres).
3. Haz capturas de pantalla (`grim`) de la barra, de cada panel, del menú,
   del bloqueo y de las notificaciones. Sirven de referencia visual y
   conviene guardarlas fuera de Git o con Git LFS.
4. Toma un snapshot del código que vas a copiar. La opción preferida es
   `git clone https://github.com/basecamp/omarchy` en el tag de la versión
   4.0.4 (comprueba que el tag exista). Como alternativa, haz un tar de
   `/usr/share/omarchy/{shell,bin,default/hypr}`. Guarda la licencia MIT y
   el número de versión.
5. Decide qué configuración de §1.2-20 pasa a dotfiles. Lo mínimo sería
   `nvim` (LazyVim), `tmux`, `btop`, `git`, `lazygit`, `mpv`, `imv`,
   `fontconfig`, `gtk-*`, `mimeapps.list`, `environment.d` y `uwsm`.
   Puedes crear nuevos paquetes Stow (`apps/`, `nvim/`) o ampliar
   `terminal/`.
6. Haz una lista de respaldo de los datos personales: `~/.ssh`, `~/.gnupg`,
   los perfiles de navegador, la bóveda de Obsidian, `~/workspace`, los
   `.env` y las licencias.

**Para cerrar la fase**, `arch/reference/` debe estar en Git y `~/dotfiles`
limpio y publicado.

### Fase 1 — Prueba de arranque del fork (M)

1. Prepara una VM con Arch mínimo, `hyprland`, `quickshell`, `uwsm`,
   `kitty`, `jq` y `git`.
2. Copia el snapshot de `shell/` a `~/.local/share/wh01s17/shell`, y
   `shell.json`, `plugins/wh01s17.*` y `bar/` a `~/.config/wh01s17/`.
3. Crea un directorio de *stubs* en `PATH` con un script por cada comando
   `omarchy*`. Cada stub registra su invocación en
   `~/.local/state/wh01s17/compat.log` y termina con éxito. Así obtienes la
   lista **real** de comandos que se usan en tiempo de ejecución, además de
   la estática.
4. Arranca con `qs -p ~/.local/share/wh01s17/shell/shell.qml`. Revisa
   `qs log` y anota los errores QML, las rutas fijas a
   `/usr/share/omarchy` o `~/.config/omarchy` y las dependencias del
   *pipeline* de temas.
5. Clasifica cada comando en `arch/reference/compat-commands.tsv` (con la
   categoría y el tratamiento de la tabla de la Fase 4.4).
6. **Resultado esperado.** Una lista priorizada de bloqueos para la
   Fase 4. Si alguna pieza depende de servicios de Omarchy que no pueden
   copiarse, se reemplaza sólo esa pieza (opción C de D2). Anótalo en
   `arch/reference/compat-commands.tsv`.

### Fase 2 — Reestructurar dotfiles sin romper Omarchy (M)

Todo esto se hace en el equipo con Omarchy, y Omarchy debe seguir
funcionando igual.

1. Crea los esqueletos `platform/` y `desktop-arch/`. Documenta en el README
   de dotfiles qué paquetes corresponden a cada plataforma (la tabla de D1).
2. Neutraliza `terminal/`:
   - **Kitty.** Cambia el `include` por `include ~/.config/kitty/theme.conf`.
     Ese `theme.conf` es un enlace local, no versionado, como ya ocurre con
     `machine-profile.conf`: en Omarchy apunta a
     `~/.local/state/omarchy/current/theme/kitty.conf`, y en Arch a
     `~/.local/state/wh01s17/theme/kitty.conf`. Crea el enlace en el equipo
     actual y añade esa línea a `omarchy/post_installation.sh`. Por ahora
     no toques `listen_on`.
   - **Zsh.** Mueve `ctf-aliases.zsh` y `git-branch-hook.zsh` a
     `terminal/.config/zsh/` y cárgalos desde ahí. Antes, revisa si
     `ctf-ip.sh` y `git-branch.sh` usan esas rutas.
   - **Oh My Posh.** Haz que `compose-theme.py` y `theme-picker.zsh` lean
     la paleta de `~/.config/kitty/theme.conf` por defecto, que resuelve en
     las dos plataformas. Conserva `--omarchy` como alias de un nombre
     neutro, como `--theme-colors`.
   - Comprueba con `stow -n -v -R terminal`, `zsh -n ~/.zshrc`,
     `omp-theme --current` y abriendo Kitty con la misma paleta.
3. Mueve el tema a `platform/.local/share/wh01s17/themes/wh01s17`. En
   `desktop/.config/omarchy/themes/` deja un **enlace simbólico relativo**
   hacia esa ruta y comprueba con `omarchy theme set wh01s17`. Si prefieres
   no tocar Omarchy, puedes posponer este paso a la Fase 8 a cambio de
   duplicar el tema durante la transición.
4. Amplía `~/dotfiles/test.sh` cuando existan `platform/` y
   `desktop-arch/`:
   - `luac -p` sobre todo el Lua nuevo;
   - `Hyprland --verify-config` con un HOME temporal donde se apliquen con
     Stow `platform` y `desktop-arch` (así validé el prototipo);
   - `qmllint -I platform/.local/share/wh01s17/shell` sobre los plugins;
   - `shellcheck` sobre `platform/.../bin/*`;
   - una **auditoría de compatibilidad** que falle si aparece `omarchy`
     fuera de `LICENSE.omarchy`, `UPSTREAM` o una lista de excepciones;
   - mientras dure la transición, un diff entre `desktop/` y
     `desktop-arch/` de los archivos que deben ser idénticos (`input.lua`,
     `looknfeel.lua`, `profiles/*.lua`), para que no se desincronicen
     cuando ajustes algo en Omarchy.

**Para cerrar la fase**, tu sesión de Omarchy debe quedar intacta y
`./test.sh` en verde.

### Fase 3 — Plataforma: base de Hyprland (M)

Archivos en `platform/.local/share/wh01s17/hypr/` y
`desktop-arch/.config/hypr/`.

1. **`bootstrap.lua`.** Fija
   `package.path = ~/.local/state/?.lua; ~/.config/?.lua; $WH_PATH/?.lua`
   y borra `package.loaded` para los prefijos `wh.`, `hypr` y `wh.theme`
   en cada recarga. Sin esto, `hyprctl reload` no vuelve a leer los
   módulos cargados con `require`. Omarchy lo resuelve igual; el prototipo
   lo evita usando `dofile`.
2. **`helpers.lua`.** Porta `o.*` con los mismos nombres: `bind` con
   `description`, `launch` (→ `uwsm app --`), `launch_sole` (enfocar o
   abrir), `launch_webapp`, `window`, `notify`, `exec_on_start`,
   `cmd_present` y `shell_quote`. Así tu `bindings.lua` personal se copia
   sin cambios, salvo los comandos.
3. **`envs.lua`.**
   - Incluye la lista de §1.2-8, `WH_PATH`, el `PATH` con
     `$WH_PATH/bin` al principio, `xwayland.force_zero_scaling` y
     `ecosystem.no_update_news`.
   - **`nvidia.lua`** se carga sólo si existe `/proc/driver/nvidia/version`.
     Porta el `default/hypr/nvidia.lua` de Omarchy (19 líneas) después de
     revisarlo.
4. **`looknfeel.lua` e `input.lua` base.** Revisa y porta los de Omarchy
   (126 y 79 líneas): curvas y animaciones, `dwindle`, `misc` y el
   touchpad del terminal. Después carga el tema y luego tus
   `looknfeel.lua` e `input.lua` personales, copiados tal cual. El
   redondeo efectivo debe dar 3.
5. **`windows.lua` y `apps/`.** Porta las reglas generales (§1.2-10) y sólo
   las de las aplicaciones que aparezcan en `reference/packages.tsv`:
   navegadores, PiP, diálogos del sistema, terminales, 1Password,
   LocalSend, Steam, QEMU, overlay de cámara, selección de capturas y las
   reglas de capa del shell.
6. **`autostart.lua`.**
   - `systemctl --user import-environment …` y
     `dbus-update-activation-environment --systemd --all`;
   - `systemctl --user start wh-shell.service`;
   - `udiskie --automount --no-notify --no-tray`;
   - inicializar los perfiles de energía y el vigilante de monitores;
   - después, tu `autostart.lua` personal (`solaar`).
7. **`bindings/`.**
   - Porta los cinco módulos de Omarchy (media, clipboard, tiling,
     utilities y applications) y el de voxtype, sustituyendo cada
     `omarchy-*` por su equivalente `wh`. Mantén todas las descripciones.
   - Los atajos opcionales se registran sólo si el programa existe
     (`o.cmd_present`). Esto corrige F9 (§1.2-12).
   - Puedes copiar `_G.omarchy_default_bindings` como
     `_G.wh_default_bindings` para desactivarlos en bloque.
8. **`toggles/`.** Porta el mecanismo de archivos en
   `~/.local/state/wh01s17/toggles/hypr/`: `window-no-gaps.lua`
   (Super+Shift+Retroceso), `single-window-aspect-ratio.lua`
   (Super+Ctrl+Retroceso), `disabled-input-device` (touchpad) y los
   layouts por espacio. Con esto se resuelven 4 de los avisos actuales.
9. **Monitores y perfiles.**
   - Copia a `desktop-arch` `monitors.lua`, `monitor_*.lua` y
     `profiles/`. Cambia el estado de `~/.local/state/omarchy/` a
     `~/.local/state/wh01s17/` mediante un módulo `paths`, y
     `omarchy-hyprland-monitor-internal*` por `wh-monitor-*`.
   - `machine-profile.lua` sigue siendo local y no se versiona; lo escribe
     el instalador (Fase 6.8).
   - Amplía el formato de perfil sin romper los actuales. Un perfil puede
     seguir devolviendo una función de monitores, como `omen.lua` y
     `hp-gray.lua`, o una tabla con más datos:

     ```lua
     return {
       monitors = function(scale_for, mode_for, mode_size) ... end,
       input = { tablet = { output = "DP-1" } },  -- ajustes propios del equipo
       autostart = { "solaar" },                  -- sólo si existe el receptor
     }
     ```

   - Saca `tablet.output = "DP-1"` de `input.lua` y llévalo al perfil
     `omen`. Ese valor sólo tiene sentido en el equipo que tiene `DP-1`.
10. **`desktop-arch/.config/hypr/hyprland.lua`.** Usa el mismo esqueleto
    que hoy, cambiando el bootstrap de Omarchy por el de
    `$WH_PATH/hypr/bootstrap.lua` y `default.hypr.omarchy` por
    `wh.hypr.base`.
11. **`xdph.conf` y `hyprsunset.conf`.** Instala
    `hyprland-preview-share-picker-git` o quita `custom_picker_binary` para
    usar el selector por defecto de xdph.

**Cómo verificarlo:**

- `Hyprland --verify-config` y `./test.sh`;
- en la VM, la sesión arranca con el aspecto correcto;
- `tools/compare-options.sh` no muestra diferencias con
  `reference/options.tsv`;
- `tools/compare-binds.sh` (ver la Fase 7) sólo muestra las diferencias
  aceptadas.

### Fase 4 — Plataforma: fork del shell y comandos (XL)

1. **Importa el código sin cambios.** El primer commit,
   `vendor: Omarchy Shell 4.0.4 (MIT)`, copia `shell/` sin modificarlo y
   añade `LICENSE.omarchy` y `UPSTREAM`. Cada cambio posterior va en su
   propio commit, para que el diff con el original muestre sólo tu delta.
2. **Poda lo que no usas.** Tomando como guía `shell.json → bar.layout`,
   tus atajos y D7, quita `dev-gallery`, `dropbox`, `tailscale`,
   `speedtest`, `disk-speedtest` y, si no lo usas, `wifiqr`. Mantén
   `weather`, `agents` (con Claude Code como agente predeterminado),
   `keyboard-layout`, `system-update`, `tray`, `emojis`, `clipboard`,
   `reminders`, `image-picker` y `background`.
3. **Identidad propia.** Cambia `~/.config/omarchy` por
   `~/.config/wh01s17`, `~/.local/state/omarchy` por
   `~/.local/state/wh01s17` y los nombres del objetivo IPC y del proceso.
   Si el host lo permite, centraliza las rutas en un singleton de Commons.
4. **Comandos de compatibilidad.** Crea `bin/wh`, un despachador con
   subcomandos como el CLI `omarchy`, y los `bin/wh-*`. Porta y simplifica
   sólo los comandos de `compat-commands.tsv`:

   | Categoría | Ejemplos actuales | Implementación |
   | --- | --- | --- |
   | Audio, brillo y medios | `omarchy audio output volume raise`, `omarchy-brightness-display`, `omarchy-audio-output-set-default` | `wpctl`, `brightnessctl`, `playerctl` |
   | Red y Bluetooth | `omarchy-network-status`, `omarchy-network-band`, `omarchy-dns`, `omarchy-bluetooth-device/power` | `nmcli`, `bluetoothctl` |
   | Monitores | `omarchy-hyprland-monitor-internal{,-mirror}`, `omarchy-hyprland-monitor-scaling`, `omarchy-monitor-state` | `hyprctl` y estado en `~/.local/state/wh01s17` |
   | Energía y estadísticas | `omarchy-powerprofiles-list/set`, `omarchy-system-stats` | `powerprofilesctl`, `/proc` |
   | Shell, menú y barra | `omarchy shell …`, `omarchy menu select`, `omarchy-menu toggle`, `omarchy-toggle-bar`, `omarchy bar position/move`, `omarchy plugin …` | `qs -p … ipc call …` |
   | Grabación | `omarchy-capture-screenrecording` | `gpu-screen-recorder` (extra) |
   | Recordatorios y dictado | `omarchy-reminder`, `omarchy-voxtype-*` | `systemd-run --user`, `voxtype` |
   | Actualizaciones y versión | `omarchy-update(-available)`, `omarchy-version*` | `checkupdates` (`pacman-contrib`) y `yay -Qua`; `wh-update` toma un snapshot y actualiza |
   | Tema y fuente | `omarchy-font-set`, `omarchy theme …` | `wh-theme` (un solo tema) |
   | Lanzadores | `omarchy-launch-*`, `omarchy-launch-or-focus*`, `omarchy-launch-floating-terminal-with-presentation` | Port directo |

   Después, sustituye las cadenas en el código copiado, un commit por
   categoría. La auditoría de la Fase 2.4 debe acabar sin coincidencias.
5. **Tema.** Haz que Commons (Color y Style) lea de
   `~/.local/state/wh01s17/current/theme`, un enlace a
   `themes/wh01s17`. Si el shell espera archivos que Omarchy genera desde
   plantillas `themed`, como el `kitty.conf` del tema, créalos con
   `wh-theme-render` a partir de `colors.toml`.
6. **Servicio.** Crea `systemd/user/wh-shell.service` con
   `PartOf=graphical-session.target`, `Restart=on-failure` y
   `OnFailure=wh-shell-safe.service`. Este último arranca la barra mínima
   actual, que pasa a `shell-safe/`.
7. **Idle y bloqueo.**
   - El idle se configura en el shell, como hoy (salvapantallas a los
     150 s, bloqueo a los 300 s).
   - El bloqueo al suspender se resuelve con `hypridle` o con un manejador
     de `lock-session`.
   - Mantén **hyprlock como bloqueo de respaldo**: el bloqueo es crítico
     para la seguridad y no debe depender sólo del fork.
   - Comprueba el cierre de tapa, la suspensión y la hibernación con los
     servicios `nvidia-*`.
8. **Plugin de terceros.** Reinstala `io.github.sirjul1337.lock-explorer`
   con `git clone` en un commit fijado.
9. **Paneles propios.** Comprueba cada uno: audio, bluetooth, network,
   power, monitor, clock, indicators y metronome (este último con
   `python` y su motor de audio). Revisa también los módulos de
   `StatusModule`: git-branch, ctf, pomodoro, firewall-status,
   mounted-devices, services-monitor y clipboard-history.

### Fase 5 — Acciones pendientes y aplicaciones (M)

| Acción y atajo | Implementación |
| --- | --- |
| `close-all` (Ctrl+Alt+Supr) | `hyprctl clients -j` y cerrar cada ventana; pedir confirmación |
| `width-save`/`width-restore` (Super+Alt+Inicio / Super+Inicio) | Guardar el tamaño de la ventana activa en el estado y restaurarlo con `resize` exacto |
| `opacity-toggle` (Super+Retroceso) | Alternar la etiqueta `default-opacity` en la ventana activa |
| `gaps-toggle` y `square-toggle` | Toggles de la Fase 3.8 |
| `zoom-in`/`zoom-reset` | `cursor:zoom_factor` mediante `hyprctl eval` |
| `touchpad-*` | Mecanismo `disabled-input-device` de la Fase 3.8 |
| `weather` (Super+Ctrl+Alt+W) | Panel `weather` del fork (revisar su proveedor) |
| `theme` (Super+Ctrl+Shift+Espacio) | Abre aether. Antes, comprueba dónde guarda los temas que genera y si puede exportar a `themes/wh01s17` sin la estructura de Omarchy |
| `transcode` (Super+Ctrl+.) | `wh-transcode`: preajustes de `ffmpeg` con menú |
| `share` (Super+Ctrl+S) | LocalSend (`localsend-bin`) |
| `webcam-*` (Super+Alt+[ y ]) | Regla `apps/webcam-overlay` más `mpv av://v4l2:/dev/video0` |
| `screenrecord` (Alt+Impr Pant) | `gpu-screen-recorder` con audio e indicador `ScreenRecording` en la barra |
| `screenshot` (Impr Pant) y menú de captura (Super+Ctrl+C) | `grim` y `slurp`, edición con **tensaku**, `wl-copy` y notificación |
| `emojis` (Super+Ctrl+E) | Plugin `emojis` del fork (hoy son 6 emojis fijos) |
| `agent` (Super+Ctrl+Shift+A) | `wh-agent`: Claude Code en Kitty |
| Webapps conservadas | `wh-webapp` con Chromium `--app` y un `.desktop` por webapp: ChatGPT, WhatsApp, YouTube Music, Discord y Basecamp |
| Atajos descartados en D7 | No se portan; se listan en `reference/binds-dropped.txt` |

Instala las aplicaciones de D7 desde `packages/apps.txt` y
`packages/aur.txt`, y añade la regla de ventana de cada una cuando haga
falta.

### Fase 6 — Sistema base e instalador v2 (L)

1. **`arch/INSTALL.md`.** Reutiliza `omarchy/dual-boot.md`: §1–4 para
   preparar Windows y la USB, §6 para la entrada de Windows en Limine y §7
   para las comprobaciones. Cubre:
   - particiones, compartiendo la ESP con Windows;
   - subvolúmenes btrfs como en `reference/btrfs.txt`;
   - swapfile e hibernación (`resume_offset` y el hook `resume`);
   - locale, teclado `us altgr-intl`, usuario y sudo.
2. **Arranque.**
   - `limine` y `snap-pac` (extra);
   - `limine-mkinitcpio-hook` y `limine-snapper-sync` (AUR), que aportan
     el hook `btrfs-overlayfs` para arrancar snapshots;
   - la configuración `root` de Snapper con `snapper-cleanup.timer`.
3. **Kernel y GPU.**
   - Instala `linux`, `linux-headers`, `linux-lts` y `linux-lts-headers`.
   - Con Pascal: `nvidia-580xx-dkms`, `nvidia-580xx-utils` y
     `lib32-nvidia-580xx-utils` (requiere multilib).
   - Crea `/etc/mkinitcpio.conf.d/nvidia.conf` y
     `/etc/modprobe.d/nvidia.conf` iguales a los actuales, y habilita
     `nvidia-{suspend,resume,hibernate}`.
   - El instalador detecta la GPU por su ID PCI: Pascal → 580xx, Turing o
     posterior → `nvidia-open`, AMD/Intel → mesa.
   - Comprueba que `/sys/module/nvidia_drm/parameters/modeset` sea `Y`.
4. **Listas de paquetes en archivos.** Crea `arch/packages/*.txt` a partir
   de `reference/packages.tsv` y de D7, para sacar los paquetes del array
   del script. Cada archivo es un grupo que el instalador puede ofrecer u
   omitir según el equipo (Fase 6.8):

   | Archivo | Contenido |
   | --- | --- |
   | `base.txt` | `base-devel`, `git`, `stow`, `zsh`, `curl`, `jq`, `python`, `lua`, `pacman-contrib`, `snapper`, `snap-pac`, `limine` |
   | `desktop.txt` | `hyprland`, `uwsm`, `sddm`, `quickshell`, `qt6-svg`, `qt6-5compat`, `qt6-multimedia` (según lo que pida el fork), `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk`, `hypridle`, `hyprlock`, `hyprsunset`, `hyprpicker`, `grim`, `slurp`, `wl-clipboard`, `cliphist`, `gpu-screen-recorder`, `pipewire`, `pipewire-pulse`, `wireplumber`, `playerctl`, `brightnessctl`, `networkmanager`, `bluez`, `power-profiles-daemon`, `udiskie`, `gnome-keyring`, `xdg-user-dirs`, `kitty`, `nautilus`, `firefox`, `chromium` (webapps), `mpv`, `imv`, `ffmpeg`, `tesseract` |
   | `fonts.txt` | `ttf-jetbrains-mono-nerd`, `ttf-meslo-nerd`, `noto-fonts`, `noto-fonts-emoji` |
   | `terminal.txt` | `neovim`, `tmux`, `btop`, `fzf`, `eza`, `bat`, `zoxide`, `mise`, `nvm`, `lazydocker` |
   | `dev.txt` | `docker`, `docker-compose` |
   | `apps.txt` | `obsidian`, `obs-studio`, `kdenlive`, `libreoffice-fresh`, `qbittorrent`, `strawberry`, `xournalpp`, `pinta`, `solaar` |
   | `gaming.txt` | `steam` (multilib) |
   | `virtualization.txt` | `virtualbox`, `virtualbox-host-dkms` |
   | `aur.txt` | `visual-studio-code-bin`, `google-chrome`, `typora`, `spotify`, `localsend-bin`, `herdr-bin`, `cliamp`, `wayscriber-bin`, `voxtype-bin`, `tensaku`, `aether`, `try-cli`, `oh-my-posh-bin`, `limine-mkinitcpio-hook`, `limine-snapper-sync` |
   | `gpu-*.txt` | Uno por familia de GPU (paso 3); el instalador elige cuál |
   | `pentest.txt` | Las herramientas de BlackArch que usas hoy |

   No se instalan `fcitx5` (D8), `satty` (lo sustituye tensaku), `wofi`,
   `swaync`, `swaybg` ni `walker`/`elephant`, porque el fork ya cubre el
   lanzador, las notificaciones y el fondo.
5. **Servicios.**
   - Del sistema: NetworkManager, bluetooth, sddm, power-profiles-daemon,
     ufw, `docker.socket`, `limine-snapper-sync`, `snapper-cleanup.timer`,
     `btrfs-balance-auto.timer` (mediante `system/btrfs/install.sh`), los
     `nvidia-*` y, si los usas, cups, avahi y tor.
   - Del usuario: `wh-shell`, `xdg-user-dirs`,
     `gnome-keyring-daemon.socket` y los timers de `maintenance/`. PipeWire
     ya se activa por socket.
6. **`install.sh` v2.** Extrae a `lib/common.sh` las funciones de
   `omarchy/post_installation.sh` (`log`, `warn`, `die`, `ask`,
   `clone_or_pull` y Stow con respaldo de conflictos). Etapas:

   ```text
   preflight   Arch, usuario normal, sin Omarchy, red, sudo -v
   detect      hardware y respuestas guardadas; preguntas de la Fase 6.8
   packages    pacman --needed desde los packages/*.txt elegidos
   aur         yay-bin con makepkg; luego packages/aur.txt
   gpu         driver de la familia detectada y confirmada (paso 3)
   dotfiles    clone_or_pull de ~/dotfiles
   stow        platform desktop-arch terminal maintenance (respaldo de conflictos)
   machine     perfil elegido o creado; machine-profile.lua y .conf locales
   theme       enlaces de ~/.local/state/wh01s17/current y kitty/theme.conf
   shell       Oh My Zsh y plugins, NVM, oh-my-posh-bin, chsh -s zsh
   services    sistema y usuario (paso 5)
   pentest     BlackArch opcional (reutilizar la función con verificación SHA-1)
   validate    ~/dotfiles/test.sh y Hyprland --verify-config
   summary     respaldos, avisos y siguiente paso
   ```

   Opciones: `--profile NOMBRE`, `--gpu FAMILIA`, `--groups LISTA`,
   `--reconfigure`, `--dry-run`, `--yes`,
   `--with-pentest`/`--without-pentest` y `--only ETAPA`/`--skip ETAPA`.
   Toda pregunta de la Fase 6.8 puede responderse con una opción, para
   poder ejecutar el instalador sin intervención. El `--dry-run` debe
   recorrer todas las etapas, incluida la detección, e imprimir las
   acciones sin efectos; el actual termina antes de las comprobaciones.

   Elimina `arch/config/*` (que ya está en dotfiles), `check_target_path`
   y la paleta de compatibilidad en `~/.local/state/omarchy`. Conserva la
   protección que impide ejecutarlo sobre Omarchy.
7. **SDDM y llavero.** Usa la sesión `hyprland-uwsm.desktop` con
   autologin para tu usuario, como hoy (D3). Con autologin no hay
   contraseña que desbloquee el llavero, así que replica lo que hace
   Omarchy:
   - un llavero predeterminado **sin contraseña**
     (`~/.local/share/keyrings/Default_keyring.keyring` y el archivo
     `default`), creado como en `install/user/default-keyring.sh`;
   - quitar las líneas `-auth` y `-password` de `pam_gnome_keyring.so` en
     `/etc/pam.d/sddm`, como en `install/login/sddm.sh`, para que un inicio
     con contraseña no cree un segundo llavero cifrado.

   Comprueba que Chrome y VS Code conserven las sesiones sin pedir la
   contraseña del llavero.

#### 6.8 Perfiles por equipo y decisiones en ejecución

El objetivo es que el instalador sirva para cualquier equipo. El HP y el
Omen son perfiles más, no casos especiales.

**Qué detecta** (sin pedir nada; todo sale de `/sys` o de `lspci`):

| Dato | Fuente | Para qué |
| --- | --- | --- |
| Fabricante y modelo | `/sys/class/dmi/id/{sys_vendor,product_name}` | Proponer un perfil conocido |
| Portátil o sobremesa | `/sys/class/dmi/id/chassis_type` | Tapa, batería, brillo e hibernación |
| Batería y retroiluminación | `/sys/class/power_supply/BAT*`, `/sys/class/backlight` | Módulos de la barra y teclas de brillo |
| GPU | `lspci -nn` (fabricante e ID de dispositivo) | Driver; híbrida o dedicada |
| Pantallas conectadas | `/sys/class/drm/card*-*/{status,modes}` | Nombre (`eDP-1`, `DP-1`, `HDMI-A-1`) y modo preferido de cada una |
| Touchpad y tableta | `/proc/bus/input/devices` | Reglas de touchpad y `tablet.output` |
| Receptor Logitech | `lsusb` con fabricante `046d` | Instalar e iniciar Solaar |
| Bluetooth y Wi-Fi | `/sys/class/bluetooth`, `/sys/class/net/*/wireless` | Servicios y paneles |
| Máquina virtual | `systemd-detect-virt` | Sin driver de GPU; `virtualbox-guest-utils` |

**Qué pregunta** (con la respuesta detectada como opción por defecto):

1. **Perfil.** Si el modelo coincide con uno de `profiles/index.tsv`, lo
   propone. Opciones: los perfiles conocidos (`omen`, `hp-gray`, …),
   `auto` (genérico: modo preferido y posición automática) o
   **«crear perfil nuevo»**.
2. **Perfil nuevo.** Pide un nombre y, para cada pantalla detectada, la
   escala (propone 1, o 1,5 si es 4K) y la posición respecto a la principal
   (derecha, izquierda, arriba, abajo o espejo). También pide el tamaño de
   la fuente de Kitty, con 11 como propuesta y 12 si la pantalla principal
   es 4K. Con eso genera `desktop-arch/.config/hypr/profiles/<nombre>.lua`
   y `terminal/.config/kitty/profiles/<nombre>.conf` **dentro de
   `~/dotfiles`**, para que el perfil quede versionado, y añade la línea
   «modelo → perfil» a `profiles/index.tsv`. Recuerda hacer commit.
3. **GPU.** Muestra lo detectado y la propuesta: Pascal o Maxwell →
   `nvidia-580xx`; Turing o posterior → `nvidia-open`; AMD → mesa con
   `vulkan-radeon` (y, si quieres, OpenCL para hashcat, como en
   `notes/arch-linux.md`); Intel → mesa con `vulkan-intel` e
   `intel-media-driver`; VM → ninguno. Si la GPU es híbrida, pregunta
   también por la descarga PRIME.
4. **Grupos de paquetes.** Una casilla por grupo opcional: `dev`, `apps`,
   `gaming`, `virtualization` y `pentest`. Así el HP puede quedarse sin
   Steam ni VirtualBox, por ejemplo.
5. **Hibernación.** Sólo en portátiles con btrfs: crear el swapfile y
   configurar `resume` y `resume_offset`.
6. **Autologin.** Por defecto sí (D3), con la opción de bloquear al iniciar.

**Dónde guarda las respuestas.** En `~/.config/wh01s17/machine.env`, un
archivo local y fuera de Git, por ejemplo:

```sh
WH_PROFILE=omen
WH_GPU=nvidia-580xx
WH_GROUPS="dev apps gaming virtualization"
WH_HIBERNATE=1
WH_AUTOLOGIN=1
```

Al volver a ejecutar el instalador, no repite las preguntas: usa ese
archivo, salvo que pases `--reconfigure`. A partir de él se generan los
archivos locales que ya usa la configuración:

- `~/.config/hypr/machine-profile.lua` (`return "omen"`);
- `~/.config/kitty/machine-profile.conf` (enlace a `profiles/<perfil>.conf`).

**Afinar después del primer inicio.** Durante la instalación, Hyprland
aún no está en marcha, así que el perfil nuevo es sólo un punto de
partida. Ya en la sesión, ajusta las pantallas con el panel Monitor y
ejecuta `wh-profile capture`. Ese comando lee `hyprctl monitors -j` y
reescribe el perfil activo en `~/dotfiles` con las posiciones, modos y
escalas reales.

**Lo que no necesita perfil.** El entorno de NVIDIA se activa solo si
existe `/proc/driver/nvidia/version` (Fase 3.3). Los módulos de batería y
brillo se ocultan en equipos sin batería ni retroiluminación.

### Fase 7 — Validación y paridad (M)

1. **Estática.** `~/dotfiles/test.sh` y `bash -n`/`shellcheck` sobre
   `arch/`.
2. **Atajos.** `hyprctl binds -j | tools/compare-binds.sh
   reference/binds.json` normaliza cada atajo (modmask, tecla o código y
   las opciones `locked`, `release`, `repeat` y `mouse`) y lista los que
   faltan y los que sobran, con su descripción. Las ausencias
   intencionadas van en `reference/binds-dropped.txt`. Con la misma
   salida se genera `KEYBINDINGS.md`, que deja de mantenerse a mano.
3. **Opciones.** `tools/compare-options.sh` contra `reference/options.tsv`.
4. **Funcional.** Recorre la matriz de [§5](#5-matriz-de-paridad-funcional).
5. **Hardware.**
   - En el Omen: NVIDIA, los 3 monitores, suspensión, hibernación y tapa.
   - En el HP: proyector en modo extender y espejo.
   - En ambos: arranque de un snapshot desde Limine y arranque de Windows.

### Fase 8 — Migración real y retirada de Omarchy (M)

1. El orden es: VM → equipo menos crítico → Omen.
2. **Reinstala en limpio; no conviertas Omarchy en el sitio.** Omarchy deja
   su kernel, el repositorio `[omarchy]` con su keyring, sus
   `etc-overrides`, la configuración de SDDM, Plymouth y Limine, hooks de
   pacman y unidades `omarchy-*`. Quitarlo todo a mano es más arriesgado
   que reinstalar.
3. En dotfiles:
   - crea el tag `omarchy-final`;
   - elimina `desktop/`;
   - renombra `desktop-arch` a `desktop` y vuelve a aplicar Stow;
   - actualiza el README y `test.sh`;
   - opcionalmente, renombra lo que quede (`listen_on omarchy-kitty-*`).
4. En `post-install-linux`:
   - actualiza `arch/README.md`;
   - genera `KEYBINDINGS.md`;
   - adapta `omarchy/dual-boot.md` a `arch/INSTALL.md` y archiva
     `omarchy/` como referencia.

---

## 5. Matriz de paridad funcional

| Área | Comprobación | Cómo |
| --- | --- | --- |
| Atajos | 237 de referencia, salvo los descartados | `compare-binds.sh` |
| Aspecto | Redondeo 3, bordes en gradiente a 45°, sombra, blur, opacidad 0.985/0.96, animación de espacios | `compare-options.sh` y captura junto a la referencia |
| Teclado | `altgr-intl` con ñ y tildes, Caps Lock, repetición 40/600 y Bloq Num, sin fcitx5 (D8) | Escribir «ñáéíóú¿¡» en Kitty, Firefox, Chrome, VS Code y una aplicación Electron (Obsidian) |
| Perfiles | Detección, perfil conocido, perfil nuevo y `wh-profile capture` | Ejecutar el instalador en la VM con `--reconfigure` y elegir «crear perfil nuevo» |
| Monitores | Perfiles omen y hp-gray, extender/espejo/sólo portátil/sólo externo, escala y modo persistentes, hotplug, recuperación de `eDP-1` | Panel Monitor y conectar o desconectar |
| Barra | Todos los IDs de `shell.json → bar.layout` (left, center y right) | Visual, frente a las capturas |
| Menú y lanzador | Super+Espacio, Super+Alt+Espacio y Super+Escape | Manual |
| Notificaciones | Envío, descartar (Super+,), DND (Super+Ctrl+,) e historial | `notify-send` |
| OSD | Volumen y brillo | Teclas multimedia |
| Polkit | Diálogo de autenticación | `pkexec true` |
| Portales | Compartir pantalla en Chrome y Firefox, selector de archivos | Meet de prueba y diálogo «Abrir» |
| Bloqueo e idle | Salvapantallas a los 150 s, bloqueo a los 300 s, bloqueo al suspender o cerrar la tapa, respaldo con hyprlock | Esperar, `systemctl suspend`, tapa |
| Energía | Suspensión e hibernación con NVIDIA, perfiles de energía y batería | `systemctl hibernate`, panel Power |
| Audio y Bluetooth | Cambio de salida, micrófono, emparejado y `bt-agent` | Paneles |
| Red | Wi-Fi, DNS y diagnóstico | Panel Network |
| Capturas | Región, grabación con audio, OCR y selector de color | Impr Pant, Alt+Impr Pant, Super+Ctrl+Impr Pant |
| Portapapeles y emojis | Historial (Super+Ctrl+V), copiar y pegar con Super+C/V en Kitty y fuera | Manual |
| Terminal | Paleta, Meslo, opacidad 0.85, prompt, `omp-theme` y zoxide/NVM | Abrir Kitty |
| Llavero | Chrome y VS Code recuerdan sesiones | Reiniciar sesión |
| Snapshots | `snap-pac` pre/post, arranque de un snapshot desde Limine | `pacman -S` de prueba y reinicio |
| Dual boot | Entrada de Windows en Limine | Reinicio |

---

## 6. Riesgos

| Riesgo | Impacto | Mitigación |
| --- | --- | --- |
| La rama NVIDIA 580xx depende de mantenedores del AUR y DKMS puede romperse con un kernel nuevo | Arranque sin gráficos | Entrada `linux-lts` en Limine, snapshots con `snap-pac`, actualizar el kernel de forma deliberada |
| Cambios en la API Lua de Hyprland (reciente desde 0.55) | La configuración no carga | `Hyprland --verify-config` en `test.sh` antes de actualizar; `IgnorePkg` opcional para `hyprland` y `quickshell`; rollback con Snapper |
| Cambios en la API de Quickshell rompen el fork | El shell no arranca | `wh-shell-safe` con `OnFailure`, la barra mínima del prototipo y actualizaciones de Quickshell bajo control |
| Mantener unas 2 MB de QML ajeno | Deuda técnica | Poda temprana (4.2), commits pequeños sobre la copia original y diff con `UPSTREAM` |
| El bloqueo del fork falla | Seguridad | hyprlock como respaldo y pruebas de suspensión y tapa en la Fase 7 |
| Autologin sin cifrado (aceptado en D3) | Cualquiera con acceso físico entra en la sesión | Opción de bloquear al iniciar (desactivada por defecto) |
| aether está pensado para el formato de temas de Omarchy | El selector de temas no aplica nada | Comprobarlo en la Fase 5; si no puede exportar a `themes/wh01s17`, usarlo sólo para extraer colores |
| Las apps del AUR con pocos votos (`tensaku`, `aether`, `try-cli`, `cliamp`) se abandonan | Pierdes una herramienta | Revisar el PKGBUILD antes de instalar; tienen alternativas (`satty`, editar `colors.toml`) |
| `desktop` y `desktop-arch` se desincronizan durante la transición | Pérdida de ajustes | Diff de archivos compartidos en `test.sh` (Fase 2.4) y una transición corta |
| Pérdida de datos al reinstalar | Alta | Fase 0.6, verificar los respaldos antes de formatear |
| Una actualización de Windows altera el orden de arranque | No arranca Arch | `omarchy/dual-boot.md` §7–10, reutilizado en `INSTALL.md` |

---

## 7. Preguntas abiertas

Las preguntas de la primera versión ya están resueltas en D2, D3 y
D7–D10. Quedan estas, que no bloquean las fases 0 a 4:

1. **Equipo de la primera migración.** No hace falta decidirlo todavía,
   porque el instalador detecta el equipo (D10). Sólo habrá que capturar el
   modelo DMI del HP para añadirlo a `profiles/index.tsv`; el del Omen es
   «OMEN by HP Laptop 15-ce0xx».
2. **Atajos libres.** ¿Asignas alguno de los que quedan libres a YouTube
   Music, Discord o Basecamp? Se puede decidir en la Fase 5.

---

## 8. Próximo paso

Empieza por la **Fase 0**: es lo único que no podrás repetir después de
formatear. Requiere `arch/tools/capture-reference.sh` y un commit de
`arch/reference/`. Después, la Fase 1 decide el enfoque del shell antes de
mover ningún archivo.
