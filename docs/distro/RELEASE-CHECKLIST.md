# Checklist de release — Mytical V1.0

> **Estado: NO-GO.** Auditado el 2026-11-23 (18:26–18:36 UTC) sobre
> `main` en `152a96d`, con el tag `v0.1.0` en `61f5443`.
>
> **Alcance:** release del overlay V1.0 (repo + 4 paquetes `.deb` + repo APT).
> La ISO V1.1 queda fuera de esta entrega según `distro/README.md` y
> `CHANGELOG.md`; se marca igualmente qué falta para publicarla.
>
> Este documento es el único archivo creado por la auditoría. No se modificó
> código ni configuración.

## 0. Resumen ejecutivo

**Listo y verificado:**

- `make -C distro test` pasa: construye los 4 `.deb` y valida sesión, welcome
  y tema SDDM.
- `python3 -m unittest discover -s tests` pasa: 30 tests.
- `nix flake check --no-build` pasa (con aviso de árbol sucio).
- El repo APT se genera con los 4 paquetes y el flujo de firma funciona
  (probado con una clave efímera en un directorio temporal).
- Licencia raíz GPL-3.0-or-later, throbbers e iconos wlogout propios, 4
  wallpapers CC0 propios, `LICENSE` del tema SDDM dentro del `.deb`.

**No listo (bloqueantes reales):**

1. **El tag no representa el release:** `v0.1.0` quedó 4 commits atrás de
   `main`; además es anotado pero **sin firma**.
2. **Árbol sucio:** 9 archivos rastreados de `graphify-out/` modificados y
   este documento sin commitear. `git describe` da
   `v0.1.0-4-g152a96d-dirty`.
3. **CI en rojo:** el job `shellcheck` falla en el commit del tag, en
   `7d5186c` y en `152a96d` (5 hallazgos reproducidos localmente). Los otros
   4 jobs pasan.
4. **Wallpapers personales sin licencia siguen en el repo público:** 22
   archivos, ~40 MB, servidos con HTTP 200 en `v0.1.0`. La propia auditoría
   (`ASSET-LICENSES.md`, P0-03) exige retirarlos.
5. **No hay clave APT de producción:** el flujo está implementado y
   commiteado en `152a96d`, pero no existe la clave real, fingerprint,
   revocación ni backup. El `distro/apt/public/` del working tree es de prueba
   (clave efímera no disponible), está incompleto (2 de 4 paquetes) y no sirve
   para publicar.
6. **No hay checksums, ni artefactos firmados, ni GitHub Release.** El tag
   no está firmado y no existe `SHA256SUMS`.
7. **Changelog incompleto y etiquetas inconsistentes:** la entrada 0.1.0 es
   del 2026-11-17, pero el tag incluye 11 commits posteriores y `main` 3 más;
   los paquetes dicen `0.1.0` y la documentación dice `V1.0`.
8. **Rollback no documentado ni probado:** `install-overlay.sh` no tiene
   desinstalación y `distro/RELEASE.md` no describe recuperación.
9. **Instalación limpia no reproducible con artefactos finales:** solo hay
   notas históricas de una VM; el nuevo verificador se omite fuera de Ubuntu
   y no sustituye una instalación real.
10. **Gate de assets incompleto:** el config `mytical.plymouth` sigue derivado
    de CachyOS según la auditoría (P0-02) y no hay manifiesto por asset con
    SPDX/autor/URL/SHA-256.

**Cambio durante la auditoría:** `main` avanzó de `61f5443` a `152a96d` en
medio de la auditoría (4 commits, ya empujados a `origin/main`). Al empezar,
`HEAD` era exactamente `v0.1.0`. Cualquier conclusión de "release" debe fijar
un commit explícito; hoy el tag y `main` no coinciden. Los estados de abajo
son una foto de las 18:36 UTC; si `main` volvió a moverse, hay que revalidar
§1, §2 y la CI.

---

## 1. Estado de Git

### 1.1 Rama, HEAD y tag

| Dato | Valor | Comando |
|---|---|---|
| Rama | `main` | `git branch --show-current` |
| Upstream | `origin/main`, sin divergencia (`+0 -0`) | `git status -sb` |
| HEAD | `152a96d` (`feat(apt): firma y snapshots de produccion`) | `git rev-parse --short HEAD` |
| `origin/main` | `152a96d` | `git rev-parse origin/main` |
| Tag | `v0.1.0` (anotado, objeto `9000790`) | `git cat-file -t v0.1.0` |
| Tag apunta a | `61f5443` | `git rev-parse v0.1.0^{commit}` |
| Tag en remoto | sí, `refs/tags/v0.1.0` | `git ls-remote --tags origin` |
| Mensaje del tag | `Mytical V1.0 Preview` | `git tag -l -n20 v0.1.0` |
| Firma del tag | **no firmado**: `error: no signature found` | `git tag -v v0.1.0` |
| Distancia tag→HEAD | 4 commits | `git rev-list --count v0.1.0..HEAD` |
| `git describe` | `v0.1.0-4-g152a96d-dirty` | `git describe --tags --always --dirty` |

