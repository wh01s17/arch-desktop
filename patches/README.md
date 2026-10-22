# Correcciones sobre la base congelada

El escritorio 1.0.1 mantiene la base Omarchy 4.0.4 y las personalizaciones
wh01s17. No instala Omarchy 4.0.6 ni sus repositorios, kernel o migraciones.

`omarchy-4.0.4-fixes.json` conserva bloques exactos del
[diff oficial 4.0.4 → 4.0.6](https://github.com/omacom/omarchy/compare/v4.0.4...v4.0.6),
con los commits de origen y licencia MIT. Se seleccionaron:

- separación de opciones y argumentos en comandos, paquetes y hooks;
- comprobación del estado real del bloqueo y recuperación sin tomar el de otro proceso;
- temporizadores de inactividad: cero desactiva la acción;
- espera de salida y arranque al reiniciar el shell;
- API Lua para activar/desactivar monitores, también en el plugin personalizado;
- calendario calculado en UTC, consistente con el reloj personalizado ya corregido;
- detección de la GPU que controla la pantalla antes de forzar variables NVIDIA;
- eliminación completa de las variantes estándar de reglas UFW al desactivar SSH;
- conservación de `__sourceDir` para los scripts de plugins externos;
- provisión sin la entrada automática `{{ cwd }}/bin` de mise.

No se aplica el `--` de upstream en `launch-editor`: ese script es `$EDITOR`,
y con `--` el editor toma como archivo el `+línea` que pasan `less`,
lazygit o yazi (`nvim -- +3 f.txt` abre `+3` y `f.txt`).

Se conservaron la solución propia de colores Qt 6.12, el tema, los plugins,
los atajos, las aplicaciones y la política de tapa. El parche de colores de
upstream usa un alias de importación; el renombrado mantiene `Colors` para
compatibilidad con los plugins wh01s17.

`tools/backport-omarchy.py` revisa todos los contextos antes de escribir y
acepta una segunda ejecución sin cambios. Si un archivo difiere en un bloque
afectado, se detiene para revisión. Cada archivo se sustituye atómicamente.
El generador usa los mismos parches con los nombres originales.

`mise-work-cleanup.sh` adapta la
[migración de seguridad #11336](https://github.com/omacom/omarchy/pull/11336):
retira la confianza anterior, elimina el archivo estándar o respalda el
personalizado antes de quitar la asignación insegura. Conserva enlaces y
configuraciones ignoradas. Usa una marca de éxito para no revocar otra vez una
configuración que revises y vuelvas a autorizar. No limpia la sesión de un
shell ya abierto: hay que volver a iniciar sesión o reiniciar.

El comando para desactivar SSH queda corregido, pero la actualización no lo
ejecuta ni cambia las reglas actuales: el equipo puede estar usando SSH.

Pruebas: `TEST_DOTFILES=~/dotfiles python3 -B -m unittest discover -s tests -v`.
Las pruebas de integración ejecutan helpers con sustitutos de pacman, sudo y
mise: ejecútalas en un entorno desechable. La validación de suspensión y PAM
se hace en el equipo de destino, según [UPDATE.md](../UPDATE.md).
