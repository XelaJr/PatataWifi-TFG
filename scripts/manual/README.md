# Scripts manuales (precursores interactivos)

Los dos scripts de este directorio son **precursores manuales** de los
servicios `systemd` que orquestan el laboratorio. Conservan valor durante
desarrollo y debugging porque pueden ejecutarse con `sudo` en línea y dan
salida visible en tiempo real (cosa que los `tfg-*.service` no: su salida
va a `journalctl`).

## `reset.sh`

Equivalente manual de `tfg-cleanup.service`. Mata procesos, baja interfaces,
recarga el driver `mt76x2u` y detiene NetworkManager + wpa_supplicant. Es
seguro re-ejecutarlo en cualquier momento.

```bash
sudo ./reset.sh
```

Termina imprimiendo el estado actual de las interfaces y procesos para
verificación visual.

## `start-todo.sh`

Equivalente manual de `tfg-mgmt.service` + `tfg-attack.service` encadenados.
Asume que `reset.sh` se acaba de ejecutar (lo invoca él mismo al inicio).

```bash
sudo ./start-todo.sh
```

Levanta `wlan0` con `172.31.0.1/24`, lanza `hostapd-mgmt` y `dnsmasq`, y
después ejecuta `hostapd-freeradius.sh` que entra en modo tmux para el
Evil Twin en `wlan1`.

## Producción vs. desarrollo

| Modo | Cómo arrancar | Salida visible | Reset tras fallo |
|---|---|---|---|
| **Producción (recomendado)** | `sudo systemctl restart tfg-cleanup tfg-mgmt tfg-attack` o reboot | `journalctl -u tfg-*` + `/var/log/tfg-*.log` | systemd reintenta según `Restart=` |
| **Desarrollo (estos scripts)** | `sudo ./reset.sh && sudo ./start-todo.sh` | stdout directo + tmux 5 paneles | manual |

## Por qué se conservan

- Las primeras versiones del laboratorio se ejecutaban exclusivamente con
  estos scripts antes de añadir la cadena `systemd`. Mantenerlos en el repo
  documenta la evolución del proyecto.
- Son útiles para debugging cuando los `tfg-*.service` fallan y no es obvio
  por qué: ejecutarlos a mano permite ver inmediatamente el primer error
  sin tener que `journalctl`-buscar.
- El `tmux` interactivo que dispara `start-todo.sh` (a través de
  `hostapd-freeradius.sh`) es más cómodo durante demos en vivo.

## Notas

- `reset.sh` usa `sudo` internamente. Si lo ejecutas ya como root, los
  `sudo` adicionales son no-ops.
- `start-todo.sh` usa `set -e`: cualquier paso que falle aborta el resto.
  Esto facilita identificar el primer punto de fallo, pero es estricto:
  prefiera `tfg-*.service` para arranque automático tolerante a fallos
  transitorios.
- Ninguno de los dos scripts es invocado por `install.sh`. Se copian al
  directorio para uso del operador, no para producción.
