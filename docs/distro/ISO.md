# ISO V1.1 — alcance, decisiones y criterios

**Estado:** pipeline implementado en `distro/iso/` y cubierto por tests
locales, con detección de los dos layouts de casper (26.04 y anteriores). No se
ha descargado ninguna ISO, no se ha ejecutado root, no se ha ejecutado
`mksquashfs`/`xorriso` de verdad y no se ha construido ni publicado nada. El
build real sigue pendiente de validación con ISO y QEMU.

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
| D7 | Remux con `xorriso -boot_image any keep` | Sustituye solo squashfs/tamaño/manifiesto/`md5sum.txt` y conserva shim, GRUB y kernel firmados de Ubuntu (Secure Boot) |
| D8 | Lista APT + repo local firmado `--repo` | Los paquetes `mytical-*` no están en el archive; el repo local los aporta y el build exige su clave para `Signed-By` |
| D9 | Branding de Calamares solo texto hasta cerrar assets | No distribuir logos/wallpapers sin licencia ni meter binarios en la imagen |
| D10 | Salida en `distro/iso/work/`; `clean` solo borra ese directorio | Evita borrar la ISO de entrada, el repo o `distro/build` por error |

## 3. Pipeline implementado

```text
ISO oficial (ubuntu-26.04-desktop-amd64.iso)
  │  xorriso -osirrox -extract /
  ▼
work/iso/casper/<SQUASHFS_NAME>     (minimal.standard.squashfs | filesystem.squashfs)
  │  unsquashfs                                    ┌── repo local
  ▼                                                ├── chroot APT
work/rootfs/  ─────────────────────────────────────├── Calamares
  │                                                └── branding
  │  mksquashfs -comp xz
  ▼
work/rootfs.squashfs ──▶ update_casper_metadata:
                            <base>.size + <base>.manifest
                            install-sources.yaml (entrada standard)
                            md5sum.txt
  │
  └── xorriso -indev ... -outdev ... -boot_image any keep
          -map work/iso/casper/<SQUASHFS_NAME>   /casper/<SQUASHFS_NAME>
          -map work/iso/casper/<base>.size       /casper/<base>.size
          -map work/iso/casper/<base>.manifest   /casper/<base>.manifest
          -map work/iso/casper/install-sources.yaml /casper/install-sources.yaml
          -map work/iso/md5sum.txt               /md5sum.txt
                                                          │
                                                          ▼
                                   work/mytical-26.04-amd64.iso + .sha256
```

`<base>` es `minimal.standard` o `filesystem`, derivado del squashfs elegido
(`$SQUASHFS_BASE`). El gate `assert_implemented()` ya no bloquea el build:
comprueba que existan las funciones y los `.conf` de Calamares antes de crear
`work/`. El build real exige root y `--repo`.

### 3.1 Layout de casper: `minimal.standard` vs `filesystem`

La ISO oficial de Ubuntu 26.04 no publica `/casper/filesystem.squashfs`. Su
layout es:

| Archivo | Contenido |
|---|---|
| `/casper/minimal.standard.squashfs` | rootfs real (~4,9 GB) |
| `/casper/minimal.standard.size` | tamaño del rootfs sin comprimir |
| `/casper/minimal.standard.manifest` | paquetes del rootfs |
| `/casper/install-sources.yaml` | fuentes que ofrece el instalador (`path: minimal.standard.squashfs`, `size: 4911607808`) |
| `/casper/minimal.standard.<idioma>.*` | variantes de idioma y `enhanced` |

Las ISO anteriores (24.04 y previas) usan `filesystem.squashfs`,
`filesystem.size` y `filesystem.manifest`, sin `install-sources.yaml`.

`remaster.sh` resuelve el layout una sola vez y guarda el nombre:

- `SQUASHFS_CANDIDATES=(minimal.standard.squashfs filesystem.squashfs)`; se
  prefiere `minimal.standard.squashfs` si existen los dos.
- `resolve_squashfs_from_listing()` decide con el listado de
  `xorriso -find /casper` (lo usa `--check`/`--dry-run`); si no hay ninguno de
  los dos, el script aborta con un mensaje accionable.
- `resolve_squashfs_from_tree()` decide sobre `work/iso/casper/` (lo usan
  `unsquash_rootfs`, `update_casper_size`, `update_casper_metadata` y
  `rebuild_iso`); respeta `SQUASHFS_NAME` si ya está fijado.
- `SQUASHFS_NAME` guarda el archivo y `SQUASHFS_BASE` su prefijo
  (`minimal.standard` o `filesystem`). Ninguna función vuelve a escribir
  `filesystem.*` a mano.

