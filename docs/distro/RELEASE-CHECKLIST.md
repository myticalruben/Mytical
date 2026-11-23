# Checklist de release — Mytical V1.0

> **Addendum 2026-11-23 18:45 UTC:** este documento conserva la foto de la
> auditoría de las 18:38. Después se commitearon: P0-02/Plymouth (`c82f0db`),
> shellcheck y rollback (`c82f0db`), y la limpieza de `graphify-out/` y
> `Wallpapers/` en HEAD (`09239f6`). Siguen abiertos: tag firmado, historia
> pública con wallpapers, clave APT real, checksums/GitHub Release, copyright
> en los `.deb`, manifiesto por asset y prueba de rollback real. El veredicto
> global sigue siendo **NO-GO**.

> **Estado: NO-GO.** Snapshot de la auditoría: 2026-11-23 18:38 UTC, `main`
> en `09239f6`, tag `v0.1.0` en `61f5443`.
>
> **Alcance:** release del overlay V1.0 (repo + 4 paquetes `.deb` + repo APT).
> La ISO V1.1 queda fuera de esta entrega según `distro/README.md` y
> `CHANGELOG.md`; se marca igualmente qué falta para publicarla.
>
> Este documento lo creó la auditoría; trabajo concurrente lo commiteó en
> `09239f6` y después quedó una revisión sin commitear. No se modificó código
> ni configuración para producir el diagnóstico.

## 0. Resumen ejecutivo

**Listo y verificado (en `09239f6`):**

- `make -C distro test` pasa: construye los 4 `.deb` y valida sesión, welcome
  y tema SDDM.
- `python3 -m unittest discover -s tests` pasa: 30 tests.
- `nix flake check --no-build` pasa (con aviso de árbol sucio).
- El repo APT se genera con los 4 paquetes y el flujo de firma funciona
  (probado con una clave efímera en un directorio temporal).
- El flujo de producción (`PRODUCTION.md`, `production-sign.sh`) está
  commiteado y su test aislado pasa con clave efímera.
- Licencia raíz GPL-3.0-or-later, throbbers e iconos wlogout propios, 4
  wallpapers CC0 propios, `LICENSE` del tema SDDM dentro del `.deb`.
- `e9176fe` sacó los 22 wallpapers personales y `graphify-out/` del **árbol
  de `main`**; `setup.py`/`nix/home.nix`/`session-start` ahora apuntan a
  `distro/branding/wallpapers/`.

**No listo (bloqueantes reales):**

1. **El tag no representa el release:** `v0.1.0` quedó **6 commits** atrás de
   `main`; además es anotado pero **sin firma**. El tag todavía contiene los
   wallpapers personales y `graphify-out/` (la limpieza está solo en `main`).
2. **CI en rojo:** el job `shellcheck` falla en el commit del tag y en
   `09239f6` (5 hallazgos reproducidos localmente). Los otros 4 jobs pasan.
3. **Wallpapers personales sin licencia siguen públicos en el tag y en la
   historia:** 22 archivos, ~40 MB, servidos con HTTP 200 en `v0.1.0`. La
   propia auditoría (`ASSET-LICENSES.md`, P0-03) exige retirarlos también del
   historial; borrarlos en un commit nuevo no elimina los blobs.
4. **No hay clave APT de producción:** el flujo está implementado y
   commiteado, pero no existe la clave real, fingerprint, revocación ni
   backup. El `distro/apt/public/` del working tree es de prueba (clave
   efímera no disponible), está incompleto (2 de 4 paquetes) y no sirve para
   publicar.
5. **No hay checksums, ni artefactos firmados, ni GitHub Release.** El tag
   no está firmado y no existe `SHA256SUMS`.
6. **Changelog incompleto y etiquetas inconsistentes:** la entrada 0.1.0 es
   del 2026-11-17, pero hay 11 commits entre esa fecha y el tag y 6 más en
   `main`; los paquetes dicen `0.1.0` y la documentación dice `V1.0`.
