#!/usr/bin/env python3
"""Tests for the SDDM palette modes.

`adaptive` reads a synthetic Waybar palette and `neon` must use the fixed
brand colours without touching that palette. The synchroniser tests run the
real script against a temporary theme and a fake `getent`, so they never need
root, SDDM or the user's real home.
"""

import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PALETTE_PY = ROOT / "ubuntu" / "sddm" / "palette.py"
SYNC = ROOT / "ubuntu" / "sddm" / "mytical-sddm-sync"

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
CONF_LINE = re.compile(r'^([A-Za-z0-9_]+)="([^"]*)"$')

COLOR_KEYS = (
    "HeaderTextColor",
    "DateTextColor",
    "TimeTextColor",
    "FormBackgroundColor",
    "BackgroundColor",
    "DimBackgroundColor",
    "LoginFieldBackgroundColor",
    "PasswordFieldBackgroundColor",
    "LoginFieldTextColor",
    "PasswordFieldTextColor",
    "UserIconColor",
    "PasswordIconColor",
    "PlaceholderTextColor",
    "WarningColor",
    "LoginButtonTextColor",
    "LoginButtonBackgroundColor",
    "SystemButtonsIconsColor",
    "SessionButtonTextColor",
    "VirtualKeyboardButtonTextColor",
    "DropdownTextColor",
    "DropdownSelectedBackgroundColor",
    "DropdownBackgroundColor",
    "HighlightTextColor",
    "HighlightBackgroundColor",
    "HighlightBorderColor",
    "HoverUserIconColor",
    "HoverPasswordIconColor",
    "HoverSystemButtonsIconsColor",
    "HoverSessionButtonTextColor",
    "HoverVirtualKeyboardButtonTextColor",
)

BRAND = {
    "neon_solid": "#05080f",
    "neon_accent1": "#00f0ff",
    "neon_accent2": "#ff2bd6",
    "neon_text": "#d9fbff",
    "neon_power": "#ff4d6d",
}

PALETTE_A = {
    "neon_solid": "#101820",
    "neon_accent1": "#ff8800",
    "neon_accent2": "#0088ff",
    "neon_text": "#e0e0e0",
    "neon_power": "#ff0044",
}

PALETTE_B = {
    "neon_solid": "#1a0f1f",
    "neon_accent1": "#33ff66",
    "neon_accent2": "#ff33aa",
    "neon_text": "#f0e8ff",
    "neon_power": "#ffaa00",
}


def write_palette(path, colors):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(f"@define-color {name} {value};\n" for name, value in colors.items()),
        encoding="utf-8",
    )
    return path