Los 4 commits posteriores al tag (todos ya en `origin/main`):

```text
152a96d feat(apt): firma y snapshots de produccion
7d5186c docs(dist): registrar paleta neon e instalacion limpia
12750e4 test(dist): verificador de instalacion limpia
d20b005 feat(sddm): modo neon fijo configurable
```

`git diff --stat v0.1.0..HEAD`: 13 archivos, +1830/−72. Incluye cambio de
comportamiento en `palette.py` y `mytical-sddm-sync`, 428 líneas de tests
nuevos, el verificador de instalación limpia y el flujo de firma/snapshot de
producción. **No es solo documentación.**

### 1.2 Cambios sin commit

```text
 M graphify-out/.graphify_build_state.json
 M graphify-out/.graphify_labels.json
 M graphify-out/.graphify_labels.json.sig
 M graphify-out/.graphify_labels.pending.json
 M graphify-out/GRAPH_REPORT.md
 M graphify-out/cache/stat-index.json
 M graphify-out/graph.html
 M graphify-out/graph.json
 M graphify-out/manifest.json
?? docs/distro/RELEASE-CHECKLIST.md
```

- Los 9 archivos de `graphify-out/` están **rastreados** aunque
  `graphify-out/` figura en `.gitignore`. Hay 68 archivos de graphify en el
  índice (4,1 MB) y el diff acumulado es +1516/−150. El `.gitignore` no
  aplica a archivos ya rastreados: es una contradicción de configuración, no
  un olvido de commit.
- `graphify-out/.graphify_python` contiene una ruta local
  (`/home/ruben/.local/share/uv/...`); el grafo es salida de máquina y no
  fuente del release.
- `distro/apt/PRODUCTION.md`, `production-sign.sh` y
  `test_production_repo.sh` estuvieron sin commitear durante la auditoría y
  se commitearon en `152a96d`; **no están en `v0.1.0`**. Este documento sigue
  sin commitear, por diseño.
- `distro/build/` y `distro/apt/public/` están ignorados y no ensucian
  `git status`, pero `public/` está obsoleto (ver §4).

### 1.3 Qué contiene el artefacto fuente

`git archive --format=tar v0.1.0` pesa **68.669.440 bytes** e incluye
**22 wallpapers** de `Wallpapers/` y **78 entradas** de `graphify-out/`.
El repositorio es **público** (`private: false` en la API de GitHub), pesa
~113 MB según GitHub y **no tiene ningún GitHub Release** (`releases: []`).

Consecuencia: publicar el tag actual publica también los wallpapers sin
licencia y el grafo generado. No es un release "solo de código".

### 1.4 Rama y ramas laterales

- 10 ramas `feat/*` locales; 3 no fusionadas en `main`:
  `feat/alacritty-neon`, `feat/session-splash-gtk`, `feat/ubuntu-gdm-neon`.
- 2 worktrees extra en `../dotfiles-splash-gtk` y
  `../dotfiles-splash-quickshell`.
- Las 3 ramas no fusionadas no entran en el tag (el resto sí está fusionado);
  no bloquean por sí solas, pero conviene decidir su destino antes de anunciar
  el release (ver D-06).

---

## 2. Build y tests actuales

Ejecutado en `7d5186c` salvo donde se indica. Todos los comandos se corrieron
desde la raíz del repo.

| Comando | Resultado | Evidencia / notas |
|---|---|---|
| `make -C distro test` | **OK** (exit 0) | Construye 4 `.deb`; `OK: paquete mytical-session`, `mytical-welcome`, `mytical-sddm-theme`; `OK: test_session.sh`. `test_packages.sh` no cubre `mytical-desktop` (metapaquete). |
| `python3 -m unittest discover -s tests` | **OK** | `Ran 30 tests in 1.108s` — `OK` |
| `nix flake check --no-build` | **OK** (exit 0) | `all checks passed!`; aviso `Git tree ... is dirty` y `app ... lacks attribute 'meta'`. Se usó `/opt/deepseek-harness/.nix-profile/bin/nix` (Nix 2.35.5): `nix` no está en `PATH`. |
| `shellcheck --shell=bash $(git ls-files '*.sh') scripts/volume scripts/wallpaper scripts/session-splash` | **FALLA** (exit 1) | 5 hallazgos: `install-overlay.sh:27` SC1091; `test_session.sh:93,101,143,146` SC2016. Reproducido con shellcheck 0.11.0. |
| `make -C distro/apt test` (sobre el árbol extraído de `v0.1.0`) | **OK** (exit 0) | 4 paquetes, clave GPG efímera, `firma OpenPGP correcta`, `apt-get update` aislado y descarga de `mytical-session`. No se repitió sobre `7d5186c`, pero los cambios posteriores no tocan el flujo APT. |
| `bash distro/tests/test_clean_install.sh` | **SKIP** (exit 0) | En Debian 13 imprime `SKIP: el sistema no es Ubuntu`; no verifica nada. |
| `distro/tests/test_production_repo.sh` | **no ejecutado** | Archivo sin commitear; no forma parte del tag. |
| `distro/apt/production-sign.sh` | **no ejecutado** | Archivo sin commitear; el flujo equivalente se validó con `make sign` y clave efímera. |

