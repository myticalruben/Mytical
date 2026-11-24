# Escritorio APT para la ISO V1.1

## Auditoría real de Ubuntu 26.04 (10.0.0.166)

| Paquete | Estado |
|---|---|
| hyprland | **0.53.3**; no carga la configuración Lua de 0.55/0.56 |
| hyprlock | 0.9.2 |
| hypridle | 0.1.7 |
| waybar | 0.15.0 |
| hyprpaper | 0.8.3 |
| swaybg | 1.2.1 |
| dunst, kitty, wlogout, rofi, thunar | disponibles |
| quickshell | **ausente** |
| awww | **ausente** |

## Camino elegido

- **Hyprland:** empaquetar 0.55.2/0.55.4 desde fuente en el repo Mytical,
  tomando como base el paquete Debian de 0.55.2 si se puede adaptar a Ubuntu.
  No se usa 0.53.3.
- **Quickshell:** no está en Ubuntu. Para V1.1 se retira el carrusel
  `MOD+W`/Quickshell; el cierre de sesión conserva el fallback `hyprctl`.
- **awww:** se sustituye por `hyprpaper` (preferido, tiene IPC) o `swaybg`
  detrás de `scripts/wallpaper`; la Preview sigue usando awww si está.
- **Wallpapers:** sembrar `~/Pictures/Wallpapers` desde los CC0 de
  `/usr/share/backgrounds/mytical` o cambiar el fallback para no arrancar negro.

## Reglas

- Sin `/nix` en V1.1.
- No portar la configuración a Hyprland 0.53.
- La migración a Nix queda para V2.
