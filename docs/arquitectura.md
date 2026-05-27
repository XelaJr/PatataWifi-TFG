# Arquitectura del laboratorio

## Visión general

El objetivo del laboratorio es reproducir, sobre una única Raspberry Pi 5, el
escenario completo del ataque *Evil Twin* contra una red WPA2-Enterprise tipo
`eduroam`: un punto de acceso atacante con el SSID legítimo, autenticando
peticiones EAP contra un servidor RADIUS bajo control del atacante que captura
el `Challenge` y la `Response` MSCHAPv2.

Adicionalmente, la Pi expone una **segunda red WPA2-PSK** (`PatataWiFi_mgmt`)
en otra radio independiente; sirve como vía de control out-of-band sobre la
propia Pi mientras el AP atacante está al aire (la víctima usa el primario,
el operador del laboratorio usa el de gestión).

## Diagrama de flujo

```
                                ┌──────────────────────────────────────────┐
                                │  Raspberry Pi 5                          │
                                │                                          │
  [Dispositivo víctima]         │  ┌────────────────────────────────────┐  │
        │                       │  │ wlan0 — Broadcom BCM4345C0 (int.)  │  │
        │                       │  │ AP: PatataWiFi_mgmt                │  │
        │                       │  │ WPA2-PSK · canal 1 · 172.31.0.1/24 │  │
        │                       │  └────────────────────────────────────┘  │
        │  probe Request        │                                          │
        │  ───────────────────► │  ┌────────────────────────────────────┐  │
        │  ◄─── beacon          │  │ wlan1 — Alfa AWUS036ACM MT7612U    │  │
        │       eduroam-tfg     │  │ AP: eduroam-tfg                    │  │
        │                       │  │ WPA2-EAP · canal 6 · 10.0.0.1/24   │  │
        │  EAP/PEAP Identity    │  └────────────────────────────────────┘  │
        │  ───────────────────► │                  ↓ EAPOL                 │
        │                       │  ┌────────────────────────────────────┐  │
        │  TLS Server-Hello     │  │ hostapd-2.6 (forkeado por jesux)   │  │
        │  ◄───────────────     │  │ Driver: nl80211                    │  │
        │  (cert "Example Inc.")│  └─────────────────┬──────────────────┘  │
        │                       │                    ↓ RADIUS              │
        │  Cliente acepta cert  │  ┌────────────────────────────────────┐  │
        │  o lo rechaza         │  │ FreeRADIUS-WPE 3.2.5  (Kali pkg)   │  │
        │  ───────────────────► │  │ Inner: GTC → fallback MSCHAPv2     │  │
        │                       │  └─────────────────┬──────────────────┘  │
        │                       │                    ↓                     │
        │                       │  /var/log/freeradius-wpe/                │
        │                       │  freeradius-server-wpe.log               │
        │                       │  ───────────────────────────────         │
        │                       │  pap: alice@uloyola.es / <pwd>   ← GTC   │
        │                       │  mschap: bob@uloyola.es / <hash> ← NAK   │
        │                       └──────────────────────────────────────────┘
```

Hay tres escenarios posibles según cómo gestione el cliente el cert TLS y
el inner EAP propuesto por el RADIUS:

1. **Cliente acepta cert + acepta GTC** (iOS sin perfil CAT estricto):
   credenciales en claro capturadas + conexión completa al rogue AP
   (`pap: <user> / <password>` en el log WPE).
2. **Cliente acepta cert + rechaza GTC con NAK** (Android moderno):
   fallback automático a MSCHAPv2 → hash NETNTLM capturado, crackeable
   offline (`mschap: <user> / <hash>`). El cliente recibe `Access-Reject`
   y NO se conecta — pero la credencial queda en disco.
3. **Cliente rechaza el cert TLS exterior** (eduroam CAT con CA pinning):
   ningún paquete EAP interno llega al servidor → **sin captura**. Es
   la única configuración que mitiga el ataque.

## Decisiones de diseño

### 1. Por qué dos radios físicas en lugar de multi-BSSID