### 3.2 `install_mytical_packages()`

- Monta `/proc`, `/sys`, `/dev` y `/dev/pts` en el rootfs y copia un
  `resolv.conf` temporal; todo se desmonta y se restaura con un `trap` aunque
  APT falle.
- Copia la clave pública del repo (`mytical-release.asc` o `.gpg`) a
  `/usr/share/keyrings/mytical-apt.*` y escribe
  `/etc/apt/sources.list.d/mytical.sources` con `Signed-By`. La clave se busca
  junto al repo, en su directorio padre o en `distro/apt/`.
- Ejecuta `apt-get update` e instala `package-lists/mytical.list` con
  `--no-install-recommends` y `APT::Get::AutomaticRemove=false`. **Sin
  autoremove**: el pipeline nunca borra paquetes del rootfs.
- Falla con un mensaje accionable si falta `--repo`, si el repo no tiene
  `dists/mytical/` o si no aparece la clave pública. Sin repo no se configuran
  repos anónimos ni `trusted=yes`.
- Después de instalar, comprueba que no entraron `ubuntu-session`, `gdm3`,
  `gnome-shell` ni `ubuntu-desktop*`, y que sí están `casper` y `calamares`.

### 3.3 `apply_branding()`

- Copia los wallpapers CC0 de `distro/branding/wallpapers/` a
  `/usr/share/backgrounds/mytical/` y `distro/branding/LICENSES.md` a
  `/usr/share/doc/mytical/branding/`.
- Escribe `/etc/os-release` con `NAME="Mytical"`, `ID=mytical`,
  `ID_LIKE=ubuntu`, `VERSION_ID="26.04"`, `MYTICAL_VERSION_ID="1.1"` y
  `UBUNTU_CODENAME=resolute`. El `VERSION_ID` de Ubuntu se conserva para que
  las herramientas de la base sigan detectando 26.04; la versión de Mytical
  viaja en `MYTICAL_VERSION_ID`.
- Instala el tema SDDM `mytical` y fija
  `/etc/sddm.conf.d/90-mytical.conf` (`Current=mytical`,
  `SessionDir=/usr/share/wayland-sessions`). Usa un wallpaper CC0 como fondo.
- No copia logos ni arte de Ubuntu. Si la ISO base trae el tema SDDM oficial
  de Ubuntu, lo retira del rootfs para no ofrecerlo en el greeter.

### 3.4 `update_casper_metadata()`

- Mueve el squashfs recién comprimido (`work/rootfs.squashfs`) dentro del árbol
  extraído sobre el archivo elegido (`casper/<SQUASHFS_NAME>`) para que
  `md5sum.txt` describa exactamente lo que montará el remux.
- `update_casper_size()` recalcula `casper/<base>.size` con
  `du -sx --block-size=1` (rootfs sin comprimir): `minimal.standard.size` en el
  layout nuevo, `filesystem.size` en el viejo.
- `update_install_sources()` actualiza `casper/install-sources.yaml` si existe.
  Solo toca la entrada `id: standard`: reescribe su `path` a
  `minimal.standard.squashfs` y su `size` con el tamaño **comprimido** del
  squashfs (`stat -c %s`). Las variantes de idioma y `enhanced` conservan su
  `path`/`size`. Si el archivo existe pero no contiene una única entrada
  `standard`, el build aborta sin modificar el fichero. En el layout viejo,
  sin `install-sources.yaml`, la función solo informa y no hace nada.
- Regenera `casper/<base>.manifest` con `dpkg-query` si el chroot trae la
  herramienta; si no, conserva el manifiesto base y avisa. Solo se regenera el
  manifiesto del squashfs elegido, no los de las variantes de idioma.
- Regenera `md5sum.txt` desde el árbol extraído, excluyéndose a sí mismo.
- Deja un `TODO(iso)` explícito: `md5sum.txt` solo puede validarse contra la
  ISO final después de ejecutar el remux y montar la imagen.

### 3.5 Calamares

`calamares/settings.conf` y `calamares/modules/` incluyen, como mínimo,
`partition`, `unpackfs`, `bootloader`, `users`, `locale`, `keyboard`,
`displaymanager` y `finished`, más los módulos de soporte de la secuencia
(`welcome`, `summary`, `mount`, `machineid`, `fstab`, `localecfg`,
`networkcfg`, `hwclock`, `services`, `grubcfg`, `umount`). `unpackfs.conf`
versiona `/cdrom/casper/minimal.standard.squashfs`; `stage_calamares()`
reescribe ese `source` al nombre detectado, de modo que una ISO del layout
viejo instale desde `filesystem.squashfs`. `bootloader` usa GRUB/shim;
`services` habilita SDDM; `displaymanager` solo ofrece la sesión `mytical`.


