#!/usr/bin/env python3
"""Comprueba que ningún paquete/binario pertenezca a APT y Nix a la vez."""

import argparse
import json
import sys
from pathlib import Path


def load(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("la raíz debe ser un objeto JSON")
    return {k: set(v) for k, v in data.items() if isinstance(v, list)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", nargs="?", const="distro/ownership.json")
    args = parser.parse_args()
    path = args.check or "distro/ownership.json"
    try:
        data = load(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    apt = data.get("apt", set())
    nix = data.get("nix", set())
    overlap = sorted(apt & nix)
    if overlap:
        for name in overlap:
            print(f"solapamiento: {name}", file=sys.stderr)
        return 1
    print("OK: 0 solapamientos")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
