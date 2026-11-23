# SDDM neon para Ubuntu

Login SDDM con el wallpaper actual de Hyprland y un tema neon basado en
[SDDM Astronaut](https://github.com/Keyitdev/sddm-astronaut-theme) (GPL-3.0).

## Dependencias

```sh
sudo apt install sddm xserver-xorg
```

## Instalar

```sh
sudo ubuntu/sddm/install.sh --user deepseek
```

El instalador:

- Copia el tema a `/usr/share/sddm/themes/mytical`.
- Deja `Current=mytical` en `/etc/sddm.conf.d/90-mytical.conf`.
- Copia el wallpaper actual a `Backgrounds/wallpaper`.
- Regenera las claves de color del tema desde la misma paleta neon de Waybar
  (modo `adaptive`, el de por defecto).
- Activa `mytical-sddm.path` para seguirlo cuando cambie en Hyprland.
- Cambia el display manager de GDM a SDDM y guarda el anterior.

No reinicia la sesion de Hyprland: el proximo greeter de SDDM ya usa el tema.

## Modo de paleta

`mytical-sddm-sync` acepta `--mode adaptive|neon`:

- `adaptive` (por defecto): toma los acentos de la paleta que Waybar genera
  desde el wallpaper actual. El login cambia con el fondo.
- `neon`: fija los colores de marca de `waybar/scripts/palette.py` (cian
  `#00f0ff`, magenta `#ff2bd6`, fondo `#05080f`, texto `#d9fbff` y rojo
  `#ff4d6d`). No lee la paleta ni el wallpaper, asi que el branding del login
  no cambia aunque el fondo si.

Para dejarlo fijo en cada sincronizacion, crea `/etc/mytical/sddm.conf`:

```sh
sudo install -d -m 755 /etc/mytical
printf 'MODE=neon\n' | sudo tee /etc/mytical/sddm.conf
sudo systemctl start mytical-sddm-sync.service
```

Tambien se puede forzar en una ejecucion puntual con la variable de entorno o
con el argumento:

```sh
sudo env MYTICAL_SDDM_MODE=neon mytical-sddm-sync --user deepseek
sudo mytical-sddm-sync --user deepseek --mode neon
```

Precedencia: `--mode` > `MYTICAL_SDDM_MODE` > `MODE=` en
`/etc/mytical/sddm.conf` > `adaptive`.

El fondo se sigue actualizando en ambos modos; `neon` solo congela los
colores del tema.

## Volver a GDM

```sh
sudo ubuntu/sddm/install.sh --restore
```

## Notas

- SDDM se configura en X11 porque el servidor Wayland de GDM no viene con
  Xorg en esta instalacion.
- El fondo se actualiza al cambiar `~/.local/state/hypr/wallpaper`; el greeter
  lo toma en el proximo inicio de sesion.
