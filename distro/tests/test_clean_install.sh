#!/usr/bin/env bash
# Verifica una instalación limpia de Mytical V1.0 sobre Ubuntu 26.04.
#
# Solo lectura: no ejecuta apt, dpkg -i ni systemctl start, y no escribe en
# /home. Exit 0 si todo está correcto o si el sistema no es Ubuntu (SKIP);
# exit 1 si es Ubuntu y no cumple los requisitos (incluida otra versión).
set -uo pipefail

os_release="/etc/os-release"
os_id=""
os_version=""
os_pretty=""

ok_count=0
failures=0

ok() {
    ok_count=$((ok_count + 1))
    printf '[OK]    %s\n' "$*"
}

missing() {
    failures=$((failures + 1))
    printf '[FALTA] %s\n' "$*"
}

skip() {
    printf 'SKIP: %s\n' "$*"
    exit 0
}

os_release_field() {
    local key="$1" value
    value="$(sed -n "s/^${key}=//p" "$os_release" 2>/dev/null | head -n 1)"
    value="${value#\"}"
    value="${value%\"}"
    printf '%s\n' "$value"
}

check_file() {
    local path="$1" description="$2"
    if [ -f "$path" ]; then
        ok "$description: $path"
    else
        missing "$description: falta $path"
    fi
}

check_package() {
    local package="$1" status
    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    if [ "$status" = "install ok installed" ]; then
        ok "paquete instalado: $package"
    else
        missing "paquete no instalado: $package (estado: ${status:-ausente})"
    fi
}

check_active_unit() {
    local unit="$1" description="$2" state
    if ! command -v systemctl >/dev/null 2>&1; then
        missing "$description: systemctl no está disponible para consultar $unit"
        return
    fi
    state="$(systemctl is-active "$unit" 2>/dev/null || true)"
    if [ "$state" = "active" ]; then
        ok "$description: $unit está activo"
    else
        missing "$description: $unit no está activo (estado: ${state:-desconocido})"
    fi
}

# Busca un ejecutable para el usuario actual: primero PATH y después el perfil
# de Nix, igual que el wrapper /usr/bin/mytical-session.
find_user_command() {
    local name="$1" candidate
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    if [ -n "${HOME:-}" ]; then
        candidate="$HOME/.nix-profile/bin/$name"
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi
    return 1
}

check_welcome() {
    local output rc
    if ! command -v mytical-welcome >/dev/null 2>&1; then
        missing "mytical-welcome no está en PATH; no se puede ejecutar 'mytical-welcome --check'"
        return
    fi
    output="$(mytical-welcome --check 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "mytical-welcome --check termina correctamente (exit 0)"
    else
        missing "mytical-welcome --check falló (exit $rc)"
        if [ -n "$output" ]; then
            printf '%s\n' "$output" | sed 's/^/        /'
        fi
    fi
}

check_hyprctl() {
    local path
    if path="$(find_user_command hyprctl)"; then
        ok "hyprctl disponible para el usuario actual: $path"
    else
        missing "hyprctl no está disponible para el usuario actual (PATH ni ~/.nix-profile/bin)"
    fi
}

check_hyprland() {
    local name path=""
    for name in hyprland-session Hyprland start-hyprland; do
        if path="$(find_user_command "$name")"; then
            break
        fi
    done
    if [ -n "$path" ]; then
        ok "Hyprland lanzable para el usuario actual: $path"
    else
        missing "Hyprland no está disponible (hyprland-session, Hyprland ni start-hyprland)"
    fi
}

printf 'Mytical V1.0 — verificador de instalación limpia (Ubuntu 26.04)\n'
printf 'Solo lectura: no instala, no inicia servicios y no escribe en /home.\n'
printf 'Archivo de sistema: %s\n\n' "$os_release"

if [ ! -r "$os_release" ]; then
    skip "no se puede leer $os_release; se asume que el sistema no es Ubuntu 26.04"
fi

os_id="$(os_release_field ID)"
os_version="$(os_release_field VERSION_ID)"
os_pretty="$(os_release_field PRETTY_NAME)"

printf 'Sistema: %s | ID=%s | VERSION_ID=%s\n\n' \
    "${os_pretty:-desconocido}" "${os_id:-desconocido}" "${os_version:-desconocido}"

if [ "$os_id" != "ubuntu" ]; then
    skip "el sistema no es Ubuntu (ID=${os_id:-desconocido}); no hay una instalación Mytical que verificar"
fi

if ! command -v dpkg >/dev/null 2>&1 || ! command -v dpkg-query >/dev/null 2>&1; then
    skip "dpkg/dpkg-query no están disponibles; no se puede verificar la instalación"
fi

if [ "$os_version" != "26.04" ]; then
    missing "Ubuntu ${os_version:-desconocido} no es la versión objetivo (se esperaba VERSION_ID=26.04; PRETTY_NAME=${os_pretty:-desconocido})"
    printf '\nRESULTADO: versión de Ubuntu no soportada; no se verifican el resto de requisitos.\n'
    printf 'Este verificador solo aplica a Ubuntu 26.04. Ver docs/distro/CLEAN-INSTALL.md.\n'
    exit 1
fi

ok "Ubuntu 26.04 ($os_release)"

check_active_unit sddm "SDDM"

check_file /usr/share/wayland-sessions/mytical.desktop "sesión Wayland de Mytical"

for package in mytical-session mytical-desktop mytical-welcome mytical-sddm-theme; do
    check_package "$package"
done

check_file /usr/share/sddm/themes/mytical/Main.qml "tema SDDM: Main.qml"
check_file /usr/share/sddm/themes/mytical/Backgrounds/wallpaper "tema SDDM: Backgrounds/wallpaper"

check_active_unit mytical-sddm-sync.path "sincronización del fondo de SDDM"

check_welcome
check_hyprctl
check_hyprland

printf '\nRESULTADO: %d OK, %d FALTA\n' "$ok_count" "$failures"

if [ "$failures" -ne 0 ]; then
    printf 'La instalación NO cumple los requisitos. Ver docs/distro/CLEAN-INSTALL.md.\n'
    exit 1
fi

printf 'Instalación limpia de Mytical V1.0 verificada.\n'
