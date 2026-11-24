#!/usr/bin/env bash
# Tests locales del pipeline de la ISO V1.1.
#
# Sin red, sin descargas, sin root y sin construir la ISO. Valida sintaxis,
# que `make build` falle sin ISO, que la lista no incluya /nix ni GNOME, que
# Calamares/branding/documentacion tengan la forma esperada y que las funciones
# nuevas se comporten sin tocar work/ ni ejecutar mksquashfs.
set -uo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd -- "$ISO_DIR/../.." && pwd)"
REMASTER="$ISO_DIR/remaster.sh"
LIST="$ISO_DIR/package-lists/mytical.list"
DOC="$REPO_ROOT/docs/distro/ISO.md"
CALAMARES="$ISO_DIR/calamares"
MODULES=(partition unpackfs bootloader users locale keyboard displaymanager finished)

checks=0
failures=0

pass() { checks=$((checks + 1)); printf 'OK    %s\n' "$*"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf 'FALLA %s\n' "$*" >&2; }
skip() { printf 'SKIP  %s\n' "$*"; }

expect_file() {
    local path="$1" label="$2"
    if [ -s "$path" ]; then
        pass "$label"
    else
        fail "$label (falta o esta vacio: ${path#"$REPO_ROOT"/})"
    fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mytical-iso-test.XXXXXX")"
cleanup_tests() {
    case "$TMP_ROOT" in
        /tmp/mytical-iso-test.*|/var/tmp/mytical-iso-test.*|*/mytical-iso-test.*)
            rm -rf -- "$TMP_ROOT"
            ;;
    esac
}
trap cleanup_tests EXIT

# ---------------------------------------------------------------------------
# 1. Archivos y sintaxis
# ---------------------------------------------------------------------------

expect_file "$ISO_DIR/README.md" "README del esqueleto"
expect_file "$ISO_DIR/Makefile" "Makefile"
expect_file "$REMASTER" "remaster.sh"
expect_file "$LIST" "lista de paquetes"
expect_file "$CALAMARES/settings.conf" "Calamares settings.conf"
expect_file "$CALAMARES/branding/mytical/branding.desc" "branding.desc"
expect_file "$DOC" "docs/distro/ISO.md"

for script in "$REMASTER" "$ISO_DIR/tests/test_iso_scaffold.sh"; do
    if bash -n "$script" 2>/dev/null; then
        pass "sintaxis bash: ${script#"$REPO_ROOT"/}"
    else
        fail "sintaxis bash: ${script#"$REPO_ROOT"/}"
    fi
done

if [ -x "$REMASTER" ]; then
    pass "remaster.sh es ejecutable"
else
    fail "remaster.sh no es ejecutable"
fi

# ---------------------------------------------------------------------------
# 2. Interfaz del script y targets del Makefile
# ---------------------------------------------------------------------------

if help="$("$REMASTER" --help 2>&1)"; then
    pass "remaster.sh --help"
    for flag in --iso --out --dry-run --repo; do
        if grep -q -- "$flag" <<<"$help"; then
            pass "la ayuda documenta $flag"
        else
            fail "la ayuda no menciona $flag"
        fi
    done
else
    fail "remaster.sh --help devuelve error"
fi

for target in check build clean test; do
    if grep -Eq "^${target}:" "$ISO_DIR/Makefile"; then
        pass "target make $target"
    else
        fail "falta el target make $target"
    fi
done

# ---------------------------------------------------------------------------
# 3. build sin ISO falla y no prepara work/
# ---------------------------------------------------------------------------

work_before=0
[ -e "$ISO_DIR/work" ] && work_before=1

build_out="$(make -C "$ISO_DIR" build ISO= 2>&1)"
build_status=$?
if [ "$build_status" -ne 0 ]; then
    pass "make build sin ISO falla (exit $build_status)"
else
    fail "make build sin ISO devuelve exito"
fi

if grep -qi 'ISO' <<<"$build_out"; then
    pass "el error de build sin ISO menciona la ISO"
else
    fail "el error de build sin ISO no explica que falta la ISO"
fi

if [ "$work_before" -eq 1 ] || [ ! -e "$ISO_DIR/work" ]; then
    pass "build sin ISO no crea work/"
else
    fail "build sin ISO creo work/"
fi

dry_out="$(cd "$ISO_DIR" && "$REMASTER" --dry-run 2>&1)"
dry_status=$?
if [ "$dry_status" -ne 0 ]; then
    pass "--dry-run sin ISO falla (exit $dry_status)"
else
    fail "--dry-run sin ISO devuelve exito"
fi

if grep -q -- '--iso' <<<"$dry_out"; then
    pass "el error de dry-run sin ISO menciona --iso"
else
    fail "el error de dry-run sin ISO no es accionable"
fi

# ---------------------------------------------------------------------------
# 4. Lista de paquetes
# ---------------------------------------------------------------------------

mapfile -t packages < <(
    awk '{
        sub(/#.*/, "")
        gsub(/[[:space:]]/, "")
        if ($0 != "") print
    }' "$LIST"
)

if [ "${#packages[@]}" -gt 0 ]; then
    pass "la lista tiene ${#packages[@]} paquetes activos"
else
    fail "la lista no tiene paquetes activos"
fi

if grep -q '/nix' "$LIST"; then
    fail "la lista contiene /nix"
else
    pass "la lista no contiene /nix"
fi

has_package() {
    local wanted="$1" pkg
    for pkg in "${packages[@]}"; do
        [ "$pkg" = "$wanted" ] && return 0
    done
    return 1
}

for prohibited in ubuntu-session gdm3 gnome-shell ubuntu-desktop ubuntu-desktop-minimal; do
    if has_package "$prohibited"; then
        fail "paquete GNOME prohibido en la lista: $prohibited"
    else
        pass "la lista no incluye $prohibited"
    fi
done

for required in casper calamares mytical-session sddm; do
    if has_package "$required"; then
        pass "la lista incluye $required"
    else
        fail "la lista no incluye $required"
    fi
