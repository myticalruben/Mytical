# ISO V1.1 — alcance, decisiones y criterios

**Estado:** esqueleto reproducible en `distro/iso/`; el build real está
bloqueado a propósito. No se ha descargado ninguna ISO, no se ha ejecutado
root y no se ha construido ni publicado nada.

**Objetivo:** remasterizar la ISO oficial de Ubuntu 26.04 LTS (resolute) con
casper + Calamares, APT como dueño del escritorio y Nix fuera de la imagen.

## 1. Alcance

Entra en V1.1:

- ISO live x86_64 que arranca en UEFI y BIOS y llega a SDDM con una única
  sesión `mytical.desktop`.
- Instalador Calamares que copia el sistema a disco y deja el equipo
  arrancable, con SDDM y la misma sesión.
- Rootfs construido desde la ISO oficial + repo APT local de Mytical.
- Sin GNOME Shell, GDM, `ubuntu-session` ni `ubuntu-desktop`.
- Sin `/nix` en el squashfs; Nix queda como instalación opcional posterior.
- Checksums de la ISO y publicación firmada cuando se cierren los bloqueantes.

No entra en V1.1:

- descargar o construir la ISO en CI (el runner necesita KVM y ~25 GiB);
- autoinstall/OEM, arm64, persistencia, cifrado de disco o arranque dual
  automatizado;
- una ISO con NVIDIA propietario preinstalado;
- Jarvis, tienda de apps o actualizador propio;
- arte de marca nuevo (solo se reutiliza el que tenga licencia cerrada).

## 2. Decisiones

| ID | Decisión | Motivo |
|---|---|---|
| D1 | Remaster de la ISO oficial de Ubuntu 26.04, no live-build desde cero | Reutiliza kernel, firmware, casper, shim, GRUB y el soporte de hardware ya probado por Ubuntu; menos superficie de fallo |
| D2 | casper como sistema live | Es el mecanismo nativo de Ubuntu; conserva el arranque y el usuario live |
| D3 | Calamares como instalador | Encaja con el plan V1.1 y evita Ubiquity; configuración y branding propios |
| D4 | APT es dueño del escritorio en la ISO (ADR 0002) | La ISO debe arrancar sin Nix; el cierre Nix (~3,8 GiB) no cabe ni es necesario |
| D5 | SDDM + sesión única `mytical.desktop` (ADR 0006) | Evita depender de `~/.nix-profile` y sesiones GNOME/Ubuntu duplicadas |
| D6 | Sin GNOME Shell, GDM ni `ubuntu-session` | Identidad y peso; el escritorio es Hyprland |
| D7 | Remux con `xorriso -boot_image any keep` | Sustituye solo squashfs/tamaño y conserva shim, GRUB y kernel firmados de Ubuntu (Secure Boot) |
| D8 | Lista APT + repo local opcional `--repo` | Los paquetes `mytical-*` no están en el archive; el repo local los aporta y se puede firmar |
| D9 | Branding de Calamares solo texto hasta cerrar assets | No distribuir logos/wallpapers sin licencia ni meter binarios en el esqueleto |
| D10 | Salida en `distro/iso/work/`; `clean` solo borra ese directorio | Evita borrar la ISO de entrada, el repo o `distro/build` por error |

## 3. Pipeline previsto

```text
ISO oficial (ubuntu-26.04-desktop-amd64.iso)
  │  xorriso -osirrox -extract /
  ▼
work/iso/  ── casper/filesystem.squashfs ── unsquashfs ──▶ work/rootfs/
  │                                                           │
  │                                        repo local ────────┤
  │                                        chroot APT ────────┤  [TODO]
  │                                        Calamares ─────────┤
  │                                        branding ──────────┘  [TODO]
  │                                                           │
  │                                             mksquashfs -comp xz
  │                                                           ▼
  └── xorriso -indev ... -outdev ... -boot_image any keep ── work/filesystem.squashfs
          -map filesystem.squashfs /casper/filesystem.squashfs
          -map filesystem.size     /casper/filesystem.size
                                                               │
                                                               ▼
                                        work/mytical-26.04-amd64.iso + .sha256
```

El gate `assert_implemented()` aborta antes de crear `work/` mientras falten
el chroot, el branding y los módulos de Calamares.

## 4. Estado actual

| Archivo | Contenido |
|---|---|
| `distro/iso/README.md` | requisitos, ISO oficial, dependencias, flujo, tamaño y regla de `/nix` |
| `distro/iso/Makefile` | `check`, `build`, `clean`, `test`; `build` exige `ISO=` |
| `distro/iso/remaster.sh` | flags, validaciones, plan y estructura del pipeline |
| `distro/iso/package-lists/mytical.list` | base APT sin GNOME |
| `distro/iso/calamares/settings.conf` | secuencia mínima de Calamares |
| `distro/iso/calamares/branding/mytical/branding.desc` | marca textual, sin imágenes |
| `distro/iso/tests/test_iso_scaffold.sh` | tests locales sin ISO/root/red |

