#!/usr/bin/env bash
# Remaster reproducible de la ISO oficial de Ubuntu 26.04 para Mytical V1.1.
#
# El pipeline esta implementado, pero no se ejecuta en este repositorio: el
# build real exige root, una ISO oficial ya descargada y un repo APT local.
# `--check` y `--dry-run` validan y planifican sin escribir en work/.
#
# Uso:
#   ./remaster.sh --check --iso /ruta/ubuntu-26.04-desktop-amd64.iso
#   ./remaster.sh --dry-run --iso /ruta/ubuntu-26.04-desktop-amd64.iso \
#       [--repo /ruta/distro/apt/public] [--out /ruta/mytical-26.04-amd64.iso]
#   sudo ./remaster.sh --iso ... --repo ... [--out ...]
#
# La ISO y el repo APT se pasan por ruta: el script no descarga nada. El repo
# es obligatorio para el build porque package-lists/mytical.list declara
# paquetes mytical-* que solo existen en ese repo.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
ISO_TREE="$WORK_DIR/iso"
ROOTFS_DIR="$WORK_DIR/rootfs"
NEW_SQUASHFS="$WORK_DIR/filesystem.squashfs"

# Branding textual/CC0 versionado en distro/branding/; el tema SDDM sale del
# paquete mytical-sddm-theme ya versionado en distro/debian/.
BRANDING_DIR="$SCRIPT_DIR/../branding"
SDDM_THEME_SRC="$SCRIPT_DIR/../debian/mytical-sddm-theme/usr/share/sddm/themes/mytical"
CALAMARES_MODULES=(
    welcome summary partition mount unpackfs machineid fstab locale keyboard
    localecfg users displaymanager networkcfg hwclock services grubcfg
    bootloader umount finished
)

ISO=""
OUT="$WORK_DIR/mytical-26.04-amd64.iso"
REPO=""
DRY_RUN=0
CHECK_ONLY=0

HOST_TOOLS=(mksquashfs unsquashfs xorriso sha256sum stat mount umount chroot)

# Estado del chroot. Se limpia siempre con cleanup_chroot(), tambien si el
# build aborta a mitad.
CHROOT_MOUNTS=()
RESOLV_LINK=""
RESOLV_BACKUP=""
RESOLV_CREATED=0

# Se mantiene como guarda explicita: si alguien vuelve a dejar el pipeline a
# medias, el build aborta antes de tocar work/.
BUILD_IMPLEMENTED=1

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
  --repo RUTA    raiz de un repo APT local con dists/mytical/ (obligatoria en build)
  --dry-run      valida e imprime el plan; no escribe nada y no exige root
  --check        solo valida ISO, herramientas, repo y esqueleto; no escribe
  -h, --help     esta ayuda

El build real requiere root. El repo local debe venir con su clave publica
(mytical-release.asc o .gpg) para configurar Signed-By. Ver README.md y
docs/distro/ISO.md.
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
    local module

    [ -s "$list" ] || die "falta la lista de paquetes: $list"
    [ -s "$settings" ] || die "falta Calamares settings.conf: $settings"
    [ -s "$branding" ] || die "falta el branding de Calamares: $branding"

    for module in "${CALAMARES_MODULES[@]}"; do
        [ -s "$SCRIPT_DIR/calamares/modules/$module.conf" ] ||
            die "falta el modulo de Calamares: calamares/modules/$module.conf"
    done

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
        sha256sum|stat|chroot) printf 'coreutils' ;;
        mount|umount)          printf 'util-linux' ;;
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

