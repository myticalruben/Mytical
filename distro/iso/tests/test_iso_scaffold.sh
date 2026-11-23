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

if grep -Fq '/cdrom/casper/filesystem.squashfs' "$CALAMARES/modules/unpackfs.conf"; then
    pass "unpackfs.conf usa el squashfs de casper"
else
    fail "unpackfs.conf no apunta a /cdrom/casper/filesystem.squashfs"
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

for function_name in install_mytical_packages apply_branding update_casper_metadata; do
    if grep -Eq "^${function_name}\(\)" "$REMASTER"; then
        pass "remaster.sh define $function_name()"
    else
        fail "remaster.sh no define $function_name()"
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

if grep -Fq 'filesystem.size' "$REMASTER" &&
   grep -Fq 'md5sum.txt' "$REMASTER"; then
    pass "update_casper_metadata toca size y md5sum"
else
    fail "update_casper_metadata no regenera size/md5sum"
fi

# ---------------------------------------------------------------------------
# 7. --dry-run con ISO falsa: no debe tocar work/
# ---------------------------------------------------------------------------

stub_bin="$TMP_ROOT/stub-bin"
mkdir -p "$stub_bin"

cat > "$stub_bin/xorriso" <<'EOF'
#!/usr/bin/env bash
printf '/casper\n/casper/filesystem.squashfs\n/casper/vmlinuz\n'
EOF
cat > "$stub_bin/mksquashfs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$stub_bin/unsquashfs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$stub_bin/xorriso" "$stub_bin/mksquashfs" "$stub_bin/unsquashfs"

fake_iso="$TMP_ROOT/ubuntu-26.04-desktop-amd64.iso"
if truncate -s 1610612736 "$fake_iso"; then
    snapshot_work() {
        if [ -d "$ISO_DIR/work" ]; then
            find "$ISO_DIR/work" -printf '%P|%y|%s|%T@\n' | LC_ALL=C sort
        else
            printf '__NO_WORK__\n'
        fi
    }

    work_snapshot_before="$(snapshot_work)"
    dry_iso_out="$(PATH="$stub_bin:$PATH" "$REMASTER" --dry-run --iso "$fake_iso" 2>&1)"
    dry_iso_status=$?
    work_snapshot_after="$(snapshot_work)"

    if [ "$dry_iso_status" -eq 0 ]; then
        pass "--dry-run con ISO falsa sale 0"
    else
        fail "--dry-run con ISO falsa sale $dry_iso_status: $dry_iso_out"
    fi

    if grep -qF 'Plan de remaster' <<<"$dry_iso_out"; then
        pass "--dry-run imprime el plan"
    else
        fail "--dry-run no imprime el plan"
    fi

    for needle in 'chroot: APT' 'md5sum.txt' 'se conservan' 'Secure Boot'; do
        if grep -qF -- "$needle" <<<"$dry_iso_out"; then
            pass "el plan menciona $needle"
        else
            fail "el plan no menciona $needle"
        fi
    done

    if [ "$work_snapshot_before" = "$work_snapshot_after" ]; then
        pass "--dry-run no toca work/"
    else
        fail "--dry-run modifico work/"
    fi

    check_iso_out="$(PATH="$stub_bin:$PATH" "$REMASTER" --check --iso "$fake_iso" 2>&1)"
    check_iso_status=$?
    if [ "$check_iso_status" -eq 0 ] &&
       grep -qF 'check OK' <<<"$check_iso_out"; then
        pass "--check con ISO falsa valida sin escribir"
    else
        fail "--check con ISO falsa falla: $check_iso_out"
    fi

    if [ "$work_snapshot_before" = "$(snapshot_work)" ]; then
        pass "--check no toca work/"
    else
        fail "--check modifico work/"
    fi
else
    skip "no se pudo crear una ISO dispersa de prueba"
fi

# ---------------------------------------------------------------------------
# 8. install_mytical_packages(): repo obligatorio y Signed-By
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
# 9. apply_branding(): os-release, wallpapers CC0 y SDDM
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
# 10. update_casper_metadata(): filesystem.size y md5sum.txt
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
    pass "update_casper_metadata completa"
else
    fail "update_casper_metadata falla: $(cat "$TMP_ROOT/meta.out")"
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
    pass "md5sum -c pasa sobre el arbol extraido"
else
    fail "md5sum -c falla sobre el arbol extraido"
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
    pass "el squashfs nuevo se mueve al arbol de la ISO"
else
    fail "el squashfs nuevo no se movio al arbol de la ISO"
fi

# ---------------------------------------------------------------------------
# 11. Documentacion
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
    'md5sum.txt' 'Signed-By' 'sin autoremove'; do
    if grep -qF -- "$needle" "$DOC"; then
        pass "ISO.md documenta $needle"
    else
        fail "ISO.md no documenta $needle"
    fi
done

# ---------------------------------------------------------------------------
# 12. clean solo apunta a work/
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
# 13. shellcheck opcional (CI lo ejecuta sobre los .sh versionados)
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