Verificado localmente: `make -C distro/iso test` pasa; `make build` sin ISO
falla con un mensaje accionable y no crea `work/`; la lista no contiene
`/nix`, `ubuntu-session`, `gdm3` ni `gnome-shell`.

## 5. Bloqueantes

### B1 — Integración casper + Calamares

`casper` y `calamares` están declarados en la lista, pero el build todavía no
instala nada en el chroot. Faltan:

- `install_mytical_packages()`: montar `/proc`, `/sys` y `/dev`, configurar el
  repo local con `signed-by`, `apt-get update` e instalar con
  `--no-install-recommends`; comprobar después que no entró GNOME.
- `calamares/modules/`: `unpackfs.conf` (origen
  `/cdrom/casper/filesystem.squashfs`), `partition.conf`, `bootloader.conf`,
  `users.conf`, `displaymanager.conf`, `locale.conf`, `services.conf` y los
  hooks de post-instalación.
- `update_casper_metadata()`: regenerar `filesystem.manifest`,
  `filesystem.size` y `md5sum.txt`; el remux actual no actualiza `md5sum.txt`,
  así que la comprobación de disco de casper fallaría.
- Lanzador de Calamares en el live (`.desktop` + autostart) y usuario live.

**Cierre:** un build con `ISO=` y `REPO=` llega al final; Calamares instala
en QEMU con disco virtio; el sistema instalado arranca.

### B2 — Secure Boot

El remux conserva shim/GRUB/kernel firmados de Ubuntu y no toca binarios EFI.
Riesgos pendientes:

- módulos fuera de árbol (NVIDIA, VirtualBox) sin firma: Secure Boot los
  bloquea; hacen falta MOK o una ISO aparte;
- Calamares reinstala GRUB en el disco: debe usar el shim firmado y no romper
  la cadena;
- probar con OVMF + Secure Boot activado y desactivado, y con `mokutil
  --sb-state`.

**Cierre:** la ISO arranca en UEFI con Secure Boot y en BIOS; el sistema
instalado también; limitaciones de módulos documentadas.

### B3 — Assets y licencias

La auditoría [`ASSET-LICENSES.md`](ASSET-LICENSES.md) bloquea la publicación:

- 22 wallpapers personales fuera del repo/ISO; solo los 4 CC0 de
  `distro/branding/wallpapers/`;
- el tema SDDM es GPL-3.0: deben viajar `LICENSE`, cabeceras y fuente;
- faltan logo, icono y pantalla de bienvenida de Calamares con licencia;
- el manifiesto de assets debe listar ruta, autor, licencia, URL y SHA-256.

**Cierre:** checklist de `ASSET-LICENSES.md` completo; `branding.desc` puede
declarar `images:`/`slideshow:` sin archivos inexistentes.

### B4 — Tamaño

Presupuesto: **≤ 8 GiB** de ISO final. La oficial ronda 6 GiB y el rootfs
crece con Calamares, Hyprland, Waybar, kitty y fuentes. El cierre Nix no se
suma porque no entra. Si se supera el presupuesto, medir con
`du -xhd1 work/rootfs` y `unsquashfs -ll` antes de recortar a ciegas.

**Cierre:** ISO final ≤ 8 GiB y arranque/instalación comprobados con ese
tamaño.

### B5 — Disponibilidad de paquetes

- Ubuntu 26.04 trae Hyprland 0.53; la configuración actual usa 0.56. Si no
  hay compatibilidad, Mytical debe empaquetar 0.56 en su repo (ADR 0002).
- `quickshell` y `awww` no están confirmados en el archive; están comentados
  en la lista hasta decidir si se empaquetan o se sustituyen.
- `calamares` debe existir en universe para 26.04; si no, hay que vendorizarlo.

**Cierre:** `apt-get install --dry-run` resuelve toda la lista en el chroot
sin paquetes inventados.

### B6 — Firma y publicación

La ISO debe publicarse con SHA-256 y firma GPG de release, junto al aviso de
marca. El esqueleto solo genera `.sha256`; la firma y la subida quedan fuera
hasta cerrar B1–B5. No anunciar la ISO mientras `distro/iso/` no produzca un
artefacto reproducible y probado.

**Cierre:** `SHA256SUMS`, `.sig` verificada con la clave pública de release y
notas de release sin promesas que la ISO no cumpla.

### B7 — Pruebas de arranque e instalación

