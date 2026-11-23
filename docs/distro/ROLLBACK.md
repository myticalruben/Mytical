# Rollback del overlay Mytical V1.0

> **Alcance:** Ubuntu 26.04 con el overlay V1.0 instalado
> (`mytical-session`, `mytical-desktop`, `mytical-welcome` y
> `mytical-sddm-theme`).
> **Script:** [`distro/install-overlay.sh`](../../distro/install-overlay.sh)
> **Estado:** procedimiento documentado y con `--restore --dry-run` verificado.
> La ejecución real debe probarse en una VM con snapshot antes de publicar
> (ver [`RELEASE-CHECKLIST.md`](RELEASE-CHECKLIST.md), sección 6.9).

Este documento explica cómo volver atrás después de instalar el overlay. El
rollback tiene dos capas independientes: los paquetes APT del overlay y el
perfil de Nix/Home Manager. Se pueden revertir por separado.

La regla de oro: **el rollback no toca `/home`, no borra configuraciones de
Nix y no ejecuta `autoremove`**.

## Resumen

| Capa | Comando | Qué revierte |
|---|---|---|
| Paquetes APT | `sudo distro/install-overlay.sh --restore` | Purga solo los `mytical-*` instalados y devuelve el display manager anterior si hay backup. |
| Nix/Home Manager | `home-manager switch --rollback` | Vuelve a la generación anterior del perfil de Home Manager. |
| Nix profile (opcional) | `nix profile rollback` | Solo si instalaste paquetes con `nix profile install`; no es el flujo del flake de Mytical. |

Primero el ensayo, después la ejecución:

```sh
distro/install-overlay.sh --restore --dry-run
sudo distro/install-overlay.sh --restore
```

## 1. Antes de instalar: backup

El instalador guarda automáticamente el display manager anterior **antes** de
tocar paquetes, pero conviene saber qué guarda y cómo comprobarlo.

### 1.1 Snapshot de la VM

Si vas a probar la instalación en una VM, creá un snapshot con la VM apagada o
en el login (no con la sesión Hyprland abierta):

```sh
virsh snapshot-create-as ubuntu-mytical antes-overlay \
  "Ubuntu 26.04 limpio, antes de distro/install-overlay.sh"
```

En VirtualBox/VMware, usá la opción de snapshot equivalente. El snapshot es la
red de seguridad real: el rollback de paquetes no reemplaza un snapshot.

### 1.2 Display manager

El instalador copia, si existen, estos dos archivos:

```text
/var/lib/mytical/sddm/display-manager.service.orig
/var/lib/mytical/sddm/default-display-manager.orig
```

- `display-manager.service` es el enlace que systemd usa para arrancar el
  login. Puede apuntar a `gdm.service`, `sddm.service`, etc.
- `default-display-manager` es el archivo de `/etc/X11` que usan las
  herramientas de Debian/Ubuntu para saber cuál es el gestor por defecto.

El instalador **no sobrescribe** un backup existente: el primer estado guardado
es el original. Es intencional. Si el backup ya existe y querés rehacerlo,
revisá primero qué contiene; no lo pises con SDDM.

Podés crear el backup a mano antes de instalar (el script lo hace igual):

```sh
sudo install -d -m 0755 /var/lib/mytical/sddm

if [ -e /etc/systemd/system/display-manager.service ]; then
    sudo cp -a /etc/systemd/system/display-manager.service \
        /var/lib/mytical/sddm/display-manager.service.orig
fi

if [ -f /etc/X11/default-display-manager ]; then
    sudo cp -a /etc/X11/default-display-manager \
        /var/lib/mytical/sddm/default-display-manager.orig
fi
```

Verificá el resultado:

```sh
ls -l /var/lib/mytical/sddm
readlink -f /var/lib/mytical/sddm/display-manager.service.orig
cat /var/lib/mytical/sddm/default-display-manager.orig
```

Si `readlink -f` devuelve una ruta que no existe, el backup no sirve para
restaurar. `--restore` lo detecta y deja SDDM en su lugar.

### 1.3 Nix y Home Manager

El rollback de Nix no necesita backup de archivos: Home Manager guarda una
generación por cada `switch`. Antes de instalar, anotá la generación actual:

```sh
home-manager generations
```

No borres ni muevas `/nix`, `~/.nix-profile` ni `~/.local/state/nix/profiles`:
son justamente el historial que permite volver atrás. Si el repo se actualiza,
el `flake.lock` queda versionado en git; el rollback de Home Manager no depende
de eso.

## 2. Rollback de paquetes

### 2.1 Ensayo (no modifica nada)

```sh
distro/install-overlay.sh --restore --dry-run
```

El ensayo no pide `sudo`, no ejecuta `apt` y no escribe archivos. Imprime
exactamente qué haría: los paquetes `mytical-*` detectados como instalados, el
comando de purga, si hay backup del display manager y qué se haría con él.