**CI (GitHub Actions).** Workflow `check`, 5 jobs:

- Commit del tag `61f5443` (run `45238443883`): **failure**. Pasan
  `referencias`, `luacheck`, `python` y `nix flake check`; falla `shellcheck`.
- `HEAD` `7d5186c` (run `45239113755`, 18:30:25Z): **failure** por el mismo
  `shellcheck`. Los otros 4 jobs pasan.

El workflow solo hace chequeos estáticos: no construye paquetes, no corre
`distro/tests/`, no valida el repo APT y no verifica licencias.

---

## 3. Paquetes y versiones

| Paquete | Versión | Tamaño `.deb` | Contenido principal | Licencia dentro del `.deb` |
|---|---|---:|---|---|
| `mytical-sddm-theme` | `0.1.0-1~resolute1` | 2.163.900 B | Tema QML, 7 SVG, `palette.py`, `mytical-sddm-sync`, `Backgrounds/wallpaper` (CC0, SHA-256 `ac074f9b…` = `distro/branding/wallpapers/mytical-01.png`), `LICENSE` GPL | sí (GPL del upstream) |
| `mytical-session` | `0.1.0-1~resolute1` | 2.064 B | `/usr/bin/mytical-session`, `mytical.desktop`, `/etc/sddm.conf.d/10-mytical.conf` | no |
| `mytical-welcome` | `0.1.0-1~resolute1` | 2.612 B | `/usr/bin/mytical-welcome` | no |
| `mytical-desktop` | `0.1.0-1~resolute1` | 1.140 B | metapaquete de dependencias APT | no |

- Arquitectura `all`, `Maintainer: Mytical <dev@mytical.invalid>`.
- Los 4 comparten versión, pero **ninguno tiene
  `/usr/share/doc/<pkg>/copyright`**. El tema SDDM sí trae su `LICENSE`; los
  otros tres no llevan aviso de copyright ni oferta de fuente. Para un repo
  APT que distribuye binarios GPL conviene cerrarlo antes de publicar (D-02).
- `distro/tests/test_packages.sh` **hardcodea** `0.1.0-1~resolute1` en las
  rutas: subir versión obliga a editar el test (D-04).
- El metapaquete `mytical-desktop` no se valida en `make -C distro test` más
  allá de construirse y de comprobar que no declare dependencias GNOME/Ubuntu:
  `test_packages.sh` no lo cubre.

**Decisión pendiente de etiqueta:** el tag es `v0.1.0`, los paquetes
`0.1.0-1~resolute1`, el changelog `0.1.0 — Mytical V1.0 Preview` y
`distro/RELEASE.md` dice `Release V1.0 Preview`. No hay un `1.0.0` en ningún
artefacto. Si el release va a llamarse V1.0 final, hay que subir versión y
crear tag nuevo; si sigue siendo Preview, hay que dejar de llamarlo "release
V1.0" sin apellido (B-07).

---

## 4. Repo APT y clave de producción

### 4.1 Estado actual

- `distro/apt/public/` existe, pero está **obsoleto**: se generó el
  **2026-11-17 00:50:24 UTC**, contiene solo **2 de 4 paquetes**
  (`mytical-desktop` y `mytical-session`; faltan `mytical-sddm-theme` y
  `mytical-welcome`) y está firmado con la **clave efímera del test**
  (fingerprint de la firma en `InRelease`, clave efímera no disponible). No es un repo de
  producción ni refleja el árbol actual.
- `distro/apt/public/` está en `.gitignore`; el estado obsoleto vive solo en
  el working tree, pero confunde si alguien sirve ese directorio.
- **No hay clave de producción.** No existe fingerprint documentado, ni
  keyring, ni certificado de revocación, ni backup. `gpg`/`gpgv` no están en
  `PATH` (sí en `/nix/store/nxjq9lhr0q6x8bjlvrih0bdh4d9dz5zj-gnupg-2.4.9/bin`).
