#!/bin/bash
# uninstall.sh: Reversión del despliegue TFG Evil Twin
#
# Conservador: elimina automáticamente sólo los artefactos del laboratorio en
# /etc/systemd/system y /usr/local/bin. Pregunta interactivamente antes de tocar
# /root/patatawifi, el paquete freeradius-wpe o el repo Kali, porque pueden
# contener datos del usuario o ser usados por otros proyectos.

set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: requiere root. Use sudo." >&2
  exit 1
fi

ask_yn() {
  local q="$1" default="${2:-n}" prompt ans
  if [ "$default" = "y" ]; then prompt="$q [Y/n] "; else prompt="$q [y/N] "; fi
  read -r -p "$prompt" ans
  ans="${ans:-$default}"
  case "$ans" in y|Y|yes|YES|s|S|si|SI|sí|SÍ) return 0 ;; *) return 1 ;; esac
}

cat <<'BANNER'
===============================================================
  TFG Evil Twin · Desinstalación
===============================================================
BANNER

# ----------------------------------------------------------------
echo ""
echo "[1/7] Deteniendo y deshabilitando servicios tfg-*"
for svc in tfg-attack tfg-mgmt tfg-cleanup; do
  systemctl stop    "$svc.service" 2>/dev/null || true
  systemctl disable "$svc.service" 2>/dev/null || true
done
rm -fv /etc/systemd/system/tfg-cleanup.service \
       /etc/systemd/system/tfg-mgmt.service \
       /etc/systemd/system/tfg-attack.service
systemctl daemon-reload

# ----------------------------------------------------------------
echo ""
echo "[2/7] Eliminando scripts /usr/local/bin/tfg-*.sh"
rm -fv /usr/local/bin/tfg-cleanup.sh \
       /usr/local/bin/tfg-mgmt.sh \
       /usr/local/bin/tfg-attack.sh

# ----------------------------------------------------------------
echo ""
echo "[3/7] Eliminando logs del laboratorio (/var/log/tfg-*.log)"
rm -fv /var/log/tfg-cleanup.log /var/log/tfg-mgmt.log /var/log/tfg-attack.log

# ----------------------------------------------------------------
echo ""
echo "[4/7] Eliminando /root/patatawifi/hostapd-mgmt/ (creado por install.sh)"
if [ -d /root/patatawifi/hostapd-mgmt ]; then
  rm -rfv /root/patatawifi/hostapd-mgmt
fi

# ----------------------------------------------------------------
echo ""
echo "[5/7] Restaurando radiusd.conf original (si existe .dpkg-dist)"
if [ -f /etc/freeradius-wpe/3.0/radiusd.conf.dpkg-dist ]; then
  mv -v /etc/freeradius-wpe/3.0/radiusd.conf.dpkg-dist /etc/freeradius-wpe/3.0/radiusd.conf
else
  echo "       (no hay .dpkg-dist; para revertir manualmente:"
  echo "        sudo apt-get install --reinstall -o Dpkg::Options::='--force-confmiss' freeradius-wpe)"
fi

# ----------------------------------------------------------------
echo ""
echo "[6/7] Desinstalación opcional de paquetes y repos"
if ask_yn "¿Desinstalar paquete freeradius-wpe?" n; then
  apt-get remove -y freeradius-wpe || true
fi
if ask_yn "¿Eliminar repo Kali (sources.list.d/kali.list, preferences.d/kali, kali.gpg)?" n; then
  rm -fv /etc/apt/sources.list.d/kali.list \
         /etc/apt/preferences.d/kali \
         /etc/apt/trusted.gpg.d/kali.gpg
  apt-get update -qq || true
fi

# ----------------------------------------------------------------
echo ""
echo "[7/7] Eliminación opcional de /root/patatawifi (DATOS DEL USUARIO)"
if ask_yn "¿Eliminar /root/patatawifi (logs, hashes capturados, binarios)?" n; then
  rm -rf /root/patatawifi
  echo "       /root/patatawifi eliminado"
else
  echo "       /root/patatawifi conservado"
fi

cat <<'POSTMSG'

===============================================================
  Desinstalación completada.

  Si quiere también limpiar las dependencias huérfanas:
    sudo apt-get autoremove --purge

===============================================================
POSTMSG