## 4. Estado actual

| Archivo | Contenido |
|---|---|
| `distro/iso/README.md` | requisitos, ISO oficial, dependencias, flujo, tamaño y regla de `/nix` |
| `distro/iso/Makefile` | `check`, `build`, `clean`, `test`; `build` exige `ISO=` |
| `distro/iso/remaster.sh` | flags, validaciones, plan y pipeline completo (detección de layout, chroot, branding, metadatos, remux) |
| `distro/iso/package-lists/mytical.list` | base APT sin GNOME |
| `distro/iso/calamares/settings.conf` | secuencia de Calamares coherente con los módulos |
| `distro/iso/calamares/modules/` | `.conf` mínimos de partition, unpackfs, bootloader, users, locale, keyboard, displaymanager, finished y soporte |
| `distro/iso/calamares/branding/mytical/branding.desc` | marca textual, sin imágenes |
| `distro/iso/tests/test_iso_scaffold.sh` | tests locales sin ISO/root/red, con stubs de chroot, herramientas y los dos layouts |

Verificado localmente:

- `make -C distro/iso test` pasa y cubre las funciones nuevas con stubs; no
  ejecuta `mksquashfs`, `xorriso` ni `chroot` reales.
- `make build` sin ISO falla con un mensaje accionable y no crea `work/`.
- `--dry-run` con una ISO falsa (archivo disperso) y `xorriso` simulado
  imprime el plan, muestra el layout detectado y deja `work/` intacto.
- La detección de layout se prueba con stubs de los dos casos:
  `minimal.standard.squashfs` (26.04) y `filesystem.squashfs` (anterior),
  incluido el caso con ambos archivos (gana `minimal.standard`) y un casper
  sin ninguno (falla).
- `unsquash_rootfs()` extrae el squashfs elegido en ambos layouts;
  `unpackfs.conf` se copia al rootfs con el `source` correspondiente.
- `install_mytical_packages()` falla claro sin `--repo`; con repo y clave
  simula `apt-get update`, instala con `--no-install-recommends`, no ejecuta
  autoremove y desmonta el chroot.
- `apply_branding()` escribe `os-release`, copia wallpapers/licencias, instala
  SDDM y retira el tema de Ubuntu.
- `update_casper_metadata()` se prueba con los dos layouts:
  `minimal.standard.size`/`.manifest`/`install-sources.yaml` y
  `filesystem.size`/`.manifest`; `md5sum -c` pasa sobre el árbol extraído
  simulado.
- `update_install_sources()` actualiza solo la entrada `standard` y deja
  intactas las variantes de idioma/`enhanced`; sin entrada `standard` aborta
  sin tocar el fichero. El YAML sigue siendo válido (PyYAML) tras el cambio.
- `rebuild_iso()` se prueba con un `xorriso` que registra sus `-map`: mapea
  `/casper/<SQUASHFS_NAME>`, `<base>.size`, `<base>.manifest`,
  `install-sources.yaml` y `md5sum.txt`.
- La lista no contiene `/nix`, `ubuntu-session`, `gdm3` ni `gnome-shell`.

**No verificado:** no se descargó la ISO, no se ejecutó root, no se construyó
la imagen, no se abrió Calamares ni se arrancó QEMU.


## 5. Bloqueantes

### B1 — Integración casper + Calamares

El pipeline ya está implementado en `remaster.sh`, pero no se ha ejecutado
contra una ISO real. Queda por validar en build/QEMU:

- `install_mytical_packages()`: montajes del chroot, `Signed-By` con la clave
  del repo local, `apt-get update`, instalación con `--no-install-recommends`
  (**sin autoremove**) y comprobación de que no entró GNOME/GDM. Implementado;
  los tests lo ejercitan con un `chroot` simulado, no con APT real.
- `calamares/modules/`: `unpackfs.conf` (origen
  `/cdrom/casper/minimal.standard.squashfs`, reescrito por `stage_calamares()`
  al nombre detectado), `partition.conf`, `bootloader.conf`, `users.conf`,
  `displaymanager.conf`, `locale.conf`, `keyboard.conf`, `finished.conf` y los
  módulos de soporte de la secuencia. Implementado; falta que Calamares lo
  cargue de verdad.
- `update_casper_metadata()`: `<base>.manifest`, `<base>.size`,
  `install-sources.yaml` (entrada `standard`) y `md5sum.txt`; el remux mapea
  también esos metadatos. Implementado; la validación final de `md5sum.txt`
  sigue marcada como `TODO(iso)` hasta montar la ISO resultante.