7. **Rollback no documentado ni probado:** `install-overlay.sh` no tiene
   desinstalación y `distro/RELEASE.md` no describe recuperación. Hay un
   borrador `docs/distro/ROLLBACK.md` sin commitear ni probar.
8. **Instalación limpia no reproducible con artefactos finales:** solo hay
   notas históricas de una VM; el verificador se omite fuera de Ubuntu y no
   sustituye una instalación real.
9. **Gate de assets incompleto:** el config `mytical.plymouth` sigue derivado
   de CachyOS según la auditoría (P0-02) y no hay manifiesto por asset con
   SPDX/autor/URL/SHA-256.

**Cambio durante la auditoría:** `main` avanzó de `61f5443` (el tag) a
`09239f6` (6 commits, ya empujados a `origin/main`). Al empezar, `HEAD` era
exactamente `v0.1.0`. Cualquier conclusión de "release" debe fijar un commit
explícito; hoy el tag y `main` no coinciden. Si `main` volvió a moverse
después de las 18:38 UTC, hay que revalidar §1, §2 y la CI.

---

## 1. Estado de Git

### 1.1 Rama, HEAD y tag

| Dato | Valor | Comando |
|---|---|---|
| Rama | `main` | `git branch --show-current` |
| Upstream | `origin/main`, sin divergencia (`+0 -0`) | `git status -sb` |
| HEAD | `09239f6` (`docs(release): auditar v1.0 y bloquear publicacion`) | `git rev-parse --short HEAD` |
| `origin/main` | `09239f6` | `git rev-parse origin/main` |
| Tag | `v0.1.0` (anotado, objeto `9000790`) | `git cat-file -t v0.1.0` |
| Tag apunta a | `61f5443` | `git rev-parse v0.1.0^{commit}` |
| Tag en remoto | sí, `refs/tags/v0.1.0` | `git ls-remote --tags origin` |
| Mensaje del tag | `Mytical V1.0 Preview` | `git tag -l -n20 v0.1.0` |
| Firma del tag | **no firmado**: `error: no signature found` | `git tag -v v0.1.0` |
| Distancia tag→HEAD | 6 commits | `git rev-list --count v0.1.0..HEAD` |
| `git describe` | `v0.1.0-6-g09239f6-dirty` | `git describe --tags --always --dirty` |

Los 6 commits posteriores al tag (todos ya en `origin/main`):

```text
09239f6 docs(release): auditar v1.0 y bloquear publicacion
e9176fe chore(release): sacar graphify y wallpapers personales del arbol
152a96d feat(apt): firma y snapshots de produccion
7d5186c docs(dist): registrar paleta neon e instalacion limpia
12750e4 test(dist): verificador de instalacion limpia
d20b005 feat(sddm): modo neon fijo configurable
```

`git diff --stat v0.1.0..HEAD`: **108 archivos, +2398/−17459**. El borrado
masivo es la limpieza de `Wallpapers/` y `graphify-out/` en `e9176fe`. El
resto incluye cambio de comportamiento en `palette.py` y
`mytical-sddm-sync`, 428 líneas de tests nuevos, el verificador de instalación
limpia y el flujo de firma/snapshot de producción. **No es solo
documentación.**

### 1.2 Cambios sin commit

A las 18:38 UTC, `git status --porcelain` muestra **16 archivos modificados y
1 sin rastrear** (`docs/distro/ROLLBACK.md`). Nada de eso está en `v0.1.0`:

- **Este documento** (`docs/distro/RELEASE-CHECKLIST.md`), commiteado en
  `09239f6` y editado después por la auditoría.
