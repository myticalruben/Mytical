> **Histórico / superseded:** este análisis se hizo para una ISO APT-only.
> El ADR 0010 aprobó incluir Nix en V1.1; por tanto Quickshell y awww se
> mantienen desde Nix y **no** se sustituyen por swaybg en esta release. El
> defecto de `~/Pictures/Wallpapers` y el gate del archive siguen siendo
> hallazgos válidos.

# Quickshell y awww en la ISO V1.1: empaquetar o sustituir

**Estado:** propuesto (2026-11-24). Este documento decide y planifica; no aplica
ningún cambio.

**Alcance:** ISO V1.1 APT-only (ADR 0009), sin `/nix`. La Preview V1.0 sigue
igual: conserva Quickshell y awww desde Nix.

**Cierra:** la parte de **B5** de [`ISO.md`](ISO.md) que quedó abierta para
estos dos paquetes. Sustituye los puntos 2 y 3 de la estrategia de
[`APT-DESKTOP.md`](APT-DESKTOP.md).

**No cubre:** el empaquetado de Hyprland 0.55.4, la entrega de las
configuraciones de usuario en la ISO ni las pruebas de arranque B7. Las tres
aparecen aquí solo cuando condicionan la decisión.

---

## Decisión en 30 segundos

| Componente | V1.1 | Coste | Se pierde |
|---|---|---|---|
| **Quickshell** | No se empaqueta. Se consume del archive **si** el gate G1 lo resuelve en 26.04; si no, se retira la feature | 0 build; +55–72 MiB de ISO si entra | Nada si entra; si no, el fundido de salida y el carrusel `MOD+W` |
| **awww** | No se empaqueta. `swaybg` (APT) como backend en la ISO, detrás de `scripts/wallpaper`; awww se autodetecta en la Preview | ~4 h de script y tests | Fundido de 1 s al cambiar/restaurar y GIF animados |

Ninguno de los dos se empaqueta desde upstream en V1.1. El motivo no es que no
se pueda: es que el coste de mantenimiento (ABI privada de Qt en un caso,
vendorizado de Rust en el otro) compra dos detalles visuales, no
funcionalidad de sesión.

---

## 1. Método y evidencia

Todo lo que sigue se leyó en local, sin red, sin `apt-get update`, sin root y
sin descargar nada:

- el repositorio, con `git status` limpio en `main`;
- metadatos APT del host (**Debian 13 trixie + trixie-backports**), con
  `apt-cache show`, `apt-cache showsrc` y `apt-cache policy`;
- el árbol de nixpkgs del pin de `flake.lock`
  (`b349185bb79c7cf7ad8ea8c097931730bf473c71`), para versión, licencia,
  dependencias y tamaño de awww y Quickshell.

El host **no es Ubuntu 26.04**. Por eso hay una columna de verificación y un
gate explícito antes de tocar la lista de paquetes.

| Dato | Fuente | ¿Verificado? |
|---|---|---|
| `quickshell 0.3.0-1~bpo13+1` existe en Debian | `apt-cache show quickshell` | sí en el host; **no** en 26.04 |
| Build-Depends y origen de Quickshell | `apt-cache showsrc quickshell` | sí |
| Quickshell depende de `qt6-*-private-abi (= 6.8.2)` | `Depends` del `.deb` | sí |
| `awww` no existe en Debian (ni trixie ni backports) | `apt-cache policy awww` | sí en el host |
| `swaybg 1.2.1-1` está en trixie main | `apt-cache policy swaybg` | sí en el host |
| `hyprpaper 0.8.4-1~bpo13+1` está en trixie-backports | `apt-cache policy hyprpaper` | sí en el host |
| awww 0.12.1, GPL-3.0, deps y tamaño | nixpkgs del pin | sí |
| Quickshell 0.3.0, LGPL-3.0-only, deps y tamaño | nixpkgs del pin | sí |
| Qt, `wayland-protocols` y versiones del archive 26.04 | — | **no** |
| Que el QML de este repo funcione con el build del archive | — | **no** (solo con Nix 0.3.0) |

