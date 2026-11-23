#!/usr/bin/env bash
# Firma una copia inmutable del repo APT de producción de Mytical.
#
# Uso:
#   distro/apt/production-sign.sh \
#       --key <FINGERPRINT> \
#       --repo <DIR con dists/mytical y pool> \
#       --out  <DIR nuevo para la snapshot firmada>
#
# El repo de entrada no se modifica. La snapshot de salida contiene solo
# `dists/` y `pool/`, con `Release`, `Release.gpg` e `InRelease` firmados.
#
# Requisitos de la clave:
#   - debe existir la clave SECRETA en el GNUPGHOME de gpg;
#   - no se pide passphrase: usa `gpg --batch` y `--pinentry-mode error`.
#     Si la clave tiene passphrase, debe estar ya desbloqueada en gpg-agent.
#
# No se guardan claves privadas ni passphrases en este script ni en el repo.
set -euo pipefail

PROG="$(basename "$0")"
GPG_BIN="${GPG:-gpg}"

KEY=""
REPO=""
OUT=""

usage() {
    cat <<EOF
Uso: $PROG --key FINGERPRINT --repo DIR --out DIR

  --key FINGERPRINT  Fingerprint (40 o 64 hex) de la clave de firma.
  --repo DIR         Repo sin firmar: debe existir DIR/dists/mytical/Release
                     y DIR/pool.
  --out DIR          Snapshot nueva donde escribir el repo firmado. No debe
                     existir: las snapshots son inmutables.
  -h, --help         Muestra esta ayuda.

Variables:
  GPG                Binario de GnuPG (por defecto: gpg).
  GNUPGHOME          Keyring donde está la clave secreta.

Ejemplo:
  GNUPGHOME=/media/offline/gnupg-mytical-apt \\
    $PROG --key 0123456789ABCDEF0123456789ABCDEF01234567 \\
          --repo distro/apt/public \\
          --out /srv/apt/snapshots/20261123T182600Z
EOF
}

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --key)
            [ "$#" -ge 2 ] || die "falta el valor de --key"
            KEY="$2"
            shift 2
            ;;
        --repo)
            [ "$#" -ge 2 ] || die "falta el valor de --repo"
            REPO="$2"
            shift 2
            ;;
        --out)
            [ "$#" -ge 2 ] || die "falta el valor de --out"
            OUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "opción desconocida: $1 (ver --help)"
            ;;
    esac
done

[ -n "$KEY" ]  || die "falta --key FINGERPRINT"
[ -n "$REPO" ] || die "falta --repo DIR"
[ -n "$OUT" ]  || die "falta --out DIR"

# Fingerprint completo: 40 hex (OpenPGP v4) o 64 hex (v5). Esto también evita
# que un valor que empiece por '-' se interprete como opción de gpg.
case "$KEY" in
    *[!0-9A-Fa-f]*) die "--key no es un fingerprint hexadecimal: $KEY" ;;
esac
case "${#KEY}" in
    40|64) ;;
    *) die "--key debe tener 40 o 64 hex (fingerprint completo): $KEY" ;;
esac

command -v "$GPG_BIN" >/dev/null 2>&1 \
    || die "falta '$GPG_BIN' (Ubuntu: sudo apt install gnupg)"

[ -d "$REPO" ] || die "--repo no es un directorio: $REPO"
REPO="$(cd "$REPO" && pwd -P)"
DIST="$REPO/dists/mytical"

[ -f "$DIST/Release" ] \
    || die "no existe $DIST/Release; el repo debe tener dists/mytical/Release"
[ -d "$REPO/pool" ] \
    || die "no existe $REPO/pool; el repo debe tener el pool de paquetes"

# La clave debe existir antes de crear nada en --out. `--list-secret-keys`
# falla si solo está la clave pública: firmar necesita la secreta.
key_listing="$("$GPG_BIN" --batch --with-colons --list-secret-keys "$KEY" 2>/dev/null || true)"
printf '%s\n' "$key_listing" | grep -q '^sec:' \
    || die "no hay clave secreta para $KEY en GNUPGHOME=${GNUPGHOME:-~/.gnupg}"