### 2.2 Ejecución

Desde una **TTY**, no desde la sesión gráfica (ver sección 4):

```sh
sudo distro/install-overlay.sh --restore
```

Qué hace, en orden:

1. Consulta `dpkg-query` y selecciona **solo** los paquetes `mytical-*` que
   están en estado `install ok installed`.
2. Ejecuta `apt-get purge -y --no-auto-remove` sobre esa lista. No usa
   `autoremove`, no borra dependencias compartidas (`sddm`, `xserver-xorg`,
   `pipewire`, `network-manager`, etc.) y no incluye paquetes ajenos en la
   purga.
3. El `postrm` de `mytical-sddm-theme` deshabilita y elimina
   `mytical-sddm-sync.path` / `.service` si seguían activos. El `postrm` de
   `mytical-session` no toca `/home`.
4. Si existe un backup usable del display manager, lo restaura, ejecuta
   `systemctl daemon-reload` y reinicia `display-manager`.
5. Si no hay backup, o el enlace guardado apunta a un unit inexistente, **deja
   SDDM activo** y avisa. No inventa un display manager ni rompe el login.
6. No ejecuta `nix`, no llama a `home-manager` y no lee ni escribe `/home`.

La purga también elimina el conffile del overlay
`/etc/sddm.conf.d/10-mytical.conf`. Los demás archivos de
`/etc/sddm.conf.d/` no se tocan. El backup en `/var/lib/mytical/sddm` se
conserva.

### 2.3 Verificar

```sh
dpkg -l 'mytical-*' | cat
systemctl is-active sddm
systemctl --failed --no-pager
ls /usr/share/wayland-sessions
```

Esperado:

- `dpkg -l 'mytical-*'` no muestra paquetes en estado `ii` (puede quedar algún
  `rc` si una corrida anterior dejó restos; ver 2.5).
- SDDM sigue activo si no había backup; si había backup de GDM, el login es
  GDM otra vez.
- `systemctl --failed` no muestra unidades `mytical-*`.
- La sesión `mytical.desktop` ya no aparece en `/usr/share/wayland-sessions`.

### 2.4 Si el backup apunta a GDM y `gdm3` ya no está

`mytical-session` declara `Conflicts: gdm3`, así que instalar el overlay pudo
haber desinstalado GDM. En ese caso el backup existe pero su destino
(`gdm.service`) no. `--restore` avisa y deja SDDM, que es el comportamiento
seguro.

Para recuperar GDM, primero terminá el rollback de paquetes y después:

```sh
sudo apt-get install gdm3
sudo dpkg-reconfigure gdm3
sudo systemctl restart display-manager
```

Si querés que el backup se aplique otra vez, volvé a ejecutar
`sudo distro/install-overlay.sh --restore`; el backup no se borró. No instales
`gdm3` mientras `mytical-session` siga instalado: el conflicto vuelve a
desinstalarlo.

### 2.5 Restos en estado `config-files`

Si `dpkg -l 'mytical-*'` muestra paquetes `rc` (configuración sin binarios),
`--restore` no los purga porque no están instalados. Limpialos a mano:

```sh
sudo apt-get purge mytical-session mytical-sddm-theme mytical-welcome mytical-desktop
```

Esto elimina únicamente configuración del sistema de esos paquetes; no toca
`/home` ni Nix.

## 3. Rollback de Nix

El rollback de paquetes APT no revierte el perfil de Nix. Son capas separadas.

### 3.1 Home Manager (flujo normal del repo)

Como el usuario de escritorio, **no como root**:

```sh
home-manager generations
home-manager switch --rollback
```

Si `home-manager` no está en el `PATH` (la sesión no carga
`~/.nix-profile/bin`), usá la ruta completa:

```sh
~/.nix-profile/bin/home-manager generations
~/.nix-profile/bin/home-manager switch --rollback
```

El primer comando lista las generaciones y marca la actual. El segundo activa
la anterior. Es el mecanismo documentado por Home Manager: no hace falta
reinstalar paquetes ni editar archivos a mano.

### 3.2 Volver a una generación concreta

Si querés una generación anterior que no es la inmediatamente previa:

```sh
home-manager generations
# copiá la ruta /nix/store/...-home-manager-generation de la generación elegida
/nix/store/...-home-manager-generation/activate
```

Después comprobá con `home-manager generations` cuál quedó como actual.

### 3.3 Nix profile (solo si usaste `nix profile install`)

El flake de Mytical activa paquetes con Home Manager, no con `nix profile
install`. Si además instalaste paquetes sueltos en el perfil de Nix, su
historial es otro:

```sh
nix profile list
nix profile rollback
```

No ejecutes `nix profile rollback` esperando revertir Home Manager: son
perfiles distintos.

