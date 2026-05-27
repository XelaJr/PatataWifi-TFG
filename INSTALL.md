# Guía de instalación

> Recordatorio: [`README.md`](README.md) contiene el disclaimer legal y el
> contexto del proyecto. Léalo antes de continuar.

## Requisitos previos

| Requisito | Detalle |
|---|---|
| Hardware | Raspberry Pi 5 + adaptador Alfa AWUS036ACM (MT7612U). Otros adaptadores soportados por el driver `mt76x2u` deberían funcionar pero no están validados. |
| Sistema operativo | Raspberry Pi OS 64-bit `bookworm` o superior. Kernel 6.x. |
| Conectividad | Acceso a Internet **durante la instalación** (descarga ~50 MB de paquetes + clone de upstreams). |
| Espacio en disco | ~500 MB libres en `/` tras instalar dependencias y compilar `hostapd`. |
| Permisos | Acceso `sudo` (o usuario `root`). |

Para confirmar que el sistema cumple los mínimos:

```bash
uname -m              # debe imprimir: aarch64
cat /etc/os-release   # ID=raspbian o ID=debian, VERSION_CODENAME=bookworm (o superior)
df -h /               # ≥500 MB disponibles
ip link show wlan0 wlan1   # ambas presentes (Alfa conectada por USB)
```

## Instalación automática (recomendada)

```bash
git clone https://github.com/xelajr/tfg-eduroam-eviltwin.git
cd tfg-eduroam-eviltwin
sudo ./install.sh
sudo reboot
```

`install.sh` ejecuta 11 pasos numerados (`[N/11] …`) e imprime una verificación
final con el estado de cada componente. Puede re-ejecutarse sin riesgo: detecta
los pasos ya completados (parches aplicados, certificados generados, binario
`hostapd` ya construido) y los omite.

Tras reiniciar:

```bash
sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack
# active / active / active

sudo iw dev wlan0 info | grep -E 'ssid|channel'
sudo iw dev wlan1 info | grep -E 'ssid|channel'
```

## Instalación manual paso a paso

Para usuarios que quieran entender (o auditar) cada cambio. Se corresponden
1:1 con los pasos de `install.sh`.

```bash
# [1/11] Dependencias base
sudo apt-get update
sudo apt-get install -y hostapd dnsmasq build-essential pkg-config \
  libssl-dev libnl-3-dev libnl-genl-3-dev libpcap-dev libdbus-1-dev \
  iw wireless-tools wpasupplicant macchanger iptables nftables net-tools \
  tmux git wget curl ca-certificates gnupg patch \
  firmware-mediatek firmware-brcm80211 python3-dev python3-pip

# [2/11] Repo Kali con pin 50
curl -fsSL https://archive.kali.org/archive-key.asc \
  | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kali.gpg
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/kali.gpg] http://http.kali.org/kali kali-rolling main' \
  | sudo tee /etc/apt/sources.list.d/kali.list
printf 'Package: *\nPin: release o=Kali\nPin-Priority: 50\n' \
  | sudo tee /etc/apt/preferences.d/kali
sudo apt-get update

# [3/11] FreeRADIUS-WPE de Kali
sudo apt-get install -y -t kali-rolling freeradius-wpe

# [4/11] Parches al config de FreeRADIUS-WPE
sudo patch -p1 -d /etc/freeradius-wpe/3.0 \
  < freeradius-wpe/radiusd.conf.patch
sudo rm /etc/freeradius-wpe/3.0/mods-enabled/eap
sudo cp /etc/freeradius-wpe/3.0/mods-available/eap /etc/freeradius-wpe/3.0/mods-enabled/eap
sudo patch -p1 -d /etc/freeradius-wpe/3.0 < freeradius-wpe/eap.patch
sudo patch -p1 -d /etc/freeradius-wpe/3.0 < freeradius-wpe/eap-gtc-downgrade.patch

# [5/11] Bootstrap de certificados
sudo make -C /etc/freeradius-wpe/3.0/certs bootstrap

# [6/11] Clonar PatataWiFiEnterprise
sudo mkdir -p /root/patatawifi
sudo git clone --depth=1 https://github.com/jesux/PatataWiFiEnterprise.git /tmp/PWE
sudo cp -a /tmp/PWE/files/. /root/patatawifi/
sudo chmod +x /root/patatawifi/*.sh
sudo rm -rf /tmp/PWE

# [7/11] Parches a PatataWiFi
sudo patch -p1 -d /root/patatawifi < patatawifi-patches/hostapd-freeradius.sh.patch
sudo patch -p1 -d /root/patatawifi < patatawifi-patches/patatawifi.conf.patch
sudo patch -p1 -d /root/patatawifi < patatawifi-patches/patatawifi-virtual.conf.patch

# [8/11] hostapd-2.6 (verificar sha256, compilar)
cd /tmp
wget https://w1.fi/releases/hostapd-2.6.tar.gz
echo '01526b90c1d23bec4b0f052039cc4456c2fd19347b4d830d1d58a0a6aea7117d  hostapd-2.6.tar.gz' \
  | sha256sum -c -    # debe imprimir: hostapd-2.6.tar.gz: OK
sudo tar -xzf hostapd-2.6.tar.gz -C /root/patatawifi
sudo cp /root/patatawifi/hostapd-2.6/hostapd/defconfig /root/patatawifi/hostapd-2.6/hostapd/.config
sudo patch -p1 -d /root/patatawifi/hostapd-2.6 < /ruta/al/repo/patatawifi-patches/hostapd-2.6-config.patch
sudo make -C /root/patatawifi/hostapd-2.6/hostapd -j$(nproc) hostapd
sudo cp /root/patatawifi/hostapd-2.6/hostapd/hostapd /root/patatawifi/hostapd/hostapd

# [9/11] hostapd-mgmt + symlinks
sudo mkdir -p /root/patatawifi/hostapd-mgmt
sudo cp hostapd-mgmt/mgmt.conf /root/patatawifi/hostapd-mgmt/mgmt.conf
sudo mkdir -p /root/patatawifi/radiuscfg
sudo ln -sfn /etc/freeradius-wpe/3.0 /root/patatawifi/radiuscfg/default

# [10/11] Instalar scripts y units
sudo install -m 0755 scripts/tfg-cleanup.sh /usr/local/bin/tfg-cleanup.sh
sudo install -m 0755 scripts/tfg-mgmt.sh    /usr/local/bin/tfg-mgmt.sh
sudo install -m 0755 scripts/tfg-attack.sh  /usr/local/bin/tfg-attack.sh
sudo install -m 0644 systemd/tfg-cleanup.service /etc/systemd/system/
sudo install -m 0644 systemd/tfg-mgmt.service    /etc/systemd/system/
sudo install -m 0644 systemd/tfg-attack.service  /etc/systemd/system/
sudo systemctl daemon-reload

# [11/11] Habilitar
sudo systemctl enable tfg-cleanup.service tfg-mgmt.service tfg-attack.service
sudo reboot
```