- **11 archivos de corrección de shellcheck**, sin commitear: `.github/
  workflows/check.yml`, `btop/theme.sh`, `distro/apt/production-sign.sh`,
  `distro/install-overlay.sh`, `distro/tests/test_apt_repo.sh`,
  `distro/tests/test_production_repo.sh`, `distro/tests/test_session.sh`,
  `gtk/theme.sh`, `kitty/theme.sh`, `scripts/wallpaper` y
  `ubuntu/sddm/install.sh`. Con el árbol actual, `shellcheck -x` pasa
  (exit 0); sin `-x` queda SC1091. Como no está commiteado, la CI de
  `09239f6` sigue roja.
- **2 archivos de reescritura de Plymouth**, sin commitear:
  `ubuntu/plymouth/mytical/mytical.plymouth` (cabecera GPL, claves
  reescritas) y `ubuntu/plymouth/README.md`. Es la remediación de P0-02, aún
  sin validar ni commitear.
- **`docs/distro/ROLLBACK.md` sin rastrear**: borrador de procedimiento de
  rollback. No está enlazado desde `RELEASE.md` ni probado en una VM.
- **`distro/RELEASE.md` y `docs/distro/ASSET-LICENSES.md` también están
  modificados** sin commitear: actualización de la guía de release y del
  estado de assets en curso. La auditoría de §5 se basa en la versión
  commiteada de `ASSET-LICENSES.md`.

- El árbol de trabajo de `main` ya **no** tiene los 9 archivos de
  `graphify-out/` ni los 22 wallpapers: `e9176fe` los sacó del índice y
  actualizó `setup.py`, `nix/home.nix` y `scripts/session-start` para usar
  `distro/branding/wallpapers/`. `git ls-files graphify-out` y
  `git ls-files Wallpapers` devuelven `0`.
- **Pero el tag `v0.1.0` sí los contiene**: 68 archivos de `graphify-out/` y
  22 wallpapers. La limpieza está solo en `main`; no en el artefacto tag.
- `graphify-out/.graphify_python` contiene una ruta local
  (`/home/ruben/.local/share/uv/...`); ese blob sigue en la historia y en el
  tag, aunque ya no en el árbol actual.
- `distro/apt/PRODUCTION.md`, `production-sign.sh` y
  `test_production_repo.sh` se commitearon en `152a96d`; **no están en
  `v0.1.0`**.
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

Ejecutado en `09239f6` salvo donde se indica. Todos los comandos se corrieron
desde la raíz del repo.

| Comando | Resultado | Evidencia / notas |
|---|---|---|
| `make -C distro test` | **OK** (exit 0) | Construye 4 `.deb`; `OK: paquete mytical-session`, `mytical-welcome`, `mytical-sddm-theme`; `OK: test_session.sh`. `test_packages.sh` no cubre `mytical-desktop` (metapaquete). |
| `python3 -m unittest discover -s tests` | **OK** | `Ran 30 tests in 1.243s` — `OK` |
| `nix flake check --no-build` | **OK** (exit 0) | `all checks passed!`; aviso `Git tree ... is dirty` y `app ... lacks attribute 'meta'`. Se usó `/opt/deepseek-harness/.nix-profile/bin/nix` (Nix 2.35.5): `nix` no está en `PATH`. |
| `shellcheck --shell=bash $(git ls-files '*.sh') scripts/volume scripts/wallpaper scripts/session-splash` | **FALLA en `09239f6`** (exit 1) | 5 hallazgos: `install-overlay.sh:27` SC1091; `test_session.sh:93,101,143,146` SC2016. Con la corrección **sin commitear** del árbol actual, `shellcheck -x` pasa (exit 0). |
| `make -C distro/apt test` (sobre el árbol extraído de `v0.1.0`) | **OK** (exit 0) | 4 paquetes, clave GPG efímera, `firma OpenPGP correcta`, `apt-get update` aislado y descarga de `mytical-session`. No se repitió sobre `09239f6`; los cambios posteriores no tocan el flujo APT (sí el tema SDDM). |
| `bash distro/tests/test_clean_install.sh` | **SKIP** (exit 0) | En Debian 13 imprime `SKIP: el sistema no es Ubuntu`; no verifica nada. |
| `bash distro/tests/test_production_repo.sh` | **OK** (exit 0) | Clave efímera RSA; `production-sign.sh` firmó la snapshot, `gpgv` devolvió `Good signature` para `InRelease` y `Release.gpg`; un fingerprint inexistente falla sin crear salida. |
| `distro/apt/production-sign.sh` | **OK** (vía test) | Probado en un snapshot temporal, no contra `/srv/apt` ni con la clave real. |

