
#!/bin/bash
# Arranque completo: red de gestión + Evil Twin

set -e

echo "[1/4] Reset previo..."
/root/patatawifi/reset.sh > /dev/null 2>&1

echo "[2/4] Arrancando red de gestión en wlan0..."
sudo ip link set wlan0 down 2>/dev/null
sudo ip link set wlan0 up
sleep 1
sudo ip addr add 172.31.0.1/24 dev wlan0 2>/dev/null || true
sudo hostapd -B /root/patatawifi/hostapd-mgmt/mgmt.conf > /tmp/hostapd-mgmt.log 2>&1
sleep 2

# Lanzar dnsmasq para la red de gestión
sudo dnsmasq --interface=wlan0 --bind-interfaces \
  --dhcp-range=172.31.0.10,172.31.0.100,12h \
  --dhcp-option=3,172.31.0.1 \
  --dhcp-option=6,1.1.1.1,8.8.8.8 \
  --no-resolv \
  --pid-file=/tmp/dnsmasq-mgmt.pid > /tmp/dnsmasq-mgmt.log 2>&1
sleep 1

echo "[3/4] Verificando wlan0..."
ip addr show wlan0 | grep "inet "
echo "Red 'PatataWiFi_mgmt' al aire en wlan0 (canal 1)"

echo "[4/4] Arrancando PatataWiFi para Evil Twin en wlan1..."
cd /root/patatawifi
sudo ./hostapd-freeradius.sh
