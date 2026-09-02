# Troubleshooting

Errores observados durante el desarrollo del laboratorio y cómo resolverlos.

## 1. `Exec format error` al arrancar un servicio `tfg-*`

```
systemd[1]: tfg-cleanup.service: Failed to execute /usr/local/bin/tfg-cleanup.sh: Exec format error
```

**Causa probable:** el script tiene un BOM UTF-8 al inicio o usa terminadores
CRLF en vez de LF. Suele pasar si se editó el archivo desde Windows o desde un
editor con configuración no-Unix.

**Solución:**

```bash
# Diagnóstico
file /usr/local/bin/tfg-cleanup.sh    # debería decir "shell script, ASCII"
od -c /usr/local/bin/tfg-cleanup.sh | head -1   # NO debe empezar con \357\273\277

# Reparar
sudo dos2unix /usr/local/bin/tfg-cleanup.sh
# o, sin dos2unix:
sudo sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' /usr/local/bin/tfg-cleanup.sh
```

En el peor caso, **recree el script con `nano` directamente** (no copie con
`cat <<EOF` desde una sesión SSH cuyo cliente terminal pueda haber metido
caracteres invisibles).

## 2. `Address already in use` en `dnsmasq`

```
dnsmasq: failed to create listening socket for 172.31.0.1: Address already in use
```

**Causa típica:** colisión de IP entre `wlan0` y `wlan1`. En el laboratorio
nuevo, `wlan0` (mgmt) usa **`172.31.0.1/24`** y `wlan1` (Evil Twin) usa
**`10.0.0.1/24`**. Si ambas radios acaban con la misma IP (por una versión
previa del script donde ambas usaban 172.31.0.1), `dnsmasq` colisiona.

**Solución:**

```bash
# Confirmar IPs únicas
ip addr show wlan0   # debe mostrar 172.31.0.1
ip addr show wlan1   # debe mostrar 10.0.0.1

# Si están iguales, el parche está mal aplicado. Re-ejecute:
cd ~/PatataWifi-TFG
sudo ./install.sh    # idempotente, re-aplica los parches
```

El parche `patatawifi-patches/hostapd-freeradius.sh.patch` cambia
`mgmt_ip=172.31.0.1` → `mgmt_ip=10.0.0.1` dentro del wrapper de PatataWiFi
para resolver esta colisión.

## 3. `Already running` en PatataWiFi

```
[PatataWiFi: Hostapd + FreeRadius]
Already running
tmux attach -t PatataWifi_Hostapd
```

**Causa:** sesión `tmux` huérfana de un arranque previo que no terminó
limpio. PatataWiFi detecta sesiones existentes y se niega a arrancar
para no duplicar procesos.

**Solución:**

```bash
sudo tmux list-sessions
sudo tmux kill-server     # mata TODAS las sesiones tmux (sin selección)

# Si prefiere ser quirúrgico:
sudo tmux kill-session -t PatataWifi_Hostapd

# Después relanzar
sudo systemctl restart tfg-attack
```

`tfg-cleanup.sh` ya hace `tmux kill-server` al inicio, así que un `reboot`
también resuelve esto.

## 4. El cliente da "No se puede conectar" sin mostrar diálogo de certificado

**Síntoma:** el cliente ve el SSID `eduroam-tfg`, intenta conectarse y
rápidamente da un error genérico de tipo "No se puede conectar a la red" o
similar, **sin mostrar diálogo del tipo "Continuar de todos modos /
Cancelar" ante un certificado desconocido**.

**Causa: NO es un bug.** Es el comportamiento esperado cuando el supplicant
del cliente está configurado con CA pinning estricto contra una CA distinta
de la del FreeRADIUS-WPE del laboratorio. Sucede típicamente cuando:

- El cliente tiene un perfil eduroam preinstalado (vía la herramienta
  oficial *eduroam CAT* o equivalente) que fija el certificado CA legítimo
  de la institución.
- O cuando la política de seguridad por defecto del sistema operativo
  rechaza certificados no firmados por ninguna CA del almacén del sistema
  sin pedir intervención al usuario.

**Impacto en la captura:** en este escenario el cliente cierra la sesión
en el outer PEAP/TLS (**antes de abrir el túnel**) y por tanto **no se
genera ninguna entrada** en `freeradius-server-wpe.log`. El log de
`hostapd` (vía `journalctl -u tfg-attack`) sí muestra ciclos repetidos de
`authentication failed - EAP type: 25 (PEAP)` con la MAC del cliente.

