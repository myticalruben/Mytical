#!/usr/bin/env bash
# Remaster reproducible de la ISO oficial de Ubuntu 26.04 para Mytical V1.1.
#
# Este es un ESQUELETO. Valida la ISO, las herramientas y el repo local, y en
# --dry-run imprime el plan completo sin escribir nada. El build real esta
# bloqueado a proposito en el gate TODO: falta implementar el chroot APT, los
# hooks de branding y los .conf de los modulos de Calamares.
#
# Uso:
#   ./remaster.sh --check --iso /ruta/ubuntu-26.04-desktop-amd64.iso
#   ./remaster.sh --dry-run --iso /ruta/ubuntu-26.04-desktop-amd64.iso \
#       [--repo /ruta/distro/apt/public] [--out /ruta/mytical-26.04-amd64.iso]
#
# El build de verdad exige root. La ISO y el repo APT se pasan por ruta: el
# script no usa red y no descarga nada.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
ISO_TREE="$WORK_DIR/iso"
ROOTFS_DIR="$WORK_DIR/rootfs"
NEW_SQUASHFS="$WORK_DIR/filesystem.squashfs"

ISO=""
OUT="$WORK_DIR/mytical-26.04-amd64.iso"
REPO=""
DRY_RUN=0
CHECK_ONLY=0

HOST_TOOLS=(mksquashfs unsquashfs xorriso sha256sum stat)

# Se pone a 1 solo cuando install_mytical_packages(), apply_branding() y
# update_casper_metadata() esten implementados. Hasta entonces el build real
# aborta antes de tocar work/.
BUILD_IMPLEMENTED=0

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Remaster casper de la ISO oficial de Ubuntu 26.04 para Mytical V1.1.

Opciones:
  --iso RUTA     ISO oficial ubuntu-26.04*-desktop-amd64.iso (obligatoria)
  --out RUTA     ISO de salida (por defecto distro/iso/work/mytical-26.04-amd64.iso)
  --repo RUTA    raiz de un repo APT local con dists/mytical/ (opcional)
  --dry-run      valida e imprime el plan; no escribe nada y no exige root
  --check        solo valida ISO, herramientas, repo y esqueleto; no escribe
  -h, --help     esta ayuda

El build real requiere root y hoy se detiene en el gate TODO (chroot APT y
Calamares sin implementar). Ver README.md y docs/distro/ISO.md.
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --iso)
                [ "$#" -ge 2 ] || die "--iso requiere una ruta"
                ISO="$2"
                shift 2
                ;;
            --iso=*)
                ISO="${1#*=}"
                shift
                ;;
            --out)
                [ "$#" -ge 2 ] || die "--out requiere una ruta"
                OUT="$2"
                shift 2
                ;;
            --out=*)
                OUT="${1#*=}"
                shift
                ;;
            --repo)
                [ "$#" -ge 2 ] || die "--repo requiere una ruta"
                REPO="$2"
                shift 2
                ;;
            --repo=*)
                REPO="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --check)
                CHECK_ONLY=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "argumento desconocido: $1 (usa --help)"
                ;;
        esac
    done

    if [ "$DRY_RUN" -eq 1 ] && [ "$CHECK_ONLY" -eq 1 ]; then
        die "--dry-run y --check son excluyentes"
    fi
}

