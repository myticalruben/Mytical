# Changelog

## 0.1.3 — Mytical V1.0 Preview (2026-11-23)

- Hyprlock pasa a ser el binario APT del sistema: el de Nix usa módulos PAM
  de Nix y falla al autenticar en Ubuntu.
- `mytical-desktop` instala `hyprlock`; se retiró del perfil Nix.
- `/etc/pam.d/hyprlock` sigue siendo del paquete `mytical-session`.

## 0.1.2 — Mytical V1.0 Preview (2026-11-23)

- Añadido `/etc/pam.d/hyprlock` propio; evita el fallback a `su` y que PAM
  rechace la contraseña por `@include` no soportado.
- El paquete `mytical-session` instala esa configuración como conffile.

## 0.1.1 — Mytical V1.0 Preview (2026-11-23)

- `mytical-session` usa `90-mytical.conf`, por encima de la configuración de
  Budgie/GDM; el postinst habilita y arranca SDDM.
- Waybar recibe explícitamente `config.jsonc`; la barra aparece en una
  instalación limpia.
- Bootstrap detecta QEMU/KVM y activa render por software, no solo VirtualBox.
- `set-zsh-shell` se busca también en `~/.local/bin`.
- Wallpapers personales movidos al repo privado `mytical-wallpapers`; el repo
  público conserva solo los CC0.
- Comando `wallpapers` enlazado en PATH.

## 0.1.0 — Mytical V1.0 Preview (2026-11-17)

- Overlay instalable sobre Ubuntu 26.04 con APT + Nix.
- `mytical-session`: sesión única Hyprland y wrapper `/usr/bin/mytical-session`.
- `mytical-desktop`: base APT de login, red, audio, portales, keyring, Thunar.
- `mytical-welcome`: primer arranque, comprobaciones y elección de wallpaper.
- Nix 26.05 (`nixos-26.05` + Home Manager `release-26.05`).
- Kitty como terminal por defecto, con paleta adaptativa.
- SDDM solo con la sesión Mytical.
- hypridle, captura regional con grim/slurp y wallpaper dinámico.
- Repo APT local firmado y test aislado.
- Assets propios: throbbers, iconos wlogout y wallpapers CC0.

### Limitaciones conocidas

- Licencia raíz: GPL-3.0-or-later (ADR 0008).
- Los wallpapers personales no se distribuyen.
- La ISO V1.1 queda fuera de esta entrega.
- El repo APT usa una clave efímera en tests; producción requiere clave real.