Los tamaños de dependencias son sumas de `Installed-Size` de las dependencias
directas, sin desduplicar contra lo que la ISO ya trae; sirven para comparar
órdenes de magnitud, no como cifra final. La cifra final se mide en el chroot
con `apt-get install -s`.

---

## 2. Auditoría: dónde se usan

### 2.1 Quickshell

| Archivo:línea | Uso | Sin Quickshell |
|---|---|---|
| `hypr/modules/keysbindings.lua:38` | `MOD+W` → `quickshell -c hyprquickpaper` | la tecla no hace nada |
| `wlogout/layout:15,21,27` | logout/reboot/shutdown → `session-splash exit ... \|\| acción` | la acción corre igual por el `\|\|` |
| `hypr/modules/keysbindings.lua:65` | `MOD+SHIFT+M` → `session-splash exit logout \|\| hl.dsp.exit()` | el cierre corre igual |
| `scripts/session-splash:27-30` | resuelve el directorio QML | cae al fallback del checkout y sale con aviso |
| `scripts/session-splash:178-186` | `run_start` comprueba el binario y sale 0 | el arranque sigue sin splash |
| `scripts/session-splash:194-216` | `run_exit` pinta overlay y ejecuta la acción | ejecuta la acción de inmediato |
| `quickshell/hyprquickpaper/` | carrusel `MOD+W`: `shell.qml`, `commands.sh`, `cache.sh`, `config.json` (~28 KB) | feature completa perdida |
| `quickshell/session-splash/shell.qml` | overlay de arranque/cierre (~8 KB) | solo se pierde el cierre (ver H1) |
| `hypr/modules/autostart.lua:11` | llama `session-start`, **no** `session-splash start` | nada |
| `hypr/modules/envs.lua:3-4` | comentario sobre el `PATH` | nada |
| `nix/home.nix:282,332` | enlace y paquete de la Preview | nada en la ISO |
| `setup.py:47` | enlaza `quickshell/` a `~/.config` | nada en la ISO |
| `packages/required-commands.txt:20` | `install.sh --check` lo exige | aviso de dependencia faltante |

Hallazgos del audit:

- **H1 — el splash de arranque ya no existe.** `autostart.lua` solo invoca
  `session-start`; nadie llama a `session-splash start`. El comentario de
  cabecera de `scripts/session-splash:13-15` sigue describiéndolo como si
  estuviera cableado. Es decir: retirar Quickshell **no cambia el arranque**,
  porque el arranque ya no pinta logo ni fundido de entrada.
- **H2 — el cierre ya degrada solo.** `wlogout` y `MOD+SHIFT+M` usan `||` para
  ejecutar la acción si el overlay falta o falla, y `run_exit` hace lo mismo
  cuando no hay binario. Sin Quickshell se pierde el fundido, no el cierre.
- **H3 — el overlay añade latencia al cierre.** `wait_for_layer` (poll de
  `hyprctl -j layers` hasta 1,5 s) más `SESSION_SPLASH_EXIT_WAIT` (0,45 s por
  defecto) son tiempo que se espera antes de salir. Sin overlay, el cierre es
  más rápido.

### 2.2 awww

| Archivo:línea | Uso | Sin awww |
|---|---|---|
| `scripts/session-start:16` | lanza `awww-daemon` | nada; el error se ignora |
| `scripts/session-start:17` | `wallpaper restore "$wallpaper"` con `\|\| true` | escritorio en negro, resto de la sesión intacta |
| `scripts/wallpaper:21` | guarda `command -v awww` | sale 1 con mensaje |
| `scripts/wallpaper:76` | `awww query` para esperar al daemon | — |
| `scripts/wallpaper:87` | `awww img ... -t random` | — |
| `scripts/wallpaper:111` | `awww img ... -t fade` | — |
| `quickshell/hyprquickpaper/commands.sh:9` | `exec wallpaper set` (indirecto) | — |
| `scripts/wallpapers:36` | `wallpaper set` (indirecto) | — |
| `waybar/scripts/theme.sh:12-16` | lee `~/.local/state/hypr/wallpaper` | **no** se ve afectado |
| `kitty/theme.sh:8-12` | ídem | **no** se ve afectado |
| `gtk/theme.sh`, `btop/theme.sh` | ídem, vía `~/.config/*-theme/` | **no** se ven afectados |
| `packages/required-commands.txt:21-22` | `install.sh --check` exige `awww` y `awww-daemon` | aviso de dependencia faltante |
| `nix/home.nix:315` | paquete de la Preview | nada en la ISO |
| `distro/first-run/mytical-welcome:25,41,98` | usa `wallpaper`, no awww | nada |