done

# ---------------------------------------------------------------------------
# 5. Calamares, modulos y branding sin binarios
# ---------------------------------------------------------------------------

settings="$CALAMARES/settings.conf"
if grep -Eq '^branding:[[:space:]]*mytical$' "$settings"; then
    pass "settings.conf usa el branding mytical"
else
    fail "settings.conf no declara 'branding: mytical'"
fi

for module in welcome partition unpackfs bootloader users locale keyboard displaymanager finished; do
    if grep -q -- "$module" "$settings"; then
        pass "settings.conf referencia el modulo $module"
    else
        fail "settings.conf no referencia el modulo $module"
    fi
done

for module in "${MODULES[@]}"; do
    expect_file "$CALAMARES/modules/$module.conf" "modulo Calamares: $module.conf"
done

# Todos los .conf que viajan al instalador deben estar referenciados por la
# secuencia o por una instancia; si sobra uno, settings.conf no es coherente.
while IFS= read -r conf; do
    module="$(basename -- "$conf" .conf)"
    if grep -q -- "$module" "$settings"; then
        pass "settings.conf conoce modules/$module.conf"
    else
        fail "modules/$module.conf no aparece en settings.conf"
    fi
done < <(find "$CALAMARES/modules" -maxdepth 1 -type f -name '*.conf' | LC_ALL=C sort)

if grep -q $'\t' "$settings"; then
    fail "settings.conf contiene tabuladores (YAML no los acepta)"
else
    pass "settings.conf no contiene tabuladores"
fi

