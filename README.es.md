# TFG Evil Twin — Laboratorio educativo sobre eduroam

[English](README.md) · **Español**

> 🏅 **Este TFG obtuvo la máxima calificación: 10 sobre 10.**

> ### 📄 Memoria completa
> La memoria completa del TFG (112 páginas) — contexto, estado del arte,
> decisiones de diseño, resultados por dispositivo y conclusiones — está incluida
> como **[`tfg.pdf`](tfg.pdf)**.

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
RADIUS bajo su control, capturando las credenciales del usuario en una forma
susceptible de uso directo o de ataque offline.

Este repositorio convierte una Raspberry Pi 5 limpia en un laboratorio
auto-arrancable que materializa ese escenario sobre dos radios físicas: la
interna de la Pi 5 (BCM4345C0) levanta una red WPA2-PSK de gestión, y un Alfa
AWUS036ACM (MT7612U) levanta el AP malicioso `eduroam-tfg` con
**FreeRADIUS-WPE 3.x** como backend de captura. Todo el ciclo de vida
(*cleanup → mgmt → attack*) se orquesta vía tres servicios `systemd` que
arrancan ~30 s tras el POST.

El RADIUS está configurado con **downgrade attack a EAP-GTC** en el inner
PEAP (ver [`docs/arquitectura.md`](docs/arquitectura.md) §5). Resultado
según el comportamiento del cliente:

- Cliente que acepta el certificado del RADIUS y acepta EAP-GTC →
  **password en claro** capturada + conexión completa al rogue AP.
- Cliente que acepta el certificado pero rechaza GTC vía `EAP-NAK`
  proponiendo MSCHAPv2 → fallback automático del servidor a MSCHAPv2 →
  **hash NETNTLM** capturado, crackeable offline.
- Cliente con CA pinning estricto que rechaza el certificado del RADIUS
  en el outer PEAP/TLS → no se abre el túnel → **ninguna captura**. Es
  la única configuración del cliente que mitiga por completo el ataque.

## Hardware probado

| Componente | Modelo | Notas |
|---|---|---|
| Plataforma | Raspberry Pi 5 (8 GB) | aarch64 / kernel 6.12.x |
| Radio interna | Broadcom BCM4345C0 (wlan0) | usa `firmware-brcm80211` |
| Radio externa | Alfa AWUS036ACM (wlan1) | MediaTek MT7612U, `firmware-mediatek` |
| Cliente víctima | Cualquier dispositivo con stack 802.1X/EAP que se asocie a `eduroam-tfg`. El comportamiento concreto (captura GTC plain, fallback MSCHAPv2 o rechazo TLS) depende de la configuración del supplicant y del perfil eduroam instalado, no del fabricante. Pruebas en hardware concreto en curso. |

> El AWUS036ACM se requiere porque la radio interna no permite, sobre el driver
> Broadcom, el modo AP con WPA2-Enterprise + multi-BSSID simultáneo. Ver
> [`docs/arquitectura.md`](docs/arquitectura.md) para el detalle.

## Quickstart

```bash
git clone https://github.com/XelaJr/PatataWifi-TFG.git
cd PatataWifi-TFG
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
| Captura de password en claro vía EAP-GTC (línea `pap:` en `freeradius-server-wpe.log`) | Validado contra clientes que aceptan GTC |
| Captura de hash NETNTLM vía fallback MSCHAPv2 (línea `mschap:`) | Validado contra clientes que rechazan GTC con `EAP-NAK` |
| Comportamiento sobre familias concretas de hardware víctima | **En curso** — no documentado por dispositivo todavía |
| Despliegue en armv7 (Pi 3/4) | **No** validado — `install.sh` avisa pero no aborta |
| Despliegue en otras distros (Ubuntu, Kali, Debian estable) | **No** validado |

## Memoria completa

La memoria completa del Trabajo Fin de Grado — contexto, estado del arte,
decisiones de diseño, resultados por dispositivo y conclusiones — está incluida
como [**`tfg.pdf`**](tfg.pdf) (112 páginas).

*Cañadas Fleury, A. (2026). «Plataforma portable sobre Raspberry Pi para
auditoría de redes WPA-Enterprise».* Trabajo Fin de Grado, Universidad Loyola
Andalucía. Tutores: Jordi García Quintanilla, Raúl Martín Santamaría.

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