- Lanzador de Calamares en el live (`.desktop` + autostart) y usuario live:
  **pendiente**, fuera de esta entrega.

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

Presupuesto: **≤ 8 GiB** de ISO final. La oficial ronda 6 GiB y su
`minimal.standard.squashfs` ya pesa ~4,9 GB; el rootfs crece con Calamares,
Hyprland, Waybar, kitty y fuentes. El cierre Nix no se suma porque no entra.
Si se supera el presupuesto, medir con `du -xhd1 work/rootfs` y
`unsquashfs -ll` antes de recortar a ciegas. Como el layout nuevo conserva las
variantes de idioma/`enhanced` de la ISO base, el remux no libera su espacio:
el presupuesto se calcula sobre la ISO original sustituyendo solo el squashfs
elegido.

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
marca. El pipeline solo genera `.sha256`; la firma y la subida quedan fuera
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
| AC4 | `make build ISO=... REPO=...` genera `work/mytical-26.04-amd64.iso` y `.sha256` verificable | implementado; pendiente de ejecutar con ISO |
| AC5 | La ISO arranca en UEFI y BIOS y llega a SDDM | pendiente (B1/B7) |
| AC6 | La única sesión es `mytical.desktop`; no hay `gdm3`, `ubuntu-session` ni `gnome-shell` | pendiente de build |
| AC7 | El rootfs y el squashfs no contienen `/nix` | pendiente de build |
| AC8 | El live llega a Hyprland sin red y sin Nix | pendiente (B1/B5) |
| AC9 | Calamares instala en disco virtio y el sistema instalado arranca con SDDM | pendiente (B1/B7) |
| AC10 | Assets con licencia, avisos y manifiesto incluidos; sin arte P0 | pendiente (B3) |
| AC11 | ISO ≤ 8 GiB y checksum/firma publicados | pendiente (B4/B6) |
| AC12 | README/ISO.md describen el comando exacto y las limitaciones | **cumple** |
| AC13 | Los tests cubren `install_mytical_packages`, `apply_branding`, `update_casper_metadata` y `--dry-run` no toca `work/` | **cumple** |
| AC14 | El build no ejecuta autoremove y el repo local usa `Signed-By` | **cumple en código/tests**; pendiente de APT real |
| AC15 | El pipeline detecta `minimal.standard.squashfs` (26.04) y `filesystem.squashfs` (anterior), y extrae/remuxa el elegido | **cumple en tests**; pendiente de ISO real |
| AC16 | `install-sources.yaml` actualiza solo la entrada `standard` (path y size comprimido) sin tocar idioma/`enhanced` | **cumple en tests**; pendiente de ISO real |


## 7. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| APT arrastra recommends de GNOME | ISO más grande y sesiones duplicadas | `--no-install-recommends`, `AutomaticRemove=false`, lista explícita y test que falla si aparece GNOME |
| `xorriso -map` deja `md5sum.txt` obsoleto | “Check disc” falla; no afecta al arranque normal | regenerar `md5sum.txt` antes del remux y mapearlo en `rebuild_iso` |
| `install-sources.yaml` desincronizado | el instalador elige un `path` inexistente o un `size` que no corresponde y la instalación falla o se queda sin barra de progreso | `update_install_sources()` reescribe solo la entrada `standard` con el squashfs detectado y su tamaño comprimido; si no la encuentra, el build aborta. El esquema real de la ISO 26.04 no se validó todavía |
| Se tocan variantes de idioma/`enhanced` | el instalador ofrece imágenes que ya no coinciden con la ISO | el parser solo edita el bloque con `id: standard` exacto; tests comprueban que las demás entradas conservan `path`/`size` |
| Layout de casper distinto del esperado | el build extrae el squashfs equivocado o falla tarde | detección temprana con `resolve_squashfs_from_listing()` en `--check`/`--dry-run`; aborta si no hay ningún candidato |
| Calamares sin `.conf` de módulos | instalador aborta a mitad | `.conf` mínimos versionados; falta probar Calamares en QEMU |
| Repo local sin clave pública | APT no puede validar `Signed-By` y el build aborta | falla clara de `repo_key()`; la clave viaja junto al repo o en `distro/apt/` |
| Montajes del chroot quedan abiertos si APT falla | `work/` a medio montar | `trap cleanup_chroot` desmonta `/proc`, `/sys`, `/dev`, `/dev/pts` y restaura `resolv.conf` |
| Secure Boot + NVIDIA | pantalla negra o módulo rechazado | MOK documentado; ISO NVIDIA aparte |
| Root mal escrito en `remaster.sh` | borrar `work/` o el repo equivocado | `WORK_DIR` fijo, guardas de ruta y `clean` acotado |
| La ISO oficial cambia (26.04.1/2) | checksums y rutas distintas | validar nombre + `/casper`; fijar SHA-256 en las notas |
| Build no determinista | dos builds con SHA distinto | B8: `SOURCE_DATE_EPOCH`, orden y metadatos |
| Marca “Mytical” sin verificar | conflicto de marca | búsqueda de anterioridad antes de publicar |

