"""Rename Omarchy to wh01s17 in text and paths.

Shared by vendor-omarchy.py (the frozen runtime) and arch-dotfiles.py (your
desktop and terminal packages, rebuilt for plain Arch).

Rules, in order:
  1. URLs and upstream names (omarchy.org mirrors, github.com/basecamp/omarchy)
     are kept: they point to real places and are credits, not our names.
  2. Built-in shell plugin ids (omarchy.clock, omarchy.menu, ...) and the
     namespace the shell reserves for them become core.*: wh01s17.* is
     already taken by your own plugins.
  3. Every other omarchy/Omarchy/OMARCHY becomes wh01s17/wh01s17/WH01S17
     (Wh01s17 inside camelCase identifiers).

QML files (.qml, .js, qmldir) also get rename_qml: Qt 6.12 added a QtQuick
`Color` singleton that hides the shell's qs.Commons.Color in every file that
imports QtQuick (Color.bar reads undefined and the bar loses its widgets), so
the shell's singleton is called Colors.
"""

from __future__ import annotations

import re

NAME = "wh01s17"
BUILTIN_NAMESPACE = "core"

# Ids from the manifests of /usr/share/omarchy/shell/plugins (Omarchy 4.0.4).
BUILTIN_PLUGINS = (
    "active-window", "agents", "audio", "background", "bar", "battery", "bluetooth",
    "clipboard", "clock", "dev-gallery", "disk-speedtest", "dropbox", "emojis", "idle",
    "image-picker", "indicators", "keyboard-layout", "lock", "media", "menu",
    "microphone", "monitor", "network", "nightlight", "notifications", "osd",
    "polkit", "power", "reminders", "spacer", "speedtest", "system-update",
    "tailscale", "tray", "weather", "wifiqr", "workspaces",
)

_PROTECTED = re.compile(
    r"https?://[^\s\"'`)<>\]]*"                   # any URL
    r"|[\w.-]*\bomarchy\.org\b"                     # bare upstream domains
    r"|basecamp/omarchy",
    re.IGNORECASE,
)
_PLUGIN_ID = re.compile(
    r"(?<![\w.])omarchy\.(" + "|".join(sorted(map(re.escape, BUILTIN_PLUGINS), key=len, reverse=True)) + r")(?![\w-])"
)
# The reserved prefix itself ("omarchy." + id, `omarchy.*`, "omarchy.$service").
_NAMESPACE = re.compile(r"(?<![\w.])omarchy\.(?=[\"'`*$])")
_UPPER = re.compile(r"OMARCHY")
# Inside identifiers, and before an uppercase letter (QML types like OmarchyLogo).
_TITLE_IN_WORD = re.compile(r"(?<=[A-Za-z0-9_])Omarchy|Omarchy(?=[A-Z])")
_TITLE = re.compile(r"Omarchy")
_LOWER = re.compile(r"omarchy")
# qs.Commons.Color members (Color.bar, Color.accent, Color.qml): not Qt.Color, MyColor.x.
_COLOR_SINGLETON = re.compile(r"(?<![\w.])Color(?=\.\w)")
_COLOR_QMLDIR = re.compile(r"^singleton Color ", re.MULTILINE)
# `import qs.Commons as Commons` reaches the singleton as Commons.Color (also in
# QML that a plugin builds from strings, like lock-explorer's Designer.js).
_COMMONS_ALIAS = re.compile(r"\bimport\s+qs\.Commons\s+as\s+(\w+)")
QML_SUFFIXES = (".qml", ".js")


def rename_text(text: str) -> str:
    kept: list[str] = []

    def keep(match: re.Match[str]) -> str:
        if "omarchy" not in match.group(0).lower():
            return match.group(0)
        kept.append(match.group(0))
        return f"\0{len(kept) - 1}\0"

    text = _PROTECTED.sub(keep, text)
    text = _PLUGIN_ID.sub(lambda m: f"{BUILTIN_NAMESPACE}.{m.group(1)}", text)
    text = _NAMESPACE.sub(f"{BUILTIN_NAMESPACE}.", text)
    text = _UPPER.sub(NAME.upper(), text)
    text = _TITLE_IN_WORD.sub(NAME.capitalize(), text)
    text = _TITLE.sub(NAME, text)
    text = _LOWER.sub(NAME, text)
    return re.sub(r"\0(\d+)\0", lambda m: kept[int(m.group(1))], text)


def is_qml(name: str, text: str = "") -> bool:
    """QML sources, plus scripts that write shell QML (they import qs.Commons)."""
    return name.endswith(QML_SUFFIXES) or name == "qmldir" or "qs.Commons" in text


def rename_qml(text: str) -> str:
    text = _COLOR_SINGLETON.sub("Colors", text)
    for alias in set(_COMMONS_ALIAS.findall(text)):
        text = re.sub(rf"(?<![\w.]){re.escape(alias)}\.Color(?=\.\w)", f"{alias}.Colors", text)
    return _COLOR_QMLDIR.sub("singleton Colors ", text)


def rename_name(name: str) -> str:
    """A file or directory name (no URLs or plugin ids in paths)."""
    if name == "Color.qml":
        return "Colors.qml"
    name = _UPPER.sub(NAME.upper(), name)
    name = _TITLE_IN_WORD.sub(NAME.capitalize(), name)
    name = _TITLE.sub(NAME, name)
    return _LOWER.sub(NAME, name)


def leftovers(text: str) -> list[str]:
    """Mentions that survived rename_text other than the protected ones."""
    stripped = _PROTECTED.sub("", text)
    return re.findall(r"(?i)[\w./-]*omarchy[\w./-]*", stripped)
