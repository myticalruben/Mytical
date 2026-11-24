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
#
# Layout de casper: Ubuntu 26.04 publica el rootfs como
# casper/minimal.standard.squashfs (con minimal.standard.size/.manifest e
# install-sources.yaml). Las ISO anteriores usan casper/filesystem.squashfs
# con filesystem.size/.manifest. El script detecta uno de los dos y deriva de
# ese nombre sus metadatos.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
NIX_SOURCE="${MYTICAL_NIX_SOURCE:-/nix}"
ISO_TREE="$WORK_DIR/iso"
ROOTFS_DIR="$WORK_DIR/rootfs"
NEW_SQUASHFS="$WORK_DIR/rootfs.squashfs"

# Squashfs soportados, en orden de preferencia. "minimal.standard" es el
# layout de 26.04; "filesystem" queda como compatibilidad con ISO anteriores.
SQUASHFS_CANDIDATES=(minimal.standard.squashfs filesystem.squashfs)
SQUASHFS_NAME=""
SQUASHFS_BASE=""

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

# Fija el squashfs elegido y el prefijo de sus metadatos. Todo el pipeline lee
# $SQUASHFS_NAME (squashfs) y $SQUASHFS_BASE (size/manifest) en vez de asumir
# filesystem.*, de modo que el layout nuevo y el antiguo comparten codigo.
set_squashfs_name() {
    case "$1" in
        minimal.standard.squashfs|filesystem.squashfs) ;;
        *) die "squashfs de casper no soportado: $1" ;;
    esac
    SQUASHFS_NAME="$1"
    SQUASHFS_BASE="${1%.squashfs}"
}

# Elige el squashfs a partir de un listing de /casper (lineas /casper/...).
# Prefiere minimal.standard.squashfs: es el rootfs principal en 26.04.
resolve_squashfs_from_listing() {
    local listing="$1" candidate
    for candidate in "${SQUASHFS_CANDIDATES[@]}"; do
        if grep -qxF -- "/casper/$candidate" <<<"$listing"; then
            set_squashfs_name "$candidate"
            return 0
        fi
    done
    return 1
}

# Elige el squashfs a partir del arbol ya extraido. Respeta $SQUASHFS_NAME si
# viene fijado y existe; si no, detecta el layout por presencia de archivos.
resolve_squashfs_from_tree() {
    local candidate
    if [ -n "$SQUASHFS_NAME" ] && [ -f "$ISO_TREE/casper/$SQUASHFS_NAME" ]; then
        set_squashfs_name "$SQUASHFS_NAME"
        return 0
    fi
    for candidate in "${SQUASHFS_CANDIDATES[@]}"; do
        if [ -f "$ISO_TREE/casper/$candidate" ]; then
            set_squashfs_name "$candidate"
            return 0
        fi
    done
    return 1
}