# Devuelve la clave publica que APT usara en Signed-By. La clave de release
# vive junto al repo o en distro/apt/; nunca se guarda una clave privada.
repo_key() {
    local candidate
    for candidate in \
        "${MYTICAL_APT_KEY:-}" \
        "$REPO/mytical-release.asc" \
        "$REPO/mytical-release.gpg" \
        "$REPO/../mytical-release.asc" \
        "$REPO/../mytical-release.gpg" \
        "$SCRIPT_DIR/../apt/mytical-release.asc" \
        "$SCRIPT_DIR/../apt/mytical-release.gpg"; do
        [ -n "$candidate" ] || continue
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

check_repo() {
    [ -n "$REPO" ] || return 0

    [ -d "$REPO" ] || die "no existe el repo APT: $REPO"
    if [ ! -f "$REPO/dists/mytical/Release" ] && [ ! -f "$REPO/dists/mytical/InRelease" ]; then
        die "el repo no parece APT mytical (falta dists/mytical/Release o InRelease): $REPO"
    fi
    if ! repo_key >/dev/null; then
        die "falta la clave publica del repo (mytical-release.asc o .gpg).
Se busca junto al repo, en su directorio padre y en distro/apt/.
Sin clave no se puede configurar Signed-By en el chroot."
    fi

    info "repo local: $REPO"
    info "clave publica: $(repo_key)"
}

print_plan() {
    log "Plan de remaster (dry-run: no se escribe nada)"
    info "ISO de entrada : $ISO"
    info "ISO de salida  : $OUT"
    info "Repo local     : ${REPO:-(ninguno; el build lo exige)}"
    info "Work           : $WORK_DIR"
    info ""
    info "  1. validar ISO y /casper ................. hecho"
    info "  2. crear work y extraer la ISO ............ xorriso -osirrox"
    info "  3. extraer el squashfs .................... unsquashfs"
    info "  4. copiar el repo local ................... /opt/mytical/apt"
    info "  5. chroot: APT instala package-lists ...... apt-get, --no-install-recommends"
    info "  6. copiar Calamares, modulos y branding ... /etc/calamares"
    info "  7. aplicar branding y licencias ........... /etc/os-release + SDDM mytical"
    info "  8. verificar que no hay /nix .............. obligatorio"
    info "  9. recomprimir squashfs ................... mksquashfs + xz"
    info " 10. filesystem.size + md5sum.txt ........... implementado"
    info " 11. remux de la ISO ....................... xorriso -boot_image keep"
    info " 12. checksum SHA256 ....................... $OUT.sha256"
    info ""
    info "El build real exige root y --repo; este dry-run no ha creado work/."
    info "La ISO oficial, su shim/GRUB/kernel y el arranque Secure Boot se conservan."
}

# ---------------------------------------------------------------------------
# Pipeline de build
# ---------------------------------------------------------------------------

assert_implemented() {
    local module

    if [ "$BUILD_IMPLEMENTED" -ne 1 ]; then
        die "estado inconsistente: BUILD_IMPLEMENTED debe ser 1 para construir"
    fi

    for module in "${CALAMARES_MODULES[@]}"; do
        [ -s "$SCRIPT_DIR/calamares/modules/$module.conf" ] ||
            die "falta calamares/modules/$module.conf; el build no puede continuar"
    done

    for module in install_mytical_packages apply_branding update_casper_metadata; do
        declare -F "$module" >/dev/null ||
            die "falta la funcion $module(); el build no puede continuar"
    done
}

prepare_workdir() {
    log "1/12 preparar work"
    case "$WORK_DIR" in
        "$SCRIPT_DIR/work") ;;
        *) die "WORK_DIR inesperado: $WORK_DIR" ;;
    esac
    mkdir -p -- "$WORK_DIR"
    rm -rf -- "$ISO_TREE" "$ROOTFS_DIR" "$NEW_SQUASHFS"
}

extract_iso() {
    log "2/12 extraer la ISO"
    mkdir -p -- "$ISO_TREE"
    xorriso -osirrox on -indev "$ISO" -extract / "$ISO_TREE" >/dev/null
    chmod -R u+w -- "$ISO_TREE"
}

unsquash_rootfs() {
    log "3/12 extraer el squashfs"
    rm -rf -- "$ROOTFS_DIR"
    unsquashfs -d "$ROOTFS_DIR" "$ISO_TREE/casper/filesystem.squashfs" >/dev/null
}

