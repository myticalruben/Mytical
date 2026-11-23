#!/usr/bin/env bash
# Instala o revierte el overlay Mytical V1.0 sobre Ubuntu 26.04.
#
#   sudo distro/install-overlay.sh --user USUARIO
#   sudo distro/install-overlay.sh --restore
#   distro/install-overlay.sh --restore --dry-run
#
# La instalación no ejecuta autoremove. Antes de tocar paquetes guarda el
# display manager anterior en /var/lib/mytical/sddm y no sobrescribe backups.
# El perfil Nix se activa aparte con home-manager.
#
# --restore purga solo paquetes mytical-*, no ejecuta autoremove, restaura el
# display manager si hay backup usable y nunca toca /home ni la config de Nix.
# Si no hay backup del display manager, deja SDDM y avisa.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build="${MYTICAL_BUILD_DIR:-$here/build}"
user="${SUDO_USER:-}"
action=install
dry_run=0
state_base=/var/lib/mytical/sddm
dm_service=/etc/systemd/system/display-manager.service
dm_default=/etc/X11/default-display-manager
packages=(mytical-sddm-theme mytical-session mytical-welcome mytical-desktop)

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\n==> %s\n' "$*"; }
warn() { printf 'aviso: %s\n' "$*" >&2; }

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

check_target_os() {
    # shellcheck source=/dev/null
    . /etc/os-release
    [ "${ID:-}" = ubuntu ] || die "este overlay asume Ubuntu"
    [ "${VERSION_ID:-}" = "26.04" ] || die "este overlay asume Ubuntu 26.04 (encontrado ${VERSION_ID:-?})"
}

# Paquetes mytical-* realmente instalados. No incluye los que solo dejaron
# configuración (`config-files`), para no purgar restos ajenos a esta corrida.
installed_mytical_packages() {
    # shellcheck disable=SC2016  # ${...} es formato de dpkg-query, no del shell
    { dpkg-query -W -f='${binary:Package}\t${Status}\n' 'mytical-*' 2>/dev/null || true; } \
        | awk -F'\t' '$2 == "install ok installed" { print $1 }'
}

# Estado del backup del display manager:
#   ninguno | roto | archivo | ok:<ruta-del-unit>
dm_backup_state() {
    local backup="$state_base/display-manager.service.orig"
    local target=""
    if [ -L "$backup" ]; then
        target=$(readlink -f "$backup" 2>/dev/null || true)
        if [ -n "$target" ] && [ -e "$target" ]; then
            printf 'ok:%s\n' "$target"
        else
            printf 'roto\n'
        fi
    elif [ -f "$backup" ]; then
        printf 'archivo\n'
    else
        printf 'ninguno\n'
    fi
}

describe_dm_backup() {
    local state
    local target
    state=$(dm_backup_state)
    echo "  backup: $state_base/display-manager.service.orig"
    case "$state" in
        ok:*)
            target="${state#ok:}"
            echo "  contenido: apunta a $target"
            echo "  accion: cp -a $state_base/display-manager.service.orig $dm_service"
            if [ "$(basename "$target")" != "sddm.service" ]; then
                echo "  accion: systemctl disable sddm.service"
            fi
            echo "  accion: systemctl daemon-reload && systemctl restart display-manager"
            if [ -f "$state_base/default-display-manager.orig" ]; then
                echo "  default-display-manager: se restaura desde $state_base/default-display-manager.orig"
            else
                echo "  default-display-manager: sin backup; no se modifica"
            fi
            ;;
        archivo)
            echo "  contenido: archivo regular de display-manager.service"
            echo "  accion: cp -a $state_base/display-manager.service.orig $dm_service"
            echo "  accion: systemctl daemon-reload && systemctl restart display-manager"
            ;;
        roto)
            echo "  contenido: el destino del enlace ya no existe"
            echo "  accion: no tocar el display manager; dejar SDDM y avisar"
            ;;
        *)
            echo "  contenido: no existe"
            echo "  accion: no tocar el display manager; dejar SDDM y avisar"
            ;;
    esac
}

show_restore_plan() {
    local installed=()
    mapfile -t installed < <(installed_mytical_packages)

    say "--restore --dry-run: simulación, no se modifica nada"
    echo "sistema: no se valida en dry-run (el objetivo es Ubuntu 26.04)"
    echo
    echo "Paquetes:"
    if [ "${#installed[@]}" -eq 0 ]; then
        echo "  mytical-* instalados: ninguno"
        echo "  accion: no ejecutar apt"
    else
        printf '  mytical-* instalados: %s\n' "${installed[*]}"
        echo "  accion: apt-get purge -y --no-auto-remove ${installed[*]}"
        echo "  autoremove: no"
    fi
    echo
    echo "Display manager:"
    describe_dm_backup
    echo
    echo "No se toca /home ni la configuración de Nix."
    echo "No se ejecuta autoremove."
}

