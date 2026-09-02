# TFG Evil Twin: Educational lab on eduroam

**English** · [Español](README.es.md)

> 🏅 **This thesis was awarded the top grade: 10 out of 10.**

> ### 📄 Full thesis
> The complete 112-page thesis behind this lab (context, state of the
> art, design decisions, per-device results and conclusions) is included as
> **[`tfg.pdf`](tfg.pdf)** *(Spanish)*.

> ## ⚠️ EDUCATIONAL USE - CLOSED LAB ONLY ⚠️
>
> This code accompanies the **Bachelor's thesis (TFG) of Alejandro Cañadas
> Fleury** (BSc in Computer Engineering, **Universidad Loyola Andalucía**). It
> reproduces, for teaching purposes and inside the author's isolated lab, the
> *Evil Twin* attack against `eduroam`-style WPA2-Enterprise networks.
>
> **Using it against networks you do not own, or without explicit written
> consent** from the legitimate network operator *and* its users, is a criminal
> offence in Spain under **Article 197 of the Criminal Code** (discovery and
> disclosure of secrets), punishable with prison.
>
> **The author accepts no responsibility for misuse of this code.**

---

## About the project

`eduroam` is the international academic wireless federation. Its security rests
on WPA2-Enterprise with 802.1X/EAP authentication: the client hands its
corporate credentials to its own institution's RADIUS server through a TLS
tunnel. If the client does not correctly validate the RADIUS server's
certificate (very common on poorly-configured personal devices), an attacker can
stand up an access point with the same SSID and a RADIUS server under their
control, capturing the user's credentials in a form that is directly usable or
susceptible to offline attack.

This repository turns a clean Raspberry Pi 5 into a self-booting lab that
materialises that scenario over two physical radios: the Pi 5's internal radio
(BCM4345C0) serves a WPA2-PSK management network, and an Alfa AWUS036ACM
(MT7612U) serves the rogue `eduroam-tfg` AP with **FreeRADIUS-WPE 3.x** as the
capture backend. The whole lifecycle (*cleanup → mgmt → attack*) is orchestrated
by three `systemd` services that start ~30 s after POST.

The RADIUS server is configured with an **inner-PEAP downgrade to EAP-GTC** (see
[`docs/arquitectura.md`](docs/arquitectura.md) §5). Depending on client
behaviour:

- Client that accepts the RADIUS certificate and accepts EAP-GTC →
  **plaintext password** captured + full connection to the rogue AP.
- Client that accepts the certificate but rejects GTC via `EAP-NAK`,
  proposing MSCHAPv2 → automatic server fallback to MSCHAPv2 →
  **NETNTLM hash** captured, crackable offline.
- Client with strict CA pinning that rejects the RADIUS certificate in
  the outer PEAP/TLS → the tunnel never opens → **no capture**. This is
  the only client configuration that fully mitigates the attack.

## Hardware tested

| Component | Model | Notes |
|---|---|---|
| Platform | Raspberry Pi 5 (8 GB) | aarch64 / kernel 6.12.x |
| Internal radio | Broadcom BCM4345C0 (wlan0) | uses `firmware-brcm80211` |
| External radio | Alfa AWUS036ACM (wlan1) | MediaTek MT7612U, `firmware-mediatek` |
| Victim client | Any device with an 802.1X/EAP stack that associates to `eduroam-tfg`. The specific outcome (plaintext GTC, MSCHAPv2 fallback, or TLS rejection) depends on the supplicant configuration and the installed eduroam profile, not on the manufacturer. Testing on specific hardware is ongoing. |

> The AWUS036ACM is required because, on the Broadcom driver, the internal radio
> does not allow AP mode with WPA2-Enterprise + multi-BSSID simultaneously. See
> [`docs/arquitectura.md`](docs/arquitectura.md) for the detail.

## Quickstart

```bash
git clone https://github.com/XelaJr/PatataWifi-TFG.git
cd PatataWifi-TFG
sudo ./install.sh
sudo reboot
sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack   # after boot
```

About ~30 seconds after the first boot, both APs should be on the air and
visible from a client device. The capture log lives at
`/var/log/freeradius-wpe/freeradius-server-wpe.log`.