No hay test de QEMU todavía. Hace falta:

- arranque UEFI y BIOS de la ISO live hasta SDDM;
- login en Hyprland sin red y sin `/nix`;
- instalación Calamares con disco virtio y arranque del disco;
- comprobación de sesión única y ausencia de GNOME/GDM.

**Cierre:** script de QEMU reproducible (KVM) y evidencia adjunta al release.

### B8 — Reproducibilidad byte a byte (P2)

`mksquashfs` y `xorriso` pueden meter timestamps, orden de archivos y
metadatos variables. Para que dos builds den el mismo SHA-256 hace falta fijar
`SOURCE_DATE_EPOCH`, ordenar el árbol y revisar xattrs/ids. No es bloqueante
para V1.1, pero sí para llamar “reproducible” a la ISO en sentido estricto.

## 6. Criterios de aceptación

| ID | Criterio | Estado |
|---|---|---|
| AC1 | `make -C distro/iso check ISO=<oficial>` sale 0 con `squashfs-tools` y `xorriso` instalados | pendiente de ISO |
| AC2 | `make -C distro/iso test` sale 0 sin ISO, root, red ni herramientas | **cumple** |
| AC3 | `make -C distro/iso build` sin `ISO=` sale distinto de 0 y no crea `work/` | **cumple** |
| AC4 | `make build ISO=... REPO=...` genera `work/mytical-26.04-amd64.iso` y `.sha256` verificable | pendiente (B1) |
| AC5 | La ISO arranca en UEFI y BIOS y llega a SDDM | pendiente (B1/B7) |
| AC6 | La única sesión es `mytical.desktop`; no hay `gdm3`, `ubuntu-session` ni `gnome-shell` | pendiente de build |
| AC7 | El rootfs y el squashfs no contienen `/nix` | pendiente de build |
| AC8 | El live llega a Hyprland sin red y sin Nix | pendiente (B1/B5) |
| AC9 | Calamares instala en disco virtio y el sistema instalado arranca con SDDM | pendiente (B1/B7) |
| AC10 | Assets con licencia, avisos y manifiesto incluidos; sin arte P0 | pendiente (B3) |
| AC11 | ISO ≤ 8 GiB y checksum/firma publicados | pendiente (B4/B6) |
| AC12 | README/ISO.md describen el comando exacto y las limitaciones | **cumple** |

## 7. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| APT arrastra recommends de GNOME | ISO más grande y sesiones duplicadas | `--no-install-recommends`, lista explícita y test que falla si aparece GNOME |
| `xorriso -map` deja `md5sum.txt` obsoleto | “Check disc” falla; no afecta al arranque normal | regenerar `md5sum.txt` antes del remux (B1) |
| Calamares sin `.conf` de módulos | instalador aborta a mitad | no publicar hasta completar B1; probar en QEMU |
| Secure Boot + NVIDIA | pantalla negra o módulo rechazado | MOK documentado; ISO NVIDIA aparte |
| Root mal escrito en `remaster.sh` | borrar `work/` o el repo equivocado | `WORK_DIR` fijo, guardas de ruta y `clean` acotado |
| La ISO oficial cambia (26.04.1/2) | checksums y rutas distintas | validar nombre + `/casper`; fijar SHA-256 en las notas |
| Build no determinista | dos builds con SHA distinto | B8: `SOURCE_DATE_EPOCH`, orden y metadatos |
| Marca “Mytical” sin verificar | conflicto de marca | búsqueda de anterioridad antes de publicar |

## 8. Próximos pasos

1. Implementar `install_mytical_packages()` y `update_casper_metadata()`.
2. Añadir `calamares/modules/` y un `.desktop` de instalación para el live.
3. Construir una ISO de prueba y arrancarla en QEMU UEFI/BIOS.
4. Cerrar assets (B3) y decidir Hyprland/Quickshell (B5).
5. Medir tamaño y, si hace falta, recortar antes de firmar (B4/B6).
6. Escribir el test de arranque/instalación (B7) y adjuntar evidencia.

## 9. Referencias

- [`distro/iso/README.md`](../../distro/iso/README.md)
- [`docs/distro/ASSET-LICENSES.md`](ASSET-LICENSES.md)
- [`docs/distro/RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md)
- [`docs/adr/0001-overlay-first.md`](../adr/0001-overlay-first.md)
- [`docs/adr/0002-apt-owned-desktop.md`](../adr/0002-apt-owned-desktop.md)
- [`docs/adr/0006-single-session.md`](../adr/0006-single-session.md)
- Plan V1: [`docs/superpowers/plans/2026-11-12-mytical-distro-v1.md`](../superpowers/plans/2026-11-12-mytical-distro-v1.md), tareas 9 y 10.