## 8. Próximos pasos

1. Ejecutar `make -C distro/iso check ISO=<oficial>` y un build real con
   `REPO=<repo firmado>`; corregir lo que falle en APT/Calamares y revisar el
   diff de `casper/install-sources.yaml` contra la ISO original.
2. Añadir el lanzador de Calamares en el live (`.desktop` + autostart) y el
   usuario live; hoy el pipeline instala Calamares pero no lo abre solo.
3. Construir una ISO de prueba y arrancarla en QEMU UEFI/BIOS.
4. Cerrar assets (B3) y decidir Hyprland/Quickshell (B5).
5. Medir tamaño y, si hace falta, recortar antes de firmar (B4/B6).
6. Escribir el test de arranque/instalación (B7) y adjuntar evidencia.

## 8.1 Limitaciones de esta entrega

- No se descargó la ISO oficial, no se pidió root y no se ejecutó
  `mksquashfs`, `xorriso`, `unsquashfs` ni `chroot` reales.
- `install_mytical_packages()` está probado con stubs; APT real, la firma de la
  clave y los paquetes de Ubuntu 26.04 no se validaron en este entorno.
- `update_casper_metadata()` valida `md5sum.txt` contra el árbol extraído, no
  contra la ISO final. La comprobación contra la imagen montada sigue como
  `TODO(iso)`.
- El parser de `install-sources.yaml` es una heurística sobre el texto: separa
  entradas por la indentación mínima de la lista, elige el bloque con
  `id: standard` y reescribe su `path`/`size` conservando el resto de líneas y
  comentarios. No es un parser YAML completo: no soporta mapas en flujo
  (`- {path: ..., size: ...}`) ni entradas sin `id` y sin `path` reconocible.
  El esquema real de la ISO 26.04 no se comprobó; el primer build real debe
  revisar el diff de ese archivo antes de publicar.
- `size` en `install-sources.yaml` se interpreta como el tamaño del squashfs
  comprimido (`stat`), mientras que `<base>.size` es el rootfs sin comprimir
  (`du`). El número del enunciado (`4911607808`, ~4,9 GB) encaja con el
  squashfs; aun así no se contrastó contra la ISO real.
- El remux conserva las variantes de idioma/`enhanced` de la ISO base sin
  recomprimirlas ni actualizar sus manifiestos: solo se regenera el manifiesto
  y el squashfs del layout elegido.
- `stage_calamares()` reescribe el `source` de `unpackfs.conf` con `sed`; no se
  validó que Calamares 26.04 acepte el resto de la configuración.
- Los `.conf` de Calamares son mínimos y parsean como YAML; no se cargaron con
  `calamares -d` ni se probó una instalación.
- `apply_branding()` no instala el tema Plymouth de Mytical ni un logo de
  Calamares: los assets gráficos siguen bloqueados por B3. Solo usa texto,
  wallpapers CC0 y el tema SDDM existente.
- No se cambiaron versiones, el repo APT ni `mksquashfs`; el remux conserva
  shim/GRUB/kernel firmados de Ubuntu y queda pendiente de probar Secure Boot.
- El `README.md` de `distro/iso/` conserva la descripción del esqueleto y aún
  nombra `filesystem.squashfs`/`filesystem.size`; este documento es la
  referencia del estado implementado y del layout nuevo.


## 9. Referencias

- [`distro/iso/README.md`](../../distro/iso/README.md)
- [`docs/distro/ASSET-LICENSES.md`](ASSET-LICENSES.md)
- [`docs/distro/RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md)
- [`docs/adr/0001-overlay-first.md`](../adr/0001-overlay-first.md)
- [`docs/adr/0002-apt-owned-desktop.md`](../adr/0002-apt-owned-desktop.md)
- [`docs/adr/0006-single-session.md`](../adr/0006-single-session.md)
- Plan V1: [`docs/superpowers/plans/2026-11-12-mytical-distro-v1.md`](../superpowers/plans/2026-11-12-mytical-distro-v1.md), tareas 9 y 10.