**CI (GitHub Actions).** Workflow `check`, 5 jobs:

- Commit del tag `61f5443` (run `45238443883`): **failure**. Pasan
  `referencias`, `luacheck`, `python` y `nix flake check`; falla `shellcheck`.
- `7d5186c` (run `45239113755`, 18:30:25Z): **failure** por el mismo
  `shellcheck`. Los otros 4 jobs pasan.
- `HEAD` `09239f6` (run `45239878056`, 18:34:44Z): **failure**; `shellcheck`
  vuelve a fallar y los otros 4 jobs pasan. Hay una corrección local (11
  archivos, `shellcheck -x`) que aún no está commiteada.

El workflow solo hace chequeos estáticos: no construye paquetes, no corre
`distro/tests/`, no valida el repo APT y no verifica licencias.

---

## 3. Paquetes y versiones

| Paquete | Versión | Tamaño `.deb` | Contenido principal | Licencia dentro del `.deb` |
|---|---|---:|---|---|
| `mytical-sddm-theme` | `0.1.0-1~resolute1` | 2.164.360 B | Tema QML, 7 SVG, `palette.py`, `mytical-sddm-sync`, `Backgrounds/wallpaper` (CC0, SHA-256 `ac074f9b…` = `distro/branding/wallpapers/mytical-01.png`), `LICENSE` GPL | sí (GPL del upstream) |
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
  (fingerprint de la firma en `InRelease`, clave efímera no disponible). No es
  un repo de producción ni refleja el árbol actual.
- `distro/apt/public/` está en `.gitignore`; el estado obsoleto vive solo en
  el working tree, pero confunde si alguien sirve ese directorio.
- **No hay clave de producción.** No existe fingerprint documentado, ni
  keyring, ni certificado de revocación, ni backup. `gpg`/`gpgv` no están en
  `PATH` (sí en `/nix/store/nxjq9lhr0q6x8bjlvrih0bdh4d9dz5zj-gnupg-2.4.9/bin`).
- `docs/distro/FUTURE-FEATURES.md` ya marca como **P0 "Clave GPG de
  producción del repo APT y publicación firmada — Pendiente"**.
- `distro/apt/PRODUCTION.md`, `distro/apt/production-sign.sh` y
  `distro/tests/test_production_repo.sh` ya están **commiteados en `152a96d`**
  (no en `v0.1.0`): definen el flujo offline, snapshot inmutable y
  verificación con `gpgv`. El flujo está probado con clave efímera, pero la
  clave real y la primera snapshot de producción siguen pendientes.

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
5. `bash distro/tests/test_production_repo.sh` (en `152a96d`) pasó:
   `production-sign.sh` firmó una snapshot temporal, `gpgv` validó
   `InRelease` y `Release.gpg`, y un fingerprint inexistente falló sin crear
   salida.

Conclusión: **el mecanismo funciona**; lo que falta es la clave real, su
custodia y publicar una snapshot firmada de los 4 paquetes actuales. No se
probó contra `/srv/apt`, con la clave de producción, ni una instalación APT
real desde un servidor.

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

1. **22 wallpapers personales siguen en el tag y en la historia pública**
   (`Wallpapers/`, ~40 MB). `e9176fe` los sacó de `main`, pero el tag
   `v0.1.0` todavía los tiene. La auditoría los clasifica
   **P0-03 — bloqueante**: varios son arte de personajes, `ww.jpg` es un
   personaje reconocible de *Evangelion*, `6.jpg` es una foto real con EXIF de
   cámara/RAW y `02.jpg`/`w0.jpg` tienen riesgo alto. Verificado hoy:
   `raw.githubusercontent.com/.../v0.1.0/Wallpapers/01.png`, `02.jpg` y
   `ww.jpg` devuelven **HTTP 200**. No es un riesgo futuro: ya están
   publicados.