Esta es la mitigación funcionando como se diseñó. Para forzar la captura
sería necesario relajar la validación de CA en el supplicant del cliente
(opción típica "No validar" o "Cualquier CA" del menú avanzado de redes),
lo cual no es realista en un escenario de ataque real.

## 5. Servicios `tfg-*` no arrancan tras reboot

```bash
sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack
# inactive / inactive / inactive
```

**Diagnóstico:**

```bash
sudo systemctl status tfg-cleanup.service --no-pager
sudo journalctl -u tfg-cleanup -u tfg-mgmt -u tfg-attack --no-pager -b
```

**Causas frecuentes:**

| Síntoma | Causa | Fix |
|---|---|---|
| `Failed to start tfg-cleanup` con `not found` | enable no se aplicó | `sudo systemctl enable tfg-{cleanup,mgmt,attack}` y reboot |
| `tfg-attack` falla con "wlan1 no detectado" | Alfa conectada después del boot, o timeout corto | conecte la Alfa antes de encender; o aumente el bucle `for i in {1..15}` en `tfg-attack.sh` |
| `tfg-mgmt` falla con `interface wlan0 not found` | el driver `brcmfmac` no cargó | revise `dmesg \| grep brcm` y reinstale `firmware-brcm80211` |
| Servicios `active` pero ningún AP visible | `hostapd` falló dentro del script | `sudo tail /var/log/tfg-mgmt.log /var/log/tfg-attack.log` y `journalctl -u tfg-attack` |

## 6. `wlan1` no detectado al boot

Si el adaptador Alfa se conecta por USB y la Pi se reinicia con él
conectado, el módulo `mt76x2u` puede tardar más que el timeout de 15
segundos en exponer la interfaz.

```bash
# Confirmar en dmesg
dmesg | grep -E 'mt76|wlan1' | tail -10
# Debería mostrar "usbcore: registered new interface driver mt76x2u" y
# "mt76x2u: ASIC revision: 76120044"
```

**Workarounds:**

- Aumentar el timeout en `/usr/local/bin/tfg-attack.sh`:
  ```bash
  for i in {1..30}; do        # 30 s en vez de 15
  ```
- O añadir un `sleep 5` al inicio de `tfg-attack.sh`.
- En último caso, retire el Alfa, reinicie, y conéctelo después: el
  `udev` lo detectará y `tfg-attack` arrancará por sí solo en el siguiente
  ciclo del bucle.

## 7. Certificados de FreeRADIUS-WPE expirados

Los certificados que genera `make bootstrap` caducan al cabo de unos meses
(el `notAfter` por defecto está aprox. 1 año tras la generación). Si el
laboratorio lleva tiempo sin tocar:

```bash
sudo openssl x509 -in /etc/freeradius-wpe/3.0/certs/server.pem -noout -enddate
# notAfter=Jul 20 12:30:21 2026 GMT

# Regenerar
sudo rm -v /etc/freeradius-wpe/3.0/certs/{server,ca,client}.{pem,key,crt,csr,p12}
sudo rm -v /etc/freeradius-wpe/3.0/certs/{index.txt*,serial*,passwords.mk}
sudo make -C /etc/freeradius-wpe/3.0/certs bootstrap
sudo systemctl restart tfg-attack
```

Si quiere certs con CN/Subject personalizado (no "Example Inc."), edite
`/etc/freeradius-wpe/3.0/certs/{ca,server}.cnf` antes del bootstrap.

## 8. PatataWiFi monta `radiuscfg/default` pero `radiusd` arranca con error

`radiusd -fl …/radius-debug.log -d /root/patatawifi/radiuscfg/default` se
queda mudo (el panel tmux 2 cierra) o el log muestra
`Failed reading radiusd.conf`.

**Causa:** el symlink `radiuscfg/default → /etc/freeradius-wpe/3.0` se
rompió (porque `/etc/freeradius-wpe/3.0` no existe o no tiene los certs).

```bash
ls -la /root/patatawifi/radiuscfg/default
# debe ser un symlink a /etc/freeradius-wpe/3.0

# Re-crear si falta:
sudo ln -sfn /etc/freeradius-wpe/3.0 /root/patatawifi/radiuscfg/default
```

Si el symlink existe pero el directorio destino no, reinstale el paquete
con `sudo apt-get install --reinstall freeradius-wpe`.
