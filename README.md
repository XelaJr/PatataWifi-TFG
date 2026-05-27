# TFG Evil Twin — Laboratorio educativo sobre eduroam

> ## ⚠️ USO EDUCATIVO EN LABORATORIO CERRADO ÚNICAMENTE ⚠️
>
> Este código está asociado al **Trabajo Fin de Grado de Alejandro Cañadas
> Fleury** (Grado en Ingeniería Informática, **Universidad Loyola Andalucía**).
> Reproduce, con fines didácticos y en un entorno aislado del autor, el
> ataque *Evil Twin* contra redes WPA2-Enterprise de tipo `eduroam`.
>
> **El uso contra redes ajenas, o sin consentimiento explícito por escrito**
> del operador legítimo de la red y de sus usuarios, está tipificado en el
> **Artículo 197 del Código Penal español** (descubrimiento y revelación de
> secretos) y constituye **delito con penas de prisión**.
>
> **El autor no se responsabiliza del uso indebido de este código.**

---

## Acerca del proyecto

`eduroam` es la federación inalámbrica de la red académica internacional. Su
seguridad reposa en WPA2-Enterprise con autenticación 802.1X/EAP: el cliente
entrega credenciales corporativas al servidor RADIUS de su propia institución a
través de un túnel TLS. Si el cliente no valida correctamente el certificado
del servidor RADIUS (caso muy común en dispositivos personales mal configurados),
un atacante puede levantar un punto de acceso con el mismo SSID y un servidor
RADIUS bajo su control, capturando el handshake MSCHAPv2 que contiene las
credenciales del usuario en una forma susceptible de ataque offline.

Este repositorio convierte una Raspberry Pi 5 limpia en un laboratorio
auto-arrancable que materializa ese escenario sobre dos radios físicas: la
interna de la Pi 5 (BCM4345C0) levanta una red WPA2-PSK de gestión, y un Alfa
AWUS036ACM (MT7612U) levanta el AP malicioso `eduroam-tfg` con
**FreeRADIUS-WPE 3.x** como backend de captura. Todo el ciclo de vida
(*cleanup → mgmt → attack*) se orquesta vía tres servicios `systemd` que
arrancan ~30 s tras el POST.

## Hardware probado

| Componente | Modelo | Notas |
|---|---|---|
| Plataforma | Raspberry Pi 5 (8 GB) | aarch64 / kernel 6.12.x |
| Radio interna | Broadcom BCM4345C0 (wlan0) | usa `firmware-brcm80211` |
| Radio externa | Alfa AWUS036ACM (wlan1) | MediaTek MT7612U, `firmware-mediatek` |
| Cliente víctima (validado) | iPhone con iOS 17/18 | exige certificado válido — se valida la captura del intento de autenticación, no la conexión completa |

> El AWUS036ACM se requiere porque la radio interna no permite, sobre el driver
> Broadcom, el modo AP con WPA2-Enterprise + multi-BSSID simultáneo. Ver
> [`docs/arquitectura.md`](docs/arquitectura.md) para el detalle.

## Quickstart

```bash
git clone https://github.com/xelajr/tfg-eduroam-eviltwin.git
cd tfg-eduroam-eviltwin
sudo ./install.sh
sudo reboot
sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack   # tras boot
```

Pasados ~30 segundos tras el primer arranque, ambos APs deben estar al aire y
visibles desde un dispositivo cliente. El log de captura está en
`/var/log/freeradius-wpe/freeradius-server-wpe.log`.

## Arquitectura (resumen)

```
                       ┌────────────────────────────┐
                       │ Raspberry Pi 5             │
                       │                            │
   [Cliente víctima]   │  ┌──────────────────────┐  │
        ↓ probe        │  │ wlan0 (BCM4345C0)    │  │ → PatataWiFi_mgmt   (PSK, ch 1)
        ↓ eduroam SSID │  │ 172.31.0.1/24        │  │
                       │  └──────────────────────┘  │
                       │  ┌──────────────────────┐  │
                       │  │ wlan1 (Alfa MT7612U) │  │ → eduroam-tfg       (EAP, ch 6)
                       │  │ 10.0.0.1/24          │  │
                       │  └──────┬───────────────┘  │
                       │         ↓ PEAP/MSCHAPv2    │
                       │  ┌──────────────────────┐  │
                       │  │ FreeRADIUS-WPE 3.2.5 │  │ → /var/log/freeradius-wpe/
                       │  └──────────────────────┘  │
                       └────────────────────────────┘
```

