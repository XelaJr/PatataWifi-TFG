#!/bin/bash
LOG=/var/log/tfg-mgmt.log
echo "=== $(date) === Arrancando ===" >> $LOG
ip link set wlan0 down 2>/dev/null
iw dev wlan0 set type managed 2>/dev/null
sleep 1
ip link set wlan0 up
sleep 2
ip addr flush dev wlan0
ip addr add 172.31.0.1/24 dev wlan0
hostapd -B /root/patatawifi/hostapd-mgmt/mgmt.conf >> $LOG 2>&1
sleep 2
dnsmasq --interface=wlan0 --bind-interfaces --dhcp-range=172.31.0.10,172.31.0.100,12h --dhcp-option=3,172.31.0.1 --dhcp-option=6,1.1.1.1,8.8.8.8 --no-resolv --pid-file=/tmp/dnsmasq-mgmt.pid --log-facility=/tmp/dnsmasq-mgmt.log >> $LOG 2>&1
sleep 2
echo "=== $(date) === OK ===" >> $LOG
exit 0
