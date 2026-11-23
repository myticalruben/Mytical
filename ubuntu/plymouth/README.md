# Plymouth Mytical (Ubuntu)

Tema de arranque propio para Ubuntu. El módulo `two-step` muestra un wordmark
**MYTICAL** animado sobre fondo negro y una barra de progreso cian. La
configuración del tema es propia y se distribuye bajo GPL-3.0-or-later.

## Assets y licencias

| Ruta | Qué es | Autoría | Licencia |
|---|---|---|---|
| `mytical/mytical.plymouth` | Configuración del tema (`two-step`) | Mytical contributors | GPL-3.0-or-later |
| `mytical/animation-00.png` … `animation-87.png` | 88 frames de 640×260 con el wordmark MYTICAL | Mytical (generados por el proyecto) | CC0-1.0 |
| `mytical/throbber-00.png` … `throbber-40.png` | 41 frames de 65×65 del anillo de progreso | Mytical (generados por el proyecto) | CC0-1.0 |
| `fonts/Audiowide-Regular.ttf` + `fonts/OFL.txt` | Tipografía usada para generar el wordmark | Brian J. Bonislawsky / Astigmatic | SIL OFL 1.1 |
| `install.sh` | Instalador y reversión | Mytical contributors | GPL-3.0-or-later |

- Los frames y los throbbers son arte propio; los throbbers se regeneraron y
  ya no son blobs de CachyOS (ver la resolución de `ASSET-LICENSES.md`). La
  procedencia y el proceso de generación de los frames siguen en P1-02.
- La configuración no reproduce el archivo de CachyOS: se escribió para las
  claves de `two-step` y solo conserva los nombres de sección/clave que exige
  el módulo y los valores funcionales del tema.
- El tema usa las fuentes del sistema `Ubuntu` y `Ubuntu Light`; no se
  empaquetan en el repositorio.
- `fonts/` no se copia al initramfs: el TTF solo se usa para generar el
  wordmark. Si se redistribuye, conservar `OFL.txt`.

## Instalar

```sh
sudo ubuntu/plymouth/install.sh
```

El script guarda el initrd y el tema anterior en `/var/lib/mytical-plymouth/`.
El cambio se ve al reiniciar.

## Verificar el tema

```sh
# 1. Ver qué haría el instalador, sin tocar el sistema.
ubuntu/plymouth/install.sh --dry-run

# 2. Instalar el tema y regenerar el initramfs.
sudo ubuntu/plymouth/install.sh

# 3. Confirmar que la alternativa y Plymouth ven el tema.
readlink -f /etc/alternatives/default.plymouth
plymouth-set-default-theme --list

# 4. Reiniciar: el splash solo se ve durante el arranque.
sudo reboot
```

Si el tema no aparece, comprobá que el kernel use `quiet splash` y que
`update-initramfs` haya terminado sin errores. Para probar sin reiniciar la
máquina, usá una VM.

## Estructura del archivo

- `[Plymouth Theme]`: nombre, descripción y módulo (`two-step`).
- `[two-step]`: directorio de imágenes, fuentes, alineación de la marca de
  agua, colores y posición del texto.
- `[shutdown]` y `[reboot]`: desactivan la animación final.
- `[updates]`, `[system-upgrade]`, `[firmware-upgrade]` y `[system-reset]`:
  barra de progreso con porcentaje y textos de estado.
- No hay `[boot-up]`: `two-step` activa la animación y su end-animation por
  defecto. Las claves con el mismo valor que el default del módulo
  (alineaciones 0.5, `Transition=none`, `TransitionDuration=0.0`,
  `UseFirmwareBackground=false`) se omiten para no duplicarlas; el resultado
  efectivo es el mismo.

## Volver atrás

```sh
sudo ubuntu/plymouth/install.sh --restore
```

## Licencia

La configuración y `install.sh` son código propio bajo **GPL-3.0-or-later**
(ver `LICENSE` y `COPYRIGHT` en la raíz). Los frames y throbbers se declaran
**CC0-1.0** en `distro/branding/LICENSES.md`; Audiowide conserva **SIL OFL
1.1** en `fonts/OFL.txt`. Ubuntu es una marca de Canonical; Mytical no es una
edición oficial.