printf '%s\n' "$key_listing" \
    | awk -F: -v k="$KEY" '
        tolower($1) == "fpr" && tolower($10) == tolower(k) { found = 1 }
        END { exit(found ? 0 : 1) }
    ' \
    || die "el fingerprint $KEY no aparece en la clave secreta listada"

# Snapshot inmutable: no se sobrescribe una salida existente.
OUT="${OUT%/}"
[ -n "$OUT" ] || die "--out no puede ser la raíz"
out_name="$(basename "$OUT")"
if [ "$out_name" = "." ] || [ "$out_name" = ".." ]; then
    die "--out no puede ser '.' ni '..'"
fi

# Evitar copiar el repo dentro de sí mismo (p. ej. --out dentro de pool/).
# Se comprueba antes de crear directorios para no tocar el repo en un uso
# inválido; `realpath -m` resuelve la ruta aunque el padre aún no exista.
out_lex="$(realpath -m -- "$OUT" 2>/dev/null || true)"
if [ -n "$out_lex" ]; then
    case "$out_lex/" in
        "$REPO/"*) die "--out no puede estar dentro de --repo: $OUT" ;;
    esac
fi

out_parent="$(dirname "$OUT")"
[ "$out_parent" = "." ] && out_parent="$(pwd)"
mkdir -p "$out_parent"
out_parent="$(cd "$out_parent" && pwd -P)"
OUT="$out_parent/$out_name"

[ ! -e "$OUT" ] \
    || die "la salida ya existe: $OUT (las snapshots son inmutables; usa otra ruta)"

tmp_out=""
cleanup() {
    local status=$?
    if [ -n "$tmp_out" ] && [ -d "$tmp_out" ]; then
        rm -rf "$tmp_out"
    fi
    exit "$status"
}
trap cleanup EXIT

tmp_out="${OUT}.partial.$$"
[ ! -e "$tmp_out" ] || die "ya existe un temporal: $tmp_out"
mkdir -p "$tmp_out"

log "copiando dists/ y pool/ a la snapshot"
cp -a "$REPO/dists" "$REPO/pool" "$tmp_out/"

SIGNED_DIST="$tmp_out/dists/mytical"

log "firmando Release con $KEY (sin pedir passphrase)"
"$GPG_BIN" --batch --yes --local-user "$KEY" --no-tty --pinentry-mode error \
    --digest-algo SHA256 \
    --output "$SIGNED_DIST/Release.gpg" --detach-sign "$SIGNED_DIST/Release"
"$GPG_BIN" --batch --yes --local-user "$KEY" --no-tty --pinentry-mode error \
    --digest-algo SHA256 \
    --clearsign --output "$SIGNED_DIST/InRelease" "$SIGNED_DIST/Release"

for f in "$SIGNED_DIST/Release.gpg" "$SIGNED_DIST/InRelease"; do
    [ -s "$f" ] || die "la firma quedó vacía: $f"
done

# Verificación local antes de publicar. gpgv es la herramienta que usa APT;
# aquí basta con gpg porque la clave secreta también está en el keyring.
"$GPG_BIN" --batch --no-tty --verify "$SIGNED_DIST/InRelease" >/dev/null 2>&1 \
    || die "InRelease no verifica con la clave $KEY"
"$GPG_BIN" --batch --no-tty --verify "$SIGNED_DIST/Release.gpg" "$SIGNED_DIST/Release" \
    >/dev/null 2>&1 \
    || die "Release.gpg no verifica con la clave $KEY"

# Un repo publicado tiene que ser legible por el servidor web, aunque el
# operador tenga umask restrictivo. No se agrega permiso de escritura.
chmod -R a+rX "$tmp_out"

mv -T "$tmp_out" "$OUT"
tmp_out=""

printf 'OK: snapshot firmada en %s\n' "$OUT"
printf '    clave:      %s\n' "$KEY"
printf '    InRelease:  %s\n' "$OUT/dists/mytical/InRelease"
printf '    Release.gpg: %s\n' "$OUT/dists/mytical/Release.gpg"
printf '    sha256:     %s\n' \
    "$(sha256sum "$OUT/dists/mytical/InRelease" | awk '{print $1}')"