## Architecture (summary)

```
                       ┌────────────────────────────┐
                       │ Raspberry Pi 5             │
                       │                            │
   [Victim client]     │  ┌──────────────────────┐  │
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

Full flow, design rationale and the extended diagram in
[`docs/arquitectura.md`](docs/arquitectura.md).

## Default configuration

| Parameter | Default | File to change it |
|---|---|---|
| Management SSID | `PatataWiFi_mgmt` | `hostapd-mgmt/mgmt.conf` |
| Management PSK | `patatas333` | `hostapd-mgmt/mgmt.conf` |
| Management channel | 1 (2.4 GHz) | `hostapd-mgmt/mgmt.conf` |
| Management IP (Pi) | `172.31.0.1/24` | `scripts/tfg-mgmt.sh` |
| Evil Twin SSID | `eduroam-tfg` | `patatawifi-patches/hostapd-freeradius.sh.patch` |
| Evil Twin channel | 6 (2.4 GHz) | idem |
| Evil Twin IP (Pi) | `10.0.0.1/24` | idem |
| RADIUS cert CN | `Example Server Certificate` | `/etc/freeradius-wpe/3.0/certs/server.cnf` |

> **Note on `patatas333`:** the password for the `PatataWiFi_mgmt` management
> network is inherited from the upstream project
> [PatataWiFi](https://github.com/jesux/PatataWiFiEnterprise). **It is not a
> secret**: it is the lab default. Edit `hostapd-mgmt/mgmt.conf` before running
> `install.sh` to change it.

## Validation status

| Component | Status |
|---|---|
| Deployment on Pi 5 8 GB + AWUS036ACM | Validated |
| Automatic startup after reboot | Validated (~30 s) |
| Plaintext password capture via EAP-GTC (`pap:` line in `freeradius-server-wpe.log`) | Validated against clients that accept GTC |
| NETNTLM hash capture via MSCHAPv2 fallback (`mschap:` line) | Validated against clients that reject GTC with `EAP-NAK` |
| Behaviour on specific victim-hardware families | **Ongoing** (not documented per device yet) |
| Deployment on armv7 (Pi 3/4) | **Not** validated (`install.sh` warns but does not abort) |
| Deployment on other distros (Ubuntu, Kali, Debian stable) | **Not** validated |

## Full thesis

The complete Bachelor's thesis (memoria) (context, state of the art, design
decisions, per-device results and conclusions) is included as
[**`tfg.pdf`**](tfg.pdf) (112 pages, Spanish).

*Cañadas Fleury, A. (2026). «Plataforma portable sobre Raspberry Pi para
auditoría de redes WPA-Enterprise».* Bachelor's thesis, Universidad Loyola
Andalucía. Advisors: Jordi García Quintanilla, Raúl Martín Santamaría.

## Acknowledgements

- [**PatataWiFi / PatataWiFiEnterprise**](https://github.com/jesux/PatataWiFiEnterprise),
  by Jesús Antón ([@jesux](https://github.com/jesux)). The `hostapd` templates,
  the `hostapd-freeradius.sh` and `init.sh` scripts, and the tmux multiplexing
  pattern are his work.
- [**FreeRADIUS-WPE**](https://github.com/brad-anton/freeradius-wpe), the
  *Wireless Pwn Edition* originally published by
  [Joshua Wright](https://github.com/joswr1ght) and maintained in its modern
  revisions by the Kali project. Packaged in `kali-rolling` as
  `freeradius-wpe 3.2.5+dfsg-3kali1`.

## Contributing

Issues and pull requests are welcome. Please follow these guidelines:

- Open an issue before a large PR to discuss the approach.
- Contributions must respect the **educational** character of the project:
  improvements oriented at detection evasion, identity obfuscation, or expanding
  the scope beyond Art. 197 CP (Spain) will not be accepted.
- If your contribution needs captured material (PCAP, hashes), redact it with
  synthetic data before attaching it.

## License

[GPL-3.0-or-later](LICENSE). Inherited from the upstream components (PatataWiFi
GPL-3.0; FreeRADIUS-WPE GPL-2.0).