## Post-instalación

Tras reiniciar, las dos redes deberían estar visibles desde un dispositivo
cliente. Para verificar desde la propia Pi:

```bash
# Estado de los servicios
sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack
sudo systemctl status tfg-attack.service --no-pager

# Confirmar SSIDs activos
sudo iw dev wlan0 info | grep -E 'ssid|channel'   # PatataWiFi_mgmt / channel 1
sudo iw dev wlan1 info | grep -E 'ssid|channel'   # eduroam-tfg     / channel 6

# Monitorizar capturas en tiempo real
sudo tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log

# Logs de los scripts del laboratorio
sudo tail -F /var/log/tfg-cleanup.log /var/log/tfg-mgmt.log /var/log/tfg-attack.log
```

Con el dispositivo víctima a un par de metros, intente conectarlo a
`eduroam-tfg`. Tres comportamientos posibles según la configuración del
cliente (no atribuibles al fabricante: dependen del supplicant y del
perfil eduroam instalado):

- **Cliente acepta el cert + acepta EAP-GTC**: envía la **password
  literal** dentro del túnel TLS. Queda en el log como
  `pap: <user> / <password>`. Además, **completa la conexión** al
  rogue AP (porque WPE conoce la password y emite `Access-Accept` con
  MSK válida).
- **Cliente acepta el cert + rechaza GTC con `EAP-NAK`**: el servidor
  cae automáticamente a MSCHAPv2 y captura el **hash NETNTLM** (línea
  `mschap:`). El cliente recibe `Access-Reject` y NO se conecta, pero
  la credencial queda en disco para crack offline — ver
  [`docs/analisis-offline.md`](docs/analisis-offline.md).
- **Cliente con CA pinning estricto rechaza el cert exterior**: no se
  abre el túnel PEAP. **Sin captura.** Es la mitigación recomendada
  por eduroam (perfil CAT con CA legítima).

## Personalización

| Cambio | Archivo a editar | Después |
|---|---|---|
| SSID del Evil Twin | `/root/patatawifi/hostapd-freeradius.sh` (`mgmt_ssid='…'` no, **ese es para la mgmt interna del wrapper**; el SSID real está heredado del `hostapd-freeradius.sh` original) | `sudo systemctl restart tfg-attack` o reboot |
| PSK red gestión | `/root/patatawifi/hostapd-mgmt/mgmt.conf` (`wpa_passphrase=`) | `sudo systemctl restart tfg-mgmt` |
| SSID red gestión | `/root/patatawifi/hostapd-mgmt/mgmt.conf` (`ssid=`) | idem |
| CN del cert RADIUS | `/etc/freeradius-wpe/3.0/certs/{ca,server}.cnf` | `sudo make -C /etc/freeradius-wpe/3.0/certs bootstrap`, luego reboot |
| Canal del Evil Twin | `/root/patatawifi/hostapd-freeradius.sh` (`channel=6`) | reboot |

## Desinstalación

```bash
sudo ./uninstall.sh
```

`uninstall.sh` elimina automáticamente:
- Los 3 servicios `systemd` y sus scripts en `/usr/local/bin`
- `/var/log/tfg-*.log`
- `/root/patatawifi/hostapd-mgmt/` (creado por este repo)
- Restaura `radiusd.conf` si encuentra `.dpkg-dist`

E **interactivamente** pregunta antes de:
- Desinstalar el paquete `freeradius-wpe`
- Quitar el repo Kali y su clave GPG
- Eliminar `/root/patatawifi` (contiene logs/hashes capturados)
