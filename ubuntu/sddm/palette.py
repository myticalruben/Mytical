#!/usr/bin/env python3
"""Pinta el tema SDDM con la paleta neon de Waybar.

En modo ``adaptive`` (por defecto) recibe la paleta generada por
waybar/scripts/palette.py y reemplaza solo las claves de color del archivo de
configuracion del tema, sin tocar el layout. En modo ``neon`` usa los colores
de marca fijos y no lee la paleta ni, por tanto, el wallpaper.
"""

import argparse
import os
import re
import sys

# Copia de FALLBACK en waybar/scripts/palette.py. No se importa porque el tema
# se instala solo en /usr/share/sddm/themes/mytical.
BRAND = {
    "neon_solid": "#05080f",
    "neon_accent1": "#00f0ff",
    "neon_accent2": "#ff2bd6",
    "neon_text": "#d9fbff",
    "neon_power": "#ff4d6d",
}
MODES = ("adaptive", "neon")


def parse(path):
    colors = dict(BRAND)
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return colors
    for name, value in re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;", text):
        colors[name] = value
    return colors


def rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def hexc(values):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in values)


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def lighten(value, t):
    return hexc(mix(rgb(value), (255, 255, 255), t))


def darken(value, t):
    return hexc(mix(rgb(value), (0, 0, 0), t))


def build(colors):
    solid = colors["neon_solid"]
    accent1 = colors["neon_accent1"]
    accent2 = colors["neon_accent2"]
    text = lighten(colors["neon_text"], 0.28)
    power = colors["neon_power"]

    field = lighten(solid, 0.10)
    field_bg = mix(rgb(solid), rgb(accent1), 0.06)
    highlighted = mix(rgb(solid), rgb(accent1), 0.22)
    button = mix(rgb(solid), rgb(accent2), 0.22)

    return {
        "HeaderTextColor": text,
        "DateTextColor": accent1,
        "TimeTextColor": text,
        "FormBackgroundColor": hexc(mix(rgb(solid), (255, 255, 255), 0.05)),
        "BackgroundColor": solid,
        "DimBackgroundColor": darken(solid, 0.25),
        "LoginFieldBackgroundColor": hexc(field_bg),
        "PasswordFieldBackgroundColor": hexc(field_bg),
        "LoginFieldTextColor": text,
        "PasswordFieldTextColor": text,
        "UserIconColor": accent1,
        "PasswordIconColor": accent2,
        "PlaceholderTextColor": hexc(mix(rgb(text), rgb(solid), 0.55)),
        "WarningColor": power,
        "LoginButtonTextColor": text,
        "LoginButtonBackgroundColor": hexc(button),
        "SystemButtonsIconsColor": accent1,
        "SessionButtonTextColor": accent1,
        "VirtualKeyboardButtonTextColor": accent1,
        "DropdownTextColor": text,
        "DropdownSelectedBackgroundColor": hexc(highlighted),
        "DropdownBackgroundColor": field,
        "HighlightTextColor": text,
        "HighlightBackgroundColor": hexc(highlighted),
        "HighlightBorderColor": accent1,
        "HoverUserIconColor": accent2,
        "HoverPasswordIconColor": accent1,
        "HoverSystemButtonsIconsColor": accent2,
        "HoverSessionButtonTextColor": accent2,
        "HoverVirtualKeyboardButtonTextColor": accent2,
    }


def apply(config_path, values):
    try:
        with open(config_path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        raise SystemExit("no se puede leer %s" % config_path)

    out = []
    seen = set()
    for line in lines:
        m = re.match(r'^([A-Za-z0-9_]+)="[^"]*"$', line)
        if m and m.group(1) in values:
            key = m.group(1)
            out.append('%s="%s"' % (key, values[key]))
            seen.add(key)
        else:
            out.append(line)

    with open(config_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    missing = sorted(set(values) - seen)
    if missing:
        print("no encontre claves:", ", ".join(missing), file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Aplica una paleta neon al tema SDDM de Mytical.",
        epilog="adaptive (por defecto) sigue la paleta de Waybar; neon usa "
               "los colores de marca sin leer el wallpaper.",
    )
    parser.add_argument("--mode", metavar="MODO", help="adaptive (por defecto) o neon")
    parser.add_argument("palette", nargs="?", default="", metavar="PALETA")
    parser.add_argument("config", nargs="?", default="", metavar="CONFIG")
    args = parser.parse_args()

    mode = args.mode or os.environ.get("MYTICAL_SDDM_MODE", "").strip() or "adaptive"
    if mode not in MODES:
        parser.error("modo invalido: %s (usa adaptive o neon)" % mode)
    if not args.config:
        parser.error("uso: palette.py [--mode adaptive|neon] PALETA CONFIG")

    colors = dict(BRAND) if mode == "neon" else parse(args.palette)
    apply(args.config, build(colors))


if __name__ == "__main__":
    main()
