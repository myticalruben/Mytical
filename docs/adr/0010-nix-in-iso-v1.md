# ADR 0010 — Nix dentro de la ISO V1.1

**Estado:** aceptado (2026-11-24). Supersede el APT-only de ADR 0009.

## Contexto

Ubuntu 26.04 trae Hyprland 0.53.3 y no carga la configuración Lua de 0.55/0.56.
Quickshell y awww no están en el archive. Empaquetar todo para APT es más caro y
arriesgado que reutilizar el perfil Nix ya probado.

## Decisión

- La ISO V1.1 es **híbrida**: APT para kernel, firmware, login, red, audio,
  portales y base del sistema; **Nix para el escritorio**.
- La ISO **incluye `/nix`** con el cierre de Hyprland/Waybar/Quickshell/Kitty
  y las apps de usuario.
- No se instala Hyprland 0.53 de Ubuntu ni se usa como compositor.
- El perfil Nix del usuario se activa con Home Manager desde el flake incluido,
  sin depender de una descarga en el primer arranque.
- La V2 podrá profundizar la migración a Nix; V1.1 ya no es APT-only.

## Consecuencias

- La ISO crece ~3.8 GiB y necesita más almacenamiento temporal.
- `mytical-session` debe encontrar el perfil Nix antes que cualquier Hyprland
  de APT.
- La regla anterior “sin `/nix` en la ISO” queda revocada para V1.1.
- Quickshell/awww se conservan desde Nix; no hay que empaquetarlos para APT.
