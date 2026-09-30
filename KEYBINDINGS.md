# Atajos del perfil Arch visual

Esta configuración conserva las combinaciones de teclas de los módulos de
atajos de Omarchy Quattro y de `dotfiles/desktop/.config/hypr/bindings.lua`.
Hyprland ejecuta directamente las funciones de ventanas y espacios de trabajo;
`arch-look-action` reemplaza las acciones del menú, medios y aplicaciones.

| Atajo | Función en Arch |
| --- | --- |
| Super + Espacio | Menú de Quickshell |
| Super + Alt + Espacio | Lanzador de aplicaciones Wofi |
| Super + Escape | Menú de energía de Quickshell |
| Super + Enter | Kitty |
| Super + Shift + F | Nautilus |
| Super + Shift + N | Neovim en Kitty |
| Super + W | Cerrar ventana |
| Super + Flechas | Cambiar foco |
| Super + Shift + Flechas | Intercambiar ventanas |
| Super + 1…0 | Cambiar espacio de trabajo |
| Super + Shift + 1…0 | Mover ventana al espacio |
| Super + Shift + Alt + 1…0 | Mover ventana sin seguirla |
| Super + S / Super + Alt + S | Abrir o enviar al scratchpad |
| Super + F / Super + Alt + F | Pantalla completa o maximizada |
| Super + T / Super + P / Super + J | Flotante, pseudo o división |
| Super + L | Alternar dwindle/scrolling en el espacio 1…10; se conserva al reiniciar |
| Super + C / Super + V | Copiar/pegar; en Kitty usa las teclas propias de terminal |
| Super + G / Super + Alt + G | Agrupar o desagrupar |
| Super + Ctrl + Shift + Flechas | Redimensionar ventana |
| Super + Ctrl + A/B/D/W/P | Audio, Bluetooth, pantallas, red, energía |
| Super + Ctrl + L | Bloquear |
| Impr Pantalla | Captura de región |
| Alt + Impr Pantalla | Iniciar o parar grabación de región |
| Super + Ctrl + V | Historial del portapapeles |
| Ctrl + Alt + A/Z | Subir o bajar volumen |
| Ctrl + Alt + O/P/I | Pausa, siguiente o pista anterior |
| Super + Alt + A/P/D | WayScriber si está instalado |

Los atajos de las teclas multimedia, los accesos web y las combinaciones
adicionales de Hyprland están declarados en
`~/.config/arch-look/bindings.lua`; esa es la lista ejecutable completa.

## Equivalencias con limitaciones

Las teclas siguen asignadas, pero varias funciones de Omarchy requieren más
que una combinación de teclas. El script muestra un aviso para las que aún
carecen de equivalente completo: cierre masivo de ventanas, ancho guardado,
cuadratura de ventana, overlay de cámara, zoom, cambio dinámico de opacidad,
clima, tema, panel de touchpad, compartir archivos y transcodificación guiada.
WayScriber, Obsidian, Signal, Spotify,
1Password, Voxtype y Cliamp se ejecutan cuando estén instalados.

La barra, el reloj, los espacios, la bandeja y los menús se dibujan en
Quickshell. Las notificaciones se gestionan con SwayNC y los diálogos de red,
audio y Bluetooth usan aplicaciones de Arch. Conservan su atajo pero no el
panel detallado de los plugins de Omarchy Shell.
