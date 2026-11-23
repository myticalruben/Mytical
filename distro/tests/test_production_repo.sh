#!/usr/bin/env bash
# Prueba aislada de distro/apt/production-sign.sh.
#
# - crea una clave GPG efímera (1 día, sin passphrase) en un GNUPGHOME temporal
# - construye un repo mínimo con dists/mytical/Release y pool/
# - ejecuta production-sign.sh y verifica InRelease/Release.gpg con gpgv
# - comprueba que un fingerprint inexistente falla y no crea la snapshot
#
# No usa la clave de producción, no toca /srv/apt y no publica nada.
# Si no hay gpg/gpgv, imprime un SKIP explícito y sale con 0.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIGN_SCRIPT="$REPO_ROOT/distro/apt/production-sign.sh"

log()  { printf '\n==> %s\n' "$*"; }
skip() { printf 'SKIP: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$SIGN_SCRIPT" ] || die "falta $SIGN_SCRIPT"
[ -x "$SIGN_SCRIPT" ] || die "$SIGN_SCRIPT no es ejecutable"

# Igual que test_apt_repo.sh: en este entorno Debian 13 GnuPG no está en el
# PATH, pero sí en /nix/store. En Ubuntu 26.04 basta con `sudo apt install gnupg`.
find_gpg() {
    if command -v gpg >/dev/null 2>&1 && command -v gpgv >/dev/null 2>&1; then
        return 0
    fi
    local dir
    for dir in /nix/store/*-gnupg-*/bin; do
        if [ ! -x "$dir/gpg" ] || [ ! -x "$dir/gpgv" ]; then
            continue
        fi
        PATH="$dir:$PATH"
        export PATH
        log "GnuPG del sistema ausente; usando $dir"
        return 0
    done
    return 1
}

if ! find_gpg; then
    skip "gpg/gpgv no disponibles: no se puede probar production-sign.sh"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mytical-prod-repo-test.XXXXXX")"
chmod 755 "$tmp"
cleanup() {
    local status=$?
    rm -rf "$tmp"
    exit "$status"
}
trap cleanup EXIT

export GNUPGHOME="$tmp/gnupg"
mkdir -m 700 "$GNUPGHOME"

log "1/5 clave GPG efímera"
# Clave de un día, sin passphrase: solo para el test, nunca de producción.
gpg --batch --yes --no-tty --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "Mytical APT Production Test <apt-prod-test@mytical.invalid>" \
    rsa3072 sign 1d >/dev/null 2>&1
fpr="$(gpg --batch --with-colons --list-keys 2>/dev/null \
    | awk -F: '/^fpr:/{print $10; exit}')"
[ -n "$fpr" ] || die "no se pudo obtener el fingerprint de la clave efímera"
case "$fpr" in
    *[!0-9A-Fa-f]*|'') die "fingerprint inesperado: $fpr" ;;
esac
gpg --batch --export "$fpr" > "$tmp/mytical-apt.gpg" 2>/dev/null
[ -s "$tmp/mytical-apt.gpg" ] || die "no se pudo exportar la clave pública efímera"
printf 'clave efímera %s (1 día, sin passphrase)\n' "$fpr"

log "2/5 repo mínimo de prueba"
repo="$tmp/repo"
dist="$repo/dists/mytical"
bin="$dist/main/binary-amd64"
deb_rel="pool/main/m/mytical-session/mytical-session_0.1.0-1~resolute1_all.deb"
mkdir -p "$bin" "$(dirname "$repo/$deb_rel")"

printf 'no es un .deb real: repo mínimo para probar la firma\n' > "$repo/$deb_rel"
deb_size="$(wc -c < "$repo/$deb_rel" | tr -d ' ')"
deb_sha="$(sha256sum "$repo/$deb_rel" | awk '{print $1}')"

cat > "$bin/Packages" <<EOF
Package: mytical-session
Version: 0.1.0-1~resolute1
Architecture: all
Maintainer: Mytical <apt@mytical.invalid>
Filename: $deb_rel
Size: $deb_size
SHA256: $deb_sha
Description: Paquete de prueba para la firma del repo de producción
EOF
gzip -9n -c "$bin/Packages" > "$bin/Packages.gz"

{
    printf 'Origin: Mytical\n'
    printf 'Label: Mytical\n'
    printf 'Suite: mytical\n'
    printf 'Codename: mytical\n'
    printf 'Architectures: amd64\n'
    printf 'Components: main\n'
    printf 'Description: Repositorio APT de produccion de Mytical\n'
    printf 'Date: %s\n' "$(date -Ru)"
    printf 'SHA256:\n'
    ( cd "$dist" && sha256sum main/binary-amd64/Packages main/binary-amd64/Packages.gz ) \
        | sed 's/^/ /'
} > "$dist/Release"

grep -q '^SHA256:$' "$dist/Release" || die "Release de prueba sin checksums"
gzip -dc "$bin/Packages.gz" | cmp -s - "$bin/Packages" \
    || die "Packages.gz de prueba no coincide con Packages"

log "3/5 production-sign.sh firma la snapshot"
out="$tmp/snapshots/20261123T182600Z"
bash "$SIGN_SCRIPT" --key "$fpr" --repo "$repo" --out "$out"

for f in \
    "$out/dists/mytical/Release" \
    "$out/dists/mytical/Release.gpg" \
    "$out/dists/mytical/InRelease" \
    "$out/dists/mytical/main/binary-amd64/Packages" \
    "$out/dists/mytical/main/binary-amd64/Packages.gz" \
    "$out/$deb_rel"
do
    [ -s "$f" ] || die "falta o está vacío: $f"
done
[ -f "$repo/dists/mytical/Release" ] || die "el repo de entrada se modificó"
[ ! -e "$repo/dists/mytical/InRelease" ] \
    || die "production-sign.sh escribió en el repo de entrada"
cmp -s "$repo/dists/mytical/Release" "$out/dists/mytical/Release" \
    || die "el Release de la snapshot no es una copia del Release de entrada"

log "4/5 gpgv valida InRelease y Release.gpg"
gpgv --keyring "$tmp/mytical-apt.gpg" "$out/dists/mytical/InRelease"
gpgv --keyring "$tmp/mytical-apt.gpg" \
    "$out/dists/mytical/Release.gpg" "$out/dists/mytical/Release"
grep -q '^-----BEGIN PGP SIGNED MESSAGE-----$' "$out/dists/mytical/InRelease" \
    || die "InRelease no es un mensaje firmado en claro"
if gpgv --keyring "$tmp/mytical-apt.gpg" "$out/dists/mytical/Release" \
        >/dev/null 2>&1; then
    die "gpgv aceptó Release sin firma (la prueba no distingue firma)"
fi

log "5/5 clave inexistente falla sin crear salida"
missing_out="$tmp/snapshots/no-deberia-existir"
if bash "$SIGN_SCRIPT" --key "0000000000000000000000000000000000000000" \
        --repo "$repo" --out "$missing_out" >"$tmp/missing.log" 2>&1; then
    die "production-sign.sh aceptó un fingerprint sin clave secreta"
fi
grep -qi 'clave secreta' "$tmp/missing.log" \
    || { cat "$tmp/missing.log" >&2; die "el error no menciona la clave secreta"; }
[ ! -e "$missing_out" ] \
    || die "se creó la snapshot pese a faltar la clave secreta"

printf '\nOK: production-sign.sh firmó y gpgv validó InRelease con la clave efímera %s\n' "$fpr"