### 3.4 Qué no tocar de Nix

No borres ni muevas:

```text
/home/USUARIO/.nix-profile
/home/USUARIO/.local/state/nix
/home/USUARIO/.config/nix
/home/USUARIO/.dotfiles
/nix
```

Tampoco ejecutes `nix-collect-garbage -d` antes de decidir: borra las
generaciones viejas y con ellas la posibilidad de volver atrás.

## 4. TTY y recuperación

El rollback de paquetes reinicia el display manager y puede cerrar la sesión
gráfica. Por eso se ejecuta desde una TTY.

### 4.1 Entrar a una TTY

1. Presioná `Ctrl+Alt+F3` (si no responde, probá `F2`, `F4`, `F5` o `F6`; en
   algunas laptops hace falta `Fn`).
2. Iniciá sesión con tu usuario y contraseña.
3. Ejecutá el ensayo y después el rollback:

```sh
cd ~/.dotfiles
distro/install-overlay.sh --restore --dry-run
sudo distro/install-overlay.sh --restore
```

La TTY sigue disponible aunque SDDM o Hyprland estén rotos. Volver a la
gráfica: `Ctrl+Alt+F1` o `F2`, según la máquina.

### 4.2 Si ni siquiera hay TTY

Arrancá en modo multiusuario para tener consola:

1. En GRUB, seleccioná Ubuntu y presioná `e`.
2. En la línea que empieza con `linux`, agregá `systemd.unit=multi-user.target`
   al final.
3. `Ctrl+X` o `F10` para arrancar.
4. Iniciá sesión en la consola y ejecutá el rollback.
5. Reiniciá para volver al objetivo gráfico normal.

### 4.3 Si el display manager no arranca después del rollback

```sh
systemctl status display-manager --no-pager
systemctl status sddm --no-pager
journalctl -b -u display-manager --no-pager
```

Reparaciones habituales:

```sh
sudo systemctl start sddm
sudo apt-get install --reinstall sddm
sudo systemctl enable sddm
```

Si el backup apuntaba a GDM y el paquete no está, completá 2.4 antes de
reiniciar.

### 4.4 Si no hay acceso ni consola

Un live USB de Ubuntu sirve para montar el disco y revisar
`/var/lib/mytical/sddm` y `/etc/systemd/system/display-manager.service`, pero
no ejecutes `--restore` dentro de un `chroot`: `systemctl` no puede hablar con
el systemd real. Usalo solo para leer o restaurar archivos a mano. Preferí
`systemd.unit=multi-user.target` (siempre que el disco arranque) o un snapshot
de la VM.

## 5. Qué NO hacer

- **No ejecutes `apt autoremove` ni `apt-get autoremove --purge`.** Puede
  llevarse dependencias que el escritorio necesita y dejar el sistema sin
  login. El instalador y el rollback no lo hacen.
- **No desinstales a mano `sddm`, `xserver-xorg`, `pipewire`,
  `network-manager` ni el resto de la base.** El rollback solo purga
  `mytical-*`.
- **No borres `/home`, `~/.config`, `~/.dotfiles`, `~/.nix-profile`,
  `~/.local/state/nix` ni `/nix`.** No son parte del overlay y son la forma de
  recuperar la sesión.
- **No borres `/var/lib/mytical/sddm`.** Es el único backup del display
  manager; sin él no se puede volver a GDM automáticamente.
- **No hagas `rm -rf /etc/sddm.conf.d`.** Ahí viven configuraciones que no son
  de Mytical.
- **No ejecutes `--restore` desde la sesión Hyprland** (ni desde una terminal
  gráfica). El reinicio de `display-manager` corta la sesión y puede
  interrumpir la purga. Usá una TTY.
- **No instales `gdm3` mientras `mytical-session` siga instalado.** El
  conflicto de paquetes lo vuelve a quitar.
- **No ejecutes `nix-collect-garbage -d` antes de decidir el rollback.** Te
  quedás sin generaciones a las que volver.
- **No reinstales Ubuntu como primer paso.** El rollback de paquetes y
  `home-manager switch --rollback` resuelven el caso normal.

## 6. Validación de este procedimiento

Verificado en este cambio:

```sh
bash -n distro/install-overlay.sh
shellcheck --shell=bash distro/install-overlay.sh
distro/install-overlay.sh --help
distro/install-overlay.sh --restore --dry-run
```

Pendiente antes de publicar (no se ejecutó todavía porque requiere una VM
Ubuntu 26.04 real y permisos de root):

1. Snapshot de la VM.
2. Instalación real del overlay.
3. `sudo distro/install-overlay.sh --restore` y comprobar 2.3.
4. Repetir con backup de GDM y sin backup (debe dejar SDDM y avisar).
5. Registrar fecha, commit y salida en la evidencia del release.
