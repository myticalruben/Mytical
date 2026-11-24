# Escritorio APT para la ISO V1.1

## Auditoría del archive de Ubuntu 26.04

| Paquete | Estado |
|---|---|
| hyprland | 0.53.3; no carga Lua de 0.55/0.56 |
| hyprlock | 0.9.2 |
| hypridle | 0.1.7 |
| waybar | 0.15.0 |
| dunst, kitty, wlogout, rofi, thunar | disponibles |
| quickshell | **ausente** |
| awww | **ausente** |

## Estrategia

1. Empaquetar **Hyprland 0.55.4** en el repo Mytical y usarlo en la ISO.
2. Empaquetar **Quickshell** o retirar el splash de salida de la ISO.
3. Empaquetar **awww** o sustituirlo por un daemon APT compatible.
4. Reconstruir `mytical-session`, `mytical-desktop` y el repo APT con esas
   dependencias.
5. Construir la ISO y probar el escritorio completo.

## Reglas

- Sin `/nix` en V1.1.
- No portar la configuración a Hyprland 0.53.
- La migración a Nix queda para V2.