2. **`mytical.plymouth` derivado de CachyOS** (P0-02): hay una reescritura
   local sin commitear (cabecera GPL, claves documentadas) y un README
   actualizado. No está en `09239f6` ni validada; P0-02 sigue abierto hasta
   commitearla y revisarla.
3. **No hay manifiesto por asset** con ruta, SPDX, autor/titular, URL de
   origen y SHA-256, que es la puerta de release de `ASSET-LICENSES.md` §7.
4. El propio documento de assets mezcla el veredicto viejo ("no apto", 6 P0)
   con resoluciones posteriores; conviene un encabezado de "estado vigente"
   para que nadie lea la tabla vieja como actual (D-08).
5. `mytical-welcome` y `mytical-sddm-sync` dependen de
   `~/Pictures/Wallpapers/`. En `main` esa ruta se llena desde
   `distro/branding/wallpapers/` (4 CC0), pero **la copia empaquetada de
   `mytical-sddm-sync` sigue con el fallback antiguo `01.png`**, que ya no
   existe; la copia de `ubuntu/sddm/` sí usa `mytical-01.png`. El `.deb` no
   recibe esa corrección (D-13). En una instalación solo con `.deb` la ruta
   no existe y el selector de `mytical-welcome` queda vacío hasta que el
   usuario copie fondos. No es bloqueante legal, sí de coherencia y primera
   experiencia.

---

## 6. Checklist de release

Marcas: **[B]** bloqueante, **[D]** deseable. Cada casilla debe cerrarse con
evidencia reproducible (comando + salida + fecha), no con una afirmación.

### 6.1 Congelar el release

- [ ] **[B]** Detener commits y trabajo concurrente; acordar el commit exacto
      del release. Hoy `main` se movió durante la auditoría.
- [ ] **[B]** Decidir si el release es "V1.0 Preview" sobre `0.1.0` o "V1.0"
      final con `1.0.0` y tag nuevo. Dejarlo escrito en `CHANGELOG.md`.
- [ ] **[B]** Validar e incluir en el release los scripts de producción ya
      commiteados en `152a96d` (`PRODUCTION.md`, `production-sign.sh`,
      `test_production_repo.sh`); no están en `v0.1.0`.
- [ ] **[D]** Decidir el destino de las 10 ramas `feat/*` y los 2 worktrees
      extra.

### 6.2 Fuente limpia

- [ ] **[B]** `git status --porcelain` vacío en el commit de release.
- [ ] **[B]** `git ls-tree -r --name-only <tag> graphify-out | wc -l` = `0`.
      No alcanza con que `main` ya no lo tenga (`e9176fe`): el tag `v0.1.0`
      todavía incluye 68 archivos.
- [ ] **[B]** `git ls-tree -r --name-only <tag> Wallpapers | wc -l` = `0`.
      Retirar los 22 wallpapers del tag **y de la historia pública**
      (filter-repo/BFG), o decidir explícitamente que el repo deja de ser
      público. Un commit que solo los borre no elimina el blob del historial.
- [ ] **[B]** `git rev-list --objects --all | grep -E 'Wallpapers/|graphify-out/'`
      no devuelve nada; si devuelve, la historia sigue publicando los blobs.
- [ ] **[B]** Confirmar que `git archive` del commit de release no contiene
      `Wallpapers/` ni `graphify-out/`; el del tag actual pesa 68.669.440 B.
- [ ] **[B]** Decidir si `v0.1.0` se conserva como Preview inmutable o se
      reemplaza; si se conserva, el release final necesita un tag nuevo.
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
      limpia) y los 6 posteriores al tag.
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
- [ ] **[B]** Revisar, commitear y probar el borrador `docs/distro/ROLLBACK.md`
      (hoy sin rastrear), y enlazarlo desde `RELEASE.md`.
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
      enlazados desde `RELEASE.md` (ambos ya están en `152a96d`).
