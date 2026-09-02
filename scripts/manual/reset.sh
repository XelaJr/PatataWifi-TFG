
#!/bin/bash
# reset.sh: Limpieza total antes de arrancar PatataWiFi
# Mata todo, resetea interfaces, libera puertos

echo "[+] Matando tmux..."
tmux kill-server 2>/dev/null

echo "[+] Matando procesos relacionados..."
sudo pkill -9 hostapd 2>/dev/null
sudo pkill -9 radiusd 2>/dev/null
sudo pkill -9 freeradius 2>/dev/null
sudo pkill -9 freeradius-wpe 2>/dev/null
sudo pkill -9 dnsmasq 2>/dev/null
sudo pkill -9 -f patatawifi 2>/dev/null
sleep 2

echo "[+] Reseteando wlan1 (Alfa USB)..."
sudo ip link set wlan1 down 2>/dev/null
sleep 1
sudo iw dev wlan1 del 2>/dev/null
sleep 1

echo "[+] Recargando driver MediaTek MT7612U..."
sudo rmmod mt76x2u 2>/dev/null
sleep 2
sudo modprobe mt76x2u
sleep 4

echo "[+] Reseteando NetworkManager si está activo..."
sudo systemctl stop NetworkManager 2>/dev/null
sudo systemctl stop wpa_supplicant 2>/dev/null

echo ""
echo "================== ESTADO FINAL =================="
echo ""
echo "[1] Interfaces Wi-Fi:"
iw dev 2>/dev/null | grep -E "Interface|type"
echo ""
echo "[2] Procesos activos (debe estar vacío):"
ps aux | grep -E "hostapd|radius|dnsmasq" | grep -v grep
echo ""
echo "[3] Puertos críticos (deben estar libres):"
sudo ss -tunlp 2>/dev/null | grep -E ":(53|67|1812|1813)" || echo "    Puertos libres ✓"
echo ""
echo "[4] Tmux:"
tmux ls 2>&1
echo ""
echo "==================================================="
echo "Listo para arrancar:"
echo "  cd /root/patatawifi && sudo ./hostapd-freeradius.sh"
echo "==================================================="
