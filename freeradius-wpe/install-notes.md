# FreeRADIUS-WPE: instalación manual y configuración

Procedimiento detallado para instalar `freeradius-wpe` sin `install.sh`,
útil para auditoría o despliegues en sistemas distintos a Raspberry Pi OS.

## Origen del paquete

El paquete `freeradius-wpe 3.2.5+dfsg-3kali1` está empaquetado y firmado por
Kali (`http.kali.org/kali kali-rolling main`). No existe equivalente en los
repositorios oficiales de Debian. La versión instalada por este laboratorio
es una rama mantenida del *FreeRADIUS Wireless Pwn Edition* original de
Joshua Wright, modernizada a FreeRADIUS 3.2.x.

## Añadir el repo Kali con pin de prioridad 50

```bash
# 1. Clave GPG
curl -fsSL https://archive.kali.org/archive-key.asc \
  | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kali.gpg
# Huella esperada (verificar tras descargar):
sudo gpg --no-default-keyring --keyring /etc/apt/trusted.gpg.d/kali.gpg --fingerprint
# Debe coincidir con la huella publicada en https://www.kali.org/blog/

# 2. Source list
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/kali.gpg] http://http.kali.org/kali kali-rolling main' \
  | sudo tee /etc/apt/sources.list.d/kali.list

# 3. Pin de prioridad 50 (NADA de Kali se instala sin -t kali-rolling)
sudo tee /etc/apt/preferences.d/kali <<'EOF'
Package: *
Pin: release o=Kali
Pin-Priority: 50
EOF

# 4. Refrescar índices
sudo apt-get update
```

**Por qué pin 50:** evita que un `apt upgrade` posterior pise paquetes Debian
con versiones (a menudo más recientes) de Kali, lo que podría romper la
distribución base. Sólo el paquete que pidamos explícitamente con
`-t kali-rolling` se instalará desde ese origen.

## Instalar el paquete

```bash
sudo apt-get install -y -t kali-rolling freeradius-wpe
```

Esto trae como dependencias `freeradius-common`, `freeradius-config`,
`freeradius-utils`, `libfreeradius3` desde **Debian** (no Kali — el pin lo
asegura), y `freeradius-wpe` desde Kali.

Verificación:

```bash
dpkg-query -W -f='${Package} ${Version} ${Status}\n' freeradius-wpe
# freeradius-wpe 3.2.5+dfsg-3kali1 install ok installed

/usr/sbin/radiusd -v
# radiusd: FreeRADIUS Version 3.2.5, ...
```

El binario `radiusd` es en realidad un symlink:

```bash
readlink /usr/sbin/radiusd
# /usr/sbin/freeradius-wpe
```

## Aplicar los parches

Ver [`README.md`](README.md) en este directorio para el detalle. Resumen:

```bash
# radiusd.conf — comentar user/group
sudo patch -p1 -d /etc/freeradius-wpe/3.0 < radiusd.conf.patch

# mods-enabled/eap — reemplazar symlink + parchear paths de certs
sudo rm /etc/freeradius-wpe/3.0/mods-enabled/eap
sudo cp /etc/freeradius-wpe/3.0/mods-available/eap /etc/freeradius-wpe/3.0/mods-enabled/eap
sudo patch -p1 -d /etc/freeradius-wpe/3.0 < eap.patch
```

## Bootstrap de certificados

```bash
sudo make -C /etc/freeradius-wpe/3.0/certs bootstrap
```

Esto ejecuta `openssl` con los `.cnf` del directorio (`ca.cnf`, `server.cnf`,
`client.cnf`, `inner-server.cnf`) y produce:

```
ca.pem    ca.key    ca.der    ca.crl
server.pem  server.key  server.crt  server.csr  server.p12
client.pem  client.key  client.crt  client.csr  client.p12
user@example.org.pem  user@example.org.p12
index.txt  serial  passwords.mk
```

### Personalización del CN

Antes del bootstrap, edite:

- **`ca.cnf`** — campos `[CA_default]` y `[req_distinguished_name]`. Cambie
  `CN`, `O`, `emailAddress` para que el certificado CA tenga su nombre.
- **`server.cnf`** — análogo para el cert del servidor RADIUS. El campo
  `CN` es el que el cliente ve.

Por defecto:

```
CN = Example Server Certificate
O = Example Inc.
emailAddress = admin@example.org
```

Por ejemplo, para "Servidor eduroam Uloyola" (laboratorio TFG):

```ini
# server.cnf, dentro de [server]
CN = eduroam-tfg.example.lab
O  = TFG Laboratorio
emailAddress = tfg@example.lab
```

Tras editar, `sudo make -C /etc/freeradius-wpe/3.0/certs bootstrap` y
reiniciar `tfg-attack`.

## Vincular FreeRADIUS-WPE con PatataWiFi

PatataWiFi espera encontrar la config de RADIUS en
`/root/patatawifi/radiuscfg/default/`. Lo enlazamos al sistema:

```bash
sudo mkdir -p /root/patatawifi/radiuscfg
sudo ln -sfn /etc/freeradius-wpe/3.0 /root/patatawifi/radiuscfg/default
```

Esto evita duplicar la configuración. Cualquier cambio en
`/etc/freeradius-wpe/3.0/` afecta inmediatamente al `radiusd` que lanza
PatataWiFi.

## Logs

```bash
# Log principal (donde aparecen los hashes capturados al final)
sudo tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log

# Logs duplicados en el flujo PatataWiFi (modo tmux)
sudo tail -F /root/patatawifi/logs/PatataWifi_Hostapd/wpe.log
sudo tail -F /root/patatawifi/logs/PatataWifi_Hostapd/auth-detail
```

## Diagnóstico rápido

```bash
# El servicio del paquete NO se usa en este lab (PatataWiFi lanza su propio radiusd):
sudo systemctl is-active freeradius
# inactive  — correcto

# El que importa es el process spawn dentro de tfg-attack:
ps -ef | grep radiusd
# root ... radiusd -fl /root/patatawifi/logs/PatataWifi_Hostapd/radius-debug.log -d /root/patatawifi/radiuscfg/default

# Probar la config sin lanzar el servidor:
sudo /usr/sbin/radiusd -XC -d /root/patatawifi/radiuscfg/default
# Debe terminar con "Configuration appears to be OK"
```
