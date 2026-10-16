#!/usr/bin/env python3
"""Freeze the installed Omarchy runtime into the `platform` Stow package.

Copies /usr/share/omarchy (without the stock themes and migrations) and the
files that the omarchy and omarchy-settings packages install elsewhere, then
applies the adaptations needed to run it from ~/.local/share/omarchy on plain
Arch. Every patch checks the exact upstream text it replaces, so a different
Omarchy version fails loudly instead of being half-patched.

Usage:
    tools/vendor-omarchy.py [--source /usr/share/omarchy]
                                 [--dest ~/dotfiles/platform] [--force]

The result is a Stow package:
    platform/.local/share/omarchy/    runtime (OMARCHY_PATH)
    platform/.local/share/omarchy/system/
                                      files the packages put outside
                                      /usr/share/omarchy; install.sh picks them
    platform/.config/uwsm/env.d/      session environment (OMARCHY_PATH, PATH)
    platform/.config/systemd/user/    user services, pointing to the copy
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

PACKAGES = ("omarchy", "omarchy-settings")
EXCLUDED_TOP = {"themes", "migrations"}
USER_UNITS = (
    "bt-agent.service",
    "omarchy-crash-watch.service",
    "omarchy-recover-internal-monitor.service",
    "omarchy-sleep-lock.service",
)
# Units left out on purpose: fcitx5 (not used), migrate-notify (no migrations),
# speaker-tuning (Dell XPS only) and tailscale-receive (Tailscale not used).

LICENSE = """\
Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

COPY_PATH = "$HOME/.local/share/omarchy"

# The bar's menu button draws the wh01s17 W instead of the Omarchy glyph.
# Same rectangles as themes/wh01s17/brand/logo.svg (stroked like the
# 02-outline-mark wallpaper), moved to the origin.
MENU_BAR_WIDGET = """\
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// wh01s17: the W mark replaces the Omarchy glyph in this frozen copy.
BarWidget {
  id: root
  moduleName: "omarchy.menu"

  readonly property real markHeight: Math.round(Style.font.body * 1.25)
  readonly property real markWidth: Math.round(markHeight * 336 / 304)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7.5
    fixedWidth: root.vertical ? -1 : root.markWidth + scaledHorizontalMargin * 2
    tooltipText: "Menú"
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\\"menu\\":\\"root\\"}'")
    }

    Shape {
      anchors.centerIn: parent
      width: root.markWidth
      height: root.markHeight
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        readonly property real unit: root.markHeight / 304
        fillColor: "transparent"
        strokeColor: Color.accent
        strokeWidth: 1.4
        joinStyle: ShapePath.MiterJoin
        scale: Qt.size(unit, unit)
        PathSvg { path: "M0 0h80v240H0zm128 0h80v240h-80zm128 0h80v240h-80zM64 240h80v64H64zm128 0h80v64h-80z" }
      }
    }
  }
}
"""

# Bindings for apps and web apps the user does not use (PLAN.md, D7).
# Matched by the description argument of o.bind(...).
DROPPED_BINDINGS = {
    "default/hypr/bindings/applications.lua": (
        "Signal", "Omawrite", "Passwords", "Grok", "Calendar", "Email", "New email",
        "YouTube", "Google Messages", "Google Photos", "Google Maps", "X", "X Post",
    ),
    "default/hypr/bindings/utilities.lua": ("Calculator",),
}


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def package_version(name: str) -> str:
    result = subprocess.run(["pacman", "-Q", name], capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"package {name} is not installed; run this on the Omarchy machine")
    return result.stdout.split()[1]


def package_files(name: str) -> list[Path]:
    result = subprocess.run(["pacman", "-Qlq", name], capture_output=True, text=True, check=True)
    return [Path(line) for line in result.stdout.splitlines() if line and not line.endswith("/")]


def replace(path: Path, old: str, new: str, count: int = 1) -> None:
    """Replace `old` exactly `count` times (0 means at least once)."""
    text = path.read_text()
    found = text.count(old)
    if found == 0 or (count and found != count):
        fail(f"{path}: expected {count or 'some'} occurrence(s) of {old!r}, found {found}")
    path.write_text(text.replace(old, new))


