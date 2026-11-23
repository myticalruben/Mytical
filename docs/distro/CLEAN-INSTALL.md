# Verificación de instalación limpia — Mytical V1.0

> **Alcance:** Ubuntu 26.04 recién instalado con el overlay Mytical V1.0
> (`mytical-session`, `mytical-desktop`, `mytical-welcome` y
> `mytical-sddm-theme`).
> **Modo:** solo lectura. El verificador no instala, no inicia servicios y no
> escribe en `/home`.
> **Script:** [`distro/tests/test_clean_install.sh`](../../distro/tests/test_clean_install.sh)
> **Fecha:** 2026-11-23

Este documento explica qué comprueba el verificador, cómo se ejecuta, cómo se
interpreta su salida y qué hacer cuando falla. No reemplaza al
[smoke test manual de release](../../distro/RELEASE.md): es la comprobación
objetiva y repetible del estado del sistema tras una instalación limpia.

## Requisitos

- **Ubuntu 26.04.** El script lee `/etc/os-release` y exige `ID=ubuntu` y
  `VERSION_ID=26.04`. En Debian u otra distribución se omite con `SKIP`; en otra
  versión de Ubuntu falla sin continuar (ver [códigos de salida](#comando)).
- **systemd operativo**, con SDDM como display manager y la sesión Wayland
  `mytical.desktop` instalada.
- **`dpkg` y `dpkg-query`** disponibles para consultar el estado de los
  paquetes.
- **Overlay V1.0 instalado**: los cuatro paquetes `mytical-*` y el tema SDDM
  completo.
- **Ejecutar como el usuario de escritorio**, sin `sudo`. Las comprobaciones de
  `hyprctl` y Hyprland usan el `PATH` y `~/.nix-profile/bin` de quien ejecuta;
  como root darían un falso negativo.
- No hace falta conexión de red ni permisos de escritura.

## Qué comprueba

| # | Comprobación | Cómo se verifica (solo lectura) |
|---|---|---|
| 1 | Base Ubuntu 26.04 | `ID` y `VERSION_ID` en `/etc/os-release` |
| 2 | SDDM activo | `systemctl is-active sddm` |
| 3 | Sesión Wayland de Mytical | existe `/usr/share/wayland-sessions/mytical.desktop` |
| 4 | Paquetes `mytical-session`, `mytical-desktop`, `mytical-welcome` y `mytical-sddm-theme` | `dpkg-query -W -f='${Status}'` devuelve `install ok installed` |
| 5 | Tema SDDM: `Main.qml` | existe `/usr/share/sddm/themes/mytical/Main.qml` |
| 6 | Tema SDDM: fondo | existe `/usr/share/sddm/themes/mytical/Backgrounds/wallpaper` |
| 7 | Sincronización del fondo | `systemctl is-active mytical-sddm-sync.path` |
| 8 | Guía de primer arranque | `mytical-welcome --check` termina con exit 0 |
| 9 | `hyprctl` disponible para el usuario | `command -v hyprctl` o `~/.nix-profile/bin/hyprctl` ejecutable |
| 10 | Hyprland lanzable para el usuario | `hyprland-session`, `Hyprland` o `start-hyprland` en `PATH` o `~/.nix-profile/bin` |

En total se contabilizan 13 comprobaciones: los cuatro paquetes de la fila 4
cuentan por separado. La comprobación 10 replica el orden de fallback del wrapper
`/usr/bin/mytical-session` (ver [ADR 0006](../adr/0006-single-session.md)): no
exige que Hyprland esté corriendo, sino que exista una forma de lanzarlo.

## Comando

Desde la raíz del repositorio:

```sh
./distro/tests/test_clean_install.sh
```

También se puede invocar con `bash distro/tests/test_clean_install.sh`. No
acepta argumentos, no necesita `sudo` y no modifica el sistema.

Códigos de salida:

| Exit | Significado |
|---|---|
| `0` | Todas las comprobaciones pasan, **o** el sistema no es Ubuntu (o falta `dpkg`) y se omitió con `SKIP`. |
| `1` | Es Ubuntu 26.04 y falta al menos un requisito, **o** es Ubuntu pero no 26.04 (en ese caso el script se detiene tras comprobar la versión). |

El `SKIP` con exit 0 aplica si no se puede leer `/etc/os-release`, si `ID` no es
`ubuntu` o si faltan `dpkg`/`dpkg-query`. Un `SKIP` significa "no aplicable",
no "instalación verificada": en automatización conviene revisar también que la
salida no contenga una línea `SKIP:`.

## Interpretación de la salida

Ejemplo de una instalación correcta:

```text
Mytical V1.0 — verificador de instalación limpia (Ubuntu 26.04)
Solo lectura: no instala, no inicia servicios y no escribe en /home.
Archivo de sistema: /etc/os-release

Sistema: Ubuntu 26.04 LTS | ID=ubuntu | VERSION_ID=26.04

[OK]    Ubuntu 26.04 (/etc/os-release)
[OK]    SDDM: sddm está activo
[OK]    sesión Wayland de Mytical: /usr/share/wayland-sessions/mytical.desktop
[OK]    paquete instalado: mytical-session
...
RESULTADO: 13 OK, 0 FALTA
Instalación limpia de Mytical V1.0 verificada.
```

- `[OK]`: la comprobación pasó.
- `[FALTA]`: el requisito no se cumple; se muestra el motivo y, si aplica, el
  estado real (`inactive`, `install ok config-files`, etc.).
- `SKIP: ...`: el sistema no es Ubuntu o falta `dpkg`; no se evaluó el resto.
  Exit 0.
- `RESULTADO: N OK, M FALTA`: resumen final. Si `M` es mayor que cero, el exit
  es 1.

Todas las comprobaciones de una instalación Ubuntu 26.04 se ejecutan aunque
alguna falle, para obtener la lista completa de problemas en una sola pasada.
La única excepción es una versión de Ubuntu distinta de 26.04: el script
informa el error y se detiene, porque el resto de requisitos no aplica.

## Si falla

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `[FALTA] Ubuntu X no es la versión objetivo` | La base no es 26.04. | Repetir la instalación limpia sobre Ubuntu 26.04. El script no continúa con otras versiones. |
| `[FALTA] SDDM: sddm no está activo` | SDDM no está habilitado, está enmascarado o el arranque no llegó al display manager. | Revisar `systemctl status sddm` y `systemctl is-enabled sddm`; habilitarlo/arrancarlo manualmente si corresponde. Si el paquete no está, reinstalar las dependencias del overlay. |
| `[FALTA] sesión Wayland de Mytical` | No se instaló `mytical-session` o su postinst no copió la entrada. | Reinstalar `mytical-session` desde `distro/build` o volver a ejecutar [`distro/install-overlay.sh`](../../distro/install-overlay.sh). |
| `[FALTA] paquete no instalado: mytical-*` | El paquete falta o quedó en estado `config-files`/`half-installed`. | Ver `dpkg -l 'mytical-*'` y reinstalar el `.deb` correspondiente. También se puede volver a ejecutar `sudo distro/install-overlay.sh` (con `--user USUARIO` si `SUDO_USER` no está definido). |
| `[FALTA] tema SDDM: Main.qml` o `Backgrounds/wallpaper` | `mytical-sddm-theme` está instalado a medias o se borraron archivos del tema. | Reinstalar `mytical-sddm-theme`; el tema vive bajo `/usr/share/sddm/themes/mytical`. |
| `[FALTA] sincronización del fondo de SDDM: mytical-sddm-sync.path no está activo` | El postinst del tema no creó/habilitó la unidad porque no había usuario humano al instalar, o la unidad se deshabilitó. | Revisar `systemctl status mytical-sddm-sync.path` y `systemctl cat mytical-sddm-sync.path`. Si la unidad no existe, reinstalar `mytical-sddm-theme` con un usuario humano presente; si existe pero está inactiva, habilitarla/arrancarla manualmente. |
| `[FALTA] mytical-welcome --check falló` | `python3` ausente o el script de bienvenida no está instalado/completo. | Ejecutar `mytical-welcome --check` a mano para ver el detalle; comprobar `python3` y reinstalar `mytical-welcome`. |
| `[FALTA] hyprctl no está disponible` | El perfil de Nix/Home Manager no está activo para ese usuario, o se ejecutó el verificador como root/otro usuario. | Ejecutar como el usuario de escritorio; activar el perfil de Home Manager y volver a iniciar sesión; comprobar `command -v hyprctl` y `ls ~/.nix-profile/bin/hyprctl`. |
| `[FALTA] Hyprland no está disponible` | No hay `Hyprland`, `hyprland-session` ni `start-hyprland` en el `PATH` del usuario ni en `~/.nix-profile/bin`. | Verificar el perfil de Nix/Home Manager del usuario; en la ISO, que el paquete de Hyprland de APT esté instalado. |
| `SKIP: el sistema no es Ubuntu` o `SKIP: dpkg...` | El script se ejecutó en una máquina que no es la base objetivo. | Ejecutarlo dentro de Ubuntu 26.04. No es un fallo de Mytical. |

Para diagnosticar, adjuntar al reporte la salida completa del verificador y:

```sh
dpkg -l 'mytical-*' | cat
systemctl status sddm --no-pager
systemctl status mytical-sddm-sync.path --no-pager
```

Los comandos de reparación son manuales: el verificador **no** los ejecuta.

## Qué no hace

- No ejecuta `apt`, `apt-get`, `dpkg -i`, `systemctl start/restart/enable` ni
  `autoremove`.
- No crea, modifica ni borra archivos, tampoco en `/home`.
- Solo lee `/etc/os-release`, los archivos del tema y la sesión, consulta
  `dpkg-query`/`systemctl is-active`, busca ejecutables en `PATH` (y
  `~/.nix-profile/bin`) y ejecuta `mytical-welcome --check`, que retorna antes
  de escribir su estado de primer arranque.
- No forma parte de `make -C distro test`: requiere una instalación real y un
  usuario de escritorio. Se ejecuta a mano después del
  [smoke test de release](../../distro/RELEASE.md).