stage_repo() {
    log "4/12 copiar el repo local"
    [ -n "$REPO" ] ||
        die "falta --repo: package-lists/mytical.list declara paquetes mytical-*.
El build necesita la raiz de un repo APT local con dists/mytical/ y su clave publica."
    [ -d "$REPO" ] || die "no existe el repo APT: $REPO"
    if [ ! -f "$REPO/dists/mytical/Release" ] && [ ! -f "$REPO/dists/mytical/InRelease" ]; then
        die "el repo no parece APT mytical (falta dists/mytical/Release o InRelease): $REPO"
    fi

    install -d -- "$ROOTFS_DIR/opt/mytical/apt"
    cp -a --no-preserve=ownership -- "$REPO/." "$ROOTFS_DIR/opt/mytical/apt/"
}

cleanup_chroot() {
    local index target

    if [ -n "${RESOLV_LINK:-}" ] || [ -n "${RESOLV_BACKUP:-}" ] || [ "$RESOLV_CREATED" -eq 1 ]; then
        rm -f -- "$ROOTFS_DIR/etc/resolv.conf"
        if [ -n "$RESOLV_LINK" ]; then
            ln -s -- "$RESOLV_LINK" "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || true
        elif [ -n "$RESOLV_BACKUP" ] && [ -f "$RESOLV_BACKUP" ]; then
            mv -f -- "$RESOLV_BACKUP" "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || true
        fi
        [ -z "$RESOLV_BACKUP" ] || rm -f -- "$RESOLV_BACKUP"
    fi
    RESOLV_LINK=""
    RESOLV_BACKUP=""
    RESOLV_CREATED=0

    for ((index = ${#CHROOT_MOUNTS[@]} - 1; index >= 0; index--)); do
        target="${CHROOT_MOUNTS[$index]}"
        umount -- "$target" 2>/dev/null || true
    done
    CHROOT_MOUNTS=()
}

prepare_chroot_resolv() {
    local target="$ROOTFS_DIR/etc/resolv.conf"

    install -d -- "$ROOTFS_DIR/etc"
    if [ -L "$target" ]; then
        RESOLV_LINK="$(readlink -- "$target")"
        rm -f -- "$target"
    elif [ -e "$target" ]; then
        RESOLV_BACKUP="$(mktemp "${TMPDIR:-/tmp}/mytical-resolv.XXXXXX")"
        cp -a -- "$target" "$RESOLV_BACKUP"
    else
        RESOLV_CREATED=1
    fi

    if [ -r /etc/resolv.conf ]; then
        install -m 0644 -- /etc/resolv.conf "$target"
    else
        warn "no hay /etc/resolv.conf en el host; APT solo podra usar el repo local"
        : > "$target"
        RESOLV_CREATED=1
    fi
}

mount_chroot() {
    local target
    for target in proc sys dev dev/pts; do
        install -d -- "$ROOTFS_DIR/$target"
    done

    mount -t proc proc "$ROOTFS_DIR/proc"
    CHROOT_MOUNTS+=("$ROOTFS_DIR/proc")
    mount --bind /sys "$ROOTFS_DIR/sys"
    CHROOT_MOUNTS+=("$ROOTFS_DIR/sys")
    mount --bind /dev "$ROOTFS_DIR/dev"
    CHROOT_MOUNTS+=("$ROOTFS_DIR/dev")
    mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
    CHROOT_MOUNTS+=("$ROOTFS_DIR/dev/pts")
}

# Lee la lista sin comentarios ni espacios. Falla si alguna entrada no es un
# nombre de paquete valido: el chroot nunca interpreta la lista como shell.
read_package_list() {
    local list="$SCRIPT_DIR/package-lists/mytical.list"
    local package

    [ -s "$list" ] || die "falta la lista de paquetes: $list"
    while IFS= read -r package; do
        case "$package" in
            *[!A-Za-z0-9.+-]*)
                die "entrada invalida en $list: $package"
                ;;
        esac
        printf '%s\n' "$package"
    done < <(
        awk '{
            sub(/#.*/, "")
            gsub(/[[:space:]]/, "")
            if ($0 != "") print
        }' "$list"
    )
}

install_mytical_packages() {
    local key key_ext keyring package
    local -a packages=()
    local installed prohibited required

    log "5/12 instalar paquetes en el chroot"

    [ -n "$REPO" ] ||
        die "falta --repo: el chroot necesita el repo local para mytical-*.
Usa: --repo /ruta/distro/apt/public (con su clave mytical-release.asc)."
    [ -d "$ROOTFS_DIR" ] || die "no existe el rootfs extraido: $ROOTFS_DIR"
    [ -x "$ROOTFS_DIR/usr/bin/apt-get" ] ||
        die "el rootfs no trae /usr/bin/apt-get; la ISO no parece Ubuntu desktop"
    if [ ! -f "$ROOTFS_DIR/opt/mytical/apt/dists/mytical/Release" ] &&
       [ ! -f "$ROOTFS_DIR/opt/mytical/apt/dists/mytical/InRelease" ]; then
        info "repo no copiado aun; ejecutando stage_repo()"
        stage_repo
    fi
    if [ ! -f "$ROOTFS_DIR/opt/mytical/apt/dists/mytical/Release" ] &&
       [ ! -f "$ROOTFS_DIR/opt/mytical/apt/dists/mytical/InRelease" ]; then
        die "falta el repo copiado en /opt/mytical/apt; revisa --repo"
    fi

    key="$(repo_key)" || die "falta la clave publica del repo (mytical-release.asc o .gpg).
Sin clave no se configura Signed-By; el build no usa repos sin firmar."
    case "$key" in
        *.gpg) key_ext="gpg" ;;
        *)     key_ext="asc" ;;
    esac
    keyring="/usr/share/keyrings/mytical-apt.$key_ext"

    install -d -- "$ROOTFS_DIR/usr/share/keyrings" "$ROOTFS_DIR/etc/apt/sources.list.d"
    install -m 0644 -- "$key" "$ROOTFS_DIR$keyring"
    cat > "$ROOTFS_DIR/etc/apt/sources.list.d/mytical.sources" <<EOF
Types: deb
URIs: file:/opt/mytical/apt
Suites: mytical
Components: main
Architectures: amd64
Signed-By: $keyring
EOF

    mapfile -t packages < <(read_package_list)
    [ "${#packages[@]}" -gt 0 ] || die "la lista de paquetes esta vacia"

    trap cleanup_chroot EXIT
    mount_chroot
    prepare_chroot_resolv

    info "apt-get update (repo local firmado + archive de Ubuntu)"
    chroot "$ROOTFS_DIR" env DEBIAN_FRONTEND=noninteractive \
        apt-get update

    info "apt-get install --no-install-recommends (${#packages[@]} paquetes)"
    # Sin borrado automatico: este pipeline nunca elimina paquetes del rootfs.
    chroot "$ROOTFS_DIR" env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends \
        -o APT::Get::AutomaticRemove=false \
        "${packages[@]}"

    # shellcheck disable=SC2016
    installed="$(chroot "$ROOTFS_DIR" dpkg-query -W -f='${Package}\n' 2>/dev/null || true)"
    for prohibited in ubuntu-session gdm3 gnome-shell ubuntu-desktop ubuntu-desktop-minimal; do
        if grep -qx -- "$prohibited" <<<"$installed"; then
            die "el chroot instalo $prohibited; la ISO debe quedar sin GNOME/GDM"
        fi
    done
    for required in casper calamares; do
        if ! grep -qx -- "$required" <<<"$installed"; then
            die "el chroot no declaro $required; revisa package-lists/mytical.list"
        fi
    done

    cleanup_chroot
    trap - EXIT
    info "paquetes instalados; sin GNOME/GDM/ubuntu-session"
}

