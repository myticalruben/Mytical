# Branding de Calamares

Solo hay texto: `branding.desc`. No se versionan binarios ni imagenes en este
directorio.

Cuando se cierre la auditoria de assets (`docs/distro/ASSET-LICENSES.md`), el
build copiara aqui, como minimo:

| Archivo | Uso en Calamares | Estado |
|---|---|---|
| `productLogo.svg` | logo de la barra lateral | TODO / bloqueado |
| `productIcon.svg` | icono de ventana | TODO / bloqueado |
| `productWelcome.png` | pantalla de bienvenida | TODO / bloqueado |
| `show.qml` | presentacion durante la instalacion | TODO / bloqueado |

Cada archivo debe viajar con su licencia, autoria y checksum en el manifiesto
de assets. Hasta entonces, `branding.desc` no declara `images:` ni `slideshow:`
para que Calamares no intente cargar archivos inexistentes.