backup_display_manager() {
    install -d -m 0755 "$state_base"

    if [ -e "$state_base/display-manager.service.orig" ] ||
       [ -L "$state_base/display-manager.service.orig" ]; then
        echo "Backup existente: $state_base/display-manager.service.orig (no se sobrescribe)"
    elif [ -e "$dm_service" ] || [ -L "$dm_service" ]; then
        cp -a "$dm_service" "$state_base/display-manager.service.orig"
        echo "Display manager anterior: $state_base/display-manager.service.orig"
    else
        echo "No hay $dm_service; --restore dejará SDDM."
    fi

    if [ -e "$state_base/default-display-manager.orig" ]; then
        echo "Backup existente: $state_base/default-display-manager.orig (no se sobrescribe)"
    elif [ -f "$dm_default" ]; then
        cp -a "$dm_default" "$state_base/default-display-manager.orig"
        echo "default-display-manager anterior: $state_base/default-display-manager.orig"
    fi
}

restore_display_manager() {
    local state
    local unit=""
    state=$(dm_backup_state)

    if [ "$state" = "ninguno" ]; then
        warn "no hay backup del display manager en $state_base"
        warn "se deja SDDM activo; no se toca el login"
        return 0
    fi
    if [ "$state" = "roto" ]; then
        warn "el backup $state_base/display-manager.service.orig apunta a un destino inexistente"
        warn "se deja SDDM activo; no se toca el login"
        warn "si el backup era GDM: sudo apt-get install gdm3 && sudo $0 --restore"
        return 0
    fi
    if [ "$state" != "archivo" ]; then
        unit=$(basename "${state#ok:}")
    fi

    if [ -n "$unit" ] && [ "$unit" != "sddm.service" ]; then
        echo "Deshabilitando SDDM (el backup apunta a $unit)"
        systemctl disable sddm.service 2>/dev/null || true
    fi

    cp -a "$state_base/display-manager.service.orig" "$dm_service"
    if [ -f "$state_base/default-display-manager.orig" ]; then
        cp -a "$state_base/default-display-manager.orig" "$dm_default"
    fi
    systemctl daemon-reload

    if ! systemctl restart display-manager; then
        warn "no se pudo reiniciar el display manager"
        warn "desde una TTY: sudo systemctl start sddm"
        return 1
    fi
    echo "Display manager restaurado: ${unit:-archivo de backup}"
}

do_restore() {
    local installed=()
    command -v dpkg-query >/dev/null || die "falta dpkg-query"
    command -v apt-get >/dev/null || die "falta apt-get"
    mapfile -t installed < <(installed_mytical_packages)

    say "Revirtiendo el overlay Mytical"
    if [ "${#installed[@]}" -eq 0 ]; then
        echo "No hay paquetes mytical-* instalados; no se ejecuta apt."
    else
        echo "Paquetes: ${installed[*]}"
        echo "apt-get purge (sin autoremove)"
        DEBIAN_FRONTEND=noninteractive apt-get purge -y --no-auto-remove "${installed[@]}"
    fi

    say "Revisando el display manager"
    restore_display_manager

    echo
    echo "Rollback de paquetes terminado."
    echo "/home y la configuración de Nix no se tocaron."
    echo "El perfil Nix se revierte aparte: home-manager switch --rollback"
    echo "Detalle: docs/distro/ROLLBACK.md"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --user) [ "$#" -ge 2 ] || die "falta el usuario"; user=$2; shift 2 ;;
        --build-dir) [ "$#" -ge 2 ] || die "falta el directorio"; build=$2; shift 2 ;;
        --restore) action=restore; shift ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "opcion desconocida: $1" ;;
    esac
done

if [ "$action" = restore ]; then
    if [ "$dry_run" -eq 1 ]; then
        show_restore_plan
        exit 0
    fi
    check_target_os
    [ "$(id -u)" -eq 0 ] || die "ejecutalo con sudo"
    do_restore
    exit 0
fi

[ -n "$user" ] && [ "$user" != root ] || die "usa --user USUARIO"

check_target_os

for package in "${packages[@]}"; do
    deb=$(find "$build" -maxdepth 1 -name "${package}_*.deb" -print -quit)
    [ -n "$deb" ] || die "falta el .deb de $package en $build"
done

if [ "$dry_run" -eq 1 ]; then
    echo "usuario: $user"
    echo "build:   $build"
    for package in "${packages[@]}"; do
        echo "paquete: $(find "$build" -maxdepth 1 -name "${package}_*.deb" -print -quit)"
    done
    echo "backup:  $state_base/display-manager.service.orig (si no existe; no se sobrescribe)"
    echo "Nix:     se comprueba después; no se instala sin red"
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "ejecutalo con sudo"

say "Guardando el display manager anterior"
backup_display_manager

say "Instalando paquetes del overlay"
for package in "${packages[@]}"; do
    deb=$(find "$build" -maxdepth 1 -name "${package}_*.deb" -print -quit)
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$deb"
done

# El paquete zsh puede preguntar por /etc/zsh/zshrc en una instalación previa.
DEBIAN_FRONTEND=noninteractive dpkg --force-confold --configure -a

home=$(getent passwd "$user" | cut -d: -f6)
say "Comprobando Nix y Home Manager para $user"
if [ -x "$home/.nix-profile/bin/home-manager" ]; then
    echo "Home Manager presente; activá el perfil con:"
    echo "  cd $home/.dotfiles && nix run .#home-manager -- switch --flake .#default --impure -b backup"
else
    echo "Nix/Home Manager no están instalados todavía."
    echo "Ejecutá como $user: bash $home/.dotfiles/nix/setup/bootstrap.sh"
fi

echo
echo "Overlay instalado. SDDM leerá /usr/share/wayland-sessions/mytical.desktop."
echo "Primer arranque: mytical-welcome"
