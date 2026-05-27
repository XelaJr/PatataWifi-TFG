#!/bin/bash
LOG=/var/log/tfg-attack.log
echo "=== $(date) === Arrancando Evil Twin ===" >> $LOG
for i in {1..15}; do
    if ip link show wlan1 &>/dev/null; then
        break
    fi
    sleep 1
done
if ! ip link show wlan1 &>/dev/null; then
    echo "ERROR: wlan1 no detectado" >> $LOG
    exit 1
fi
cd /root/patatawifi
./hostapd-freeradius.sh >> $LOG 2>&1 &
sleep 10
if ! pgrep -f "hostapd PatataWifi_Hostapd" > /dev/null; then
    echo "ERROR: PatataWiFi no arranco" >> $LOG
    exit 1
fi
echo "=== $(date) === OK ===" >> $LOG
exit 0
