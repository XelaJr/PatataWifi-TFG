# Parches sobre FreeRADIUS-WPE (paquete `freeradius-wpe` de Kali)

Estos dos patches modifican la configuración del paquete
**`freeradius-wpe 3.2.5+dfsg-3kali1`** instalado desde Kali rolling.
`install.sh` los aplica automáticamente.

## `radiusd.conf.patch` (13 líneas, 1 hunk)

```diff
@@ -544,8 +544,8 @@
     #  member.  This can allow for some finer-grained access
     #  controls.
     #
-    user = freerad-wpe
-    group = freerad-wpe
+    #user = freerad-wpe
+    #group = freerad-wpe
```

**Por qué:** el paquete está pensado para arrancar `radiusd` como servicio
systemd con usuario propio `freerad-wpe`. En este laboratorio,
**`radiusd` lo lanza `hostapd-freeradius.sh` desde dentro de
`tfg-attack.service`** (que corre como root), porque PatataWiFi necesita
root para tocar la interfaz wlan1 y para que `radiusd` pueda leer los certs
del directorio `/etc/freeradius-wpe/3.0/certs/`. Comentar `user`/`group`
hace que `radiusd` herede el UID/GID del proceso que lo invoca (root) en
vez de hacer `setuid()` a `freerad-wpe`.

Sin este cambio, el log de `radiusd` muestra:

```
Failed binding to authentication address * port 1812 bound to server default: Permission denied
```

## `eap.patch` (29 líneas, 3 hunks)

Modifica `mods-enabled/eap` para que los certs apunten al directorio que
`make bootstrap` genera, no a los certs snake-oil de Debian:

```diff
-    private_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
+    private_key_file = ${certdir}/server.key

-    certificate_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
+    certificate_file = ${certdir}/server.pem

-    ca_file = /etc/ssl/certs/ca-certificates.crt
+    ca_file = ${certdir}/ca.pem
```

**Por qué:** el paquete instala `mods-enabled/eap` como **symlink** a
`mods-available/eap`. La configuración por defecto en `mods-available/eap`
apunta a los certs auto-generados por el paquete `ssl-cert` (snakeoil),
no a los del propio FreeRADIUS-WPE. Para PEAP/MSCHAPv2 hace falta que el
servidor responda con un certificado y una CA generados por
`make bootstrap` dentro del propio `/etc/freeradius-wpe/3.0/certs/`.

`install.sh` también:
1. Reemplaza el symlink `mods-enabled/eap` por una **copia regular**
   de `mods-available/eap` (porque `patch` no funciona bien sobre symlinks).
2. Aplica este patch sobre la copia.

## Aplicación manual

```bash
# radiusd.conf
sudo patch -p1 -d /etc/freeradius-wpe/3.0 < radiusd.conf.patch

# eap (cuidado con el symlink)
sudo rm /etc/freeradius-wpe/3.0/mods-enabled/eap
sudo cp /etc/freeradius-wpe/3.0/mods-available/eap /etc/freeradius-wpe/3.0/mods-enabled/eap
sudo patch -p1 -d /etc/freeradius-wpe/3.0 < eap.patch
```

## Bootstrap de certificados

Tras los patches, hay que generar los certs:

```bash
sudo make -C /etc/freeradius-wpe/3.0/certs bootstrap
```

Esto genera `ca.pem`, `ca.key`, `server.pem`, `server.key`, `client.*` y
demás material — `notAfter` ~1 año desde la generación. Ver
[`install-notes.md`](install-notes.md) y
[`docs/troubleshooting.md`](../docs/troubleshooting.md) (sección "Certificados expirados")
para regeneración y personalización del CN.

## Por qué FreeRADIUS-WPE de Kali en vez del original

Ver [`docs/arquitectura.md`](../docs/arquitectura.md), sección 2.

## Generación de los patches

```bash
# Descargar el .deb original a /tmp y extraer
mkdir -p /tmp/fr-wpe-orig/extracted
cd /tmp/fr-wpe-orig
apt-get download freeradius-wpe -t kali-rolling
dpkg-deb -x freeradius-wpe_*_arm64.deb extracted/

# Regenerar el patch
diff -u --label a/radiusd.conf --label b/radiusd.conf \
     /tmp/fr-wpe-orig/extracted/etc/freeradius-wpe/3.0/radiusd.conf \
     /etc/freeradius-wpe/3.0/radiusd.conf \
  > freeradius-wpe/radiusd.conf.patch
```