check_iso_layout() {
    local listing
    info "leyendo el arbol de $ISO"
    if ! listing="$(xorriso -indev "$ISO" -find /casper -maxdepth 1 2>/dev/null)"; then
        die "xorriso no pudo leer la ISO: $ISO"
    fi
    # xorriso -find entrecomilla las rutas; normalizar para comparar.
    listing="${listing//\'/}"

    if ! resolve_squashfs_from_listing "$listing"; then
        die "la ISO no trae /casper/minimal.standard.squashfs ni /casper/filesystem.squashfs; no parece Ubuntu desktop"
    fi
    if ! grep -qx '/casper/vmlinuz' <<<"$listing"; then
        die "la ISO no trae /casper/vmlinuz; no parece Ubuntu desktop"
    fi

    info "squashfs de origen: casper/$SQUASHFS_NAME"
    if [ "$SQUASHFS_BASE" = "minimal.standard" ]; then
        if grep -qx '/casper/install-sources.yaml' <<<"$listing"; then
            info "metadata: minimal.standard.size/.manifest + install-sources.yaml"
        else
            warn "la ISO usa minimal.standard.squashfs pero no trae casper/install-sources.yaml"
        fi
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
    info "Layout casper  : casper/$SQUASHFS_NAME ($SQUASHFS_BASE.size, $SQUASHFS_BASE.manifest)"
    info ""
    info "  1. validar ISO y /casper ................. hecho"
    info "  2. crear work y extraer la ISO ............ xorriso -osirrox"
    info "  3. extraer el squashfs elegido ............ unsquashfs casper/$SQUASHFS_NAME"
    info "  4. copiar el repo local ................... /opt/mytical/apt"
    info "  4b. copiar /nix y Home Manager ............. cierre Nix de la ISO"
    info "  5. chroot: APT instala package-lists ...... apt-get, --no-install-recommends"
    info "  6. copiar Calamares, modulos y branding ... /etc/calamares"
    info "  7. aplicar branding y licencias ........... /etc/os-release + SDDM mytical"
    info "  8. verificar que no hay /nix .............. obligatorio"
    info "  9. recomprimir squashfs ................... mksquashfs + xz"
    info " 10. metadata: $SQUASHFS_BASE.size/manifest, install-sources.yaml y md5sum.txt"
    info " 11. remux con /casper/$SQUASHFS_NAME ......... xorriso -boot_image keep"
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

    for module in install_mytical_packages apply_branding update_casper_size \
        update_install_sources update_casper_metadata rebuild_iso; do
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
    resolve_squashfs_from_tree ||
        die "no hay casper/minimal.standard.squashfs ni casper/filesystem.squashfs en $ISO_TREE"
    info "extrayendo casper/$SQUASHFS_NAME"
    rm -rf -- "$ROOTFS_DIR"
    unsquashfs -d "$ROOTFS_DIR" "$ISO_TREE/casper/$SQUASHFS_NAME" >/dev/null
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

stage_nix() {
    log "4b/12 copiar cierre Nix y Home Manager"
    [ -x "$NIX_SOURCE/var/nix/profiles/default/bin/nix" ] ||
        die "no existe Nix en $NIX_SOURCE; definí MYTICAL_NIX_SOURCE"
    [ -d "$SOURCE_ROOT/nix" ] || die "falta el arbol Nix en $SOURCE_ROOT"

    cp -a "$NIX_SOURCE" "$ROOTFS_DIR/nix"
    install -d "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/etc/nix" "$ROOTFS_DIR/etc/profile.d"
    if [ -e "$ROOTFS_DIR/nix/var/nix/profiles/default/bin/nix" ]; then
        ln -sfn /nix/var/nix/profiles/default/bin/nix "$ROOTFS_DIR/usr/bin/nix"
    fi

    # Home Manager del perfil de build: el cierre ya trae sus dependencias.
    hm="$(readlink -f /home/mytical/.nix-profile/bin/home-manager 2>/dev/null || true)"
    if [ -n "$hm" ] && [ -x "$hm" ]; then
        ln -sfn "$hm" "$ROOTFS_DIR/usr/bin/home-manager"
    else
        die "no se encontro home-manager en /home/mytical/.nix-profile"
    fi

    for unit in nix-daemon.service nix-daemon.socket; do
        for src in "/etc/systemd/system/$unit" "/lib/systemd/system/$unit" "/usr/lib/systemd/system/$unit"; do
            [ -f "$src" ] && cp -a "$src" "$ROOTFS_DIR/etc/systemd/system/$unit" && break
        done
    done
    install -d "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"         "$ROOTFS_DIR/etc/systemd/system/sockets.target.wants"
    [ -e "$ROOTFS_DIR/etc/systemd/system/nix-daemon.service" ] &&
        ln -sfn /etc/systemd/system/nix-daemon.service             "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/nix-daemon.service"
    [ -e "$ROOTFS_DIR/etc/systemd/system/nix-daemon.socket" ] &&
        ln -sfn /etc/systemd/system/nix-daemon.socket             "$ROOTFS_DIR/etc/systemd/system/sockets.target.wants/nix-daemon.socket"
    [ -f /etc/nix/nix.conf ] && cp -a /etc/nix/nix.conf "$ROOTFS_DIR/etc/nix/nix.conf"
    [ -f /etc/profile.d/nix.sh ] && cp -a /etc/profile.d/nix.sh "$ROOTFS_DIR/etc/profile.d/nix.sh"

    install -d "$ROOTFS_DIR/usr/share/mytical/dotfiles"
    tar -C "$SOURCE_ROOT" -cf -         flake.nix flake.lock nix hypr waybar quickshell wlogout rofi dunst         kitty btop gtk scripts 2>/dev/null |
        tar -C "$ROOTFS_DIR/usr/share/mytical/dotfiles" -xf -
    ln -sfn /usr/share/mytical/dotfiles "$ROOTFS_DIR/etc/skel/.dotfiles"

    install -d "$ROOTFS_DIR/etc/skel/Pictures/Wallpapers"
    if [ -d "$ROOTFS_DIR/usr/share/backgrounds/mytical" ]; then
        cp -a "$ROOTFS_DIR/usr/share/backgrounds/mytical/."             "$ROOTFS_DIR/etc/skel/Pictures/Wallpapers/"
    fi
    info "Nix copiado; Home Manager: $hm; configs: /usr/share/mytical/dotfiles"
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
    local unpackfs="$ROOTFS_DIR/etc/calamares/modules/unpackfs.conf"

    log "6/12 copiar Calamares"
    install -d -- "$ROOTFS_DIR/etc/calamares/modules"
    install -d -- "$ROOTFS_DIR/usr/share/calamares/branding/mytical"
    install -m 0644 -- "$SCRIPT_DIR/calamares/settings.conf" \
        "$ROOTFS_DIR/etc/calamares/settings.conf"
    cp -a --no-preserve=ownership -- "$SCRIPT_DIR/calamares/modules/." \
        "$ROOTFS_DIR/etc/calamares/modules/"
    cp -a --no-preserve=ownership -- "$SCRIPT_DIR/calamares/branding/mytical/." \
        "$ROOTFS_DIR/usr/share/calamares/branding/mytical/"

    # unpackfs.conf se versiona con el nombre del layout nuevo. Si la ISO de
    # entrada usa filesystem.squashfs, el instalador debe copiar ese nombre:
    # se reescribe solo la linea source de la copia que va al rootfs.
    [ -n "$SQUASHFS_NAME" ] ||
        die "SQUASHFS_NAME sin resolver; no se puede configurar unpackfs.conf"
    sed -i -E \
        "s|^([[:space:]]*-[[:space:]]*source:[[:space:]]*\")/cdrom/casper/[^\"]*\"|\1/cdrom/casper/$SQUASHFS_NAME\"|" \
        "$unpackfs"
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

assert_nix() {
    log "8/12 verificar el cierre Nix"
    [ -x "$ROOTFS_DIR/nix/var/nix/profiles/default/bin/nix" ] ||
        die "falta el binario Nix en el rootfs"
    [ -x "$ROOTFS_DIR/usr/bin/home-manager" ] ||
        die "falta home-manager en el rootfs"
    [ -x "$ROOTFS_DIR/usr/bin/mytical-nix-activate" ] ||
        die "falta mytical-nix-activate en el rootfs"
}

update_casper_size() {
    local bytes size_file
    resolve_squashfs_from_tree ||
        die "no hay squashfs de casper en $ISO_TREE; no se puede nombrar el .size"
    bytes="$(du -sx --block-size=1 "$ROOTFS_DIR" | cut -f1)"
    size_file="$ISO_TREE/casper/$SQUASHFS_BASE.size"
    printf '%s\n' "$bytes" > "$size_file"
    info "casper/$SQUASHFS_BASE.size = $bytes (rootfs sin comprimir)"
}

# install-sources.yaml lo consume el instalador para elegir la imagen que
# copia. Solo se toca la entrada standard: las variantes de idioma y enhanced
# describen otros squashfs y conservan su path/size. El size se refiere al
# squashfs comprimido, no al rootfs sin comprimir.
update_install_sources() {
    local sources="$ISO_TREE/casper/install-sources.yaml"
    local squashfs="$ISO_TREE/casper/$SQUASHFS_NAME"
    local tmp bytes

    if [ ! -f "$sources" ]; then
        info "sin casper/install-sources.yaml (layout antiguo); nada que actualizar"
        return 0
    fi
    [ -f "$squashfs" ] ||
        die "falta casper/$SQUASHFS_NAME; no se puede calcular su tamano para install-sources.yaml"
    bytes="$(stat -c '%s' -- "$squashfs")"

    tmp="$sources.mytical.tmp"
    if ! awk -v squashfs="$SQUASHFS_NAME" -v bytes="$bytes" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function unquote(s,   first, last) {
            if (length(s) >= 2) {
                first = substr(s, 1, 1)
                last = substr(s, length(s), 1)
                if ((first == "\"" && last == "\"") || (first == "\047" && last == "\047"))
                    s = substr(s, 2, length(s) - 2)
            }
            return s
        }
        function key_of(line,   rest) {
            rest = line
            sub(/^[[:space:]]*(-[[:space:]]+)?/, "", rest)
            if (rest !~ /^[A-Za-z0-9_.-]+[[:space:]]*:/)
                return ""
            return trim(substr(rest, 1, index(rest, ":") - 1))
        }
        function value_of(line,   rest) {
            rest = line
            sub(/^[[:space:]]*(-[[:space:]]+)?/, "", rest)
            sub(/^[^:]*:/, "", rest)
            return unquote(trim(rest))
        }
        function indent_of(line) {
            match(line, /^[[:space:]]*/)
            return RLENGTH
        }
        {
            line[NR] = $0
            if ($0 ~ /^[[:space:]]*-[[:space:]]/) {
                indent = indent_of($0)
                if (dashes == 0 || indent < min_indent)
                    min_indent = indent
                dashes++
            }
        }
        END {
            n = NR
            blocks = 0
            if (dashes > 0) {
                # Las entradas de la lista comparten la indentacion minima; las
                # listas anidadas (description, name) quedan dentro del bloque.
                for (i = 1; i <= n; i++) {
                    if (line[i] ~ /^[[:space:]]*-[[:space:]]/ && indent_of(line[i]) == min_indent) {
                        blocks++
                        start[blocks] = i
                    }
                }
            } else {
                blocks = 1
                start[1] = 1
            }

            for (b = 1; b <= blocks; b++) {
                first = start[b]
                last = (b < blocks ? start[b + 1] - 1 : n)
                for (i = first; i <= last; i++) {
                    key = key_of(line[i])
                    if (key == "id") {
                        id[b] = value_of(line[i])
                    } else if (key == "path") {
                        path_value[b] = value_of(line[i])
                        path_line[b] = i
                        path_count[b]++
                    } else if (key == "size") {
                        size_value[b] = value_of(line[i])
                        size_line[b] = i
                        size_count[b]++
                    }
                }
            }

            # Preferencia: entrada con id exacto "standard". Si el esquema no
            # trae id, se acepta la unica entrada cuyo path apunte al squashfs.
            selected = 0
            matches = 0
            for (b = 1; b <= blocks; b++)
                if (id[b] == "standard") { selected = b; matches++ }
            if (matches == 0) {
                for (b = 1; b <= blocks; b++)
                    if (path_value[b] == squashfs) { selected = b; matches++ }
            }
            if (matches == 0) {
                printf("install-sources.yaml: no se encontro la entrada standard ni un path %s\n", squashfs) > "/dev/stderr"
                exit 3
            }
            if (matches > 1) {
                printf("install-sources.yaml: %d entradas candidatas; no se modifica\n", matches) > "/dev/stderr"
                exit 4
            }
            if (path_count[selected] != 1 || size_count[selected] != 1) {
                printf("install-sources.yaml: la entrada standard no declara un unico path/size\n") > "/dev/stderr"
                exit 5
            }

            for (i = 1; i <= n; i++) {
                if (i == path_line[selected]) {
                    print substr(line[i], 1, index(line[i], "path") - 1) "path: " squashfs
                } else if (i == size_line[selected]) {
                    print substr(line[i], 1, index(line[i], "size") - 1) "size: " bytes
                } else {
                    print line[i]
                }
            }
        }
    ' "$sources" > "$tmp"; then
        rm -f -- "$tmp"
        die "no se pudo actualizar la entrada standard de casper/install-sources.yaml"
    fi
    mv -f -- "$tmp" "$sources"
    info "casper/install-sources.yaml: standard -> $SQUASHFS_NAME ($bytes bytes)"
}

repack_squashfs() {
    log "9/12 recomprimir squashfs"
    rm -f -- "$NEW_SQUASHFS"
    mksquashfs "$ROOTFS_DIR" "$NEW_SQUASHFS" \
        -noappend -comp xz -b 1M -Xdict-size 100% -no-progress
}

update_casper_metadata() {
    local manifest squashfs

    log "10/12 metadatos de casper"
    [ -d "$ISO_TREE/casper" ] || die "falta el arbol /casper en $ISO_TREE"
    resolve_squashfs_from_tree ||
        die "no hay casper/minimal.standard.squashfs ni casper/filesystem.squashfs en $ISO_TREE"

    squashfs="$ISO_TREE/casper/$SQUASHFS_NAME"
    manifest="$ISO_TREE/casper/$SQUASHFS_BASE.manifest"

    # El squashfs nuevo se mueve dentro del arbol extraido (mismo filesystem)
    # para que md5sum.txt describa exactamente lo que va a montar el remux.
    if [ -f "$NEW_SQUASHFS" ] && [ "$NEW_SQUASHFS" != "$squashfs" ]; then
        mv -f -- "$NEW_SQUASHFS" "$squashfs"
        NEW_SQUASHFS="$squashfs"
    fi
    [ -f "$squashfs" ] || die "falta casper/$SQUASHFS_NAME en $ISO_TREE"

    update_casper_size
    update_install_sources

    if [ -x "$ROOTFS_DIR/usr/bin/dpkg-query" ]; then
        # shellcheck disable=SC2016
        chroot "$ROOTFS_DIR" dpkg-query -W -f='${Package} ${Version}\n' > "$manifest"
        info "casper/$SQUASHFS_BASE.manifest regenerado"
    elif [ -s "$manifest" ]; then
        info "casper/$SQUASHFS_BASE.manifest conservado del rootfs base"
    else
        warn "no se pudo regenerar casper/$SQUASHFS_BASE.manifest (falta dpkg-query en el chroot)"
    fi

    (
        cd -- "$ISO_TREE"
        rm -f -- md5sum.txt
        find . -type f ! -name 'md5sum.txt' -print0 |
            LC_ALL=C sort -z |
            xargs -0 -r md5sum > md5sum.txt
    )
    info "casper/$SQUASHFS_BASE.size, install-sources.yaml y md5sum.txt regenerados"
    # TODO(iso): comprobar md5sum.txt contra la ISO final exige ejecutar el
    # remux y montar la imagen. Sin ISO no se puede validar en este repo.
    info "TODO(iso): validacion de md5sum.txt contra la ISO final pendiente de build"
}

rebuild_iso() {
    local -a maps=()
    local squashfs size manifest sources

    log "11/12 remux de la ISO (conserva shim/GRUB/kernel)"
    resolve_squashfs_from_tree ||
        die "no hay casper/minimal.standard.squashfs ni casper/filesystem.squashfs en $ISO_TREE"

    squashfs="$ISO_TREE/casper/$SQUASHFS_NAME"
    size="$ISO_TREE/casper/$SQUASHFS_BASE.size"
    manifest="$ISO_TREE/casper/$SQUASHFS_BASE.manifest"
    sources="$ISO_TREE/casper/install-sources.yaml"

    [ -f "$NEW_SQUASHFS" ] || die "falta el squashfs nuevo: $NEW_SQUASHFS"
    [ -f "$squashfs" ] || die "falta casper/$SQUASHFS_NAME en $ISO_TREE"
    [ -f "$ISO_TREE/md5sum.txt" ] || die "falta $ISO_TREE/md5sum.txt"
    mkdir -p -- "$(dirname -- "$OUT")"
    rm -f -- "$OUT"

    maps=(
        -map "$squashfs" "/casper/$SQUASHFS_NAME"
        -map "$size" "/casper/$SQUASHFS_BASE.size"
        -map "$ISO_TREE/md5sum.txt" /md5sum.txt
    )
    if [ -f "$manifest" ]; then
        maps+=(-map "$manifest" "/casper/$SQUASHFS_BASE.manifest")
    fi
    if [ -f "$sources" ]; then
        maps+=(-map "$sources" /casper/install-sources.yaml)
    fi

    info "squashfs: /casper/$SQUASHFS_NAME + $SQUASHFS_BASE.size/manifest"

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
    stage_nix
    assert_nix
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
        info "Casper: $SQUASHFS_NAME"
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
