# Clave de release de Mytical

- Fingerprint: `E2B91E877C120ABC0442685C17DE2F11062CBDEA`
- UID: `Mytical Release <release@mytical.local>`
- Algoritmo: RSA 4096, uso de firma, expira 2028-11-22.
- Clave pública: `mytical-release.asc` y `mytical-release.gpg`.
- Clave privada: **fuera del repositorio**, en el almacén seguro del release.
- Revocación: guardar el certificado de revocación junto a la clave privada.

La clave privada de esta máquina es de desarrollo; para publicar, moverla a un
almacén offline y sustituir el fingerprint en este documento. No se versiona
ninguna clave privada.

Verificar una firma:

```sh
gpg --import mytical-release.asc
gpg --verify InRelease
```