Detalles completos del flujo, motivaciones de diseño y diagrama extendido en
[`docs/arquitectura.md`](docs/arquitectura.md).

## Configuración por defecto

| Parámetro | Valor por defecto | Archivo donde se cambia |
|---|---|---|
| SSID red de gestión | `PatataWiFi_mgmt` | `hostapd-mgmt/mgmt.conf` |
| PSK red de gestión | `patatas333` | `hostapd-mgmt/mgmt.conf` |
| Canal red de gestión | 1 (2.4 GHz) | `hostapd-mgmt/mgmt.conf` |
| IP red de gestión (Pi) | `172.31.0.1/24` | `scripts/tfg-mgmt.sh` |
| SSID Evil Twin | `eduroam-tfg` | `patatawifi-patches/hostapd-freeradius.sh.patch` |
| Canal Evil Twin | 6 (2.4 GHz) | idem |
| IP Evil Twin (Pi) | `10.0.0.1/24` | idem |
| Cert CN (servidor RADIUS) | `Example Server Certificate` | `/etc/freeradius-wpe/3.0/certs/server.cnf` |

> **Nota sobre `patatas333`:** la contraseña de la red de gestión `PatataWiFi_mgmt`
> está heredada del proyecto upstream [PatataWiFi](https://github.com/jesux/PatataWiFiEnterprise).
> **No es un secreto** — es el valor por defecto del laboratorio. Edite
> `hostapd-mgmt/mgmt.conf` antes de ejecutar `install.sh` si desea personalizarla.

## Estado de validación

| Componente | Estado |
|---|---|
| Despliegue sobre Pi 5 8 GB + AWUS036ACM | Validado |
| Arranque automático tras reboot | Validado (~30 s) |
| Captura de hash MSCHAPv2 desde cliente iPhone iOS 17/18 | Validado (intento de autenticación con cert rechazado por el cliente) |
| Despliegue en armv7 (Pi 3/4) | **No** validado — `install.sh` avisa pero no aborta |
| Despliegue en otras distros (Ubuntu, Kali, Debian estable) | **No** validado |

## Reconocimientos

- [**PatataWiFi / PatataWiFiEnterprise**](https://github.com/jesux/PatataWiFiEnterprise),
  de Jesús Antón ([@jesux](https://github.com/jesux)). Las plantillas de
  `hostapd`, los scripts `hostapd-freeradius.sh` y `init.sh`, y el patrón de
  multiplexación con tmux son obra suya.
- [**FreeRADIUS-WPE**](https://github.com/brad-anton/freeradius-wpe), versión
  *Wireless Pwn Edition* originalmente publicada por
  [Joshua Wright](https://github.com/joswr1ght) y mantenida en sus revisiones
  modernas por el proyecto Kali. Empaquetada en `kali-rolling` como
  `freeradius-wpe 3.2.5+dfsg-3kali1`.
- [**Moxie Marlinspike & David Hulton — DEFCON 20 (2012)**](https://www.youtube.com/watch?v=k6oZsy7Pe-Q),
  *Defeating PPTP VPNs and WPA2 Enterprise with MS-CHAPv2*. La base teórica
  detrás de la captura/recuperación que motiva este laboratorio.

## Contribuir

Issues y pull requests son bienvenidos. Por favor, siga estas pautas:

- Abra un issue antes de un PR grande para discutir el enfoque.
- Las contribuciones deben respetar el carácter **educativo** del proyecto:
  no se aceptarán mejoras orientadas a evasión de detección, ofuscación de
  identidad, o ampliación del alcance fuera del Art. 197 CP (España).
- Si su contribución necesita material capturado (PCAP, hashes), redáctelo
  con datos sintéticos antes de adjuntarlo.

## Licencia

[GPL-3.0-or-later](LICENSE). Hereda esta licencia de los componentes upstream
(PatataWiFi GPL-3.0; FreeRADIUS-WPE GPL-2.0).