- `docs/distro/FUTURE-FEATURES.md` ya marca como **P0 "Clave GPG de
  producción del repo APT y publicación firmada — Pendiente"**.
- `distro/apt/PRODUCTION.md`, `distro/apt/production-sign.sh` y
  `distro/tests/test_production_repo.sh` existen **sin commitear**: son un
  buen punto de partida, pero no están en `v0.1.0` ni en `7d5186c` y no se
  auditaron como parte del release.

### 4.2 Lo que sí se verificó

En un directorio temporal, a partir del árbol de `v0.1.0`:

1. `make -C distro/apt repo PUBLIC=<tmp>` generó **4 paquetes** con
   `Packages`/`Packages.gz` y checksums SHA256/SHA512 correctos.
2. Se creó una clave RSA-3072 efímera (1 día, sin passphrase) en un
   `GNUPGHOME` temporal y `make -C distro/apt sign` firmó `Release.gpg` e
   `InRelease`.
3. `gpg --verify InRelease` devolvió **Good signature**.
4. `make -C distro/apt test` sobre el árbol extraído pasó completo:
   `apt-get update` aislado resolvió `mytical-session` y descargó el `.deb`.

Conclusión: **el mecanismo funciona**; lo que falta es la clave real, su
custodia y publicar una snapshot firmada de los 4 paquetes actuales. No se
probó `production-sign.sh` ni una instalación APT real desde un servidor.

---

## 5. Assets y licencias

### 5.1 Cerrado o encaminado

| Activo | Estado |
|---|---|
| Licencia raíz | **GPL-3.0-or-later** aceptada (ADR 0008, `LICENSE`, `COPYRIGHT`). |
| Throbbers Plymouth (41) | Reemplazados por anillo propio según `ASSET-LICENSES.md` (resolución 2026-11-17). No se re-verificó byte a byte contra CachyOS en esta auditoría. |
| Iconos wlogout (5) | Reemplazados por line-art propio según la misma resolución. |
| Wallpapers de la distro | 4 PNG propios en `distro/branding/wallpapers/`, dedicados a **CC0-1.0**; el tema SDDM empaqueta `mytical-01.png`. |
| Tema SDDM | GPL-3.0-or-later, `LICENSE` incluida en el `.deb`; upstream atribuido en `THIRD_PARTY_NOTICES`. |
| Fuente Audiowide | OFL-1.1, `OFL.txt` presente. |

### 5.2 Abierto (bloquea publicación)

1. **22 wallpapers personales siguen en el repo público** (`Wallpapers/`,
   ~40 MB, 22 archivos rastreados). La auditoría los clasifica
   **P0-03 — bloqueante**: varios son arte de personajes, `ww.jpg` es un
   personaje reconocible de *Evangelion*, `6.jpg` es una foto real con EXIF de
   cámara/RAW y `02.jpg`/`w0.jpg` tienen riesgo alto. Verificado hoy:
   `raw.githubusercontent.com/.../v0.1.0/Wallpapers/01.png`, `02.jpg` y
   `ww.jpg` devuelven **HTTP 200**. No es un riesgo futuro: ya están
   publicados.