Waybar no invoca a ninguno de los dos: su único vínculo es
`waybar/scripts/theme.sh`, que lee el archivo de estado y por tanto es
agnóstico del backend.

Hallazgos del audit:

- **H4 — awww no es crítico para arrancar.** `session-start` ignora el fallo de
  `restore`; la sesión queda usable con el fondo negro.
- **H5 — el contrato real es el archivo de estado.** Los cuatro hooks de tema
  leen `~/.local/state/hypr/wallpaper`, que escribe `scripts/wallpaper`, no
  awww. `scripts/wallpaper` es el **único** punto de acoplamiento con el
  daemon: sustituir el backend no toca temas ni Waybar.
- **H6 — el fondo por defecto no existe en la ISO.** `autostart.lua` cae a
  `~/Pictures/Wallpapers/01.png`, pero la ISO instala los CC0 en
  `/usr/share/backgrounds/mytical/mytical-0*.png` (`apply_branding` de
  `distro/iso/remaster.sh`) y ningún paquete siembra `~/Pictures`. Esto afecta
  igual a awww, a swaybg y a hyprpaper: sin sembrar el directorio o cambiar el
  default, la ISO arranca en negro aunque el backend funcione.

---

## 3. Ficha upstream: Quickshell

| Campo | Valor |
|---|---|
| Fuente | `git.outfoxxed.me/quickshell`, tag `v0.3.0` (espejo en `github.com/quickshell-mirror/quickshell`) |
| Versión en el repo | 0.3.0 (la del pin de nixpkgs; el QML se validó contra ella) |
| Licencia | LGPL-3.0-only (nixpkgs `lgpl3Only`) |
| Lenguaje | C++ / Qt 6 / QtQuick |
| Build | CMake + Ninja |
| Build deps (Debian) | `qt6-base-dev`, `qt6-declarative-dev`, `qt6-wayland-dev`, `qt6-shadertools-dev`, **`qt6-base-private-dev`**, **`qt6-declarative-private-dev`**, **`qt6-wayland-private-dev`**, `libcli11-dev`, `libcpptrace-dev`, `libjemalloc-dev`, `libwayland-dev`, `wayland-protocols (>= 1.47)`, `libpipewire-0.3-dev`, `libpam0g-dev`, `libpolkit-agent-1-dev`, `libpolkit-gobject-1-dev`, `libglib2.0-dev`, `libdrm-dev`, `libgbm-dev`, `libegl-dev`, `libgles-dev`, `libvulkan-dev`, `libxcb1-dev`, `spirv-tools`, `pkgconf`, `cmake`, `ninja-build` |
| Runtime (`.deb` 0.3.0) | 6,9 MiB instalado; deps directas 72 MiB, de las que Qt 6 es lo nuevo para la ISO |
| Runtime extra | `hicolor-icon-theme`, `qt6-svg-plugins`, `qml6-module-qtquick`, `qml6-module-qtquick-controls`, `qml6-module-qtquick-layouts` |
| Empaquetado Debian | existe: 0.3.0-1, mantenedor Michael Lloyd, `salsa.debian.org/micl/quickshell`; `orig.tar.xz` de 370 KB y `debian.tar.xz` de 5,9 KB (sin parches propios aparentes) |

