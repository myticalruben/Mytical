# Wallpapers de Mytical

La distro no distribuye wallpapers personales. La colección que usa el autor
vive en el repo privado
[`myticalruben/mytical-wallpapers`](https://github.com/myticalruben/mytical-wallpapers).

## Instalar la colección

```sh
git clone git@github.com:myticalruben/mytical-wallpapers.git
cd mytical-wallpapers
./install.sh
```

Destino por defecto: `~/Pictures/Wallpapers`.

## Gestión

```sh
wallpapers list
wallpapers add ~/Descargas/nuevo.jpg
wallpapers remove viejo.jpg
wallpapers set 03.jpg
```

## Por qué separado

- Evita distribuir arte personal sin licencia.
- Mantiene intacta la configuración de Mytical: `wallpaper`, paleta, SDDM sync,
  Waybar, GTK, btop y Kitty siguen usando el mismo directorio y estado.
- El repo público conserva solo los 4 fondos CC0 de `distro/branding/wallpapers`.