El driver `mt76x2u` para el chipset MT7612U (el de los Alfa AWUS036ACM)
**no soporta combinar simultáneamente WPA-Enterprise y multi-BSSID** sobre
una sola radio. Si se intenta levantar `hostapd` con dos BSSIDs virtuales
donde uno usa `wpa_key_mgmt=WPA-PSK` y el otro `wpa_key_mgmt=WPA-EAP`,
el segundo `bss=` falla con error `nl80211: Could not configure driver mode`
o el AP arranca pero los clientes no completan la asociación EAPOL.

Tracker upstream: [OpenWrt mt76 #433](https://github.com/openwrt/mt76/issues/433)
y discusiones relacionadas en la lista hostap-devel.

**Solución:** la red de gestión (WPA2-PSK) se asigna a la radio interna de la
Pi (BCM4345C0, driver `brcmfmac`), que sí soporta AP-mode estable, y el AP
atacante (WPA2-Enterprise) se queda solo en la radio MT7612U.

### 2. Por qué FreeRADIUS-WPE 3.x de Kali en lugar de FreeRADIUS 2.x del upstream

El instalador upstream `jesux/PatataWiFiEnterprise` compila **FreeRADIUS 2.1.12**
desde fuentes archivadas, aplicando el parche WPE clásico de `jesux/freeradius-wpe`.
Eso requiere `libssl1.0-dev`, que en `bookworm`/aarch64 ya no está disponible y
hay que traer manualmente como `.deb` de `archive.debian.org` (lo hace
`raspi-install-aarch64.sh` de upstream). Funciona, pero genera fricción y deja
una versión obsoleta de OpenSSL en el sistema.

**Solución del laboratorio:** usar el paquete **`freeradius-wpe`** de
`kali-rolling` (versión `3.2.5+dfsg-3kali1`), que es la versión actualizada del
WPE original mantenida por Kali. Se instala con `apt`, sin paquetes obsoletos.

El precio: hay que **comentar las líneas `user =` y `group = freerad-wpe`** de
`radiusd.conf` para que `radiusd` herede los privilegios root del proceso que
lo invoca (`hostapd-freeradius.sh` desde `tfg-attack.service`). El paquete
asume que se lanza vía `systemd` con su propio usuario `freerad-wpe`; en este
laboratorio se lanza embebido en el flujo de PatataWiFi, que necesita root para
manipular la interfaz wlan1.

### 3. Cadena de servicios systemd

Los tres servicios se ejecutan en orden estricto vía dependencias
`Requires=` + `After=`:

```
tfg-cleanup.service        (After=network.target, DefaultDependencies=no)
       │ Requires
       ▼
tfg-mgmt.service           (levanta wlan0)
       │ Requires
       ▼
tfg-attack.service         (levanta wlan1 + FreeRADIUS-WPE)
```

Todos son `Type=oneshot` con `RemainAfterExit=yes`. Los daemons reales
(`hostapd`, `dnsmasq`, `radiusd`) los lanzan los scripts en background o
dentro de `tmux`, y los servicios se consideran "completos" en cuanto los
scripts retornan.

- **`tfg-cleanup`** mata cualquier instancia previa, baja interfaces,
  recarga el módulo `mt76x2u` para garantizar un estado de driver limpio,
  y detiene `NetworkManager` y `wpa_supplicant` (interfieren con `hostapd`
  si están activos).
- **`tfg-mgmt`** configura `wlan0` con `172.31.0.1/24` y lanza `hostapd` +
  `dnsmasq` para servir la red `PatataWiFi_mgmt`.
- **`tfg-attack`** espera a que `wlan1` esté presente (timeout 15 s) y
  lanza `/root/patatawifi/hostapd-freeradius.sh`, que orquesta hostapd,
  radiusd y dnsmasq dentro de una sesión `tmux` (5 paneles).

Las definiciones literales están en [`systemd/`](../systemd/) y los scripts
en [`scripts/`](../scripts/).

### 4. Por qué hostapd-2.6 en lugar de hostapd-2.10

El upstream `PatataWiFiEnterprise` construye `hostapd-2.10`. Sin embargo,
en pruebas reales contra el driver `mt76x2u` en kernels 6.x, **2.10 mostraba
desconexiones espurias** durante la asociación EAPOL cuando el cliente
abandonaba el handshake (caso común con cert pinning iOS). La versión 2.6,
más antigua pero estable con `mt76x2u`, mantiene el AP al aire de forma
confiable para que sucesivos clientes puedan re-intentar.

`install.sh` descarga `hostapd-2.6.tar.gz` directamente del repo oficial
de [`w1.fi`](https://w1.fi/releases/), verifica su sha256
(`01526b90c1d23bec4b0f052039cc4456c2fd19347b4d830d1d58a0a6aea7117d`),
aplica el patch `hostapd-2.6-config.patch` (que sólo descomenta
`CONFIG_LIBNL32=y` y `CONFIG_IEEE80211N=y`), y compila con `make -j$(nproc)`.

### 5. Downgrade attack a EAP-GTC en el inner PEAP

Por defecto el bloque `peap { }` de FreeRADIUS-WPE viene configurado con
`default_eap_type = mschapv2`. Eso captura **hashes** NETNTLM
(crackeables offline pero no inmediatos). El patch
[`freeradius-wpe/eap-gtc-downgrade.patch`](../freeradius-wpe/eap-gtc-downgrade.patch)
lo cambia a `default_eap_type = gtc`.

Con GTC como tipo inicial:

- El servidor propone EAP-GTC al cliente dentro del túnel TLS.
- Si el cliente lo acepta (caso común en iOS sin perfil CAT estricto)
  envía la password **literal**. WPE la conoce → genera
  `Access-Accept` con MSK válida → el cliente completa el 4-way
  handshake WPA2 y queda asociado al rogue AP, abriendo la puerta a
  MITM total.
- Si el cliente lo rechaza con `EAP-NAK` (Android moderno, Windows
  con perfil eduroam), FreeRADIUS **automáticamente** cambia al inner
  EAP propuesto por el cliente — típicamente MSCHAPv2 — porque los
  módulos `gtc { }` y `mschapv2 { }` están ambos enabled. Resultado:
  hash NETNTLM capturado, idéntico al escenario previo al downgrade.

El fallback es transparente y no requiere reintento por parte del
cliente: ocurre dentro de la misma sesión EAP. Para el operador del
laboratorio significa **mejorar el caso peor (hash crackeable) con
un caso mejor (password en claro) sin perder el comportamiento
anterior**.

Limitación importante: el downgrade afecta sólo al inner EAP,
**no al outer PEAP/TLS**. Si el cliente rechaza el certificado del
RADIUS antes de abrir el túnel (CA pinning estricto del perfil
eduroam CAT), no hay nada que capturar — ni hash ni password. El
ataque queda neutralizado por completo. Esta es, por diseño, la
mitigación recomendada en la documentación oficial de eduroam.

### 6. PatataWiFi como wrapper de tmux

PatataWiFi orquesta `hostapd` + `dnsmasq` + `radiusd` + `tail -f` de los logs
en una sesión `tmux` con 5 paneles. Permite operación interactiva durante el
desarrollo (se hace `tmux attach -t PatataWifi_Hostapd` y se ve todo en
tiempo real) y simultáneamente sirve como mecanismo de "lanzamiento en
background" — `tmux -d` desacopla la sesión del proceso padre, así que
`tfg-attack.service` puede retornar mientras los daemons siguen vivos.

## Tablas de rutas y archivos

| Componente | Origen | Destino tras `install.sh` |
|---|---|---|
| Scripts tfg-*.sh | `scripts/` | `/usr/local/bin/tfg-*.sh` |
| Units systemd | `systemd/` | `/etc/systemd/system/tfg-*.service` |
| Config wlan0 | `hostapd-mgmt/mgmt.conf` | `/root/patatawifi/hostapd-mgmt/mgmt.conf` |
| Scripts PatataWiFi | Upstream `jesux/PatataWiFiEnterprise/files/` | `/root/patatawifi/*.sh` (3 archivos parcheados) |
| Binario hostapd | Construido desde `w1.fi/releases/hostapd-2.6.tar.gz` | `/root/patatawifi/hostapd/hostapd` |
| Config FreeRADIUS-WPE | Paquete `freeradius-wpe` (Kali) | `/etc/freeradius-wpe/3.0/` (con 3 parches: radiusd.conf, eap, eap-gtc-downgrade) |
| Certificados RADIUS | Generados por `make bootstrap` | `/etc/freeradius-wpe/3.0/certs/` |
| Symlink lazo | — | `/root/patatawifi/radiuscfg/default → /etc/freeradius-wpe/3.0` |
