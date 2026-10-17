#!/usr/bin/env python3
"""Build the plain-Arch version of your desktop and terminal Stow packages.

Your dotfiles keep Omarchy's names because your Omarchy machine uses them.
On plain Arch everything is called wh01s17 (see tools/rename.py), so this
copies desktop/ and terminal/ into ~/dotfiles/.arch-build/ with the names
changed, and install.sh stows them from there.

Usage:
    tools/arch-dotfiles.py [--dotfiles ~/dotfiles] [--packages desktop terminal]
    tools/arch-dotfiles.py --in-place DIR     # e.g. a cloned third-party plugin

Edit desktop/ and terminal/, not .arch-build/: it is rebuilt on every run
(./install.sh --only stow).
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rename import NAME, is_qml, leftovers, rename_name, rename_qml, rename_text  # noqa: E402

SKIP_NAMES = {".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}

# fastfetch: on Omarchy the OS line is Omarchy's version; on Arch, show the real
# OS (fastfetch's os module reads /etc/os-release).
FASTFETCH_OS = re.compile(
    r'"type": "command",(\s*"key": "[^"]*OS",\s*"keyColor": "[^"]*"),\s*'
    r'"text": "version=\$\(' + NAME + r'-version\)[^\n]*'
)
SKIP_SUFFIXES = (".pyc",)


def skipped(name: str) -> bool:
    return name in SKIP_NAMES or name.endswith(SKIP_SUFFIXES) or ".bak" in name


def convert_file(source: Path, target: Path) -> list[str]:
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        target.symlink_to(rename_name(os.readlink(source)))
        return []
    try:
        text = source.read_text()
    except UnicodeDecodeError:
        shutil.copy2(source, target)
        return []
    new_text = rename_text(text)
    if is_qml(target.name, new_text):
        new_text = rename_qml(new_text)
    if target.name == "config.jsonc" and target.parent.name == "fastfetch":
        new_text = FASTFETCH_OS.sub(r'"type": "os",\1', new_text)
    if target.suffix == ".lua":
        # Plain Arch has no /usr/share/wh01s17: fall back to the stowed copy.
        new_text = new_text.replace(f'"/usr/share/{NAME}"', f'(os.getenv("HOME") .. "/.local/share/{NAME}")')
    target.write_text(new_text)
    shutil.copymode(source, target)
    return leftovers(new_text)


def build(source_root: Path, target_root: Path) -> dict[str, list[str]]:
    remaining: dict[str, list[str]] = {}
    for directory, dirnames, filenames in os.walk(source_root):
        dirnames[:] = [d for d in dirnames if not skipped(d)]
        base = Path(directory)
        relative = base.relative_to(source_root)
        target_dir = target_root / Path(*[rename_name(part) for part in relative.parts])
        # Symlinked directories are links too: recreate them, do not descend.
        for name in list(dirnames):
            if (base / name).is_symlink():
                dirnames.remove(name)
                filenames.append(name)
        for name in filenames:
            if skipped(name):
                continue
            found = convert_file(base / name, target_dir / rename_name(name))
            if found:
                remaining[str(relative / name)] = found
    return remaining


def rename_in_place(root: Path) -> dict[str, list[str]]:
    staging = root.with_name(root.name + ".renaming")
    shutil.rmtree(staging, ignore_errors=True)
    remaining = build(root, staging)
    shutil.rmtree(root)
    staging.rename(root)
    return remaining


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dotfiles", type=Path,
                        default=Path(os.environ.get("DOTFILES_DIR", Path.home() / "dotfiles")))
    parser.add_argument("--packages", nargs="+", default=["desktop", "terminal"])
    parser.add_argument("--in-place", type=Path, help="rename a directory in place instead")
    args = parser.parse_args()

    if args.in_place:
        remaining = rename_in_place(args.in_place.expanduser().resolve())
    else:
        dotfiles = args.dotfiles.expanduser().resolve()
        build_dir = dotfiles / ".arch-build"
        remaining = {}
        for package in args.packages:
            source = dotfiles / package
            if not source.is_dir():
                sys.exit(f"error: {source} does not exist")
            target = build_dir / package
            shutil.rmtree(target, ignore_errors=True)
            remaining.update({f"{package}/{k}": v for k, v in build(source, target).items()})
        print(f"{', '.join(args.packages)} → {build_dir} ({NAME})")

    if remaining:
        print(f"Aviso: menciones sin renombrar en {len(remaining)} archivo(s):", file=sys.stderr)
        for path, found in sorted(remaining.items())[:20]:
            print(f"  {path}: {', '.join(sorted(set(found))[:3])}", file=sys.stderr)


if __name__ == "__main__":
    main()
