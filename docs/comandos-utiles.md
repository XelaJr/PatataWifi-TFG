# Comandos útiles

Recetario operativo para usar durante el laboratorio.

## Estado del laboratorio

```bash
# Servicios systemd: los 3 deben estar 'active'
sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack

# Estado detallado + última línea de log
sudo systemctl status tfg-cleanup tfg-mgmt tfg-attack --no-pager -n 5

# SSIDs activos
sudo iw dev wlan0 info | grep -E 'ssid|channel|type'   # PatataWiFi_mgmt / 1 / AP
sudo iw dev wlan1 info | grep -E 'ssid|channel|type'   # eduroam-tfg / 6 / AP

# Procesos clave
ps -ef | grep -E 'hostapd|radiusd|dnsmasq' | grep -v grep
```

## Capturar credenciales en tiempo real

El laboratorio captura **dos tipos** de credenciales según el cliente
(ver [`arquitectura.md`](arquitectura.md) §5 sobre el downgrade GTC):

```bash
# Log principal de FreeRADIUS-WPE: contiene tanto entradas pap: (GTC plain)
# como mschap: (hashes NETNTLM)
sudo tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log
```

### Filtros separados (terminal split)

```bash
# Terminal 1 — passwords en claro (clientes que aceptan EAP-GTC)
sudo tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log \
  | grep --line-buffered -A2 '^pap:'

# Terminal 2 — hashes NETNTLM (clientes que rechazan GTC y caen a MSCHAPv2)
sudo tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log \
  | grep --line-buffered -A4 '^mschap:'
```

### Formato esperado

Entrada GTC (password en claro):

```
pap: Wed May 27 19:14:17 2026
    username: alice@uloyola.es
    password: Passw0rd2026
```

Entrada MSCHAPv2 (hash crackeable offline):

```
mschap: Wed May 27 19:46:05 2026
    username: bob@uloyola.es
    challenge: a9:84:ee:c0:5e:92:cb:9c
    response: dd:e0:60:31:d7:fb:10:e7:ab:db:3b:ff:b8:ba:ec:bd:5b:e2:cf:eb:18:af:f2:f2
    john NETNTLM: bob@uloyola.es:$NETNTLM$a984eec05e92cb9c$dde06031d7fb...
```

La línea `john NETNTLM:` está lista para `john --format=netntlm`. Para
`hashcat -m 5500` reformatear según [`analisis-offline.md`](analisis-offline.md).

### Log del wrapper PatataWiFi

```bash
# (cuando se accede por SSH a la Pi durante el ataque)
sudo tail -F /root/patatawifi/logs/PatataWifi_Hostapd/wpe.log
sudo tail -F /root/patatawifi/logs/PatataWifi_Hostapd/auth-detail
```

## Limpiar y reiniciar manualmente

```bash
# Resetear todo desde cero (equivale a tfg-cleanup):
sudo /usr/local/bin/tfg-cleanup.sh
# Levantar manualmente la cadena (equivale a tfg-mgmt + tfg-attack):
sudo /usr/local/bin/tfg-mgmt.sh
sudo /usr/local/bin/tfg-attack.sh

# Alternativa interactiva (scripts originales del autor con sudo embebido):
sudo /root/patatawifi/reset.sh
sudo /root/patatawifi/start-todo.sh

# Reiniciar la cadena vía systemd:
sudo systemctl restart tfg-cleanup tfg-mgmt tfg-attack
```

## Conectarse a la red de gestión

Desde un portátil o móvil:

```
SSID:        PatataWiFi_mgmt
Seguridad:   WPA2-PSK
Contraseña:  patatas333
Banda:       2.4 GHz, canal 1
```

Una vez asociado, recibirá una IP en `172.31.0.0/24` por DHCP. Para acceder
a la Pi:

```bash
ssh xelajr@172.31.0.1
```

## Ver logs del sistema

```bash
# journalctl por servicio
sudo journalctl -u tfg-cleanup -u tfg-mgmt -u tfg-attack -b --no-pager

# Solo errores del boot actual
sudo journalctl -p err -b --no-pager

# Logs del lab (cleanup/mgmt/attack)
sudo tail -F /var/log/tfg-cleanup.log /var/log/tfg-mgmt.log /var/log/tfg-attack.log

# Logs de FreeRADIUS-WPE
sudo tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log
```

## Conexión al tmux interno de PatataWiFi (5 paneles)

Cuando `tfg-attack.service` está activo, internamente arranca `hostapd-freeradius.sh`
que crea una sesión tmux con 5 paneles (`hostapd`, `dnsmasq`, `radiusd`, `wpe.log`
tail, `auth-detail` tail). Para verla:

```bash
sudo tmux attach -t PatataWifi_Hostapd
# Para salir sin matar la sesión: prefix (Ctrl-b) + d
```

## Cambiar SSID temporalmente (sin re-ejecutar install.sh)

```bash
sudo systemctl stop tfg-attack
sudo nano /root/patatawifi/hostapd-freeradius.sh   # editar mgmt_ssid='...'
sudo systemctl start tfg-attack
```

Para que el cambio sobreviva a una re-ejecución de `install.sh` (que vuelve
a aplicar los parches sobre upstream virgen), modifique también
`patatawifi-patches/hostapd-freeradius.sh.patch` o, mejor, copie el patch a
un nuevo `patatawifi-patches/local-overrides.patch` que se aplique
adicionalmente.

## Espacio en disco

```bash
# El log de FreeRADIUS-WPE crece sin rotación: revisar tamaño periódicamente
du -sh /var/log/freeradius-wpe/ /var/log/tfg-*.log /root/patatawifi/logs/

# Rotar manualmente
sudo truncate -s 0 /var/log/freeradius-wpe/freeradius-server-wpe.log
sudo truncate -s 0 /var/log/tfg-*.log
```