def write_config(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "[General]",
        'HeaderText="Welcome back"',
        "# this comment and the layout below must survive",
        'Font="Open Sans"',
    ]
    lines.extend(f'{key}="#123456"' for key in COLOR_KEYS)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def parse_config(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = CONF_LINE.match(line)
        if match and match.group(1) in COLOR_KEYS:
            values[match.group(1)] = match.group(2)
    return values


def make_env(extra=None):
    env = os.environ.copy()
    env.pop("MYTICAL_SDDM_MODE", None)
    if extra:
        env.update(extra)
    return env


def run_palette(*args, env_extra=None):
    return subprocess.run(
        [sys.executable, str(PALETTE_PY), *args],
        cwd=ROOT,
        env=make_env(env_extra),
        text=True,
        capture_output=True,
    )


class PaletteModeTest(unittest.TestCase):
    def assert_brand_colours(self, values):
        self.assertEqual(values["BackgroundColor"], BRAND["neon_solid"])
        self.assertEqual(values["DateTextColor"], BRAND["neon_accent1"])
        self.assertEqual(values["UserIconColor"], BRAND["neon_accent1"])
        self.assertEqual(values["PasswordIconColor"], BRAND["neon_accent2"])
        self.assertEqual(values["WarningColor"], BRAND["neon_power"])
        self.assertEqual(values["HoverUserIconColor"], BRAND["neon_accent2"])
        self.assertEqual(values["HoverPasswordIconColor"], BRAND["neon_accent1"])

    def assert_adaptive_colours(self, values, palette):
        self.assertEqual(values["BackgroundColor"], palette["neon_solid"])
        self.assertEqual(values["DateTextColor"], palette["neon_accent1"])
        self.assertEqual(values["PasswordIconColor"], palette["neon_accent2"])
        self.assertEqual(values["WarningColor"], palette["neon_power"])

    def test_default_mode_is_adaptive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette = write_palette(root / "palette.css", PALETTE_A)
            config = write_config(root / "mytical.conf")

            result = run_palette(str(palette), str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            values = parse_config(config)
            self.assert_adaptive_colours(values, PALETTE_A)
            for value in values.values():
                self.assertRegex(value, HEX)

    def test_explicit_adaptive_matches_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette = write_palette(root / "palette.css", PALETTE_A)
            default_config = write_config(root / "default.conf")
            explicit_config = write_config(root / "explicit.conf")

            default = run_palette(str(palette), str(default_config))
            explicit = run_palette("--mode", "adaptive", str(palette), str(explicit_config))

            self.assertEqual(default.returncode, 0, default.stderr)
            self.assertEqual(explicit.returncode, 0, explicit.stderr)
            self.assertEqual(parse_config(default_config), parse_config(explicit_config))

    def test_synthetic_palettes_produce_distinct_adaptive_colours(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette_a = write_palette(root / "a.css", PALETTE_A)
            palette_b = write_palette(root / "b.css", PALETTE_B)
            config_a = write_config(root / "a.conf")
            config_b = write_config(root / "b.conf")

            result_a = run_palette(str(palette_a), str(config_a))
            result_b = run_palette(str(palette_b), str(config_b))

            self.assertEqual(result_a.returncode, 0, result_a.stderr)
            self.assertEqual(result_b.returncode, 0, result_b.stderr)
            values_a = parse_config(config_a)
            values_b = parse_config(config_b)
            self.assert_adaptive_colours(values_a, PALETTE_A)
            self.assert_adaptive_colours(values_b, PALETTE_B)
            self.assertNotEqual(values_a["BackgroundColor"], values_b["BackgroundColor"])
            self.assertNotEqual(values_a["DateTextColor"], values_b["DateTextColor"])

    def test_neon_ignores_the_synthetic_palette(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette = write_palette(root / "palette.css", PALETTE_A)
            config = write_config(root / "mytical.conf")

            result = run_palette("--mode", "neon", str(palette), str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            values = parse_config(config)
            self.assert_brand_colours(values)
            output = config.read_text(encoding="utf-8").lower()
            for stale in PALETTE_A.values():
                self.assertNotIn(stale.lower(), output)

    def test_neon_does_not_need_a_palette_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = write_config(root / "mytical.conf")

            result = run_palette("--mode", "neon", str(root / "missing.css"), str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_brand_colours(parse_config(config))

    def test_neon_can_be_selected_with_the_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette = write_palette(root / "palette.css", PALETTE_A)
            config = write_config(root / "mytical.conf")

            result = run_palette(
                str(palette),
                str(config),
                env_extra={"MYTICAL_SDDM_MODE": "neon"},
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_brand_colours(parse_config(config))

    def test_command_line_mode_overrides_the_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette = write_palette(root / "palette.css", PALETTE_A)
            config = write_config(root / "mytical.conf")

            result = run_palette(
                "--mode",
                "adaptive",
                str(palette),
                str(config),
                env_extra={"MYTICAL_SDDM_MODE": "neon"},
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_adaptive_colours(parse_config(config), PALETTE_A)

    def test_missing_palette_falls_back_to_brand_in_adaptive_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = write_config(root / "mytical.conf")

            result = run_palette(str(root / "does-not-exist.css"), str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_brand_colours(parse_config(config))

    def test_layout_and_comments_are_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            palette = write_palette(root / "palette.css", PALETTE_A)
            config = write_config(root / "mytical.conf")

            result = run_palette(str(palette), str(config))

            self.assertEqual(result.returncode, 0, result.stderr)
            output = config.read_text(encoding="utf-8")
            self.assertIn("[General]", output)
            self.assertIn('HeaderText="Welcome back"', output)
            self.assertIn("# this comment and the layout below must survive", output)
            self.assertIn('Font="Open Sans"', output)

    def test_invalid_mode_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = write_config(root / "mytical.conf")

            result = run_palette("--mode", "rainbow", "", str(config))

            self.assertEqual(result.returncode, 2)
            self.assertIn("modo invalido", result.stderr)
            self.assertEqual(parse_config(config)["BackgroundColor"], "#123456")

    def test_invalid_environment_mode_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = write_config(root / "mytical.conf")

            result = run_palette(str(root / "palette.css"), str(config), env_extra={"MYTICAL_SDDM_MODE": "rainbow"})

            self.assertEqual(result.returncode, 2)
            self.assertIn("modo invalido", result.stderr)


class SyncModeTest(unittest.TestCase):
    def prepare(self, root, config_body=None, palette=PALETTE_A):
        home = root / "home"
        image = home / "Pictures" / "Wallpapers" / "01.png"
        image.parent.mkdir(parents=True)
        image.write_bytes(b"fake png")
        state = home / ".local" / "state" / "hypr" / "wallpaper"
        state.parent.mkdir(parents=True)
        state.write_text(str(image) + "\n", encoding="utf-8")
        write_palette(home / ".cache" / "waybar" / "palette.css", palette)

        theme = root / "theme"
        (theme / "Themes").mkdir(parents=True)
        shutil.copy(PALETTE_PY, theme / "palette.py")
        write_config(theme / "Themes" / "mytical.conf")

        bindir = root / "bin"
        bindir.mkdir()
        getent = bindir / "getent"
        getent.write_text(
            "#!/bin/sh\nprintf 'tester:x:1000:1000::%s:/bin/sh\\n' "
            + shlex.quote(str(home))
            + "\n",
            encoding="utf-8",
        )
        getent.chmod(0o755)

        conf = root / "sddm.conf"
        if config_body is not None:
            conf.write_text(config_body, encoding="utf-8")

        env = make_env(
            {
                "PATH": str(bindir) + os.pathsep + os.environ.get("PATH", ""),
                "MYTICAL_SDDM_THEME": str(theme),
                "MYTICAL_SDDM_CONF": str(conf),
            }
        )
        return {"home": home, "theme": theme, "conf": conf, "env": env}

    def run_sync(self, tree, *args):
        return subprocess.run(
            ["bash", str(SYNC), *args],
            cwd=ROOT,
            env=tree["env"],
            text=True,
            capture_output=True,
        )

    def config_values(self, tree):
        return parse_config(tree["theme"] / "Themes" / "mytical.conf")

    def assert_brand(self, values):
        self.assertEqual(values["BackgroundColor"], BRAND["neon_solid"])
        self.assertEqual(values["DateTextColor"], BRAND["neon_accent1"])
        self.assertEqual(values["PasswordIconColor"], BRAND["neon_accent2"])

    def assert_adaptive(self, values):
        self.assertEqual(values["BackgroundColor"], PALETTE_A["neon_solid"])
        self.assertEqual(values["DateTextColor"], PALETTE_A["neon_accent1"])
        self.assertEqual(values["PasswordIconColor"], PALETTE_A["neon_accent2"])

    def test_help_documents_the_mode_option(self):
        result = subprocess.run(
            ["bash", str(SYNC), "--help"],
            cwd=ROOT,
            env=make_env(),
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--mode adaptive|neon", result.stdout)

    def test_default_mode_is_adaptive(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree = self.prepare(Path(tmp))
            result = self.run_sync(tree, "--user", "tester")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_adaptive(self.config_values(tree))

    def test_mode_neon_is_forwarded_to_palette(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree = self.prepare(Path(tmp))
            result = self.run_sync(tree, "--user", "tester", "--mode", "neon")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_brand(self.config_values(tree))

    def test_config_file_sets_neon(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree = self.prepare(Path(tmp), config_body='# branding fijo\nMODE="neon"  # no seguir el fondo\n')
            result = self.run_sync(tree, "--user", "tester")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_brand(self.config_values(tree))

    def test_environment_overrides_the_config_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree = self.prepare(Path(tmp), config_body="MODE=neon\n")
            tree["env"]["MYTICAL_SDDM_MODE"] = "adaptive"
            result = self.run_sync(tree, "--user", "tester")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_adaptive(self.config_values(tree))

    def test_command_line_overrides_the_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree = self.prepare(Path(tmp))
            tree["env"]["MYTICAL_SDDM_MODE"] = "neon"
            result = self.run_sync(tree, "--user", "tester", "--mode", "adaptive")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_adaptive(self.config_values(tree))

    def test_invalid_mode_is_rejected_before_touching_the_theme(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree = self.prepare(Path(tmp))
            result = self.run_sync(tree, "--mode", "rainbow")

            self.assertEqual(result.returncode, 2)
            self.assertIn("modo invalido", result.stderr)
            self.assertFalse(tree["theme"].joinpath("Backgrounds").exists())


if __name__ == "__main__":
    unittest.main()