**El detalle que decide todo:** el binario depende de
`qt6-base-private-abi (= 6.8.2)`, `qt6-declarative-private-abi (= 6.8.2)` y
`qt6-waylandclient-private-abi (= 6.8.2)`. Quickshell usa cabeceras privadas de
Qt, así que:

1. el `.deb` de Debian **no** se puede instalar en una 26.04 con otro Qt;
2. un paquete propio hay que **reconstruirlo en cada subida de Qt** del
   archive (26.04 es LTS: habrá subidas de seguridad de Qt durante años);
3. si 26.04 ya trae Quickshell, el paquete lo mantiene Ubuntu y el coste para
   nosotros es cero.

Compilar desde upstream no es difícil (el paquete Debian es casi el upstream
tal cual), pero convierte a Mytical en mantenedor de un binario atado a la ABI
privada de Qt. Para dos detalles visuales, no compensa en V1.1.

---

## 4. Ficha upstream: awww

| Campo | Valor |
|---|---|
| Fuente | `codeberg.org/LGFae/awww`, tag `v0.12.1` (fork de swww) |
| Versión en el repo | 0.12.1 (Nix) |
| Licencia | GPL-3.0 (nixpkgs `gpl3`; confirmar `COPYING` upstream al empaquetar) |
| Lenguaje | Rust (cargo) |
| Build deps | `pkg-config`, `lz4`, `libxkbcommon`, `wayland-protocols`, `wayland-scanner`, `scdoc` (man pages) |
| Runtime | `lz4`, `libxkbcommon`, `libwayland-client`, `libc`; `procps` en el `PATH` (nixpkgs envuelve los binarios con `makeWrapper`) |
| Tamaño | ~9 MiB instalado en el store de Nix; dos binarios, `awww` y `awww-daemon` |
| Tests | nixpkgs usa `doCheck = false`: los tests de integración no corren en sandbox |
| En Debian/Ubuntu | **no existe** (ni trixie, ni backports, ni siquiera `swww`) |

Empaquetarlo significa crear el paquete desde cero: vendorizar las crates (sin
red en el build), `dh-cargo` o equivalente, y comprobar que el `rustc` del
archive (1.85 en trixie) satisface el MSRV de awww. Técnicamente es el más
estable de los dos a largo plazo —un binario Rust no lleva ABI privada— pero es
el que menos feature aporta: solo el fundido.

---

## 5. Alternativas APT

| Opción | Paquete | Tamaño | Transición | IPC / daemon | Riesgo principal |
|---|---|---|---|---|---|
| **swaybg** | 1.2.1-1 (trixie main) | 57 KiB instalado; deps `cairo`, `gdk-pixbuf`, `glib`, `wayland` ya presentes por GTK/Waybar | no | no: proceso en primer plano; para cambiar se relanza | ninguno relevante; hotplug de monitores pobre |
| **hyprpaper** | 0.8.4-1~bpo13+1 | 517 KiB; deps `libhyprlang2`, `libhyprtoolkit5`, `libhyprutils12`, `libhyprwire3`, `libmagic1t64` | no | socket + `hyprctl hyprpaper ...` | skew de librerías hypr\* con nuestro Hyprland 0.55.4 y posible cambio de protocolo del socket |
| **awww empaquetado** | no existe | ~9 MiB | sí (fundido) | socket propio | vendorizado Rust, MSRV, mantenimiento |
| **Quickshell del archive** | 0.3.0 si 26.04 lo trae | 6,9 MiB + Qt 6 (~55 MiB nuevos) | — | — | versión fijada; API QML si sube de 0.3 |
| **Quickshell propio** | — | ídem | — | — | ABI privada de Qt, reconstruir en cada update |

Notas:

- `swaybg` no hace transiciones ni GIF animados; `awww` sí. `hyprpaper`
  tampoco hace transiciones: es cambio instantáneo, igual que `swaybg`.
- `swaybg` sin `-o` pinta en todas las salidas; `-o NAME` limita a una. Hay que
  confirmarlo en la ISO (AC-3) y, si no se comporta, lanzar un proceso por
  monitor.