stage_calamares() {
    log "6/12 copiar Calamares"
    install -d -- "$ROOTFS_DIR/etc/calamares/modules"
    install -d -- "$ROOTFS_DIR/usr/share/calamares/branding/mytical"
    install -m 0644 -- "$SCRIPT_DIR/calamares/settings.conf" \
        "$ROOTFS_DIR/etc/calamares/settings.conf"
    cp -a --no-preserve=ownership -- "$SCRIPT_DIR/calamares/modules/." \
        "$ROOTFS_DIR/etc/calamares/modules/"
    cp -a --no-preserve=ownership -- "$SCRIPT_DIR/calamares/branding/mytical/." \
        "$ROOTFS_DIR/usr/share/calamares/branding/mytical/"
}

apply_branding() {
    local wallpaper
    local -a wallpapers=()

    log "7/12 aplicar branding"
    [ -d "$ROOTFS_DIR" ] || die "no existe el rootfs extraido: $ROOTFS_DIR"
    [ -d "$BRANDING_DIR" ] || die "falta el branding de Mytical: $BRANDING_DIR"
    [ -s "$BRANDING_DIR/LICENSES.md" ] ||
        die "falta el aviso de licencias de branding: $BRANDING_DIR/LICENSES.md"

    mapfile -t wallpapers < <(
        find "$BRANDING_DIR/wallpapers" -maxdepth 1 -type f -name '*.png' | LC_ALL=C sort
    )
    [ "${#wallpapers[@]}" -gt 0 ] ||
        die "no hay wallpapers CC0 en $BRANDING_DIR/wallpapers"

    install -d -- "$ROOTFS_DIR/usr/share/backgrounds/mytical"
    for wallpaper in "${wallpapers[@]}"; do
        install -m 0644 -- "$wallpaper" \
            "$ROOTFS_DIR/usr/share/backgrounds/mytical/$(basename -- "$wallpaper")"
    done

    install -d -- "$ROOTFS_DIR/usr/share/doc/mytical/branding"
    install -m 0644 -- "$BRANDING_DIR/LICENSES.md" \
        "$ROOTFS_DIR/usr/share/doc/mytical/branding/LICENSES.md"

    install -d -- "$ROOTFS_DIR/etc"
    cat > "$ROOTFS_DIR/etc/os-release" <<'EOF'
PRETTY_NAME="Mytical 1.1"
NAME="Mytical"
VERSION="1.1 (basada en Ubuntu 26.04 LTS)"
VERSION_ID="26.04"
VERSION_CODENAME=resolute
ID=mytical
ID_LIKE=ubuntu
MYTICAL_VERSION_ID="1.1"
HOME_URL="https://github.com/myticalruben/Mytical"
SUPPORT_URL="https://github.com/myticalruben/Mytical/issues"
BUG_REPORT_URL="https://github.com/myticalruben/Mytical/issues"
PRIVACY_POLICY_URL="https://github.com/myticalruben/Mytical"
UBUNTU_CODENAME=resolute
LOGO=mytical
EOF

    if [ -d "$SDDM_THEME_SRC" ]; then
        install -d -- "$ROOTFS_DIR/usr/share/sddm/themes/mytical"
        cp -a --no-preserve=ownership -- "$SDDM_THEME_SRC/." "$ROOTFS_DIR/usr/share/sddm/themes/mytical/"
    elif [ ! -d "$ROOTFS_DIR/usr/share/sddm/themes/mytical" ]; then
        die "falta el tema SDDM mytical en $SDDM_THEME_SRC y en el rootfs"
    fi

    # El tema de SDDM usa un fondo CC0 propio; no se copia arte de Ubuntu.
    install -m 0644 -- "${wallpapers[0]}" \
        "$ROOTFS_DIR/usr/share/sddm/themes/mytical/Backgrounds/wallpaper"

    install -d -- "$ROOTFS_DIR/etc/sddm.conf.d"
    cat > "$ROOTFS_DIR/etc/sddm.conf.d/90-mytical.conf" <<'EOF'
[Theme]
Current=mytical

[General]
DisplayServer=x11
SessionDir=/usr/share/wayland-sessions
EOF

    # Sin logos de Ubuntu: el tema oficial de SDDM no se selecciona y, si la
    # ISO base lo trae, se retira del rootfs para no ofrecerlo en el greeter.
    if [ -d "$ROOTFS_DIR/usr/share/sddm/themes/ubuntu" ]; then
        rm -rf -- "$ROOTFS_DIR/usr/share/sddm/themes/ubuntu"
        info "retirado el tema SDDM de Ubuntu"
    fi

    info "branding: ${#wallpapers[@]} wallpapers CC0, os-release y SDDM mytical"
}

