#!/usr/bin/env bash
# Tests locales del esqueleto de la ISO V1.1.
#
# Sin red, sin descargas, sin root y sin construir la ISO. Valida sintaxis,
# que `make build` falle sin ISO, que la lista no incluya /nix ni GNOME, y que
# Calamares/branding/documentacion tengan la forma esperada.
set -uo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd -- "$ISO_DIR/../.." && pwd)"
REMASTER="$ISO_DIR/remaster.sh"
LIST="$ISO_DIR/package-lists/mytical.list"
DOC="$REPO_ROOT/docs/distro/ISO.md"
CALAMARES="$ISO_DIR/calamares"

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
# 5. Calamares y branding sin binarios
# ---------------------------------------------------------------------------

settings="$CALAMARES/settings.conf"
if grep -Eq '^branding:[[:space:]]*mytical$' "$settings"; then
    pass "settings.conf usa el branding mytical"
else
    fail "settings.conf no declara 'branding: mytical'"
fi

for module in welcome partition unpackfs bootloader users; do
    if grep -q -- "$module" "$settings"; then
        pass "settings.conf referencia el modulo $module"
    else
        fail "settings.conf no referencia el modulo $module"
    fi
done

if grep -q $'\t' "$settings"; then
    fail "settings.conf contiene tabuladores (YAML no los acepta)"
else
    pass "settings.conf no contiene tabuladores"
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
# 6. Documentacion
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

# ---------------------------------------------------------------------------
# 7. clean solo apunta a work/
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
# 8. shellcheck opcional (CI lo ejecuta sobre los .sh versionados)
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
