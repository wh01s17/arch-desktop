# Actualizar el equipo de pruebas a wh01s17 1.0.1

Esta actualización conserva la base 4.0.4, tu tema, plugins, atajos y política
de tapa. Aplica las correcciones seleccionadas de 4.0.5/4.0.6 y retira la
configuración insegura de mise que pudo crear la primera instalación.

## Actualizar desde GitHub

Guarda el trabajo abierto. En el otro equipo, ejecuta como tu usuario normal:

```bash
cd ~/workspace/arch-desktop &&
git pull --ff-only origin main &&
./install.sh --only "fixes stow validate"
```

Si clonaste este repo en otra ubicación, cambia la primera ruta. Si `git pull`
encuentra cambios locales incompatibles, detente y revísalos; no uses
`git reset --hard` para descartarlos.

Los parches están versionados en este repositorio. La etapa `fixes` los aplica
sobre el runtime de `~/dotfiles/platform` y el plugin personalizado de monitores,
y retira la configuración insegura de mise. `stow` regenera `.arch-build` y
reaplica los enlaces; `validate` comprueba la instalación. No hace falta
actualizar `~/dotfiles` con `git pull` para recibir estos parches, ni copiar un
comprimido entre equipos.

Si tus dotfiles están en otra ubicación, sustituye la última línea por:

```bash
DOTFILES_DIR=/ruta/dotfiles ./install.sh --only "fixes stow validate"
```

Si cualquier paso falla, detente y revisa el error antes de reiniciar. Cuando
termine correctamente, reinicia para cargar el bloqueo nuevo, limpiar el PATH
de los procesos anteriores y renovar las variables de GPU:

```bash
systemctl reboot
```

No hace falta repetir las etapas `system`, `user`, `packages` o `hibernate`.
`fixes` es idempotente y comprueba todos los contextos antes de escribir los
parches: si encuentra un bloque incompatible, se detiene para revisión.
Si mise tenía una configuración personalizada, su respaldo queda junto al
archivo original y el instalador indica su ruta. Los cambios aplicados en
`~/dotfiles` quedan locales; no se crean commits automáticamente.

## Comprobar después del reinicio

```bash
wh01s17 version                       # 1.0.1
hyprctl configerrors                 # sin errores
wh01s17-shell shell ping
cd ~/workspace/arch-desktop
tools/check-desktop.sh --only "lock"
```

La última prueba bloquea la pantalla: desbloquéala con tu contraseña cuando
lo indique. Comprueba un segundo bloqueo después de desbloquear y una
suspensión/reanudación manual: al volver debe pedir contraseña. Prueba también
activar/desactivar una pantalla desde tu panel de monitores.

Esta actualización corrige el código de desactivar SSH, pero no desactiva el
servicio ni modifica automáticamente las reglas del firewall actuales.

## Equipos instalados con el esquema de disco anterior

Las instalaciones hechas antes de que `INSTALL.md` creara los subvolúmenes `@`
tienen la raíz en el nivel superior del btrfs: los snapshots incluyen `/home`
y «Restaurar» de Limine no funciona. `install.sh` y `tools/check-system.sh`
lo avisan. El equipo sigue funcionando y puede arrancar un snapshot; para
corregir el esquema hay que reinstalar siguiendo `INSTALL.md` §2.

No cambies `RESTORE_METHOD` a `rsync` en ese esquema: `/home` no es un
subvolumen aparte, y restaurar podría devolverlo al estado del snapshot.

Mientras tanto, limita la caché de pacman, que también queda en los snapshots:

```bash
sudo systemctl enable --now paccache.timer
```
