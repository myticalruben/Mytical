# ISO V1.1 — esqueleto de remaster

Remaster reproducible de la ISO oficial de **Ubuntu 26.04 LTS (resolute)**
con **casper** + **Calamares**, APT como dueño del escritorio y Nix fuera de
la imagen. Esta carpeta es un **esqueleto**: valida, planifica y prueba, pero
todavía **no construye** la ISO (ver [Estado](#estado)).

## Estado

| Pieza | Estado |
|---|---|
| `Makefile` (`check`, `build`, `clean`, `test`) | listo |
| `remaster.sh` (`--iso`, `--out`, `--dry-run`, `--repo`) | listo para validar/planificar |
| Chroot APT, branding y metadatos de casper | **TODO** (el build real aborta a propósito) |
| `package-lists/mytical.list` | base APT, sin GNOME/GDM/ubuntu-session |
| `calamares/settings.conf` + `branding/` | mínimos, solo texto |
| `tests/test_iso_scaffold.sh` | sin ISO, sin root, sin red |

El build real se detiene en `assert_implemented()` **antes de escribir nada**
en `work/`. No hay riesgo de dejar un chroot a medias mientras falten piezas.

## Requisitos

### Host de build

| Dependencia | Para qué | Instalación |
|---|---|---|
| `squashfs-tools` | `mksquashfs` / `unsquashfs` | `sudo apt install squashfs-tools` |
| `xorriso` | extraer y remontar la ISO | `sudo apt install xorriso` |
| `coreutils`, `make`, `bash` | checksums, targets, script | base del sistema |
| root | montar el chroot y preservar permisos | `sudo make ...` |

```bash
sudo apt install squashfs-tools xorriso make
```

Además: ~20–30 GiB libres en `distro/iso/work/`, 4 GiB de RAM y una ISO de
entrada ya descargada y verificada.

### ISO oficial de entrada

- Ubuntu **26.04 LTS desktop amd64** (`resolute`).
- Nombre esperado: `ubuntu-26.04-desktop-amd64.iso` (también se acepta
  `ubuntu-26.04.1-desktop-amd64.iso`).
- Origen: <https://releases.ubuntu.com/26.04/> — **no** imágenes daily,
  minimal, ports ni servidor.
- Verificar antes de usarla:

```bash
sha256sum -c SHA256SUMS --ignore-missing
gpg --verify SHA256SUMS.gpg SHA256SUMS
```

El script no descarga nada: la ruta se pasa con `ISO=` o `--iso`.

### Dependencias dentro de la ISO

`casper` y `calamares` **no son herramientas del host**: son paquetes que se
instalan en el rootfs del remaster. Se declaran en
`package-lists/mytical.list` para que el build falle explícitamente si el
archive de Ubuntu 26.04 no los trae.

| Dependencia | Dónde vive | Uso |
|---|---|---|
| `squashfs-tools` | host | comprimir/descomprimir el rootfs |
| `xorriso` | host | extraer la ISO y reemplazar el squashfs |
| `casper` | rootfs de la ISO | arranque live, usuario live, `filesystem.squashfs` |
| `calamares` | rootfs de la ISO | instalador gráfico |

`make check` comprueba las dos primeras en el host y que la ISO traiga
`/casper/`; el build debe comprobar las dos últimas dentro del chroot.

## Flujo de remaster

```bash
# 1. Validar herramientas, ISO, /casper y repo local (sin root, no escribe)
make -C distro/iso check ISO=/ruta/ubuntu-26.04-desktop-amd64.iso

# 2. Ver el plan completo sin tocar nada
distro/iso/remaster.sh --dry-run \
    --iso /ruta/ubuntu-26.04-desktop-amd64.iso \
    --repo /ruta/distro/apt/public

# 3. Construir (hoy aborta en el gate TODO)
sudo make -C distro/iso build ISO=/ruta/ubuntu-26.04-desktop-amd64.iso \
    REPO=/ruta/distro/apt/public

# 4. Tests locales del esqueleto
make -C distro/iso test

# 5. Limpiar solo work/
make -C distro/iso clean
```

El repo local es opcional, pero sin `REPO` no se instalan
`mytical-session`, `mytical-desktop`, `mytical-welcome` ni el tema SDDM.
Se genera con `make -C distro/apt repo` (ver `distro/apt/README.md`).

Pipeline previsto:

1. validar ISO, `/casper`, herramientas y repo;
2. extraer la ISO con `xorriso -osirrox` en `work/iso/`;
3. extraer `casper/filesystem.squashfs` en `work/rootfs/`;
4. copiar el repo local a `/opt/mytical/apt` del rootfs;
5. **chroot APT**: instalar `package-lists/mytical.list` con
   `--no-install-recommends` y verificar que no entra GNOME;
6. copiar Calamares a `/etc/calamares` y el branding a
   `/usr/share/calamares/branding/mytical`;
7. aplicar tema SDDM, wallpapers y avisos de licencia;
8. verificar que **no existe `/nix`**;
9. recomprimir con `mksquashfs -comp xz`;
10. remontar la ISO con `xorriso -boot_image any keep`, reemplazando solo
    `/casper/filesystem.squashfs` y `/casper/filesystem.size`;
11. escribir `mytical-26.04-amd64.iso.sha256`.

La ISO de salida por defecto es `distro/iso/work/mytical-26.04-amd64.iso`;
`OUT=` la cambia.

## Estructura

```text
distro/iso/
├── Makefile
├── README.md
├── remaster.sh
├── package-lists/
│   └── mytical.list
├── calamares/
│   ├── settings.conf
│   └── branding/mytical/
│       ├── branding.desc
│       └── README.md
├── tests/
│   └── test_iso_scaffold.sh
└── work/                 # generado, ignorado por git
```

## Tamaño esperado

| Artefacto | Tamaño orientativo |
|---|---|
| ISO oficial de entrada | ~6 GiB |
| `work/` durante el build | 20–30 GiB |
| `filesystem.squashfs` final | 4,5–6 GiB |
| ISO final | 6–8 GiB |
| Presupuesto de aceptación | **≤ 8 GiB** |

El cierre Nix de la Preview (~3,8 GiB) **no** se suma porque no entra en la
imagen. Si la ISO supera 8 GiB, revisar el contenido antes de publicar:
`unsquashfs -ll`, `du -xhd1 work/rootfs`, y paquetes recomendados por APT.

## No hornear `/nix`

Regla dura de la V1.1:

- no copiar `/nix` al rootfs ni montarlo en el chroot;
- no ejecutar `nix` dentro del chroot;
- no incluir el cierre Nix, perfiles ni `/nix/store`;
- Nix sigue siendo opcional y se instala **después** del primer arranque.

Verificación obligatoria antes de recomprimir:

```bash
test ! -e work/rootfs/nix
unsquashfs -ll work/filesystem.squashfs | grep -E '(^|/)nix(/|$)' && echo "FALLO: /nix en la ISO"
```

`make check` y los tests rechazan `/nix` en la lista; el build lo comprueba
en el rootfs antes de empaquetar.

## Secure Boot

El remux reutiliza **tal cual** el shim, GRUB, el kernel y el initramfs de
Ubuntu: solo se sustituyen el squashfs y `filesystem.size`. No se re-firman
binarios EFI ni se toca la cadena de arranque.

- Probar UEFI **y** BIOS en QEMU antes de publicar.
- Con Secure Boot activo, los módulos fuera de árbol (NVIDIA, etc.) necesitan
  firma/MOK; documentarlo como bloqueante de hardware.
- No cambiar `-volid` ni las opciones de arranque sin volver a probar ambos
  modos.

## Bloqueantes

Resumen; detalle y criterios en [`docs/distro/ISO.md`](../../docs/distro/ISO.md):

- **B1** chroot APT, hooks de branding y `.conf` de los módulos de Calamares.
- **B2** Secure Boot y módulos de terceros sin firmar.
- **B3** assets: logo, wallpaper, avisos GPL/OFL y manifiesto de licencias.
- **B4** tamaño final > 8 GiB.
- **B5** disponibilidad de Hyprland 0.56, Quickshell y `awww` en APT.

## Tests

```bash
make -C distro/iso test
```

No requieren ISO, root, red ni herramientas de squashfs/xorriso. Validan
sintaxis, flags, targets, fallo de `build` sin ISO, ausencia de `/nix` y de
GNOME en la lista, forma de `settings.conf`/`branding.desc`, limpieza acotada
a `work/` y la documentación. Si hay `shellcheck`, lo ejecutan.

## Referencias

- [`docs/distro/ISO.md`](../../docs/distro/ISO.md) — alcance, decisiones, bloqueantes y aceptación.
- [`docs/superpowers/plans/2026-11-12-mytical-distro-v1.md`](../../docs/superpowers/plans/2026-11-12-mytical-distro-v1.md) — Task 9/10.
- [`docs/adr/0001-overlay-first.md`](../../docs/adr/0001-overlay-first.md), [`0002`](../../docs/adr/0002-apt-owned-desktop.md), [`0006`](../../docs/adr/0006-single-session.md).
- [`docs/distro/ASSET-LICENSES.md`](../../docs/distro/ASSET-LICENSES.md) — bloqueo legal de assets.