assert_no_nix() {
    log "8/12 verificar que no hay /nix"
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
    log "9/12 recomprimir squashfs"
    rm -f -- "$NEW_SQUASHFS"
    mksquashfs "$ROOTFS_DIR" "$NEW_SQUASHFS" \
        -noappend -comp xz -b 1M -Xdict-size 100% -no-progress
    update_casper_size
}

update_casper_metadata() {
    local manifest="$ISO_TREE/casper/filesystem.manifest"

    log "10/12 metadatos de casper"
    [ -d "$ISO_TREE/casper" ] || die "falta el arbol /casper en $ISO_TREE"

    # El squashfs nuevo se mueve dentro del arbol extraido (mismo filesystem)
    # para que md5sum.txt describa exactamente lo que va a montar el remux.
    if [ -f "$NEW_SQUASHFS" ]; then
        mv -f -- "$NEW_SQUASHFS" "$ISO_TREE/casper/filesystem.squashfs"
        NEW_SQUASHFS="$ISO_TREE/casper/filesystem.squashfs"
    fi
    [ -f "$ISO_TREE/casper/filesystem.squashfs" ] ||
        die "falta casper/filesystem.squashfs en $ISO_TREE"

    update_casper_size

    if [ -x "$ROOTFS_DIR/usr/bin/dpkg-query" ]; then
        # shellcheck disable=SC2016
        chroot "$ROOTFS_DIR" dpkg-query -W -f='${Package} ${Version}\n' > "$manifest"
        info "filesystem.manifest regenerado"
    elif [ -s "$manifest" ]; then
        info "filesystem.manifest conservado del rootfs base"
    else
        warn "no se pudo regenerar filesystem.manifest (falta dpkg-query en el chroot)"
    fi

    (
        cd -- "$ISO_TREE"
        rm -f -- md5sum.txt
        find . -type f ! -name 'md5sum.txt' -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r md5sum > md5sum.txt
    )
    info "filesystem.size y md5sum.txt regenerados"
    # TODO(iso): comprobar md5sum.txt contra la ISO final exige ejecutar el
    # remux y montar la imagen. Sin ISO no se puede validar en este repo.
    info "TODO(iso): validacion de md5sum.txt contra la ISO final pendiente de build"
}

