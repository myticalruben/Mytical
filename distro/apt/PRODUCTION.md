# Repo APT de producción de Mytical

Este documento define cómo publicar el repo APT **de producción**. No
confundirlo con `distro/apt/public/`, que es el repo efímero que arma
`test_apt_repo.sh` y que se firma con una clave de prueba de un día.

Reglas de producción:

- la clave privada **nunca** vive en este repo, en el servidor web ni en CI;
- cada publicación es una **snapshot inmutable** con nombre UTC;
- sólo se publica lo que se verificó con `gpgv`;
- el cliente confía en una clave concreta (`Signed-By`), no en `trusted=yes`;
- Mytical no gana por prioridad sobre los paquetes de Ubuntu
  (`Pin-Priority: 500`).

## Resumen del flujo

```text
build host                     offline signer                 servidor
----------                     --------------                 --------
make packages
make repo PUBLIC=staging  --->  production-sign.sh   --->      snapshots/<UTC>/
                               (clave privada)                 current -> <UTC>
                               gpgv + SHA256SUMS
```

El servidor sólo recibe snapshots ya firmadas y verificadas. Si usás un token
hardware, el "offline signer" puede ser el propio servidor; la clave sigue sin
salir del token.

## 1. Clave GPG offline

Generá la clave en una máquina aislada, con el keyring en un medio cifrado y
desconectado. No la generes en el servidor de producción ni en el build host.

```bash
# Medio offline, p. ej. /media/offline
export GNUPGHOME=/media/offline/gnupg-mytical-apt
install -d -m 700 "$GNUPGHOME"

# RSA 4096, sólo firma, vence a los 2 años. GPG pide la passphrase de forma
# interactiva: no la escribas en un archivo, en un script ni en el repo.
gpg --quick-generate-key "Mytical APT <apt@mytical.invalid>" rsa4096 sign 2y

# Fingerprint completo (40 hex en OpenPGP v4; 64 en v5)
gpg --list-secret-keys --keyid-format=long
FPR="$(gpg --with-colons --list-secret-keys \
  | awk -F: '/^fpr:/{print $10; exit}')"
printf '%s\n' "$FPR"
```

Notas:

- La passphrase queda sólo en tu cabeza y en el `gpg-agent`. No se versiona.
- Si la clave tiene passphrase, `production-sign.sh` no la pide. Antes de
  firmar, desbloqueala en el agente firmando algo de forma interactiva; el
  agente la cachea durante su TTL:

  ```bash
  gpg --local-user "$FPR" --detach-sign --output /dev/null /etc/hostname
  ```

  Sin passphrase cacheada, el script falla a propósito (`--batch` +
  `--pinentry-mode error`); nunca abre un pinentry.
- Generá y guardá el certificado de revocación en el mismo medio offline:

  ```bash
  gpg --output "mytical-apt-$FPR.revoke.asc" --gen-revoke "$FPR"
  ```