2. **`mytical.plymouth` derivado de CachyOS** (P0-02): la resolución parcial
   de `ASSET-LICENSES.md` lo deja explícitamente pendiente ("revisión de la
   configuración Plymouth derivada").
3. **No hay manifiesto por asset** con ruta, SPDX, autor/titular, URL de
   origen y SHA-256, que es la puerta de release de `ASSET-LICENSES.md` §7.
4. El propio documento de assets mezcla el veredicto viejo ("no apto", 6 P0)
   con resoluciones posteriores; conviene un encabezado de "estado vigente"
   para que nadie lea la tabla vieja como actual (D-08).
5. `mytical-welcome` y `mytical-sddm-sync` dependen de
   `~/Pictures/Wallpapers/` (poblado por `setup.py` desde `Wallpapers/`). En
   una instalación limpia esa ruta no existe; el tema cae al fondo CC0
   empaquetado, pero el selector de wallpapers queda vacío hasta que el
   usuario copie fondos. No es bloqueante legal, sí de primera experiencia.

---

## 6. Checklist de release

Marcas: **[B]** bloqueante, **[D]** deseable. Cada casilla debe cerrarse con
evidencia reproducible (comando + salida + fecha), no con una afirmación.

### 6.1 Congelar el release

- [ ] **[B]** Detener commits y trabajo concurrente; acordar el commit exacto
      del release. Hoy `main` se movió durante la auditoría.
- [ ] **[B]** Decidir si el release es "V1.0 Preview" sobre `0.1.0` o "V1.0"
      final con `1.0.0` y tag nuevo. Dejarlo escrito en `CHANGELOG.md`.
- [ ] **[B]** Resolver los 3 archivos sin commitear (`PRODUCTION.md`,
      `production-sign.sh`, `test_production_repo.sh`): incluirlos en el
      commit de release o retirarlos del árbol de trabajo.
- [ ] **[D]** Decidir el destino de las 10 ramas `feat/*` y los 2 worktrees
      extra.

### 6.2 Fuente limpia

- [ ] **[B]** `git status --porcelain` vacío en el commit de release.
- [ ] **[B]** `git ls-files graphify-out | wc -l` = `0`; sacar
      `graphify-out/` del índice (`git rm -r --cached graphify-out`) y
      commitear. No alcanza con `.gitignore`.
- [ ] **[B]** `git ls-files Wallpapers | wc -l` = `0`; retirar los 22
      wallpapers del HEAD **y de la historia pública** (filter-repo/BFG), o
      decidir explícitamente que el repo deja de ser público. Un commit que
      solo los borre no elimina el blob del historial.
- [ ] **[B]** Confirmar que `git archive` del commit de release no contiene
      `Wallpapers/` ni `graphify-out/`, y que su tamaño es razonable.
- [ ] **[D]** Revisar el tamaño del repo (`.git` ~118 MB) después de limpiar
      historia; evaluar LFS si se conservan assets grandes.

### 6.3 Tag

- [ ] **[B]** Crear el tag en el commit congelado, **anotado y firmado**
      (`git tag -s -a v1.0.0 -m ...`), o mover el tag existente con una
      decisión explícita (el `v0.1.0` ya está publicado; reescribirlo exige
      borrarlo en remoto y avisar).
- [ ] **[B]** `git tag -v <tag>` devuelve `Good signature`.
- [ ] **[B]** `git rev-parse <tag>^{commit}` == `git rev-parse HEAD` ==
      `git rev-parse origin/main`.
- [ ] **[B]** `git ls-remote --tags origin` muestra el tag nuevo.
- [ ] **[D]** Etiquetar también los commits de release con firma de commit
      (`git commit -S`).

### 6.4 Changelog

- [ ] **[B]** Completar `CHANGELOG.md` con **todos** los cambios del tag:
      los 11 commits entre el 2026-11-18 y el tag (keyring/polkit, mouse keys,
      sincronización de fondo SDDM, paleta neón, verificador de instalación
      limpia) y los 3 posteriores al tag.
- [ ] **[B]** Fecha y versión de la entrada coinciden con tag y paquetes.
- [ ] **[B]** "Limitaciones conocidas" actualizadas: Preview/overlay, ISO
      V1.1 fuera de alcance, clave APT, wallpapers.
- [ ] **[D]** Enlazar el changelog desde el GitHub Release.

### 6.5 Build y tests

- [ ] **[B]** `make -C distro clean packages test` desde un clon limpio
      (no desde el working tree sucio).
- [ ] **[B]** `python3 -m unittest discover -s tests` (30 tests hoy).
- [ ] **[B]** `nix flake check --no-build` (con `nix` en `PATH`; aquí se usó
      el perfil de `/opt/deepseek-harness/.nix-profile/bin`).
- [ ] **[B]** CI verde en el commit del tag: los 5 jobs, incluido
      `shellcheck`.
- [ ] **[B]** Corregir los 5 hallazgos de shellcheck (SC1091 y 4×SC2016) o
      justificarlos con `# shellcheck disable=...` revisado.
- [ ] **[B]** `make -C distro/apt test` verde con GnuPG disponible.
- [ ] **[D]** Añadir `distro/tests/test_clean_install.sh` y
      `test_production_repo.sh` a `make -C distro test` (hoy no se ejecutan).
- [ ] **[D]** Añadir un job de CI que construya los `.deb` y corra los tests
      de `distro/`; hoy CI no toca el empaquetado.
- [ ] **[D]** Quitar el hardcode de versión en `test_packages.sh` y cubrir
      `mytical-desktop`.

### 6.6 Paquetes y repo APT

- [ ] **[B]** Regenerar los 4 `.deb` desde el commit congelado y verificar
      `dpkg-deb -c` (contenido, permisos, `conffiles`).
- [ ] **[B]** Generar la clave GPG de producción **offline** (RSA 4096, solo
      firma, vencimiento definido), exportar la pública, guardar revocación y
      backup cifrado; registrar fingerprint en la documentación.
- [ ] **[B]** `make -C distro/apt repo PUBLIC=<staging>` +
      `production-sign.sh` (o `make sign`) sobre los 4 paquetes; `gpgv`
      verifica `InRelease` y `Release.gpg`.
- [ ] **[B]** Publicar una snapshot inmutable con `current -> <UTC>`; no
      reutilizar `distro/apt/public/` como repo de producción.
- [ ] **[B]** En una VM limpia: `apt-get update` con `Signed-By`, instalar
      `mytical-session` desde el repo y comprobar que el candidato viene del
      repo de Mytical (no de Ubuntu).
- [ ] **[B]** Confirmar que la clave privada no está en el repo, en CI ni en
      el servidor web.
- [ ] **[D]** Añadir `/usr/share/doc/<pkg>/copyright` a los 4 paquetes y la
      oferta de fuente GPL correspondiente.
- [ ] **[D]** Documentar rotación/revocación de la clave y el pin
      `Pin-Priority: 500`.

### 6.7 Checksums y firma de artefactos

- [ ] **[B]** Generar `SHA256SUMS` sobre los 4 `.deb` (y la ISO cuando
      exista) desde el commit congelado.
- [ ] **[B]** Firmar `SHA256SUMS` (`gpg --detach-sign --armor`) o publicar
      los checksums dentro de `InRelease`; incluir el fingerprint usado.
- [ ] **[B]** Verificar los checksums desde una descarga limpia, no desde el
      build host.
- [ ] **[B]** Crear el GitHub Release con: tag firmado, notas del changelog,
      los 4 `.deb`, `SHA256SUMS`/firma y fingerprint de la clave APT.
- [ ] **[D]** Automatizar checksums + release en un script/CI para que no
      dependa de pasos manuales.

### 6.8 Instalación limpia

- [ ] **[B]** VM nueva Ubuntu 26.04 (snapshot previo), sin restos de Nix ni
      de Mytical.
- [ ] **[B]** `sudo distro/install-overlay.sh --user "$USER" --dry-run` y
      luego la instalación real con los `.deb` del release.
- [ ] **[B]** `bash distro/tests/test_clean_install.sh` → 13 OK, 0 FALTA.
- [ ] **[B]** `systemctl is-active sddm`; `ls /usr/share/wayland-sessions`
      muestra solo `mytical.desktop`; `dpkg -s` de los 4 paquetes
      `install ok installed`.
- [ ] **[B]** Reiniciar, entrar por SDDM, comprobar Hyprland/waybar/dunst/
      wallpaper/hypridle y `mytical-welcome --check`.
- [ ] **[B]** Repetir la instalación **desde el repo APT firmado**, no solo
      desde `.deb` locales.
- [ ] **[B]** Registrar evidencia: fecha, VM, commit, SHA-256 de los `.deb`,
      salida de los comandos y captura.
- [ ] **[D]** Automatizar la instalación limpia en CI (contenedor/QEMU).

### 6.9 Rollback

- [ ] **[B]** Documentar y probar el rollback en la VM antes de publicar:
      snapshot, `apt purge` de los 4 paquetes, `systemctl disable --now
      mytical-sddm-sync.path`, borrar unidades generadas si quedan, restaurar
      `/etc/sddm.conf.d/` y el display manager original, `nix profile
      rollback` / `home-manager --rollback`.
- [ ] **[B]** Verificar que tras el rollback SDDM vuelve a listar la sesión
      original y que no quedan unidades `mytical-*` fallando.
- [ ] **[B]** Añadir la sección "Rollback" a `distro/RELEASE.md` y al GitHub
      Release (hoy no existe; `install-overlay.sh` no tiene `--uninstall`).
- [ ] **[D]** Añadir `--uninstall`/`--rollback` al instalador con `--dry-run`.

### 6.10 Documentación

- [ ] **[B]** `distro/RELEASE.md` actualizado: ya no diga "faltan clave APT y
      revisión de assets" sin estado; incluir tag, checksums, firma,
      instalación limpia y rollback.
- [ ] **[B]** `README.md` enlaza la instalación del overlay V1.0 y aclara que
      la ISO es V1.1; hoy el README es solo de dotfiles.
- [ ] **[B]** `THIRD_PARTY_NOTICES` y `ASSET-LICENSES.md` coherentes con lo
      que realmente se publica (sin wallpapers personales, sin throbbers
      CachyOS, con manifiesto de assets).
- [ ] **[B]** `docs/distro/CLEAN-INSTALL.md` y `PRODUCTION.md` commiteados y
      enlazados desde `RELEASE.md` (hoy el segundo está sin commitear).
- [ ] **[D]** Un solo lugar canónico para la versión (`VERSION` o
      `CHANGELOG.md`); el plan lo menciona y no existe.
- [ ] **[D]** Aviso de no afiliación con Ubuntu/Canonical visible en el
      release.

### 6.11 Publicación

- [ ] **[B]** Repo público sin wallpapers sin licencia (HEAD e historia) y
      sin `graphify-out/`.
- [ ] **[B]** GitHub Release creado con tag firmado + checksums + `.deb`.
- [ ] **[B]** Anuncio limitado a "overlay V1.0 Preview"; no anunciar ISO.
- [ ] **[B]** Clave APT pública publicada con fingerprint y instrucciones
      `Signed-By`.
- [ ] **[D]** ISO V1.1: no publicar hasta cerrar P0-02, manifiesto de assets
      y el pipeline `distro/iso/` (hoy vacío).

---

## 7. Bloqueantes

| ID | Bloqueante | Evidencia | Criterio de cierre |
|---|---|---|---|
| **B-01** | El tag no identifica el release actual | `v0.1.0` → `61f5443`; `main`/`origin` → `7d5186c`; 3 commits de diferencia; tag anotado sin firma (`git tag -v` → "no signature found") | Tag firmado en el commit congelado, `HEAD == tag == origin/main`, `git tag -v` OK |
| **B-02** | Árbol sucio y salida generada rastreada | 9 archivos `graphify-out/` modificados; 68 rastreados; 4,1 MB; `git describe` `...-dirty`; rutas `/home/ruben/...` en la salida | `git status` vacío; `git ls-files graphify-out` vacío; archive sin graphify |
| **B-03** | CI en rojo en el commit del tag | Run `45238443883` failure (shellcheck); HEAD `45239113755` failure; 5 hallazgos reproducidos (SC1091, 4×SC2016) | Los 5 jobs verdes en el commit del tag |
| **B-04** | Wallpapers personales sin licencia en repo público | 22 archivos, ~40 MB, HTTP 200 en `v0.1.0`; `ASSET-LICENSES.md` P0-03 | 0 wallpapers sin licencia en HEAD e historia; manifiesto con licencia/autor/URL/SHA-256 |
| **B-05** | Sin clave APT de producción y repo de prueba obsoleto | `public/` del 2026-11-17, 2/4 paquetes, firmado con clave efímera no disponible; sin fingerprint/revocación/backup | Clave offline + snapshot firmada de 4 paquetes + `apt-get update` verificado en VM limpia |
| **B-06** | Sin checksums ni artefactos firmados ni GitHub Release | No hay `SHA256SUMS`; `.deb` sin firma; tag sin firma; `releases: []` | `SHA256SUMS` firmado, tag firmado, GitHub Release con artefactos y fingerprint |
| **B-07** | Changelog incompleto y versión/label inconsistentes | Entrada 0.1.0 del 2026-11-17; 11 commits entre esa fecha y el tag + 3 posteriores sin reflejar; `0.1.0` vs "V1.0" | Changelog completo, versión/tag/paquetes alineados, decisión Preview vs final escrita |
| **B-08** | Rollback no documentado ni probado | `install-overlay.sh` sin desinstalación; `RELEASE.md` sin rollback; solo menciones en spec/ADR | Procedimiento probado en VM y publicado en `RELEASE.md` |
| **B-09** | Instalación limpia no reproducible | Solo notas históricas en `PROGRESS.md`; `test_clean_install.sh` hace SKIP fuera de Ubuntu; sin ISO | VM Ubuntu 26.04 limpia instalada con los `.deb`/repo del release, con evidencia |
| **B-10** | Gate de assets incompleto | `mytical.plymouth` derivado (P0-02 abierto); sin manifiesto por asset; paquetes sin `copyright` | P0-02 cerrado, manifiesto completo, avisos y `copyright` en los `.deb` |
| **B-11** | ISO inexistente (solo si se va a publicar ISO) | `distro/iso/` y `distro/installer/` vacíos; sin pipeline de build | Fuera de V1.0 (overlay); bloquea V1.1/ISO hasta implementarla |

---

## 8. Deseables

| ID | Deseable | Por qué |
|---|---|---|
| **D-01** | Crear un `VERSION` o fuente única de versión | Evita que tag, changelog, paquetes y tests se desincronicen |
| **D-02** | `/usr/share/doc/<pkg>/copyright` y oferta de fuente GPL en los 4 paquetes | Cumplimiento GPL/DFSG al distribuir binarios por APT |
| **D-03** | Job de CI que construya `.deb` y corra `distro/tests/` | Hoy CI no detecta roturas de empaquetado; el shellcheck rojo pasó inadvertido al tag |
| **D-04** | Incluir `test_apt_repo.sh`, `test_clean_install.sh` y `test_production_repo.sh` en `make test`; quitar versión hardcodeada | Cobertura real del release, no solo de tres paquetes |
| **D-05** | Borrar/regenerar `distro/apt/public/` y documentar el flujo de snapshots | El `public/` actual es un señuelo obsoleto con 2 paquetes y clave muerta |
| **D-06** | Triage de las 10 ramas `feat/*` y los 2 worktrees | Menos ruido y menos riesgo de publicar trabajo a medias |
| **D-07** | Evaluar LFS/historia tras retirar wallpapers | GitHub informa ~113 MB y `.git` ~118 MB; un clon limpio no debería arrastrar 40 MB de arte sin licencia |
| **D-08** | Encabezado de "estado vigente" en `ASSET-LICENSES.md` y actualizar `RELEASE.md` | El veredicto viejo (6 P0) convive con resoluciones posteriores y confunde |
| **D-09** | Script de release que genere checksums, firme y publique | Reduce el error manual y deja evidencia reproducible |
| **D-10** | Aviso de no afiliación con Ubuntu/Canonical en el release y en el README | P1 de la auditoría de marca; barato y evita confusión |
| **D-11** | Firmar commits/tags por defecto y publicar el fingerprint | Cadena de confianza verificable por terceros |
| **D-12** | Decidir si `README.md` debe mencionar el overlay o separar README de dotfiles/distro | Hoy el README no guía a la instalación V1.0 |

---

## 9. Limitaciones de esta auditoría

- **No se construyó ni probó la ISO**: `distro/iso/` y `distro/installer/` están
  vacíos; el release V1.0 es overlay, la ISO es V1.1 según la documentación.
- **No se hizo una instalación limpia en Ubuntu 26.04**: no hay VM accesible
  desde este entorno. `test_clean_install.sh` se omitió (Debian 13) y las
  únicas evidencias de instalación son las notas de `PROGRESS.md` del
  2026-11-23 en `10.0.0.154`.
- **No se usó una clave de producción**: no existe. La firma se validó con una
  clave RSA-3072 efímera en un `GNUPGHOME` temporal; no se probó
  `production-sign.sh` (sin commitear).
- **`make -C distro/apt test` no se corrió contra el working tree** para no
  sobrescribir `distro/apt/public/`; se corrió sobre una extracción limpia de
  `v0.1.0` en `/tmp`, que es el árbol del tag.
- **No se re-verificó byte a byte** que los throbbers/iconos nuevos no
  deriven de CachyOS; se toma la resolución de `ASSET-LICENSES.md` como
  estado documentado, no como peritaje nuevo.
- **CI del HEAD** terminó en failure por shellcheck durante la auditoría; el
  estado de GitHub se consultó vía API el 2026-11-23 ~18:32 UTC.
- **El árbol se movió durante la auditoría** (`61f5443` → `7d5186c`) y hay 3
  archivos de trabajo concurrente sin commitear (más este documento);
  cualquier número de "commits" o "estado limpio" debe revalidarse al congelar
  el release.
- **Solo se regeneraron artefactos ignorados** (`distro/build/`,
  `__pycache__/`) al correr los tests. Esta auditoría no modificó código ni
  configuración, no tocó `distro/apt/public/` ni creó commits; los 3 commits
  de §1.1 los produjo trabajo concurrente.

---

## Anexo A — Comandos de verificación usados

```sh
git status --porcelain=v2 --branch
git log --oneline --decorate -15
git tag -l -n20
git cat-file -t v0.1.0
git tag -v v0.1.0
git rev-parse HEAD v0.1.0^{commit} origin/main
git rev-list --count v0.1.0..HEAD
git describe --tags --always --dirty
git ls-files graphify-out | wc -l
git ls-files Wallpapers | wc -l
git archive --format=tar v0.1.0 | wc -c

make -C distro test
python3 -m unittest discover -s tests
/opt/deepseek-harness/.nix-profile/bin/nix flake check --no-build
shellcheck --shell=bash $(git ls-files '*.sh') scripts/volume scripts/wallpaper scripts/session-splash

make -C distro/apt repo PUBLIC=<tmp>
make -C distro/apt sign PUBLIC=<tmp> GPG_KEY=<efímera>
gpg --verify <tmp>/dists/mytical/InRelease
bash distro/tests/test_apt_repo.sh   # sobre extracción de v0.1.0 en /tmp
bash distro/tests/test_clean_install.sh
```

## Anexo B — Evidencia externa consultada

- Repo GitHub: `https://api.github.com/repos/myticalruben/.dotfiles`
  (`private: false`, `size: 113496`, `releases: []`).
- Run CI del tag: `https://api.github.com/repos/myticalruben/.dotfiles/actions/runs/45238443883`
  (failure; job `shellcheck`).
- Run CI de `7d5186c`: run `45239113755` (failure; mismo job).
- Wallpaper público: `https://raw.githubusercontent.com/myticalruben/.dotfiles/v0.1.0/Wallpapers/ww.jpg`
  (HTTP 200).
