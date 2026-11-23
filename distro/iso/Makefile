# Esqueleto de la ISO V1.1 de Mytical (remaster casper + Calamares).
#
# Uso:
#   make check ISO=/ruta/ubuntu-26.04-desktop-amd64.iso
#   make build ISO=/ruta/ubuntu-26.04-desktop-amd64.iso [REPO=/ruta/repo-apt]
#   make test
#   make clean
#
# `check` y `build` no descargan nada: la ISO oficial y, si se usa, el repo
# APT local se pasan como rutas. `build` se niega a ejecutarse sin ISO.
#
# Requisitos del host: squashfs-tools, xorriso, coreutils y make.
# casper y calamares son paquetes del rootfs de la ISO, no del host.

SHELL := /bin/bash

ISO_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
WORK := $(ISO_DIR)/work
OUT ?= $(WORK)/mytical-26.04-amd64.iso
ISO ?=
REPO ?=

.PHONY: check build clean test help

check:
	@$(ISO_DIR)/remaster.sh --check $(if $(strip $(ISO)),--iso "$(ISO)",)

build:
	@if [ -z "$(strip $(ISO))" ]; then \
		echo "ERROR: falta la ISO de entrada; build no se ejecuta sin ISO." >&2; \
		echo "       make build ISO=/ruta/ubuntu-26.04-desktop-amd64.iso" >&2; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory check ISO="$(ISO)"
	@$(ISO_DIR)/remaster.sh --iso "$(ISO)" --out "$(OUT)" \
		$(if $(strip $(REPO)),--repo "$(REPO)",)

# Solo borra distro/iso/work/. La ISO de entrada y el repo no se tocan.
clean:
	@if [ -z "$(WORK)" ] || [ "$(WORK)" = "/" ]; then \
		echo "ERROR: WORK no es un directorio seguro: '$(WORK)'" >&2; \
		exit 1; \
	fi
	rm -rf -- "$(WORK)"
	@printf 'OK: limpio %s\n' "$(WORK)"

test:
	@bash "$(ISO_DIR)/tests/test_iso_scaffold.sh"

help:
	@printf '%s\n' \
		'Objetivo:' \
		'  check   valida herramientas, ISO de entrada y repo local (sin root)' \
		'  build   remasteriza la ISO (requiere root; hoy se detiene en el TODO)' \
		'  test    tests locales del esqueleto (sin ISO, sin root, sin red)' \
		'  clean   borra solo distro/iso/work/' \
		'' \
		'Variables:' \
		'  ISO    ruta a ubuntu-26.04*-desktop-amd64.iso (obligatoria en check/build)' \
		'  REPO   raiz de un repo APT local con dists/mytical/ (opcional)' \
		'  OUT    ISO de salida (por defecto work/mytical-26.04-amd64.iso)' \
		'' \
		'Ejemplo:' \
		'  make check ISO=$$HOME/isos/ubuntu-26.04-desktop-amd64.iso'
