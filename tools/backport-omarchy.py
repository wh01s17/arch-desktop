#!/usr/bin/env python3
"""Apply reviewed Omarchy fixes without replacing the frozen desktop.

Exact-context, idempotent backports; all files are checked before any write.
Does not execute the runtime, restart the session or change machine settings.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rename import is_qml, rename_name, rename_qml, rename_text

REPO = Path(__file__).resolve().parent.parent
PATCHSET = REPO / "patches/omarchy-4.0.4-fixes.json"
MARKER = "Backports revisados: arch-desktop/patches/omarchy-4.0.4-fixes.json"


def converted(text: str, path: str, renamed: bool) -> str:
    if not renamed:
        return text
    text = rename_text(text)
    return rename_qml(text) if is_qml(path, text) else text


def apply_hunks(text: str, hunks: list[dict], path: str, renamed: bool) -> str:
    for number, hunk in enumerate(hunks, 1):
        old = converted(hunk["old"], path, renamed)
        new = converted(hunk["new"], path, renamed)
        if old == new or (new and new in text):
            continue
        if not old:
            if text:
                raise ValueError(f"{path}: el archivo nuevo ya existe con otro contenido")
            text = new
        elif text.count(old) == 1:
            text = text.replace(old, new, 1)
        else:
            raise ValueError(f"{path}: bloque {number} diferente; revisar antes de aplicar")
    return text


def plan_runtime(root: Path, renamed: bool = True) -> dict[Path, str]:
    changes = {}
    for entry in json.loads(PATCHSET.read_text())["files"]:
        relative = rename_name(entry["path"]) if renamed else entry["path"]
        path = root / relative
        before = path.read_text() if path.exists() else ""
        after = apply_hunks(before, entry["hunks"], entry["path"], renamed)
        if after != before:
            changes[path] = after
    # Keep the original package version: this is a selective backport, not 4.0.6.
    upstream = root / "UPSTREAM"
    if upstream.is_file() and MARKER not in upstream.read_text():
        changes[upstream] = upstream.read_text().rstrip() + "\n" + MARKER + "\n"
    version = root / "VERSION"
    own_version = (REPO / "VERSION").read_text()
    if version.exists() and version.read_text().strip() not in {"1.0", own_version.strip()}:
        raise ValueError(f"{version}: versión diferente; no se sustituye automáticamente")
    if not version.exists() or version.read_text() != own_version:
        changes[version] = own_version
    return changes


def plan_monitor(dotfiles: Path) -> dict[Path, str]:
    path = dotfiles / "desktop/.config/omarchy/plugins/wh01s17.monitor/Panel.qml"
    entry = next(e for e in json.loads(PATCHSET.read_text())["files"]
                 if e["path"] == "shell/plugins/panels/monitor/Panel.qml")
    # Only the monitor API fix. Keep the user's layout, persistence and styling.
    hunks = [h for h in entry["hunks"] if '"keyword", "monitor"' in h["old"]]
    before = path.read_text()
    after = apply_hunks(before, hunks, str(path), False)
    return {path: after} if after != before else {}


def write_changes(changes: dict[Path, str]) -> None:
    for path, text in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = path.stat().st_mode & 0o777 if path.exists() else (0o755 if path.parent.name == "bin" else 0o644)
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(text)
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--dotfiles", type=Path)
    parser.add_argument("--upstream-names", action="store_true")
    parser.add_argument("--check", action="store_true", help="mostrar cambios sin escribir")
    args = parser.parse_args()
    if not args.runtime and not args.dotfiles:
        parser.error("se requiere --runtime o --dotfiles")
    changes = {}
    try:
        if args.runtime:
            changes.update(plan_runtime(args.runtime, not args.upstream_names))
        if args.dotfiles:
            changes.update(plan_monitor(args.dotfiles))
        for path in changes:
            print(path)
        if not args.check:
            write_changes(changes)
    except (ValueError, OSError) as error:
        sys.exit(f"error: {error}")
    print(f"{len(changes)} archivos {'por actualizar' if args.check else 'actualizados'}")


if __name__ == "__main__":
    main()