- Las licencias de `swaybg` (MIT) y `hyprpaper` (BSD-3-Clause) son de upstream;
  al añadirlas hay que copiar `debian/copyright` a `THIRD_PARTY_NOTICES`.
- Quickshell es LGPL-3.0: enlazado dinámico, correcto, pero exige aviso de
  licencia y oferta de fuente en la documentación de la ISO.

---

## 6. Coste y riesgo

Estimaciones de esfuerzo para una persona que ya conoce el repo:

| Opción | Trabajo | ISO | Riesgo de build | Riesgo de mantenimiento | Reversible |
|---|---|---|---|---|---|
| Quickshell del archive | 0,5 h (lista + smoke) | +55–72 MiB | bajo | bajo (lo actualiza Ubuntu; revalidar QML si sube de 0.3) | sí, quitar de la lista |
| Quickshell propio | 1–2 días (build, `.deb`, pruebas) | +55–72 MiB | alto (`private-dev`, `wayland-protocols >= 1.47`) | alto (reconstruir en cada subida de Qt) | sí |
| awww propio | 2–3 días (vendor, `dh-cargo`, MSRV, tests) | +9 MiB | medio | medio | sí |
| hyprpaper | 0,5 h | +2–19 MiB | medio (¿está en 26.04? deps hypr\*) | medio (skew con Hyprland propio) | sí |
| swaybg + backend dual | 4–6 h con tests | +57 KiB | bajo | bajo (mantenido por el equipo de sway, sin ABI propia) | sí |

El riesgo que domina no es compilar: es **quién reconstruye el binario cuando
Qt cambia**. Por eso Quickshell propio queda descartado para V1.1 y awww
propio queda como candidato de V1.2, cuando haya una razón funcional (el
fundido) y no solo estética.

---

## 7. Recomendación para V1.1

### 7.1 awww: sustituir por `swaybg` con backend dual

Decidido: **no se empaqueta awww en V1.1**. `scripts/wallpaper` pasa a elegir
backend:

```text
awww + awww-daemon en PATH  -> backend awww   (Preview, Nix: comportamiento actual)
si no, swaybg en PATH       -> backend swaybg (ISO, APT)
si no hay ninguno           -> error explícito y exit 1
```

Consecuencias del diseño:

- La Preview no cambia: en Nix gana `awww` y se conserva el fundido.
- La ISO no necesita Rust ni vendorizado: `swaybg` está en Debian main, de
  donde sale `universe` en Ubuntu.
- `~/.local/state/hypr/wallpaper` y los cuatro hooks de tema no se tocan.
- Un solo dueño del proceso: `session-start` deja de lanzar `awww-daemon` y es
  `wallpaper restore` quien arranca el backend. Así `wallpaper set` también
  funciona si el daemon murió.
- `swaybg` se lanza como `swaybg -i "$path" -m fill` (`fill` recorta manteniendo
  el aspecto, que es lo que hace el `crop` por defecto de awww; confirmarlo
  visualmente en la ISO), con PID en `$XDG_RUNTIME_DIR/mytical-wallpaper.pid`;
  para cambiar de fondo se mata **ese** PID y se relanza, nunca `pkill` a
  ciegas.
- La espera al daemon cambia: `awww query` para awww, PID vivo + `hyprctl -j
  monitors` para swaybg (si Hyprland no responde, el fondo aún no puede
  pintarse).
- El orden de `session-start` (fondo antes que Waybar) se mantiene, pero el
  pintado es inmediato: ya no hay 1 s de fundido que oculte el arranque de la
  barra.

### 7.2 Quickshell: no empaquetar; consumir del archive si resuelve

Decidido: **no se empaqueta Quickshell desde upstream en V1.1**. Antes de
cerrar B5 se ejecuta el gate **G1** en el chroot de 26.04 (o en una 26.04 real):

```bash
apt-cache policy quickshell
apt-get install -s quickshell | tail -20     # mide el arrastre de Qt 6
```