- [ ] **[D]** Un solo lugar canónico para la versión (`VERSION` o
      `CHANGELOG.md`); el plan lo menciona y no existe.
- [ ] **[B]** Commitear los cambios pendientes de `distro/RELEASE.md` y
      `docs/distro/ASSET-LICENSES.md` (hoy modificados sin commitear).
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
| **B-01** | El tag no identifica el release actual | `v0.1.0` → `61f5443`; `main`/`origin` → `09239f6`; 6 commits de diferencia; tag anotado sin firma (`git tag -v` → "no signature found") | Tag firmado en el commit congelado, `HEAD == tag == origin/main`, `git tag -v` OK |
| **B-02** | El tag todavía contiene salida generada | `git ls-tree -r v0.1.0 graphify-out` = 68 archivos; `git archive v0.1.0` = 68.669.440 B; en `main` ya es 0 (`e9176fe`) | Tag/artefacto de release sin `graphify-out/` ni rutas `/home/...` |
| **B-03** | CI en rojo en el commit del tag | Run `45238443883` failure (shellcheck); HEAD `45239878056` failure; 5 hallazgos. Corrección local con `shellcheck -x` pasa, pero no está commiteada | Los 5 jobs verdes en el commit del tag |
| **B-04** | Wallpapers personales sin licencia en tag e historia pública | `e9176fe` los sacó de `main`, pero `git ls-tree -r v0.1.0 Wallpapers` = 22 y `raw.githubusercontent.com/.../v0.1.0/Wallpapers/ww.jpg` = HTTP 200 | 0 wallpapers sin licencia en tag e historia; URLs históricas ya no sirven; manifiesto con licencia/autor/URL/SHA-256 |
| **B-05** | Sin clave APT de producción y repo de prueba obsoleto | Flujo `PRODUCTION.md`/`production-sign.sh` commiteado en `152a96d`, probado con clave efímera; `public/` del 2026-11-17, 2/4 paquetes; sin fingerprint/revocación/backup reales | Clave offline + snapshot firmada de 4 paquetes + `apt-get update` verificado en VM limpia |
| **B-06** | Sin checksums ni artefactos firmados ni GitHub Release | No hay `SHA256SUMS`; `.deb` sin firma; tag sin firma; `releases: []` | `SHA256SUMS` firmado, tag firmado, GitHub Release con artefactos y fingerprint |
| **B-07** | Changelog incompleto y versión/label inconsistentes | Entrada 0.1.0 del 2026-11-17; 11 commits entre esa fecha y el tag + 6 posteriores sin reflejar; `0.1.0` vs "V1.0" | Changelog completo, versión/tag/paquetes alineados, decisión Preview vs final escrita |
| **B-08** | Rollback no documentado ni probado | `install-overlay.sh` sin desinstalación; `RELEASE.md` sin rollback; hay un `ROLLBACK.md` sin commitear y sin prueba real | Procedimiento probado en VM y publicado/enlazado desde `RELEASE.md` |
| **B-09** | Instalación limpia no reproducible | Solo notas históricas en `PROGRESS.md`; `test_clean_install.sh` hace SKIP fuera de Ubuntu; sin ISO | VM Ubuntu 26.04 limpia instalada con los `.deb`/repo del release, con evidencia |
| **B-10** | Gate de assets incompleto | `mytical.plymouth` derivado; reescritura local sin commitear (P0-02); sin manifiesto por asset; paquetes sin `copyright` | P0-02 commiteado y revisado, manifiesto completo, avisos y `copyright` en los `.deb` |
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
| **D-07** | Evaluar LFS/historia tras retirar wallpapers | GitHub informa ~113 MB y `.git` ~118 MB; un clon limpio no debería arrastrar 40 MB de arte sin licencia en la historia |
| **D-08** | Encabezado de "estado vigente" en `ASSET-LICENSES.md` y actualizar `RELEASE.md` | El veredicto viejo (6 P0) convive con resoluciones posteriores y confunde |
| **D-09** | Script de release que genere checksums, firme y publique | Reduce el error manual y deja evidencia reproducible |
| **D-10** | Aviso de no afiliación con Ubuntu/Canonical en el release y en el README | P1 de la auditoría de marca; barato y evita confusión |
| **D-11** | Firmar commits/tags por defecto y publicar el fingerprint | Cadena de confianza verificable por terceros |
| **D-12** | Decidir si `README.md` debe mencionar el overlay o separar README de dotfiles/distro | Hoy el README no guía a la instalación V1.0 |
| **D-13** | Sincronizar la copia empaquetada de `mytical-sddm-sync` (`distro/debian/...`) con `ubuntu/sddm/`: el `.deb` todavía cae a `01.png`, borrado en `e9176fe` | Evita un fallback roto y la divergencia entre fuente y paquete |

