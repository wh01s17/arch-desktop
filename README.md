# Arch con apariencia wh01s17

Instala en Arch Linux una sesión visual autónoma inspirada en este Omarchy:
Hyprland en Lua, barra y menús básicos en Quickshell, paleta y wallpapers
`wh01s17`, Kitty, lanzador, bloqueo y prompt Oh My Posh. No instala Omarchy ni
carga archivos de `/usr/share/omarchy`.

## Uso

En un Arch recién instalado, entra como usuario normal y ejecuta:

```bash
git clone https://github.com/wh01s17/post-install-linux.git ~/workspace/post-install-linux
cd ~/workspace/post-install-linux
./arch/install.sh --dry-run
./arch/install.sh --profile auto
```

Para la disposición de pantallas del Omen, sustituye `auto` por `omen`;
para el portátil HP, usa `hp-gray`.

Ejecuta el instalador tú mismo: usa `sudo` sólo para paquetes y servicios,
y te pedirá la contraseña cuando haga falta. Instala paquetes oficiales con
`pacman`, obtiene los wallpapers y el tema activo desde `~/dotfiles` (lo clona
si falta) y descarga Oh My Posh con su instalador oficial a `~/.local/bin`.
Después, cierra sesión e inicia **Hyprland** desde tu gestor de sesión o
ejecutando `Hyprland` desde una TTY. Se recomienda Arch x86_64 con Hyprland 0.55 o superior
por la configuración Lua.

Puedes indicar otro clon local: `DOTFILES_DIR=/ruta/dotfiles ./arch/install.sh`.
El perfil predeterminado `auto` acepta los monitores disponibles; `omen` y
`hp-gray` replican los perfiles de monitores y tamaño de fuente de Kitty de
los dotfiles actuales. Úsalos sólo si los nombres de salidas coinciden.
El instalador no se ejecuta sobre Omarchy para evitar reemplazar la sesión de
origen. Copia los archivos a `~/.config/`, `~/.zshrc` y `~/.local/bin/`;
respalda los anteriores en `~/.config-backup/arch-look/<fecha>/`. La copia
anterior de `~/.config/oh-my-posh` se respalda completa y se reemplaza por la
del clon para mantener `omp-theme` y el tema activo juntos. Si un destino o
directorio padre es un enlace de Stow, el instalador se detiene antes de instalar
paquetes; desenlaza el paquete en conflicto y decide qué configuración gestionará
esa ruta antes de continuar. No cambia la shell predeterminada: Kitty abre Zsh
directamente. El archivo `~/.zshrc` que instala activa Oh My Posh, pero este
instalador visual no instala Oh My Zsh ni sus plugins.

## Qué reproduce

- Paleta `wh01s17`, dos fondos 4K, bordes verde/cian, radio de 6 px, sombra,
  blur y separaciones de ventanas obtenidos de los dotfiles actuales. El fondo
  elegido y el layout de los espacios 1 a 10 persisten entre sesiones.
- Barra superior de Quickshell con espacios, ventana activa, reloj, bandeja y
  menú; lanzador Wofi con la misma paleta.
- Kitty con MesloLGS Nerd Font, opacidad 0,85 y el tema activo de Oh My Posh
  copiado del checkout. `omp-theme` sigue disponible. La paleta fija de Kitty
  permite usar el modo `--omarchy` del selector sin el runtime de Omarchy.
- Atajos familiares para ventanas, espacios, medios, aplicaciones y menús.
  El navegador instalado para esos atajos es Firefox, incluido el modo privado.
  Consulta [KEYBINDINGS.md](KEYBINDINGS.md) para equivalencias y límites.

## Diferencias actuales

Omarchy Shell contiene paneles y servicios propios para notificaciones,
bloqueo, configuración, recordatorios y plugins. Esta instalación usa una
barra y menús de Quickshell más sencillos, SwayNC para notificaciones y
aplicaciones independientes para ajustes. No reproduce todos los paneles,
iconos dinámicos ni las acciones propias de Omarchy. Los atajos que requieren
esos servicios conservan su combinación y avisan si no hay equivalente.

El instalador toma el último estado disponible en el clon de dotfiles. Antes
de formatear, publica o respalda los cambios sin commit y los temas descargados
localmente: Git no los transporta a un equipo nuevo.

## Verificación y restauración

```bash
bash -n arch/install.sh arch/config/arch-look-action
luac -p arch/config/hyprland.lua arch/config/bindings.lua
qmllint arch/config/shell.qml
Hyprland --verify-config --config ~/.config/hypr/hyprland.lua
```

Si el resultado no te gusta, copia los archivos guardados en
`~/.config-backup/arch-look/<fecha>/` a sus rutas originales y vuelve a
iniciar la sesión. El instalador no borra tus respaldos.