- **G1 = sí** (hay 0.3.x): se añade `quickshell` a `mytical.list` y se
  verifican los dos QML en la sesión live. Coste 0 de build; se conserva el
  carrusel y el fundido.
- **G1 = no**, o hay una versión con API distinta de 0.3: se aplica 7.3 y
  Quickshell queda fuera de la ISO.

En ningún escenario se empaqueta Quickshell en el repo Mytical durante V1.1.
Si en el futuro se quiere una versión propia, el camino barato es reutilizar el
`debian/` de Debian (`apt-get source quickshell`) en lugar de escribirlo.

### 7.3 Plan B ya decidido: retirada limpia

Si G1 falla, no se deja una tecla muerta:

- `hypr/modules/keysbindings.lua:38` pasa a llamar `wallpaper-picker` (nuevo
  `scripts/wallpaper-picker`): si existe `quickshell`, ejecuta
  `quickshell -c hyprquickpaper`; si no, `rofi -dmenu` sobre `wallpapers list`
  y aplica con `wallpaper set`. Rofi ya está en la ISO, así que no añade
  paquetes.
- `scripts/session-splash` **no se borra**: sin overlay ya ejecuta la acción y
  es el punto de extensión para V2.
- `quickshell/` se queda en el repo (Preview y V2); solo se excluye del camino
  de instalación de la ISO.

---

## 8. Qué se pierde exactamente y cómo degrada la sesión

| Feature | Hoy (Nix/Preview) | V1.1 sin Quickshell ni awww | Impacto real | Mitigación |
|---|---|---|---|---|
| Splash de arranque | ya no se ejecuta (H1) | igual | ninguno | — |
| Fundido de salida (320 ms a negro) | overlay antes de logout/reboot/shutdown | el escritorio se ve hasta que Hyprland muere | cosmético; el cierre es 0,45–1,5 s más rápido (sin `wait_for_layer`) | ninguna necesaria; `wlogout` ya deshabilita sus botones al pulsar |
| Selector `MOD+W` | carrusel con miniaturas, `J/K/D/U`, rueda, hover | lista de nombres en rofi (plan B) | se pierde la vista previa y el carrusel; elegir un fondo sigue siendo posible | `wallpaper-picker` con fallback; si no, quitar el binding y documentar `wallpapers set` |
| Fondo con fundido al iniciar/cambiar | crossfade de 1 s, `-t random`/`-t fade` | corte seco | cosmético | ninguno barato; vuelve con awww en V1.2 |
| GIF animado de fondo | soportado por awww | no soportado | ninguno hoy: el repo usa PNG/JPG | documentar el límite |
| `awww query` como health check | sí | PID + `hyprctl monitors` | equivalente | — |
| `awww restore` con caché versionada | ya no se usa (H5) | — | ninguno | — |

**Degradación en el peor caso** (sin backend y sin picker, que es lo que hay
que evitar): la sesión arranca, Waybar/dunst/temas funcionan, el escritorio
queda **negro** y `MOD+W` no hace nada. Los criterios AC-3, AC-4 y AC-7 existen
para que ese caso no llegue al release.

---

## 9. Criterios de aceptación

Se comprueban en la ISO live y en el chroot, no solo en el repo.

- **AC-1 (gate)** La salida de `apt-cache policy quickshell` y de
  `apt-get install -s quickshell` está adjunta al release, con versión y Qt
  usados. Sin esto no se cierra B5.
- **AC-2 (resolución)** `apt-get install -s` de la lista completa resuelve sin
  paquetes inexistentes ni candidatos de otra suite.
- **AC-3 (backend)** En la ISO, `command -v awww` falla y `command -v swaybg`
  responde. El fondo se pinta en todas las salidas (o en una por monitor si
  `-o` hace falta) en menos de 2 s desde el login.
- **AC-4 (estado)** Tras el login existe `~/.local/state/hypr/wallpaper` con
  una ruta legible y `hyprctl layers` no muestra un `session-splash` huérfano.