- Hacé backup de la clave secreta **cifrada** en dos medios separados (ver
  [Rotación y backup](#rotación-y-backup)). Nunca la subas al repo.

## 2. Exportación de la clave pública

Desde el keyring offline:

```bash
gpg --armor --export "$FPR" > "mytical-apt-$FPR.asc"
gpg --export       "$FPR" > "mytical-apt-$FPR.gpg"

gpg --show-keys --with-fingerprint "mytical-apt-$FPR.asc"
sha256sum "mytical-apt-$FPR.asc" "mytical-apt-$FPR.gpg"
```

- `.asc` es ASCII armored y es el formato recomendado para `Signed-By`.
- `.gpg` es binario y es el que usa `gpgv --keyring` en las verificaciones.
- Publicá el fingerprint por un canal distinto del repo (release notes,
  documentación firmada, el propio ISO) para que el cliente pueda comprobar
  que la clave no fue sustituida.
- La clave pública sí puede ir en el repo, en el paquete de keyring o en
  `/usr/share/keyrings/`. La privada no.

## 3. Construir el repo sin firmar

En el build host, a partir de los `.deb` que produce `distro/`:

```bash
make -C distro packages

STAGING="$(mktemp -d)/repo"
make -C distro/apt repo PUBLIC="$STAGING"
```

`PUBLIC` se pasa por línea de comandos y evita mezclar la publicación con
`distro/apt/public/`. El resultado tiene esta forma:

```text
$STAGING/
├── .apt-release.conf
├── dists/mytical/
│   ├── Release
│   └── main/binary-amd64/
│       ├── Packages
│       └── Packages.gz
└── pool/main/m/
    ├── mytical-session/
    │   └── mytical-session_0.1.0-1~resolute1_all.deb
    └── ...
```

Comprobá antes de sacarlo del build host:

```bash
gzip -dc "$STAGING/dists/mytical/main/binary-amd64/Packages.gz" \
  | cmp -s - "$STAGING/dists/mytical/main/binary-amd64/Packages"
grep -E '^(Origin|Label|Suite|Codename|Architectures|Components):' \
  "$STAGING/dists/mytical/Release"
```

Pasá `$STAGING` al firmador offline por el medio que corresponda (tar cifrado,
USB, etc.). No hace falta llevar `distro/apt/public/`.

## 4. Firmar `Release` / `InRelease`

En el firmador offline, con el repo sin firmar y el `GNUPGHOME` de la clave:

```bash
export GNUPGHOME=/media/offline/gnupg-mytical-apt
SNAP="$(date -u +%Y%m%dT%H%M%SZ)"

distro/apt/production-sign.sh \
  --key "$FPR" \
  --repo "$STAGING" \
  --out "/media/offline/out/$SNAP"
```

El script:

1. exige `--key` (fingerprint completo de 40 o 64 hex), `--repo` y `--out`;
2. comprueba que exista la **clave secreta** para ese fingerprint; si no,
   falla antes de crear nada;
3. rechaza un `--out` que ya exista: las snapshots no se sobrescriben;
4. copia sólo `dists/` y `pool/` a un temporal; el repo de entrada no se toca;
5. firma con `gpg --batch --yes --local-user ...`, digest SHA256, sin pinentry:
   - `Release.gpg`: firma detached de `Release`;
   - `InRelease`: `Release` firmado en claro (el que prefiere APT);
6. verifica ambas firmas con `gpg` y recién entonces renombra el temporal a
   `--out`. No queda una snapshot a medio firmar.

Si la clave no está desbloqueada, el script falla; no hay prompt interactivo.
No guarda claves ni passphrases.

## 5. Estructura `dists/mytical/...`

Una snapshot publicada queda así:

```text
/srv/apt/snapshots/20261123T182600Z/
├── SHA256SUMS                         # manifiesto externo (ver §8)
├── dists/mytical/
│   ├── InRelease                      # Release + firma en claro (APT)
│   ├── Release                        # metadatos + checksums
│   ├── Release.gpg                    # firma detached de Release
│   └── main/binary-amd64/
│       ├── Packages
│       └── Packages.gz
└── pool/main/m/
    ├── mytical-desktop/
    │   └── mytical-desktop_0.1.0-1~resolute1_all.deb
    └── mytical-session/
        └── mytical-session_0.1.0-1~resolute1_all.deb
```

- `Release` lo genera `apt-ftparchive` con `Origin`, `Label`,
  `Suite: mytical`, `Codename: mytical`, `Architectures: amd64`,
  `Components: main` y checksums SHA256/SHA512 de `Packages` y
  `Packages.gz`.
- `Release.gpg` y `InRelease` los produce `production-sign.sh`.
- `Filename` en `Packages` es relativo a la raíz servida
  (`pool/main/...`), por eso `dists/` y `pool/` deben publicarse juntos.
- Si cambiás un `.deb`, hay que reconstruir y volver a firmar; nunca edites a
  mano una snapshot ya firmada.

## 6. Cliente: `mytical.sources` (deb822)

Instalá la clave pública en el equipo cliente:

```bash
sudo install -D -m 0644 mytical-apt-$FPR.asc \
  /usr/share/keyrings/mytical-apt.asc
# gpgv no lee keyrings armored; instalá también el binario para verificar
sudo install -D -m 0644 mytical-apt-$FPR.gpg \
  /usr/share/keyrings/mytical-apt.gpg
```

Creá `/etc/apt/sources.list.d/mytical.sources`:

```text
Types: deb
URIs: https://apt.mytical.invalid
Suites: mytical
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/mytical-apt.asc
```

`apt.mytical.invalid` es un placeholder: sustituilo por el host real. `URIs`
apunta a la raíz que contiene `dists/` y `pool/`; en el servidor conviene que
sea el symlink `current` (§8), no una snapshot concreta.

`Signed-By` limita la confianza a esa clave. No uses `Trusted: yes` en
producción. Si preferís keyring binario, `Signed-By` también acepta
`/usr/share/keyrings/mytical-apt.gpg`.

```bash
sudo apt-get update
apt-cache policy mytical-session
sudo apt-get install mytical-session
```

## 7. Pin 500

El repo de Mytical no debe reemplazar paquetes de Ubuntu. Un pin explícito de
500 documenta esa intención y evita que un cambio accidental lo vuelva
prioritario.

`/etc/apt/preferences.d/mytical.pref`:

```text
Package: *
Pin: release o=Mytical, c=mytical
Pin-Priority: 500
```

Qué significa:

- 500 es la prioridad normal de un repo con `Release`; Mytical no gana por
  prioridad sobre Ubuntu.
- Si las versiones difieren, APT elige la mayor entre las que tienen la misma
  prioridad. Si querés que Ubuntu sea siempre preferido, usá una prioridad
  menor (por ejemplo 100), no 500.
- No uses 990 o 1001 salvo que quieras que Mytical pise a Ubuntu a propósito;
  eso puede romper actualizaciones de la distro.

Verificación en el cliente:

```bash
apt-cache policy mytical-session
# Debe mostrar:
#  500 https://apt.mytical.invalid mytical/main amd64 Packages
apt-cache policy
```

## 8. Snapshots inmutables

Cada ejecución de `production-sign.sh` crea una snapshot nueva con timestamp
UTC. El script rechaza un `--out` existente; no hay "re-firma" de una snapshot.

Antes de publicar, en el firmador o en el servidor:

```bash
SNAP=/srv/apt/snapshots/20261123T182600Z

# 1. Verificar la firma con gpgv (misma herramienta que usa APT)
gpgv --keyring /usr/share/keyrings/mytical-apt.gpg \
  "$SNAP/dists/mytical/InRelease"
gpgv --keyring /usr/share/keyrings/mytical-apt.gpg \
  "$SNAP/dists/mytical/Release.gpg" \
  "$SNAP/dists/mytical/Release"

# 2. Manifiesto de la snapshot (después de firmar, antes de volverla read-only)
( cd "$SNAP" && find dists pool -type f -print0 \
    | sort -z | xargs -0 sha256sum > SHA256SUMS )
( cd "$SNAP" && sha256sum -c SHA256SUMS )

# 3. Volverla read-only para que nadie la edite por accidente
chmod -R a-w "$SNAP"
```

Publicación atómica con symlink:

```bash
cd /srv/apt
ln -sfn "snapshots/20261123T182600Z" .current.new
mv -Tf .current.new current
```

`mv -Tf` reemplaza el symlink de forma atómica. El servidor web se configura
con `root /srv/apt/current;` (nginx) o el equivalente, y sigue el symlink. Si
usás otro servidor, publicá el contenido de la snapshot bajo una ruta estable
con el mismo criterio.

Para volver atrás, apuntá `current` a la snapshot anterior:

```bash
cd /srv/apt
readlink -f current             # snapshot actual
ls -1 snapshots/                # snapshots disponibles
ln -sfn "snapshots/<anterior>" .current.new
mv -Tf .current.new current
```

Nunca borres la snapshot a la que apunta `current` ni la anterior usada para
rollback.

## 9. Rotación y backup

### Rotación de snapshots

- Retené, por ejemplo, 30 snapshots diarias y 12 mensuales. La política exacta
  va en el runbook; lo importante es que sea explícita y que no se borre nada
  sin backup verificado.
- Las snapshots son read-only. Para borrar una vieja:

  ```bash
  [ "$(readlink -f /srv/apt/current)" != "$SNAP" ] || exit 1
  chmod -R u+w "$SNAP"
  rm -rf "$SNAP"
  ```

- No reutilices nombres ni sobrescribas una snapshot para "arreglar" un
  release: generá una nueva y promovéla.

### Backup

- Copiá el árbol completo de snapshots (no sólo `current`) a un destino
  distinto del servidor:

  ```bash
  rsync -aH --numeric-ids \
    /srv/apt/snapshots/ backup:/srv/backup/mytical-apt/snapshots/
  ```

- Mantené al menos una copia offsite y cifrada. Verificá el backup:

  ```bash
  ( cd /srv/backup/mytical-apt/snapshots/<UTC> && sha256sum -c SHA256SUMS )
  gpgv --keyring /usr/share/keyrings/mytical-apt.gpg \
    /srv/backup/mytical-apt/snapshots/<UTC>/dists/mytical/InRelease
  ```

- Probá una restauración completa en un host limpio (servir la snapshot y
  hacer `apt-get update` en un root temporal). Un backup que nunca se restauró
  no cuenta.
- Conservá las claves públicas históricas: las snapshots viejas deben seguir
  verificando después de una rotación.

### Backup de la clave privada

La clave secreta se exporta **cifrada por su passphrase** y se guarda en dos
medios offline separados:

```bash
umask 077
gpg --armor --export-secret-keys "$FPR" \
  > "/media/offline/backup/mytical-apt-secret-$FPR.asc"
```

- El archivo exportado sigue protegido por la passphrase; no es una clave en
  claro. Aun así, nunca lo pongas en el repo, en el servidor ni en CI.
- Verificá el backup importándolo en un `GNUPGHOME` temporal aislado y
  firmando un archivo de prueba. Después borrá ese keyring temporal.
- Guardá también el certificado de revocación.

### Rotación de la clave

1. Generá la clave nueva en el mismo entorno offline y publicá su fingerprint
   por un canal independiente.
2. Distribuí la clave nueva a los clientes **antes** de dejar de firmar con la
   vieja (paquete de keyring o actualización de
   `/usr/share/keyrings/mytical-apt.asc`).
3. Durante el solapamiento, firmá cada `Release` con las dos claves. `gpg`
   acepta varios `--local-user` y produce varias firmas:

   ```bash
   SNAP=/srv/apt/snapshots/<UTC>
   DIST="$SNAP/dists/mytical"
   OLD_FPR=<fingerprint-viejo>
   NEW_FPR=<fingerprint-nuevo>

   gpg --batch --yes --no-tty --pinentry-mode error \
     --local-user "$OLD_FPR" --local-user "$NEW_FPR" \
     --digest-algo SHA256 \
     --detach-sign --output "$DIST/Release.gpg" "$DIST/Release"
   gpg --batch --yes --no-tty --pinentry-mode error \
     --local-user "$OLD_FPR" --local-user "$NEW_FPR" \
     --digest-algo SHA256 \
     --clearsign --output "$DIST/InRelease" "$DIST/Release"
   ```

   `production-sign.sh` firma con una sola clave; para el solapamiento usá el
   bloque anterior sobre la snapshot recién creada, antes del manifiesto y de
   `chmod`, o un token que exponga ambas. Después volvé a validar las dos
   firmas con `gpgv` (§8) antes de publicar.
4. Cuando todos los clientes hayan actualizado el keyring, firmá sólo con la
   nueva y retirá la vieja del keyring distribuido. Conservá la pública vieja
   para verificar snapshots históricas.

## 10. Verificación rápida de una publicación

```bash
SNAP=/srv/apt/snapshots/<UTC>

gpgv --keyring /usr/share/keyrings/mytical-apt.gpg \
  "$SNAP/dists/mytical/InRelease"
( cd "$SNAP" && sha256sum -c SHA256SUMS )
grep -E '^(Suite|Codename|Architectures|Components):' \
  "$SNAP/dists/mytical/Release"

sudo apt-get update
apt-cache policy mytical-session
```

Si `apt-get update` falla con `NO_PUBKEY`, la clave del cliente no es la que
firmó la snapshot. Si falla con `Hash Sum mismatch`, la snapshot se modificó
después de firmar o el servidor entregó otro contenido: no promuevas esa
snapshot.

## 11. Test

```bash
bash distro/tests/test_production_repo.sh
# o
bash distro/tests/test_apt_repo.sh   # test del repo efímero, no de producción
```

`test_production_repo.sh`:

1. busca `gpg`/`gpgv` (incluido `/nix/store/*-gnupg-*/bin` en este entorno);
2. crea una clave efímera de un día, sin passphrase, en un `GNUPGHOME`
   temporal;
3. arma un repo mínimo con `dists/mytical/Release`, `Packages`,
   `Packages.gz` y un `.deb` de relleno;
4. ejecuta `production-sign.sh` y comprueba que la snapshot tenga
   `Release.gpg` e `InRelease`;
5. valida `InRelease` y `Release.gpg` con `gpgv`;
6. comprueba que un fingerprint sin clave secreta falla y no crea salida.

Si no hay `gpg`/`gpgv`, imprime un `SKIP:` explícito y sale con **0**. No usa
la clave de producción ni toca `/srv/apt`. El `.deb` del test es de relleno:
sólo prueba el camino de firma, no la instalación con APT (eso lo cubre
`test_apt_repo.sh`).

## Checklist antes de publicar

- [ ] La clave privada está sólo en el medio offline/token.
- [ ] El fingerprint se publicó por un canal independiente.
- [ ] `make repo` se hizo en un `PUBLIC` staging, no en `public/`.
- [ ] `production-sign.sh` terminó sin errores y la snapshot es nueva.
- [ ] `gpgv` valida `InRelease` y `Release.gpg`.
- [ ] `SHA256SUMS` se generó y verifica.
- [ ] La snapshot se volvió read-only.
- [ ] El backup se actualizó y se verificó.
- [ ] `current` apunta a la snapshot publicada.
- [ ] El cliente tiene el `mytical.sources` con `Signed-By` y el pin 500.
- [ ] `apt-cache policy mytical-session` muestra el repo de Mytical con 500.
