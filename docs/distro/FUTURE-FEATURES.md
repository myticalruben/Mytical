# Características futuras de Mytical

Backlog vivo. No implica compromiso de versión; cada entrada se convierte en
ADR/plan cuando se vaya a implementar.

## SDDM y branding

| Prioridad | Característica | Motivo | Estado |
|---|---|---|---|
| P1 | **Paleta neón fija para SDDM**, independiente del wallpaper | El tema actual se adapta al fondo; con wallpapers azules el login pierde el acento cian/magenta de la marca | Implementado en `ubuntu/sddm/` (2026-11-23) |
| P1 | Selector de modo en `mytical-welcome`/ajustes: `adaptive` vs `neon fijo` | Que el usuario elija sin editar `mytical.conf` | Pendiente |
| P2 | Validación y fallback del fondo SDDM | Si el wallpaper no existe o está corrupto, volver a un fondo CC0 y avisar | Pendiente |
| P2 | Recorte/posición configurable del fondo | `CropBackground` hoy fijo en `true` | Pendiente |
| P2 | Preview del fondo en el primer arranque | Ver cómo quedará el login antes de aplicarlo | Pendiente |

## Sistema y release

| Prioridad | Característica | Estado |
|---|---|---|
| P0 | Clave GPG de producción del repo APT y publicación firmada | Pendiente |
| P1 | ISO V1.1 con remaster casper + Calamares | Pendiente |
| P1 | Compositor Hyprland/portal propiedad de APT en la ISO | Pendiente |
| P1 | `mytical-settings` (apariencia, pantalla, teclado, red, sonido, energía) | Pendiente |
| P2 | Actualizador propio con notas y rollback | Pendiente |
| P2 | Recuperación desde TTY y rollback Nix visible | Pendiente |

## Jarvis

| Prioridad | Característica | Estado |
|---|---|---|
| P2 | Interfaz D-Bus `org.mytical.Jarvis1` | ADR 0005 |
| P2 | Modelo local + fallback cloud con consentimiento | ADR 0005 |
| P3 | Voz, wake word y acciones autónomas | No antes de V1.1 |