for conf in "$CALAMARES"/modules/*.conf; do
    if grep -q $'\t' "$conf"; then
        fail "modules/$(basename -- "$conf") contiene tabuladores"
    else
        pass "modules/$(basename -- "$conf") es YAML sin tabuladores"
    fi
done

if grep -Fq '/cdrom/casper/minimal.standard.squashfs' "$CALAMARES/modules/unpackfs.conf"; then
    pass "unpackfs.conf apunta a minimal.standard.squashfs"
else
    fail "unpackfs.conf no apunta a /cdrom/casper/minimal.standard.squashfs"
fi

if grep -Fq '/cdrom/casper/filesystem.squashfs' "$CALAMARES/modules/unpackfs.conf"; then
    fail "unpackfs.conf sigue apuntando a filesystem.squashfs"
else
    pass "unpackfs.conf no hardcodea filesystem.squashfs"
fi

if grep -Eq '^efiBootLoader:[[:space:]]*"grub"' "$CALAMARES/modules/bootloader.conf"; then
    pass "bootloader.conf instala GRUB"
else
    fail "bootloader.conf no declara GRUB"
fi

if grep -Eq '^[[:space:]]+-[[:space:]]*sddm$' "$CALAMARES/modules/displaymanager.conf" &&
   grep -qF 'mytical-session' "$CALAMARES/modules/displaymanager.conf"; then
    pass "displaymanager.conf usa SDDM y la sesion Mytical"
else
    fail "displaymanager.conf no usa SDDM/sesion Mytical"
fi

if python3 -c 'import yaml' >/dev/null 2>&1; then
    if python3 - "$CALAMARES" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob("*.conf")):
    with path.open(encoding="utf-8") as handle:
        yaml.safe_load(handle)
PY
    then
        pass "YAML de Calamares parseable (PyYAML)"
    else
        fail "YAML de Calamares invalido"
    fi
else
    skip "PyYAML no esta instalado; no se parsea el YAML de Calamares"
fi

branding="$CALAMARES/branding/mytical/branding.desc"
if grep -Eq '^componentName:[[:space:]]*mytical$' "$branding" &&
   grep -Eq '^[[:space:]]+productName:[[:space:]]*Mytical$' "$branding"; then
    pass "branding.desc identifica a Mytical"
else
    fail "branding.desc no identifica a Mytical"
fi

if find "$CALAMARES" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \
    -o -name '*.webp' -o -name '*.ico' -o -name '*.gif' \) -print -quit | grep -q .; then
    fail "hay imagenes binarias en calamares/"
else
    pass "calamares/ no contiene imagenes binarias"
fi

while IFS= read -r file; do
    if grep -Iq . "$file"; then
        pass "texto plano: ${file#"$REPO_ROOT"/}"
    else
        fail "archivo binario o vacio en calamares/: ${file#"$REPO_ROOT"/}"
    fi
done < <(find "$CALAMARES" -type f | sort)

# ---------------------------------------------------------------------------
# 6. Implementacion de las funciones del pipeline
# ---------------------------------------------------------------------------

if grep -Eq '^BUILD_IMPLEMENTED=1$' "$REMASTER"; then
    pass "el gate del build esta abierto"
else
    fail "BUILD_IMPLEMENTED no es 1"
fi

for function_name in install_mytical_packages apply_branding update_casper_size \
    update_install_sources update_casper_metadata rebuild_iso; do
    if grep -Eq "^${function_name}\(\)" "$REMASTER"; then
        pass "remaster.sh define $function_name()"
    else
        fail "remaster.sh no define $function_name()"
    fi
done

for squashfs in minimal.standard.squashfs filesystem.squashfs; do
    if grep -Fq "$squashfs" "$REMASTER"; then
        pass "remaster.sh contempla $squashfs"
    else
        fail "remaster.sh no contempla $squashfs"
    fi
done

if grep -q -- '--no-install-recommends' "$REMASTER"; then
    pass "el chroot APT usa --no-install-recommends"
else
    fail "el chroot APT no usa --no-install-recommends"
fi

if grep -q 'Signed-By' "$REMASTER"; then
    pass "el repo local se configura con Signed-By"
else
    fail "el repo local no se configura con Signed-By"
fi

if grep -Eq 'apt-get[^\n]*autoremove|autoremove[^\n]*apt-get' "$REMASTER"; then
    fail "el pipeline llama a apt-get autoremove"
else
    pass "el pipeline no llama a apt-get autoremove"
fi

if grep -Fq '/etc/os-release' "$REMASTER" &&
   grep -Fq 'ID=mytical' "$REMASTER"; then
    pass "apply_branding escribe un os-release Mytical"
else
    fail "apply_branding no escribe un os-release Mytical"
fi

if grep -Fq 'SQUASHFS_BASE.size' "$REMASTER" &&
   grep -Fq 'install-sources.yaml' "$REMASTER" &&
   grep -Fq 'md5sum.txt' "$REMASTER"; then
    pass "update_casper_metadata toca el .size, install-sources.yaml y md5sum"
else
    fail "update_casper_metadata no regenera size/install-sources/md5sum"
fi

# ---------------------------------------------------------------------------
# 7. Deteccion del layout de casper: minimal.standard (26.04) y filesystem
# ---------------------------------------------------------------------------

# Stub de xorriso que devuelve el listing pedido; mksquashfs no hace nada y
# unsquashfs solo registra el squashfs elegido. Nada real se ejecuta.
make_iso_stubs() {
    local dir="$1"
    shift
    mkdir -p "$dir"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'printf "%%s\\n"'
        printf ' %q' "$@"
        printf '\n'
    } > "$dir/xorriso"
    cat > "$dir/mksquashfs" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat > "$dir/unsquashfs" <<'STUB'
#!/usr/bin/env bash
printf 'unsquashfs %s\n' "$*" >> "${STUB_LOG:-/dev/null}"
exit 0
STUB
    chmod +x "$dir/xorriso" "$dir/mksquashfs" "$dir/unsquashfs"
}

new_listing=(/casper /casper/minimal.standard.squashfs /casper/minimal.standard.size
    /casper/minimal.standard.manifest /casper/install-sources.yaml /casper/vmlinuz)
old_listing=(/casper /casper/filesystem.squashfs /casper/filesystem.size
    /casper/filesystem.manifest /casper/vmlinuz)
make_iso_stubs "$TMP_ROOT/stub-new" "${new_listing[@]}"
make_iso_stubs "$TMP_ROOT/stub-old" "${old_listing[@]}"

# Resuelve el layout con el mismo codigo que usa remaster.sh --check.
probe_layout() {
    LISTING="$1" bash -c '
        source "$1"
        resolve_squashfs_from_listing "$LISTING" || exit 1
        printf "%s|%s\n" "$SQUASHFS_NAME" "$SQUASHFS_BASE"
    ' _ "$REMASTER"
}

new_layout_out="$(probe_layout "$(printf '%s\n' "${new_listing[@]}")")"
if [ "$new_layout_out" = "minimal.standard.squashfs|minimal.standard" ]; then
    pass "layout nuevo se detecta como minimal.standard.squashfs"
else
    fail "layout nuevo mal detectado: $new_layout_out"
fi

old_layout_out="$(probe_layout "$(printf '%s\n' "${old_listing[@]}")")"
if [ "$old_layout_out" = "filesystem.squashfs|filesystem" ]; then
    pass "layout viejo se detecta como filesystem.squashfs"
else
    fail "layout viejo mal detectado: $old_layout_out"
fi

both_layout_out="$(probe_layout "$(printf '%s\n' "${new_listing[@]}" "${old_listing[@]}")")"
if [ "$both_layout_out" = "minimal.standard.squashfs|minimal.standard" ]; then
    pass "con ambos squashfs se prefiere minimal.standard.squashfs"
else
    fail "ambos layouts resueltos mal: $both_layout_out"
fi

if probe_layout "$(printf '%s\n' '/casper' '/casper/otro.squashfs')" >/dev/null 2>&1; then
    fail "un listing desconocido no falla"
else
    pass "un listing sin squashfs conocidos falla"
fi

# unsquash_rootfs extrae el squashfs elegido, no un nombre hardcodeado.
for layout in new old; do
    case "$layout" in
        new)
            unsquash_tree="$TMP_ROOT/iso-unsquash-new"
            expected_squashfs="minimal.standard.squashfs"
            ;;
        old)
            unsquash_tree="$TMP_ROOT/iso-unsquash-old"
            expected_squashfs="filesystem.squashfs"
            ;;
    esac
    mkdir -p "$unsquash_tree/casper"
    printf 'rootfs de prueba\n' > "$unsquash_tree/casper/$expected_squashfs"
    if STUB_LOG="$TMP_ROOT/unsquash-$layout.log" PATH="$TMP_ROOT/stub-new:$PATH" \
        bash -c '
            source "$1"
            ISO_TREE="$2"
            ROOTFS_DIR="$3"
            unsquash_rootfs
        ' _ "$REMASTER" "$unsquash_tree" "$TMP_ROOT/rootfs-unsquash-$layout" \
        > "$TMP_ROOT/unsquash-$layout.out" 2>&1 &&
       grep -qF "casper/$expected_squashfs" "$TMP_ROOT/unsquash-$layout.log"; then
        pass "unsquash_rootfs extrae casper/$expected_squashfs ($layout)"
    else
        fail "unsquash_rootfs no extrae casper/$expected_squashfs ($layout)"
    fi
done

# ---------------------------------------------------------------------------
# 8. --dry-run y --check con ISO falsa: detectan el layout y no tocan work/
# ---------------------------------------------------------------------------

snapshot_work() {
    if [ -d "$ISO_DIR/work" ]; then
        find "$ISO_DIR/work" -printf '%P|%y|%s|%T@\n' | LC_ALL=C sort
    else
        printf '__NO_WORK__\n'
    fi
}

fake_iso="$TMP_ROOT/ubuntu-26.04-desktop-amd64.iso"
if truncate -s 1610612736 "$fake_iso"; then
    work_snapshot_before="$(snapshot_work)"
    for layout in new old; do
        case "$layout" in
            new)
                stub_bin="$TMP_ROOT/stub-new"
                expected_squashfs="minimal.standard.squashfs"
                unexpected_squashfs="filesystem.squashfs"
                ;;
            old)
                stub_bin="$TMP_ROOT/stub-old"
                expected_squashfs="filesystem.squashfs"
                unexpected_squashfs="minimal.standard.squashfs"
                ;;
        esac

        dry_iso_out="$(PATH="$stub_bin:$PATH" "$REMASTER" --dry-run --iso "$fake_iso" 2>&1)"
        dry_iso_status=$?

        if [ "$dry_iso_status" -eq 0 ]; then
            pass "--dry-run con ISO falsa sale 0 ($layout)"
        else
            fail "--dry-run con ISO falsa sale $dry_iso_status ($layout): $dry_iso_out"
        fi

        if grep -qF 'Plan de remaster' <<<"$dry_iso_out"; then
            pass "--dry-run imprime el plan ($layout)"
        else
            fail "--dry-run no imprime el plan ($layout)"
        fi

        if grep -qF "casper/$expected_squashfs" <<<"$dry_iso_out"; then
            pass "el plan usa casper/$expected_squashfs ($layout)"
        else
            fail "el plan no usa casper/$expected_squashfs ($layout)"
        fi

        if grep -qF "casper/$unexpected_squashfs" <<<"$dry_iso_out"; then
            fail "el plan menciona el squashfs equivocado ($layout)"
        else
            pass "el plan no menciona casper/$unexpected_squashfs ($layout)"
        fi

        for needle in 'chroot: APT' 'md5sum.txt' 'install-sources.yaml' 'se conservan' 'Secure Boot'; do
            if grep -qF -- "$needle" <<<"$dry_iso_out"; then
                pass "el plan menciona $needle ($layout)"
            else
                fail "el plan no menciona $needle ($layout)"
            fi
        done

        check_iso_out="$(PATH="$stub_bin:$PATH" "$REMASTER" --check --iso "$fake_iso" 2>&1)"
        check_iso_status=$?
        if [ "$check_iso_status" -eq 0 ] &&
           grep -qF 'check OK' <<<"$check_iso_out" &&
           grep -qF "Casper: $expected_squashfs" <<<"$check_iso_out"; then
            pass "--check valida el layout $layout sin escribir"
        else
            fail "--check falla con el layout $layout: $check_iso_out"
        fi
    done

    if [ "$work_snapshot_before" = "$(snapshot_work)" ]; then
        pass "--dry-run/--check no tocan work/"
    else
        fail "--dry-run/--check modificaron work/"
    fi

    # Un casper sin ninguno de los dos squashfs conocidos no debe pasar.
    make_iso_stubs "$TMP_ROOT/stub-unknown" /casper /casper/otro.squashfs /casper/vmlinuz
    unknown_out="$(PATH="$TMP_ROOT/stub-unknown:$PATH" "$REMASTER" --check --iso "$fake_iso" 2>&1)"
    unknown_status=$?
    if [ "$unknown_status" -ne 0 ] && grep -qi 'squashfs' <<<"$unknown_out"; then
        pass "--check falla con un layout de casper desconocido"
    else
        fail "--check no falla con un layout desconocido: $unknown_out"
    fi
else
    skip "no se pudo crear una ISO dispersa de prueba"
fi

# ---------------------------------------------------------------------------
# 9. install_mytical_packages(): repo obligatorio y Signed-By
# ---------------------------------------------------------------------------

missing_repo_out="$(bash -c '
    source "$1"
    ROOTFS_DIR="$2"
    REPO=""
    install_mytical_packages
' _ "$REMASTER" "$TMP_ROOT/rootfs-sin-repo" 2>&1)"
missing_repo_status=$?
if [ "$missing_repo_status" -ne 0 ] &&
   grep -qi -- 'repo' <<<"$missing_repo_out"; then
    pass "install_mytical_packages falla claro sin --repo"
else
    fail "install_mytical_packages no falla claro sin --repo: $missing_repo_out"
fi

install_root="$TMP_ROOT/rootfs-install"
install_repo="$TMP_ROOT/repo-install"
mkdir -p "$install_root/usr/bin" "$install_root/etc/apt" \
    "$install_root/proc" "$install_root/sys" "$install_root/dev/pts"
: > "$install_root/usr/bin/apt-get"
chmod +x "$install_root/usr/bin/apt-get"
mkdir -p "$install_repo/dists/mytical"
: > "$install_repo/dists/mytical/Release"
cp "$REPO_ROOT/distro/apt/mytical-release.asc" "$install_repo/mytical-release.asc"

install_stub="$TMP_ROOT/install-stub"
mkdir -p "$install_stub"
cat > "$install_stub/mount" <<'EOF'
#!/usr/bin/env bash
printf 'mount %s\n' "$*" >> "$STUB_LOG"
EOF
cat > "$install_stub/umount" <<'EOF'
#!/usr/bin/env bash
printf 'umount %s\n' "$*" >> "$STUB_LOG"
EOF
cat > "$install_stub/chroot" <<'EOF'
#!/usr/bin/env bash
printf 'chroot %s\n' "$*" >> "$STUB_LOG"
case " $* " in
    *" dpkg-query "*) cat "$STUB_DPKG" ;;
esac
exit 0
EOF
chmod +x "$install_stub/mount" "$install_stub/umount" "$install_stub/chroot"
printf 'casper\ncalamares\nsddm\nmytical-session\n' > "$TMP_ROOT/installed-packages"

STUB_LOG="$TMP_ROOT/install.log" STUB_DPKG="$TMP_ROOT/installed-packages" \
    PATH="$install_stub:$PATH" bash -c '
        source "$1"
        ROOTFS_DIR="$2"
        REPO="$3"
        install_mytical_packages
    ' _ "$REMASTER" "$install_root" "$install_repo" > "$TMP_ROOT/install.out" 2>&1
install_status=$?

if [ "$install_status" -eq 0 ]; then
    pass "install_mytical_packages completa con repo y clave"
else
    fail "install_mytical_packages falla con repo: $(cat "$TMP_ROOT/install.out")"
fi

sources="$install_root/etc/apt/sources.list.d/mytical.sources"
if [ -s "$sources" ] &&
   grep -qF 'URIs: file:/opt/mytical/apt' "$sources" &&
   grep -qF 'Signed-By: /usr/share/keyrings/mytical-apt.asc' "$sources"; then
    pass "el sources del chroot usa el repo local y Signed-By"
else
    fail "el sources del chroot no usa repo local/Signed-By"
fi

if [ -s "$install_root/usr/share/keyrings/mytical-apt.asc" ]; then
    pass "la clave publica se copia al llavero del chroot"
else
    fail "falta la clave publica en el chroot"
fi

if grep -q 'apt-get update' "$TMP_ROOT/install.log"; then
    pass "el chroot ejecuta apt-get update"
else
    fail "el chroot no ejecuta apt-get update"
fi

if grep -q -- '--no-install-recommends' "$TMP_ROOT/install.log"; then
    pass "el chroot instala con --no-install-recommends"
else
    fail "el chroot no usa --no-install-recommends"
fi

if grep -q 'autoremove' "$TMP_ROOT/install.log"; then
    fail "el chroot ejecuto autoremove"
else
    pass "el chroot no ejecuta autoremove"
fi

for mountpoint in proc sys dev dev/pts; do
    if grep -q "umount .*$install_root/$mountpoint" "$TMP_ROOT/install.log"; then
        pass "se desmonta $mountpoint al terminar"
    else
        fail "no se desmonta $mountpoint"
    fi
done

if [ ! -e "$install_root/etc/resolv.conf" ]; then
    pass "el resolv.conf temporal no queda en el rootfs"
else
    fail "el resolv.conf temporal quedo en el rootfs"
fi

# ---------------------------------------------------------------------------
# 10. apply_branding(): os-release, wallpapers CC0 y SDDM
# ---------------------------------------------------------------------------

brand_root="$TMP_ROOT/rootfs-brand"
mkdir -p "$brand_root/etc" "$brand_root/usr/share/sddm/themes/ubuntu"
: > "$brand_root/usr/share/sddm/themes/ubuntu/logo.png"

bash -c '
    source "$1"
    ROOTFS_DIR="$2"
    apply_branding
' _ "$REMASTER" "$brand_root" > "$TMP_ROOT/brand.out" 2>&1
brand_status=$?

if [ "$brand_status" -eq 0 ]; then
    pass "apply_branding completa"
else
    fail "apply_branding falla: $(cat "$TMP_ROOT/brand.out")"
fi

os_release="$brand_root/etc/os-release"
if [ -s "$os_release" ] &&
   grep -qx 'NAME="Mytical"' "$os_release" &&
   grep -qx 'ID=mytical' "$os_release" &&
   grep -qx 'ID_LIKE=ubuntu' "$os_release" &&
   grep -qx 'VERSION_ID="26.04"' "$os_release" &&
   grep -qx 'MYTICAL_VERSION_ID="1.1"' "$os_release"; then
    pass "/etc/os-release identifica a Mytical sobre Ubuntu 26.04"
else
    fail "/etc/os-release no identifica a Mytical sobre Ubuntu 26.04"
fi

expected_wallpapers="$(find "$REPO_ROOT/distro/branding/wallpapers" -maxdepth 1 -type f -name '*.png' | wc -l)"
actual_wallpapers="$(find "$brand_root/usr/share/backgrounds/mytical" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l)"
if [ "$expected_wallpapers" -gt 0 ] && [ "$actual_wallpapers" -eq "$expected_wallpapers" ]; then
    pass "se copian los $actual_wallpapers wallpapers CC0"
else
    fail "wallpapers copiados: $actual_wallpapers (esperados $expected_wallpapers)"
fi

if [ -s "$brand_root/usr/share/doc/mytical/branding/LICENSES.md" ]; then
    pass "se copia el aviso de licencias de branding"
else
    fail "falta el aviso de licencias de branding"
fi

theme="$brand_root/usr/share/sddm/themes/mytical"
if [ -s "$theme/Main.qml" ] && [ -s "$theme/LICENSE" ] && [ -s "$theme/Backgrounds/wallpaper" ]; then
    pass "el tema SDDM mytical queda completo"
else
    fail "el tema SDDM mytical esta incompleto"
fi

sddm_conf="$brand_root/etc/sddm.conf.d/90-mytical.conf"
if [ -s "$sddm_conf" ] &&
   grep -qx 'Current=mytical' "$sddm_conf" &&
   grep -qx 'SessionDir=/usr/share/wayland-sessions' "$sddm_conf"; then
    pass "SDDM apunta al tema y a la sesion Mytical"
else
    fail "SDDM no apunta al tema/sesion Mytical"
fi

if [ ! -e "$brand_root/usr/share/sddm/themes/ubuntu" ]; then
    pass "se retira el tema SDDM de Ubuntu"
else
    fail "el tema SDDM de Ubuntu sigue en el rootfs"
fi

# ---------------------------------------------------------------------------
# 11. update_casper_metadata(): layout viejo (filesystem.*)
# ---------------------------------------------------------------------------

meta_root="$TMP_ROOT/rootfs-meta"
meta_iso="$TMP_ROOT/iso-meta"
meta_new="$TMP_ROOT/filesystem.squashfs"
mkdir -p "$meta_root/etc" "$meta_iso/casper" "$meta_iso/boot/grub"
printf 'rootfs\n' > "$meta_root/etc/marker"
printf 'vmlinuz\n' > "$meta_iso/casper/vmlinuz"
printf 'squashfs viejo\n' > "$meta_iso/casper/filesystem.squashfs"
printf 'grub\n' > "$meta_iso/boot/grub/grub.cfg"
printf 'squashfs nuevo\n' > "$meta_new"

bash -c '
    source "$1"
    ROOTFS_DIR="$2"
    ISO_TREE="$3"
    NEW_SQUASHFS="$4"
    update_casper_metadata
' _ "$REMASTER" "$meta_root" "$meta_iso" "$meta_new" > "$TMP_ROOT/meta.out" 2>&1
meta_status=$?

if [ "$meta_status" -eq 0 ]; then
    pass "update_casper_metadata completa (layout viejo)"
else
    fail "update_casper_metadata falla (layout viejo): $(cat "$TMP_ROOT/meta.out")"
fi

expected_size="$(du -sx --block-size=1 "$meta_root" | cut -f1)"
actual_size="$(cat "$meta_iso/casper/filesystem.size" 2>/dev/null || true)"
if [ "$actual_size" = "$expected_size" ]; then
    pass "filesystem.size coincide con du del rootfs"
else
    fail "filesystem.size=$actual_size, esperado=$expected_size"
fi

if [ -f "$meta_iso/md5sum.txt" ] &&
   grep -q '  ./casper/filesystem.squashfs$' "$meta_iso/md5sum.txt" &&
   grep -q '  ./casper/vmlinuz$' "$meta_iso/md5sum.txt"; then
    pass "md5sum.txt lista el squashfs nuevo y el kernel"
else
    fail "md5sum.txt no lista los archivos esperados"
fi

if [ "$(md5sum "$meta_iso/casper/filesystem.squashfs" | cut -d' ' -f1)" = \
     "$(grep '  ./casper/filesystem.squashfs$' "$meta_iso/md5sum.txt" | cut -d' ' -f1)" ]; then
    pass "md5sum.txt describe el squashfs que se va a remontar"
else
    fail "md5sum.txt no coincide con el squashfs nuevo"
fi

if ( cd "$meta_iso" && md5sum -c md5sum.txt >/dev/null 2>&1 ); then
    pass "md5sum -c pasa sobre el arbol extraido (layout viejo)"
else
    fail "md5sum -c falla sobre el arbol extraido (layout viejo)"
fi

if ! grep -q 'md5sum.txt' "$meta_iso/md5sum.txt"; then
    pass "md5sum.txt no se referencia a si mismo"
else
    fail "md5sum.txt se referencia a si mismo"
fi

if grep -q 'TODO(iso)' "$TMP_ROOT/meta.out"; then
    pass "la validacion contra la ISO final queda marcada como TODO"
else
    fail "no se marca la validacion pendiente contra la ISO final"
fi

if [ ! -e "$meta_new" ]; then
    pass "el squashfs nuevo se mueve al arbol de la ISO (layout viejo)"
else
    fail "el squashfs nuevo no se movio al arbol de la ISO (layout viejo)"
fi

if grep -q 'sin casper/install-sources.yaml' "$TMP_ROOT/meta.out"; then
    pass "el layout viejo tolera la ausencia de install-sources.yaml"
else
    fail "el layout viejo no informa la ausencia de install-sources.yaml"
fi

# stub de remux: registra los -map sin escribir ninguna ISO
remux_stub="$TMP_ROOT/stub-remux"
mkdir -p "$remux_stub"
cat > "$remux_stub/xorriso" <<'EOF'
#!/usr/bin/env bash
printf 'xorriso %s\n' "$*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$remux_stub/xorriso"

run_remux() {
    local tree="$1" out="$2" log="$3" squashfs="$4"
    STUB_LOG="$log" PATH="$remux_stub:$PATH" bash -c '
        source "$1"
        ISO="$2"
        OUT="$3"
        ISO_TREE="$4"
        NEW_SQUASHFS="$5/casper/$6"
        rebuild_iso
    ' _ "$REMASTER" "$TMP_ROOT/ubuntu-26.04-desktop-amd64.iso" "$out" "$tree" "$tree" "$squashfs" \
        > "$log.out" 2>&1
}

if run_remux "$meta_iso" "$TMP_ROOT/out-old.iso" "$TMP_ROOT/remux-old.log" filesystem.squashfs &&
   grep -qF -- "-map $meta_iso/casper/filesystem.squashfs /casper/filesystem.squashfs" \
       "$TMP_ROOT/remux-old.log" &&
   grep -qF -- "-map $meta_iso/casper/filesystem.size /casper/filesystem.size" \
       "$TMP_ROOT/remux-old.log" &&
   grep -qF -- "-map $meta_iso/md5sum.txt /md5sum.txt" "$TMP_ROOT/remux-old.log"; then
    pass "el remux mapea /casper/filesystem.squashfs y sus metadatos"
else
    fail "el remux no mapea el layout viejo: $(cat "$TMP_ROOT/remux-old.log.out")"
fi

# ---------------------------------------------------------------------------
# 12. update_casper_metadata(): layout nuevo (minimal.standard.*)
# ---------------------------------------------------------------------------

meta2_root="$TMP_ROOT/rootfs-meta2"
meta2_iso="$TMP_ROOT/iso-meta2"
meta2_new="$TMP_ROOT/new-minimal-standard.squashfs"
meta2_old_size=4711
mkdir -p "$meta2_root/etc" "$meta2_root/usr/bin" \
    "$meta2_iso/casper" "$meta2_iso/boot/grub"
printf 'rootfs nuevo\n' > "$meta2_root/etc/marker"
: > "$meta2_root/usr/bin/dpkg-query"
chmod +x "$meta2_root/usr/bin/dpkg-query"
printf 'vmlinuz\n' > "$meta2_iso/casper/vmlinuz"
printf 'squashfs standard viejo\n' > "$meta2_iso/casper/minimal.standard.squashfs"
printf '%s\n' "$meta2_old_size" > "$meta2_iso/casper/minimal.standard.size"
printf 'paquete viejo 1.0\n' > "$meta2_iso/casper/minimal.standard.manifest"
printf 'squashfs variante idioma\n' > "$meta2_iso/casper/minimal.standard.en.squashfs"
printf 'grub\n' > "$meta2_iso/boot/grub/grub.cfg"
cat > "$meta2_iso/casper/install-sources.yaml" <<'EOF'
# Fuentes de instalacion (subiquity/casper)
sources:
  - id: standard
    name:
      en: Ubuntu Desktop
    description:
      en: imagen principal
    path: minimal.standard.squashfs
    size: 4911607808
    default: true
  - id: standard.en
    path: minimal.standard.en.squashfs
    size: 1234
  - id: enhanced
    path: minimal.enhanced.squashfs
    size: 4321
EOF
printf 'squashfs standard nuevo\n' > "$meta2_new"

meta_stub="$TMP_ROOT/stub-meta"
mkdir -p "$meta_stub"
cat > "$meta_stub/chroot" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" dpkg-query "*) printf 'casper 1.0\ncalamares 3.3\n' ;;
esac
exit 0
EOF
chmod +x "$meta_stub/chroot"

PATH="$meta_stub:$PATH" bash -c '
    source "$1"
    ROOTFS_DIR="$2"
    ISO_TREE="$3"
    NEW_SQUASHFS="$4"
    update_casper_metadata
' _ "$REMASTER" "$meta2_root" "$meta2_iso" "$meta2_new" > "$TMP_ROOT/meta2.out" 2>&1
meta2_status=$?

if [ "$meta2_status" -eq 0 ]; then
    pass "update_casper_metadata completa (layout nuevo)"
else
    fail "update_casper_metadata falla (layout nuevo): $(cat "$TMP_ROOT/meta2.out")"
fi

expected2_size="$(du -sx --block-size=1 "$meta2_root" | cut -f1)"
actual2_size="$(cat "$meta2_iso/casper/minimal.standard.size" 2>/dev/null || true)"
if [ "$actual2_size" = "$expected2_size" ]; then
    pass "minimal.standard.size coincide con du del rootfs"
else
    fail "minimal.standard.size=$actual2_size, esperado=$expected2_size"
fi

if [ ! -e "$meta2_iso/casper/filesystem.size" ] &&
   [ ! -e "$meta2_iso/casper/filesystem.manifest" ]; then
    pass "el layout nuevo no escribe filesystem.size/manifest"
else
    fail "el layout nuevo escribio metadatos del layout viejo"
fi

if [ ! -e "$meta2_new" ]; then
    pass "el squashfs nuevo reemplaza a minimal.standard.squashfs"
else
    fail "el squashfs nuevo no se movio al arbol de la ISO (layout nuevo)"
fi

if grep -qx 'squashfs standard nuevo' "$meta2_iso/casper/minimal.standard.squashfs"; then
    pass "se reemplaza el squashfs elegido"
else
    fail "no se reemplazo casper/minimal.standard.squashfs"
fi

if grep -qx 'casper 1.0' "$meta2_iso/casper/minimal.standard.manifest" &&
   grep -qx 'calamares 3.3' "$meta2_iso/casper/minimal.standard.manifest" &&
   ! grep -q 'paquete viejo' "$meta2_iso/casper/minimal.standard.manifest"; then
    pass "minimal.standard.manifest se regenera con dpkg-query"
else
    fail "minimal.standard.manifest no se regenero"
fi

squashfs2_size="$(stat -c '%s' "$meta2_iso/casper/minimal.standard.squashfs")"
sources2="$meta2_iso/casper/install-sources.yaml"
if grep -qF 'path: minimal.standard.squashfs' "$sources2" &&
   grep -qx "    size: $squashfs2_size" "$sources2"; then
    pass "install-sources.yaml apunta al squashfs y a su tamano comprimido"
else
    fail "install-sources.yaml no actualiza path/size del standard"
fi

if grep -qx '    size: 1234' "$sources2" &&
   grep -qx '    size: 4321' "$sources2" &&
   grep -qx '    path: minimal.standard.en.squashfs' "$sources2" &&
   grep -qx '    path: minimal.enhanced.squashfs' "$sources2"; then
    pass "las variantes de idioma/enhanced de install-sources.yaml quedan intactas"
else
    fail "install-sources.yaml modifico variantes que no eran standard"
fi

if ! grep -q "size: 4911607808" "$sources2"; then
    pass "el size viejo de 4911607808 ya no aparece"
else
    fail "install-sources.yaml conserva el size del squashfs viejo"
fi

if grep -q '  ./casper/minimal.standard.squashfs$' "$meta2_iso/md5sum.txt" &&
   ! grep -q '  ./casper/filesystem.squashfs$' "$meta2_iso/md5sum.txt" &&
   ( cd "$meta2_iso" && md5sum -c md5sum.txt >/dev/null 2>&1 ); then
    pass "md5sum.txt describe minimal.standard.squashfs y pasa md5sum -c"
else
    fail "md5sum.txt no describe el layout nuevo"
fi

if python3 -c 'import yaml' >/dev/null 2>&1; then
    if python3 - "$sources2" "$squashfs2_size" <<'PY'
import os
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
entries = data["sources"]
assert [entry["id"] for entry in entries] == ["standard", "standard.en", "enhanced"]
assert entries[0]["path"] == "minimal.standard.squashfs"
assert entries[0]["size"] == int(sys.argv[2])
assert entries[1]["path"] == "minimal.standard.en.squashfs"
assert entries[1]["size"] == 1234
assert entries[2]["path"] == "minimal.enhanced.squashfs"
assert entries[2]["size"] == 4321
assert entries[0]["name"]["en"] == "Ubuntu Desktop"
assert os.path.exists(os.path.join(os.path.dirname(sys.argv[1]), "minimal.standard.manifest"))
PY
    then
        pass "install-sources.yaml sigue siendo YAML valido tras actualizarlo"
    else
        fail "install-sources.yaml quedo invalido tras actualizarlo"
    fi
else
    skip "PyYAML no esta instalado; no se reparsea install-sources.yaml"
fi

# Una entrada standard ausente debe fallar claro y no tocar el fichero.
broken_iso="$TMP_ROOT/iso-meta-broken"
mkdir -p "$broken_iso/casper"
printf 'squashfs\n' > "$broken_iso/casper/minimal.standard.squashfs"
cat > "$broken_iso/casper/install-sources.yaml" <<'EOF'
sources:
  - id: enhanced
    path: minimal.enhanced.squashfs
    size: 4321
EOF
broken_before="$(cat "$broken_iso/casper/install-sources.yaml")"
bash -c '
    source "$1"
    ROOTFS_DIR="$2"
    ISO_TREE="$3"
    NEW_SQUASHFS="$4"
    update_casper_metadata
' _ "$REMASTER" "$meta2_root" "$broken_iso" \
    "$broken_iso/casper/minimal.standard.squashfs" > "$TMP_ROOT/broken.out" 2>&1
broken_status=$?
if [ "$broken_status" -ne 0 ] &&
   grep -q 'install-sources.yaml' "$TMP_ROOT/broken.out" &&
   [ "$broken_before" = "$(cat "$broken_iso/casper/install-sources.yaml")" ]; then
    pass "sin entrada standard, install-sources.yaml falla y queda intacto"
else
    fail "install-sources.yaml sin standard no falla claro"
fi

if run_remux "$meta2_iso" "$TMP_ROOT/out-new.iso" "$TMP_ROOT/remux-new.log" \
       minimal.standard.squashfs &&
   grep -qF -- "-map $meta2_iso/casper/minimal.standard.squashfs /casper/minimal.standard.squashfs" \
       "$TMP_ROOT/remux-new.log" &&
   grep -qF -- "-map $meta2_iso/casper/minimal.standard.size /casper/minimal.standard.size" \
       "$TMP_ROOT/remux-new.log" &&
   grep -qF -- "-map $meta2_iso/casper/minimal.standard.manifest /casper/minimal.standard.manifest" \
       "$TMP_ROOT/remux-new.log" &&
   grep -qF -- "-map $meta2_iso/casper/install-sources.yaml /casper/install-sources.yaml" \
       "$TMP_ROOT/remux-new.log" &&
   ! grep -qF 'filesystem.squashfs' "$TMP_ROOT/remux-new.log"; then
    pass "el remux mapea /casper/minimal.standard.squashfs y sus metadatos"
else
    fail "el remux no mapea el layout nuevo: $(cat "$TMP_ROOT/remux-new.log.out")"
fi

# ---------------------------------------------------------------------------
# 13. stage_calamares(): unpackfs sigue al squashfs detectado
# ---------------------------------------------------------------------------

for layout in new old; do
    case "$layout" in
        new)
            expected_squashfs="minimal.standard.squashfs"
            expected_base="minimal.standard"
            ;;
        old)
            expected_squashfs="filesystem.squashfs"
            expected_base="filesystem"
            ;;
    esac
    cal_root="$TMP_ROOT/rootfs-cal-$layout"
    mkdir -p "$cal_root"
    if bash -c '
        source "$1"
        ROOTFS_DIR="$2"
        SQUASHFS_NAME="$3"
        SQUASHFS_BASE="$4"
        stage_calamares
    ' _ "$REMASTER" "$cal_root" "$expected_squashfs" "$expected_base" \
        > "$TMP_ROOT/cal-$layout.out" 2>&1 &&
       grep -qF "/cdrom/casper/$expected_squashfs" \
           "$cal_root/etc/calamares/modules/unpackfs.conf"; then
        pass "stage_calamares deja unpackfs con $expected_squashfs ($layout)"
    else
        fail "stage_calamares no ajusta unpackfs ($layout): $(cat "$TMP_ROOT/cal-$layout.out")"
    fi
done

# ---------------------------------------------------------------------------
# 14. Documentacion
# ---------------------------------------------------------------------------

readme="$ISO_DIR/README.md"
for needle in 'squashfs-tools' 'xorriso' 'casper' 'calamares' '/nix' 'Tamaño'; do
    if grep -qF -- "$needle" "$readme"; then
        pass "README menciona $needle"
    else
        fail "README no menciona $needle"
    fi
done

for needle in 'Bloqueantes' 'Criterios de aceptación' 'Secure Boot' 'casper' 'Calamares' '/nix'; do
    if grep -qF -- "$needle" "$DOC"; then
        pass "ISO.md menciona $needle"
    else
        fail "ISO.md no menciona $needle"
    fi
done

for needle in 'install_mytical_packages' 'apply_branding' 'update_casper_metadata' \
    'md5sum.txt' 'Signed-By' 'sin autoremove' 'minimal.standard.squashfs' \
    'install-sources.yaml'; do
    if grep -qF -- "$needle" "$DOC"; then
        pass "ISO.md documenta $needle"
    else
        fail "ISO.md no documenta $needle"
    fi
done

# ---------------------------------------------------------------------------
# 15. clean solo apunta a work/
# ---------------------------------------------------------------------------

clean_dry="$(make -C "$ISO_DIR" -n clean 2>&1)" || true
if grep -qF "rm -rf -- \"$ISO_DIR/work\"" <<<"$clean_dry"; then
    pass "clean borra $ISO_DIR/work"
else
    fail "clean no borra exactamente $ISO_DIR/work"
fi

if grep -q 'distro/build' <<<"$clean_dry"; then
    fail "clean toca distro/build"
else
    pass "clean no toca distro/build"
fi

# ---------------------------------------------------------------------------
# 16. shellcheck opcional (CI lo ejecuta sobre los .sh versionados)
# ---------------------------------------------------------------------------

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x "$REMASTER" "${BASH_SOURCE[0]}"; then
        pass "shellcheck"
    else
        fail "shellcheck"
    fi
else
    skip "shellcheck no esta instalado"
fi

# ---------------------------------------------------------------------------

printf '\n%d comprobaciones, %d fallos\n' "$checks" "$failures"
if [ "$failures" -ne 0 ]; then
    exit 1
fi