# Resuelve rutas relativas contra el directorio actual sin exigir que existan.
abspath() {
    local path="$1"
    case "$path" in
        /*) printf '%s\n' "$path" ;;
        *)  printf '%s/%s\n' "$PWD" "$path" ;;
    esac
}

resolve_paths() {
    OUT="$(abspath "$OUT")"
    if [ -n "$ISO" ]; then
        ISO="$(abspath "$ISO")"
    fi
    if [ -n "$REPO" ]; then
        REPO="$(abspath "$REPO")"
    fi
}

check_scaffold() {
    local list="$SCRIPT_DIR/package-lists/mytical.list"
    local settings="$SCRIPT_DIR/calamares/settings.conf"
    local branding="$SCRIPT_DIR/calamares/branding/mytical/branding.desc"

    [ -s "$list" ] || die "falta la lista de paquetes: $list"
    [ -s "$settings" ] || die "falta Calamares settings.conf: $settings"
    [ -s "$branding" ] || die "falta el branding de Calamares: $branding"

    if ! grep -qx 'casper' "$list"; then
        die "la lista no declara casper: $list"
    fi
    if ! grep -qx 'calamares' "$list"; then
        die "la lista no declara calamares: $list"
    fi

    local prohibited
    for prohibited in ubuntu-session gdm3 gnome-shell; do
        if grep -qx "$prohibited" "$list"; then
            die "paquete prohibido en la lista: $prohibited"
        fi
    done

    if grep -q '/nix' "$list"; then
        die "la lista contiene una ruta /nix; la ISO no hornea Nix"
    fi
}

check_iso() {
    [ -n "$ISO" ] || die "falta --iso (ISO oficial de Ubuntu 26.04)"
    [ -e "$ISO" ] || die "no existe la ISO: $ISO"
    [ -f "$ISO" ] || die "la ruta de la ISO no es un archivo: $ISO"
    [ -r "$ISO" ] || die "la ISO no es legible: $ISO"

    local name size
    name="$(basename -- "$ISO")"
    case "$name" in
        ubuntu-26.04*-desktop-amd64.iso) ;;
        *)
            die "nombre de ISO inesperado: $name (se espera ubuntu-26.04*-desktop-amd64.iso)"
            ;;
    esac

    size="$(stat -c '%s' -- "$ISO")" || die "no se pudo leer el tamano de $ISO"
    if [ "$size" -lt 1073741824 ]; then
        die "la ISO parece truncada o no es la imagen oficial: $ISO ($size bytes)"
    fi
}

tool_package() {
    case "$1" in
        mksquashfs|unsquashfs) printf 'squashfs-tools' ;;
        xorriso)               printf 'xorriso' ;;
        sha256sum|stat)        printf 'coreutils' ;;
        *)                     printf '%s' "$1" ;;
    esac
}

check_tools() {
    local tool
    for tool in "${HOST_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "falta '$tool'; instala: sudo apt install $(tool_package "$tool")"
        fi
    done

    info "herramientas de host: ${HOST_TOOLS[*]}"
    info "casper/calamares no se ejecutan en el host: se instalan en el rootfs"
}

check_root_policy() {
    if [ "$DRY_RUN" -eq 1 ] || [ "$CHECK_ONLY" -eq 1 ]; then
        if [ "$(id -u)" -ne 0 ]; then
            info "sin root: correcto para --check/--dry-run (no escriben)"
        fi
        return 0
    fi

    if [ "$(id -u)" -ne 0 ]; then
        die "el build real requiere root; usa: sudo $0 --iso ..."
    fi
}

check_iso_layout() {
    local listing
    info "leyendo el arbol de $ISO"
    if ! listing="$(xorriso -indev "$ISO" -find /casper -maxdepth 1 2>/dev/null)"; then
        die "xorriso no pudo leer la ISO: $ISO"
    fi

    if ! grep -qx '/casper/filesystem.squashfs' <<<"$listing"; then
        die "la ISO no trae /casper/filesystem.squashfs; no parece Ubuntu desktop"
    fi
    if ! grep -qx '/casper/vmlinuz' <<<"$listing"; then
        die "la ISO no trae /casper/vmlinuz; no parece Ubuntu desktop"
    fi
}

check_repo() {
    [ -n "$REPO" ] || return 0

    [ -d "$REPO" ] || die "no existe el repo APT: $REPO"
    if [ ! -f "$REPO/dists/mytical/Release" ] && [ ! -f "$REPO/dists/mytical/InRelease" ]; then
        die "el repo no parece APT mytical (falta dists/mytical/Release o InRelease): $REPO"
    fi

    info "repo local: $REPO"
}

print_plan() {
    log "Plan de remaster (dry-run: no se escribe nada)"
    info "ISO de entrada : $ISO"
    info "ISO de salida  : $OUT"
    info "Repo local     : ${REPO:-(ninguno; los mytical-* no estaran)}"
    info "Work           : $WORK_DIR"
    info ""
    info "  1. validar ISO y /casper ................. hecho"
    info "  2. crear work y extraer la ISO ............ xorriso -osirrox"
    info "  3. extraer el squashfs .................... unsquashfs"
    info "  4. copiar el repo local ................... /opt/mytical/apt"
    info "  5. chroot: APT instala package-lists ...... [TODO]"
    info "  6. copiar Calamares y branding ............ /etc/calamares"
    info "  7. aplicar branding y licencias ........... [TODO]"
    info "  8. verificar que no hay /nix .............. obligatorio"
    info "  9. recomprimir squashfs ................... mksquashfs + xz"
    info " 10. remux de la ISO ....................... xorriso -boot_image keep"
    info " 11. checksum SHA256 ....................... $OUT.sha256"
    info ""
    info "El build real se detiene antes de escribir en el gate TODO."
    info "La ISO oficial, su shim/GRUB/kernel y el arranque Secure Boot se conservan."
}

# ---------------------------------------------------------------------------
# Pipeline de build (estructura; las piezas destructivas son TODO)
# ---------------------------------------------------------------------------

assert_implemented() {
    if [ "$BUILD_IMPLEMENTED" -eq 1 ]; then
        return 0
    fi

    # TODO(iso): poner BUILD_IMPLEMENTED=1 cuando existan
    # install_mytical_packages(), apply_branding(), update_casper_metadata()
    # y los .conf de Calamares.
    die "TODO(iso): el build real aun no esta implementado.

Faltan estas piezas antes de poder remasterizar:
  - install_mytical_packages(): chroot APT con el repo local, --no-install-recommends
    y verificacion de que no entra GNOME/GDM/ubuntu-session.
  - apply_branding(): tema SDDM, wallpapers CC0, LICENSE y avisos de terceros.
  - update_casper_metadata(): filesystem.manifest, filesystem.size y md5sum.txt.
  - calamares/modules/: unpackfs.conf, partition.conf, bootloader.conf, users.conf,
    displaymanager.conf y los hooks de post-instalacion.

Usa --dry-run para ver el plan sin tocar nada."
}

prepare_workdir() {
    log "1/8 preparar work"
    case "$WORK_DIR" in
        "$SCRIPT_DIR/work") ;;
        *) die "WORK_DIR inesperado: $WORK_DIR" ;;
    esac
    mkdir -p -- "$WORK_DIR"
    rm -rf -- "$ISO_TREE" "$ROOTFS_DIR" "$NEW_SQUASHFS"
}

extract_iso() {
    log "2/8 extraer la ISO"
    mkdir -p -- "$ISO_TREE"
    xorriso -osirrox on -indev "$ISO" -extract / "$ISO_TREE" >/dev/null
    chmod -R u+w -- "$ISO_TREE"
}

unsquash_rootfs() {
    log "3/8 extraer el squashfs"
    rm -rf -- "$ROOTFS_DIR"
    unsquashfs -d "$ROOTFS_DIR" "$ISO_TREE/casper/filesystem.squashfs" >/dev/null
}

stage_repo() {
    log "4/8 copiar el repo local"
    if [ -z "$REPO" ]; then
        warn "sin --repo: mytical-session, mytical-desktop y mytical-welcome no se instalaran"
        return 0
    fi

    install -d -- "$ROOTFS_DIR/opt/mytical/apt"
    cp -a -- "$REPO/." "$ROOTFS_DIR/opt/mytical/apt/"
}

install_mytical_packages() {
    log "5/8 instalar paquetes en el chroot"
    # TODO(iso): montar /proc /sys /dev, copiar resolv.conf, apt-get update con
    # el repo local y firmado, e instalar package-lists/mytical.list con
    # --no-install-recommends. Verificar despues que no hay GNOME/GDM/ubuntu-session.
    if [ "$BUILD_IMPLEMENTED" -eq 0 ]; then
        die "TODO(iso): install_mytical_packages() no esta implementado"
    fi
}

stage_calamares() {
    log "6/8 copiar Calamares"
    install -d -- "$ROOTFS_DIR/etc/calamares"
    install -d -- "$ROOTFS_DIR/usr/share/calamares/branding/mytical"
    install -m 0644 -- "$SCRIPT_DIR/calamares/settings.conf" \
        "$ROOTFS_DIR/etc/calamares/settings.conf"
    cp -a -- "$SCRIPT_DIR/calamares/branding/mytical/." \
        "$ROOTFS_DIR/usr/share/calamares/branding/mytical/"
}

apply_branding() {
    log "7/8 aplicar branding"
    # TODO(iso): instalar el tema SDDM mytical, el wallpaper CC0, la licencia
    # GPL del tema y los avisos de terceros; retirar cualquier arte sin licencia.
    if [ "$BUILD_IMPLEMENTED" -eq 0 ]; then
        die "TODO(iso): apply_branding() no esta implementado"
    fi
}

assert_no_nix() {
    log "8/8 verificar que no hay /nix"
    if [ -e "$ROOTFS_DIR/nix" ] || [ -L "$ROOTFS_DIR/nix" ]; then
        die "el rootfs contiene /nix; la ISO V1.1 no hornea Nix"
    fi
}

update_casper_size() {
    local bytes
    bytes="$(du -sx --block-size=1 "$ROOTFS_DIR" | cut -f1)"
    printf '%s\n' "$bytes" > "$ISO_TREE/casper/filesystem.size"
}

repack_squashfs() {
    log "recomprimir squashfs"
    rm -f -- "$NEW_SQUASHFS"
    mksquashfs "$ROOTFS_DIR" "$NEW_SQUASHFS" \
        -noappend -comp xz -b 1M -Xdict-size 100% -no-progress
    update_casper_size
}

update_casper_metadata() {
    # TODO(iso): regenerar filesystem.manifest desde dpkg y md5sum.txt desde
    # el arbol extraido. Sin esto, "Check disc for defects" de casper falla
    # aunque la ISO arranque.
    if [ "$BUILD_IMPLEMENTED" -eq 0 ]; then
        die "TODO(iso): update_casper_metadata() no esta implementado"
    fi
}

rebuild_iso() {
    log "remux de la ISO (conserva shim/GRUB/kernel)"
    mkdir -p -- "$(dirname -- "$OUT")"
    rm -f -- "$OUT"
    xorriso -indev "$ISO" -outdev "$OUT" -boot_image any keep \
        -map "$NEW_SQUASHFS" /casper/filesystem.squashfs \
        -map "$ISO_TREE/casper/filesystem.size" /casper/filesystem.size \
        -commit
}

write_checksum() {
    local base dir
    base="$(basename -- "$OUT")"
    dir="$(dirname -- "$OUT")"
    log "checksum"
    ( cd -- "$dir" && sha256sum -- "$base" > "$base.sha256" )
    info "OK: $OUT"
    info "SHA256: $(cut -d' ' -f1 -- "$OUT.sha256")"
}

build_iso() {
    assert_implemented
    prepare_workdir
    extract_iso
    unsquash_rootfs
    stage_repo
    install_mytical_packages
    stage_calamares
    apply_branding
    assert_no_nix
    repack_squashfs
    update_casper_metadata
    rebuild_iso
    write_checksum
}

main() {
    parse_args "$@"
    resolve_paths
    check_scaffold
    check_iso
    check_tools
    check_root_policy
    check_iso_layout
    check_repo

    if [ "$CHECK_ONLY" -eq 1 ]; then
        log "check OK"
        info "ISO:   $ISO"
        info "Repo:  ${REPO:-(ninguno)}"
        info "Salida prevista: $OUT"
        exit 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        print_plan
        exit 0
    fi

    build_iso
}

main "$@"