def write_script(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(0o755)


def stub(path: Path, summary: str, body: str) -> None:
    if not path.exists():
        fail(f"{path} does not exist upstream; review the stub list")
    write_script(
        path,
        "#!/bin/bash\n\n"
        f"# omarchy:summary={summary}\n"
        "# omarchy:hidden=true\n"
        "#\n"
        "# wh01s17: replaced in the frozen copy. Upstream ties this command to the\n"
        "# Omarchy package repository or to a git checkout of OMARCHY_PATH, which\n"
        "# here would be ~/dotfiles.\n\n"
        f"{body}\n",
    )


DISABLED = 'echo "$(basename "$0"): no disponible en la copia congelada de Omarchy (wh01s17)." >&2\nexit 1'


def patch_runtime(root: Path, version: str) -> None:
    default = root / "default"

    # Session environment: default OMARCHY_PATH to the Stow-managed copy.
    replace(
        default / "bash/env-bootstrap",
        'if [ -f /etc/omarchy.conf ]; then\n'
        '  . /etc/omarchy.conf\n'
        '  : "${OMARCHY_PATH:=/usr/share/omarchy}"\n'
        'else\n'
        '  OMARCHY_PATH=/usr/share/omarchy\n'
        'fi\n',
        '# wh01s17: frozen copy installed with Stow; see platform/README.md.\n'
        f': "${{OMARCHY_PATH:={COPY_PATH}}}"\n',
    )
    bootstrap = '/usr/share/omarchy/default/bash/env-bootstrap'
    bootstrap_copy = f'"${{OMARCHY_PATH:-{COPY_PATH}}}/default/bash/env-bootstrap"'
    for relative in ("bashrc", "bash/envs", "uwsm/env.d/10-omarchy"):
        replace(default / relative, bootstrap, bootstrap_copy, count=2)
    replace(default / "bash/rc", ': "${OMARCHY_PATH:=/usr/share/omarchy}"',
            f': "${{OMARCHY_PATH:={COPY_PATH}}}"')

    # Hyprland Lua: fall back to the copy when OMARCHY_PATH is not exported.
    replace(default / "hypr/bootstrap.lua", '(os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")',
            '(os.getenv("OMARCHY_PATH") or (home .. "/.local/share/omarchy"))')
    replace(default / "hypr/paths.lua", 'env_or("OMARCHY_PATH", "/usr/share/omarchy")',
            'env_or("OMARCHY_PATH", home .. "/.local/share/omarchy")')
    replace(root / "config/hypr/hyprland.lua", '(os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")',
            '(os.getenv("OMARCHY_PATH") or (os.getenv("HOME") .. "/.local/share/omarchy"))')

    bin_dir = root / "bin"
    # Scripts and installer steps fall back to the packaged path; use the copy.
    fallback = "${OMARCHY_PATH:-/usr/share/omarchy}"
    patched = 0
    for path in [*bin_dir.iterdir(), *(root / "install").rglob("*.sh")]:
        if path.is_file() and fallback in path.read_text(errors="replace"):
            replace(path, fallback, f"${{OMARCHY_PATH:-{COPY_PATH}}}", count=0)
            patched += 1
    if patched == 0:
        fail("no ${OMARCHY_PATH:-/usr/share/omarchy} fallbacks found; review the patch")
    # Root callers pass OMARCHY_PATH explicitly (install.sh does).
    replace(bin_dir / "omarchy-apply-lock",
            "export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin",
            'export PATH="${OMARCHY_PATH:?OMARCHY_PATH requerido}/bin:/usr/local/bin:/usr/bin:/bin"')

    # User provisioning: the stock themes are not copied, the AI tools come
    # from the user's own mise config, and only the copied units are enabled.
    user_steps = root / "install/user"
    replace(user_steps / "theme.sh", 'omarchy-theme-set "Tokyo Night"',
            'omarchy-theme-set "${OMARCHY_DEFAULT_THEME:-wh01s17}"', count=2)
    mise = user_steps / "mise.sh"
    replace(mise, "omarchy-mise-install codex\n", "", count=1)
    mise.write_text(
        "# Upgrades must not delete the version a running process is executing from:\n"
        "# mise up would prune the old install dir out from under a live session.\n"
        "mise settings set upgrade.auto_prune false\n\n"
        "# wh01s17: install the tools listed in ~/.config/mise/config.toml (Stow\n"
        "# package `apps`) instead of Omarchy's full AI tool list.\n"
        "if [[ -f $HOME/.config/mise/config.toml ]]; then\n"
        "  # A Stow link resolves into ~/dotfiles, which mise treats as untrusted.\n"
        "  mise trust \"$HOME/.config/mise/config.toml\"\n"
        "  mise install --yes || echo 'Warning: mise install failed; run it again later' >&2\n"
        "fi\n"
    )
    replace(
        user_steps / "first-run/enable-user-units.sh",
        "  omarchy-sleep-lock.service \\\n"
        "  omarchy-migrate-notify.service \\\n"
        "  omarchy-fcitx5.service \\\n"
        "  omarchy-crash-watch.service\n",
        "  omarchy-sleep-lock.service \\\n"
        "  omarchy-crash-watch.service\n",
    )

    for relative, descriptions in DROPPED_BINDINGS.items():
        path = root / relative
        lines = path.read_text().splitlines(keepends=True)
        for description in descriptions:
            marker = f'"{description}",'
            matches = [line for line in lines if line.lstrip().startswith("o.bind") and marker in line]
            if not matches:
                fail(f"{relative}: no binding described as {description!r}")
            lines = [line for line in lines if line not in matches]
        path.write_text("".join(lines))

    # Default apps: Firefox stays the browser and HEY (dropped) gets no mailto.
    replace(bin_dir / "omarchy-provision-user",
            "env -u BROWSER xdg-settings set default-web-browser chromium.desktop\n",
            "env -u BROWSER xdg-settings set default-web-browser firefox.desktop\n")
    replace(bin_dir / "omarchy-provision-user",
            "xdg-mime default HEY.desktop x-scheme-handler/mailto\n", "")

    menu_widget = root / "shell/plugins/menu/BarWidget.qml"
    replace(menu_widget, 'text: "\\ue900"', 'text: "\\ue900"')  # upstream check only
    menu_widget.write_text(MENU_BAR_WIDGET)

    # XCompose expands %H to the home directory.
    replace(root / "install/user/xcompose.sh", 'include "/usr/share/omarchy/default/xcompose"',
            'include "%H/.local/share/omarchy/default/xcompose"')

    # Never replace /etc/pacman.conf with the one that enables Omarchy's repo.
    replace(
        root / "install/post-install/pacman.sh",
        'cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf\n'
        'cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist\n',
        "# wh01s17: plain Arch keeps its own pacman.conf and mirrorlist.\n",
    )

    # These treat a non-/usr/share OMARCHY_PATH as a git checkout and would
    # fetch or pull ~/dotfiles, or they manage Omarchy's pacman repository.
    stub(bin_dir / "omarchy-update-dev", "Update Omarchy dev checkout (disabled)", "exit 0")
    stub(bin_dir / "omarchy-update-keyring", "Update Arch signing keys",
         'echo -e "\\e[32m\\nUpdate Arch signing keys\\e[0m"\n'
         "sudo pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null")
    stub(bin_dir / "omarchy-update-available", "Report available system updates",
         "count=$(checkupdates --nocolor 2>/dev/null | wc -l)\n"
         "if command -v yay >/dev/null 2>&1; then\n"
         "  count=$((count + $(yay -Qua 2>/dev/null | wc -l)))\n"
         "fi\n"
         "if ((count > 0)); then\n"
         '  echo "$count actualizaciones de paquetes disponibles"\n'
         "  exit 0\n"
         "fi\n"
         'echo "El sistema está al día"\n'
         "exit 1")
    stub(bin_dir / "omarchy-version", "Show the frozen Omarchy version",
         'cat "${OMARCHY_PATH:-$HOME/.local/share/omarchy}/VERSION"')
    for name in ("omarchy-version-channel", "omarchy-version-branch", "omarchy-channel-current"):
        stub(bin_dir / name, "Show the release channel (frozen copy)", "echo frozen")
    for name in ("omarchy-refresh-pacman", "omarchy-channel-set", "omarchy-upgrade-to-quattro",
                 "omarchy-dev-link", "omarchy-dev-unlink", "omarchy-dev-pkg-test",
                 "omarchy-reinstall", "omarchy-reinstall-pkgs", "omarchy-update-pacman-guard",
                 "omarchy-system-factory-reset"):
        stub(bin_dir / name, "Disabled in the frozen copy", DISABLED)

    (root / "VERSION").write_text(f"{version} (copia congelada wh01s17)\n")


def write_user_units(source: Path, dest_units: Path) -> None:
    dest_units.mkdir(parents=True, exist_ok=True)
    path_line = ("Environment=PATH=%h/.local/share/omarchy/bin:%h/.local/bin:"
                 "/usr/local/bin:/usr/bin\n")
    for name in USER_UNITS:
        text = (source / name).read_text()
        text = text.replace("/usr/bin/omarchy-", "%h/.local/share/omarchy/bin/omarchy-")
        if "/usr/share/omarchy" in text:
            fail(f"{name} still references /usr/share/omarchy")
        if "[Service]\n" not in text:
            fail(f"{name} has no [Service] section")
        text = text.replace("[Service]\n", "[Service]\n" + path_line, 1)
        (dest_units / name).write_text(text)
    oomd = source / "app.slice.d/10-oomd.conf"
    (dest_units / "app.slice.d").mkdir(exist_ok=True)
    shutil.copy2(oomd, dest_units / "app.slice.d/10-oomd.conf")


def copy_runtime(source: Path, root: Path) -> None:
    def ignore(directory: str, names: list[str]) -> set[str]:
        return EXCLUDED_TOP & set(names) if Path(directory) == source else set()

    # bin/ holds symlinks to /usr/bin/omarchy-*: copy the real scripts.
    shutil.copytree(source, root, symlinks=False, ignore=ignore)
    for path in root.rglob("*"):
        mode = path.stat().st_mode
        path.chmod(mode | stat.S_IWUSR)


def copy_system_files(root: Path) -> int:
    """Copy what the packages install outside /usr/share/omarchy."""
    copied = 0
    for package in PACKAGES:
        for path in package_files(package):
            text = str(path)
            if text.startswith("/usr/share/omarchy/"):
                continue
            if text.startswith("/usr/bin/omarchy"):
                # Debug helpers from omarchy-settings have no bin/ symlink.
                target = root / "bin" / path.name
                if not target.exists():
                    shutil.copy2(path, target)
                    copied += 1
                continue
            if "/skel/.local/state/omarchy/migrations/" in text:
                continue
            if not path.is_file() or path.is_symlink():
                continue
            target = root / "system" / path.relative_to("/")
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(path, target)
            except PermissionError:
                print(f"warning: cannot read {path} (root only); skipped", file=sys.stderr)
                continue
            copied += 1
    return copied


def write_docs(dest: Path, root: Path, versions: dict[str, str]) -> None:
    (root / "LICENSE").write_text(LICENSE)
    today = dt.date.today().isoformat()
    (root / "UPSTREAM").write_text(
        "Copia congelada de Omarchy (https://github.com/basecamp/omarchy), licencia MIT.\n"
        f"Fecha: {today}\n"
        + "".join(f"{name}: {version}\n" for name, version in versions.items())
        + "Generada con arch-desktop/tools/vendor-omarchy.py.\n"
    )
    (dest / "README.md").write_text(
        "# platform\n\n"
        "Paquete Stow sólo para Arch puro: una copia congelada del runtime de\n"
        f"Omarchy {versions['omarchy']} (licencia MIT, ver `.local/share/omarchy/LICENSE`).\n"
        "Con él, los paquetes `desktop`, `terminal` y `maintenance` funcionan igual\n"
        "que en Omarchy, sin el repositorio de paquetes de Omarchy.\n\n"
        "No lo instales en un equipo con Omarchy: allí `/usr/share/omarchy` ya\n"
        "proporciona lo mismo.\n\n"
        "| Ruta | Contenido |\n"
        "| --- | --- |\n"
        "| `.local/share/omarchy/` | Runtime (`OMARCHY_PATH`): shell, `bin/`, `default/`, `config/`, `install/` |\n"
        "| `.local/share/omarchy/system/` | Archivos que los paquetes instalan fuera de `/usr/share/omarchy`; `install.sh` elige cuáles aplicar |\n"
        "| `.local/share/omarchy/nvim/config/` | Configuración LazyVim de `omarchy-nvim`; se copia a `~/.config/nvim` si falta |\n"
        "| `.config/uwsm/env.d/10-omarchy` | Entorno de la sesión: `OMARCHY_PATH` y `PATH` |\n"
        "| `.config/systemd/user/` | Servicios de usuario que apuntan a la copia |\n\n"
        "## Diferencias con Omarchy\n\n"
        "- Sin los temas de serie ni las migraciones: sólo se usa el tema `wh01s17`.\n"
        "- `omarchy-update` actualiza Arch (pacman, AUR, mise) sin tocar el repositorio\n"
        "  de Omarchy ni hacer `git pull` en `OMARCHY_PATH` (que aquí es `~/dotfiles`).\n"
        "- Los comandos de canales, reinstalación y enlace de desarrollo están\n"
        "  desactivados.\n\n"
        "Regenerar desde un equipo con Omarchy:\n\n"
        "```bash\n"
        "~/workspace/arch-desktop/tools/vendor-omarchy.py --force\n"
        "```\n\n"
        "Los cambios propios hechos a mano dentro de la copia se pierden al\n"
        "regenerarla; revisa `git diff` antes de hacer commit.\n"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=Path("/usr/share/omarchy"))
    parser.add_argument("--dest", type=Path,
                        default=Path(os.environ.get("DOTFILES_DIR", Path.home() / "dotfiles")) / "platform")
    parser.add_argument("--force", action="store_true", help="replace an existing copy")
    args = parser.parse_args()

    source = args.source.resolve()
    dest = args.dest.expanduser().resolve()
    root = dest / ".local/share/omarchy"
    if not (source / "default/hypr/bootstrap.lua").is_file():
        fail(f"{source} does not look like Omarchy 4")
    versions = {name: package_version(name) for name in PACKAGES}

    if dest.exists():
        if not args.force:
            fail(f"{dest} already exists; use --force to regenerate it")
        shutil.rmtree(dest)

    print(f"==> Copiando {source} → {root}")
    copy_runtime(source, root)
    print("==> Copiando archivos de sistema de los paquetes")
    count = copy_system_files(root)
    print(f"    {count} archivos")
    # omarchy-nvim only exists in Omarchy's repo; keep its LazyVim config.
    nvim_config = Path("/usr/share/omarchy-nvim/config")
    if nvim_config.is_dir():
        shutil.copytree(nvim_config, root / "nvim/config")
        versions["omarchy-nvim"] = package_version("omarchy-nvim")
    else:
        print("warning: omarchy-nvim not installed; skipping the Neovim config", file=sys.stderr)
    print("==> Adaptando la copia a Arch puro")
    patch_runtime(root, versions["omarchy"])
    print("==> Entorno de sesión y servicios de usuario")
    env_dir = dest / ".config/uwsm/env.d"
    env_dir.mkdir(parents=True)
    shutil.copy2(root / "default/uwsm/env.d/10-omarchy", env_dir / "10-omarchy")
    write_user_units(root / "default/systemd/user", dest / ".config/systemd/user")
    write_docs(dest, root, versions)

    # Known harmless mentions: comments, the "is this the packaged path?" test in
    # env-bootstrap, pacman --overwrite globs and the disabled dev tooling.
    allowed = {"default/bash/env-bootstrap", "bin/omarchy-update-system-pkgs", "bin/omarchy-dev-status"}
    leftovers = [
        path for path in subprocess.run(
            ["grep", "-rlF", "/usr/share/omarchy", str(root / "bin"), str(root / "shell"),
             str(root / "default/hypr"), str(root / "default/bash"), str(root / "default/uwsm"),
             str(root / "install")],
            capture_output=True, text=True,
        ).stdout.split()
        if str(Path(path).relative_to(root)) not in allowed
    ]
    if leftovers:
        print("Aviso: aún mencionan /usr/share/omarchy (revisar):", file=sys.stderr)
        for path in leftovers:
            print(f"  {path}", file=sys.stderr)

    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink() and path.parent.name == "bin":
            path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"Listo: {dest}")


if __name__ == "__main__":
    main()