---

## 9. Limitaciones de esta auditoría

- **No se construyó ni probó la ISO**: `distro/iso/` y `distro/installer/` están
  vacíos; el release V1.0 es overlay, la ISO es V1.1 según la documentación.
- **No se hizo una instalación limpia en Ubuntu 26.04**: no hay VM accesible
  desde este entorno. `test_clean_install.sh` se omitió (Debian 13) y las
  únicas evidencias de instalación son las notas de `PROGRESS.md` del
  2026-11-23 en `10.0.0.154`.
- **No se usó una clave de producción**: no existe. La firma se validó con una
  clave RSA-3072 efímera en un `GNUPGHOME` temporal; `test_production_repo.sh`
  probó `production-sign.sh` en una snapshot temporal, no contra `/srv/apt`
  ni con la clave real.
- **`make -C distro/apt test` no se corrió contra el working tree** para no
  sobrescribir `distro/apt/public/`; se corrió sobre una extracción limpia de
  `v0.1.0` en `/tmp`, que es el árbol del tag.
- **No se re-verificó byte a byte** que los throbbers/iconos nuevos no
  deriven de CachyOS; se toma la resolución de `ASSET-LICENSES.md` como
  estado documentado, no como peritaje nuevo.
- **CI del HEAD** terminó en failure por shellcheck durante la auditoría; el
  estado de GitHub se consultó vía API el 2026-11-23 ~18:38 UTC.
- **El árbol se movió durante la auditoría** (`61f5443` → `09239f6`, 6
  commits) y solo este documento queda modificado sin commitear; cualquier
  número de "commits" o "estado limpio" debe revalidarse al congelar el
  release.
- **Solo se regeneraron artefactos ignorados** (`distro/build/`,
  `__pycache__/`) al correr los tests. Esta auditoría no modificó código ni
  configuración, no tocó `distro/apt/public/` ni creó commits; los 6 commits
  de §1.1 los produjo trabajo concurrente (incluido el que commiteó este
  documento y la limpieza de wallpapers/graphify).

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
bash distro/tests/test_production_repo.sh
```

## Anexo B — Evidencia externa consultada

- Repo GitHub: `https://api.github.com/repos/myticalruben/.dotfiles`
  (`private: false`, `size: 113496`, `releases: []`).
- Run CI del tag: `https://api.github.com/repos/myticalruben/.dotfiles/actions/runs/45238443883`
  (failure; job `shellcheck`).
- Run CI de `7d5186c`: run `45239113755` (failure; mismo job).
- Run CI de `152a96d`: run `45239609891` (failure; mismo job).
- Run CI de `09239f6`: run `45239878056` (failure; mismo job).
- Wallpaper público: `https://raw.githubusercontent.com/myticalruben/.dotfiles/v0.1.0/Wallpapers/ww.jpg`
  (HTTP 200).
