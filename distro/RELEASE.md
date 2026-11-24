# Release V1.0.3 Preview

## Construir

```sh
make -C distro clean packages
make -C distro test
```

## Instalar

```sh
sudo distro/install-overlay.sh --user "$USER"
```

El instalador no ejecuta `autoremove` y guarda el display manager anterior en
`/var/lib/mytical/sddm` antes de tocar paquetes. No sobrescribe un backup que
ya exista. Después, como usuario:

```sh
cd ~/.dotfiles
nix run .#home-manager -- switch --flake .#default --impure -b backup
mytical-welcome
```

## Verificar

```sh
systemctl is-active sddm
ls /usr/share/wayland-sessions
dpkg -s mytical-session mytical-desktop mytical-welcome
nix flake check --no-build
mytical-welcome --check
```

## Rollback

La guía completa, con diagnóstico y recuperación, está en
[`docs/distro/ROLLBACK.md`](../docs/distro/ROLLBACK.md). Resumen:

### Antes de instalar: backup

1. Snapshot de la VM (con la VM apagada o en el login).
2. El instalador guarda automáticamente, si existen:

   ```text
   /var/lib/mytical/sddm/display-manager.service.orig
   /var/lib/mytical/sddm/default-display-manager.orig
   ```

3. Comprobalo antes de dar la instalación por buena:

   ```sh
   ls -l /var/lib/mytical/sddm
   readlink -f /var/lib/mytical/sddm/display-manager.service.orig
   ```

El backup no se sobrescribe: guarda el primer display manager, no el último.
No borres `/var/lib/mytical/sddm` hasta confirmar que no vas a volver atrás.

### Rollback de paquetes

Desde una TTY:

```sh
cd ~/.dotfiles
distro/install-overlay.sh --restore --dry-run
sudo distro/install-overlay.sh --restore
```

`--dry-run` no pide root, no ejecuta `apt` y muestra exactamente qué haría.
`--restore`:

- purga solo los paquetes `mytical-*` instalados;
- **no** ejecuta `autoremove` ni desinstala dependencias compartidas;
- restaura SDDM/GDM si hay un backup usable en `/var/lib/mytical/sddm`;
- si no hay backup, deja SDDM como está y avisa;
- no toca `/home` ni la configuración de Nix.

Verificación posterior:

```sh
dpkg -l 'mytical-*' | cat
systemctl is-active sddm
systemctl --failed --no-pager
ls /usr/share/wayland-sessions
```

Si el backup apunta a GDM y `gdm3` ya no está, terminá el rollback de paquetes
y después instalalo:

```sh
sudo apt-get install gdm3
sudo dpkg-reconfigure gdm3
```

### Rollback de Nix

Como el usuario de escritorio:

```sh
home-manager generations
home-manager switch --rollback
```

Si no está en el `PATH`:

```sh
~/.nix-profile/bin/home-manager switch --rollback
```

Es una capa independiente del rollback de paquetes. No borres `/nix`,
`~/.nix-profile`, `~/.local/state/nix` ni `~/.dotfiles`: son el historial que
permite volver atrás. `nix profile rollback` solo aplica si instalaste paquetes
con `nix profile install`, que no es el flujo del flake.

### TTY

`Ctrl+Alt+F3` (o `F2`–`F6`) abre una consola aunque SDDM/Hyprland estén rotos.
Si no hay TTY, arrancá con `systemd.unit=multi-user.target` desde GRUB y
ejecutá el rollback desde ahí. No ejecutes `--restore` desde la sesión gráfica:
reiniciar `display-manager` corta la sesión.

### Qué NO hacer

- No ejecutes `apt autoremove` ni `apt-get autoremove --purge`.
- No desinstales a mano `sddm`, `xserver-xorg`, `pipewire` ni la base del
  escritorio.
- No borres `/home`, `~/.config`, `~/.dotfiles`, `~/.nix-profile`,
  `~/.local/state/nix` ni `/nix`.
- No borres `/var/lib/mytical/sddm` (backup del display manager).
- No hagas `rm -rf /etc/sddm.conf.d` (hay configuración ajena a Mytical).
- No instales `gdm3` mientras `mytical-session` siga instalado.
- No corras `nix-collect-garbage -d` antes de decidir el rollback.

Validación de este cambio: `bash -n`, `shellcheck`, `--help` y
`--restore --dry-run` verificados. La ejecución real del rollback debe probarse
en una VM Ubuntu 26.04 con snapshot antes de publicar (ver
[`ROLLBACK.md`](../docs/distro/ROLLBACK.md) §6).

## Publicación

La licencia raíz ya está aceptada (GPL-3.0-or-later). Antes de publicar faltan
la clave APT de producción y la revisión final de assets.

## Repo APT público temporal

Mientras no haya un host estático dedicado, el snapshot firmado de `v0.1.3`
está publicado en el repo de GitHub:

```text
https://raw.githubusercontent.com/myticalruben/Mytical/main/distro/apt/snapshots/v0.1.3
```

`apt-get update` y `apt-cache policy` fueron verificados contra esa URL en la
VM limpia `10.0.0.166`.


## Notas de release

Ver [`docs/releases/`](../docs/releases/). Cada versión incluye sus
características agregadas, cambiadas, corregidas y removidas.