- **AC-5 (robustez)** `wallpaper set` funciona con una ruta con espacios y con
  un archivo renombrado; en el segundo caso `restore` cae al fondo por defecto
  sin dejar el escritorio negro.
- **AC-6 (temas)** Tras `set` y tras `restore`, Waybar, Kitty, GTK y btop usan
  la paleta del fondo (comparar el CSS generado o su `mtime`).
- **AC-7 (tecla viva)** `MOD+W` abre el picker o rofi; nunca es un no-op
  silencioso. Si el picker no está, el binding no existe.
- **AC-8 (cierre)** Logout, reboot y shutdown desde `wlogout` y desde
  `MOD+SHIFT+M` ejecutan la acción en ≤2 s, sin pantalla negra permanente y sin
  procesos `quickshell` vivos después.
- **AC-9 (chequeo)** `install.sh --check` dentro de la ISO reporta 0 comandos
  faltantes entre los requeridos (tras actualizar `required-commands.txt`).
- **AC-10 (tests)** `make -C distro test`, `make -C distro/iso test` y
  `tools/check-ownership.py` pasan; hay un test nuevo del backend que usa
  stubs de `awww`/`swaybg` en el `PATH` y no necesita compositor.
- **AC-11 (tamaño)** ISO final ≤ 8 GiB y delta medido contra el build sin
  Quickshell.
- **AC-12 (reglas duras)** La imagen no contiene `/nix` ni `awww`/`swww`.

---

## 10. Archivos a cambiar

| Archivo | Cambio | Por qué |
|---|---|---|
| `distro/iso/package-lists/mytical.list` | añadir `swaybg`; `quickshell` solo si G1; borrar el bloque "pendiente de empaquetar o decidir" | B5 |
| `scripts/wallpaper` | backend dual (`awww` \|\| `swaybg`), PID propio y espera por backend | sustitución sin tocar llamadores |
| `scripts/session-start:16-17` | quitar `awww-daemon`; el backend lo arranca `wallpaper restore`; actualizar el comentario del fundido | un solo dueño del proceso |
| `scripts/wallpaper-picker` | **nuevo**: quickshell si existe, rofi `dmenu` si no | `MOD+W` no queda muerto |
| `hypr/modules/keysbindings.lua:38` | invocar `wallpaper-picker` | ídem |
| `setup.py:47-50` | enlazar `wallpaper-picker` en `~/.local/bin` | llegar al usuario |
| `nix/home.nix:282-315` | enlazar `wallpaper-picker` en la Preview | paridad Preview/ISO |
| `packages/required-commands.txt:20-22` | `awww`/`awww-daemon` pasan a alternativa `awww\|swaybg`; añadir `wallpaper-picker` | `install.sh --check` |
| `packages/manual.md` | nota de la ISO V1.1 y enlace a este documento | no repetir la tabla de "compilar" |
| `docs/distro/APT-DESKTOP.md:18-19` | sustituir las dos preguntas por la decisión | no dejar decisiones viejas |
| `docs/distro/ISO.md:302` y §6 | cerrar la parte de B5 y reflejar el estado | seguimiento |
| `docs/distro/PROGRESS.md` | entrada con fecha y resultado de G1 | bitácora |
| `README.md:84,211` | describir el picker según el resultado de G1 | documentación de usuario |
| `distro/first-run/mytical-welcome:94` y `distro/debian/mytical-welcome/usr/bin/mytical-welcome:94` | el texto "Nix fija ... Quickshell" no aplica a la ISO | primer arranque honesto |
| `THIRD_PARTY_NOTICES` | licencias de `swaybg` (MIT) y, si entra, Quickshell (LGPL-3.0) | cumplimiento |

No cambian: `wlogout/layout` (el `||` ya degrada),
`quickshell/hyprquickpaper/commands.sh` (`wallpaper set` sigue siendo el
contrato), `hypr/modules/autostart.lua` (ya solo llama `session-start`) ni
`distro/ownership.json` (matriz de la Preview; la ISO se gobierna por
`mytical.list`).

