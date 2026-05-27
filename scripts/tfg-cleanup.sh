#!/bin/bash
# tfg-cleanup.sh - Limpieza total antes de arrancar el laboratorio

LOG=/var/log/tfg-cleanup.log
echo "=== $(date) === Inicio cleanup ===" >> $LOG

# Matar todos los procesos relacionados
for proc in hostapd radiusd freeradius freeradius-wpe dnsmasq; do
    pkill -9 -x $proc 2>/dev/null
done
pkill -9 -f patatawifi 2>/dev/null
tmux kill-server 2>/dev/null

sleep 2

# Reset wlan0 (interna, gestión)
ip link set wlan0 down 2>/dev/null
ip addr flush dev wlan0 2>/dev/null

# Reset wlan1 (Alfa, ataque)
ip link set wlan1 down 2>/dev/null
iw dev wlan1 del 2>/dev/null

# Recargar driver MT7612U para limpiar estado kernel
rmmod mt76x2u 2>/dev/null
sleep 2
modprobe mt76x2u
sleep 3

# Detener NetworkManager y wpa_supplicant (interfieren con hostapd)
systemctl stop NetworkManager 2>/dev/null
systemctl stop wpa_supplicant 2>/dev/null

# Eliminar PIDs huérfanos
rm -f /tmp/dnsmasq-mgmt.pid /tmp/hostapd-mgmt.log /tmp/dnsmasq-mgmt.log 2>/dev/null
rm -rf /var/run/hostapd /var/run/hostapd-mgmt 2>/dev/null

echo "=== $(date) === Cleanup OK ===" >> $LOG
exit 0