rebuild_iso() {
    log "11/12 remux de la ISO (conserva shim/GRUB/kernel)"
    [ -f "$NEW_SQUASHFS" ] || die "falta el squashfs nuevo: $NEW_SQUASHFS"
    [ -f "$ISO_TREE/md5sum.txt" ] || die "falta $ISO_TREE/md5sum.txt"
    mkdir -p -- "$(dirname -- "$OUT")"
    rm -f -- "$OUT"

    local -a maps=(
        -map "$NEW_SQUASHFS" /casper/filesystem.squashfs
        -map "$ISO_TREE/casper/filesystem.size" /casper/filesystem.size
        -map "$ISO_TREE/md5sum.txt" /md5sum.txt
    )
    if [ -f "$ISO_TREE/casper/filesystem.manifest" ]; then
        maps+=(-map "$ISO_TREE/casper/filesystem.manifest" /casper/filesystem.manifest)
    fi

    xorriso -indev "$ISO" -outdev "$OUT" -boot_image any keep \
        "${maps[@]}" \
        -commit
}

write_checksum() {
    local base dir
    base="$(basename -- "$OUT")"
    dir="$(dirname -- "$OUT")"
    log "12/12 checksum"
    ( cd -- "$dir" && sha256sum -- "$base" > "$base.sha256" )
    info "OK: $OUT"
    info "SHA256: $(cut -d' ' -f1 -- "$OUT.sha256")"
}

build_iso() {
    assert_implemented
    [ -n "$REPO" ] ||
        die "falta --repo: el build necesita el repo APT local (dists/mytical/ y clave publica)."
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
        info "Repo:  ${REPO:-(ninguno; obligatorio en build)}"
        info "Salida prevista: $OUT"
        exit 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        print_plan
        exit 0
    fi

    build_iso
}

# Permite que los tests hagan `source remaster.sh` y llamen a las funciones
# sin ejecutar main. El script normal sigue igual.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
