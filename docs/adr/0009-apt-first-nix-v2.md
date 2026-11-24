# ADR 0009 — V1.1 APT-only; migración a Nix en V2

**Estado:** aceptado (2026-11-24)

## Contexto

La V1.0 Preview usa Nix para el escritorio. La primera ISO V1.1 se quería
APT-only, pero Ubuntu 26.04 trae Hyprland 0.53.3 y no carga la configuración
Lua de 0.55/0.56. Quickshell y awww tampoco están en el archive.

## Decisión

- **V1.1 será APT-only**, sin `/nix`.
- Hyprland 0.55.4 (la versión ya probada con Lua) se empaqueta en el repo
  Mytical, no se usa el 0.53.3 de Ubuntu.
- Quickshell y awww se empaquetan o se sustituyen por alternativas APT; no se
  activa la ISO hasta resolverlos.
- **V2** será la migración a Nix como capa principal del escritorio.
- La experiencia actual en Nix se conserva en la Preview y sirve de referencia
  para V2.

## Consecuencias

- La ISO V1.1 requiere trabajo de empaquetado propio.
- No se añade Nix a la ISO por comodidad.
- La configuración Lua se mantiene; no se porta a 0.53.
- La migración a Nix se planifica después de validar la ISO APT.

## Corrección 2026-11-24

- `quickshell` está ausente del archive de Ubuntu 26.04 (sí existe en Debian).
- `awww` está ausente; `hyprpaper` y `swaybg` sí están.
- `hyprland` de Ubuntu es 0.53.3; el paquete Debian de 0.55.2 es la base más
  barata para empaquetar la versión con Lua.