**Dependencia externa a este cambio:** hoy **ningún paquete** instala
`~/.config/quickshell`, `~/.config/hypr` ni `~/.local/bin/wallpaper`. Si la ISO
no entrega las configuraciones de usuario, ninguna de las dos opciones se nota.
Eso pertenece al empaquetado de dotfiles, no a este documento, pero bloquea
AC-3 a AC-7 igual.

---

## 11. Plan de trabajo

1. **G1** en una 26.04 (0,5 h): `apt-cache policy quickshell` y
   `apt-get install -s quickshell`. Anotar versión y Qt.
2. **Backend** (4–6 h): `scripts/wallpaper` con los dos backends, PID file,
   espera por backend, stubs en los tests.
3. **Picker** (2 h): `scripts/wallpaper-picker` + binding + enlaces en
   `setup.py` y `nix/home.nix`.
4. **Lista y chequeos** (0,5 h): `mytical.list`, `required-commands.txt`,
   `manual.md`.
5. **Smoke en QEMU** (B7): AC-3 a AC-8 sobre la ISO construida.
6. **Cierre documental**: `ISO.md` B5, `APT-DESKTOP.md`, `PROGRESS.md`,
   `THIRD_PARTY_NOTICES`.

Rollback: `git revert` del commit de la lista y del script devuelve la ISO al
estado anterior; la Preview no se toca en ningún paso porque awww sigue en Nix.

---

## 12. Riesgos residuales y trabajo futuro

- **R1 — versión del archive.** Si 26.04 trae 0.3.x, el QML está validado; si
  sube a 0.4 con cambios de API, hay que revalidar o fijar la versión con un
  pin del repo Mytical. Anotar la versión exacta en el release.
- **R2 — hotplug de monitores.** `swaybg` no reacciona a cambios de salida como
  awww. Si aparece una segunda pantalla, hace falta relanzar el backend; un
  hook de monitor que llame `wallpaper restore` lo resuelve. `hyprpaper` sería
  mejor aquí si entra en 26.04 sin arrastrar skew de librerías hypr\*.
- **R3 — volver a awww.** Es el candidato más barato de mantener a largo plazo
  (sin ABI privada): si el fundido se echa de menos, empaquetarlo en V1.2 con
  vendorizado es un trabajo acotado y no cambia ninguna interfaz.
- **R4 — plan C de wallpaper.** Si 26.04 no trae `swaybg` (improbable: está en
  trixie main), `hyprpaper`; y si tampoco, empaquetar `swaybg` es trivial
  (MIT, 57 KiB, dependencias ya presentes).
- **R5 — fuera de alcance.** Que Hyprland 0.55.4 entre en el repo Mytical
  cambia las versiones de `libhypr*` del sistema y con ellas el atractivo de
  `hyprpaper`. Revisar este documento cuando se cierre ese empaquetado.

---

## 13. Referencias

- [`ADR 0009`](../adr/0009-apt-first-nix-v2.md) — V1.1 APT-only, V2 Nix.
- [`ADR 0002`](../adr/0002-apt-owned-desktop.md) — APT es dueño del escritorio
  en la ISO.
- [`APT-DESKTOP.md`](APT-DESKTOP.md) — auditoría inicial del archive.
- [`ISO.md`](ISO.md) — bloqueantes B1–B8 y criterios de la ISO.
- [`../../distro/iso/package-lists/mytical.list`](../../distro/iso/package-lists/mytical.list)
  — lista de paquetes del rootfs.
- [`../../scripts/wallpaper`](../../scripts/wallpaper),
  [`../../scripts/session-start`](../../scripts/session-start),
  [`../../scripts/session-splash`](../../scripts/session-splash) — contrato de
  fondo y de cierre.
- [`../../nix/README.md`](../../nix/README.md) y `flake.lock` — versiones de la
  Preview y del pin de nixpkgs.
- Debian: `salsa.debian.org/micl/quickshell` (empaquetado de referencia),
  `codeberg.org/LGFae/awww` (upstream), `github.com/hyprwm/hyprpaper`,
  `github.com/swaywm/swaybg`.
