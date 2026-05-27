# Patches sobre PatataWiFi (upstream)

Estos cuatro patches modifican los archivos del repo
[`jesux/PatataWiFiEnterprise`](https://github.com/jesux/PatataWiFiEnterprise)
para adaptarlos al laboratorio TFG. `install.sh` los aplica automáticamente
sobre el árbol clonado en `/root/patatawifi/`.

## Resumen por archivo

| Patch | Origen → Destino | Qué cambia |
|---|---|---|
| `hostapd-freeradius.sh.patch`   | `files/hostapd-freeradius.sh` | SSID del AP (`eduroam-tfg`), orden `wlan_list`, MAC fija, `mgmt_ip=10.0.0.1` (evita colisión con la red mgmt en `172.31.0.0/24`), vacía `ssid_list`/`wlan_ip_list` (sin SSIDs virtuales). |
| `patatawifi.conf.patch`         | `files/hostapd/patatawifi.conf` | Limpia parámetros WMM/AC heredados de la plantilla. Cambia `auth_algs=3` → `auth_algs=1` (sólo Open System). Añade el bloque WPA2-Enterprise (`ieee8021x=1` y siguientes) que el script `hostapd-freeradius.sh` espera encontrar. |
| `patatawifi-virtual.conf.patch` | `files/hostapd/patatawifi-virtual.conf` | `wpa_pairwise` solo `CCMP` (no `TKIP`), añade `ieee80211w=1` (gestión de marcos protegida). |
| `hostapd-2.6-config.patch`      | `hostapd-2.6/hostapd/defconfig` → `.config` | Descomenta `CONFIG_LIBNL32=y` y `CONFIG_IEEE80211N=y`. Mínimo necesario para compilar hostapd con soporte de `libnl-3.2` (la única opción razonable en Debian moderno) y 802.11n. |

## Cómo se aplican manualmente

Cada patch se aplica con `patch -p1` sobre el directorio raíz indicado:

```bash
# Tres parches sobre el clone de PatataWiFi
cd /root/patatawifi
sudo patch -p1 < /ruta/al/repo/patatawifi-patches/hostapd-freeradius.sh.patch
sudo patch -p1 < /ruta/al/repo/patatawifi-patches/patatawifi.conf.patch
sudo patch -p1 < /ruta/al/repo/patatawifi-patches/patatawifi-virtual.conf.patch

# El cuarto se aplica sobre el árbol de fuentes de hostapd-2.6
sudo cp /root/patatawifi/hostapd-2.6/hostapd/defconfig \
        /root/patatawifi/hostapd-2.6/hostapd/.config
cd /root/patatawifi/hostapd-2.6
sudo patch -p1 < /ruta/al/repo/patatawifi-patches/hostapd-2.6-config.patch
```

`install.sh` usa el helper `apply_patch_idempotent` que:

1. Comprueba si el patch ya está aplicado (`patch --reverse --dry-run`).
2. Si lo está, omite y continúa.
3. Si no, aplica con `patch --forward` (que también ignora hunks ya aplicados).

Esto permite re-ejecutar `install.sh` sin que falle por patches ya integrados.

## Generación de los patches

Los patches están generados con `diff -u` contra **el upstream**, no contra
los `.backup*` que dejé en mi sistema durante el desarrollo. Para
regenerarlos (si se actualizan los archivos en el sistema vivo):

```bash
# Clonar upstream a /tmp
git clone --depth=1 https://github.com/jesux/PatataWiFiEnterprise.git /tmp/PWE

# Regenerar (ejemplo con hostapd-freeradius.sh)
diff -u --label a/hostapd-freeradius.sh --label b/hostapd-freeradius.sh \
     /tmp/PWE/files/hostapd-freeradius.sh \
     /root/patatawifi/hostapd-freeradius.sh \
  > patatawifi-patches/hostapd-freeradius.sh.patch
```

## Verificación de round-trip

Cada patch se ha verificado: partiendo del archivo upstream, aplicar el
patch reproduce **exactamente** el archivo del laboratorio (`diff -q`
vacío). Esto garantiza que en una Pi limpia los patches no producirán
"reject" contra el clone del upstream.

## Referencia upstream

- Repo: <https://github.com/jesux/PatataWiFiEnterprise>
- Último commit considerado: rama `master`, push 2024-02-24.
- Licencia upstream: GPL-3.0 (heredada).
