#!/system/bin/sh
# on_device_verify.sh
# Run this on the rooted Redmi Pad SE 8.7 4G after installing the patched
# Magisk module. Verifies the radiotap-monitor-enabled wlan_drv_gen4m.ko
# is actually loaded.

echo "=== Vermagic check ==="
strings /vendor/lib/modules/wlan_drv_gen4m.ko | grep vermagic

echo
echo "=== Radiotap strings present in loaded module ==="
strings /vendor/lib/modules/wlan_drv_gen4m.ko | \
    grep -iE 'radiotap|NL80211_IFTYPE_MONITOR|CFG_SUPPORT_SNIFFER_RADIOTAP|wlanoidSetIcsSniffer' | \
    head -20

echo
echo "=== Loaded module list (wlan) ==="
lsmod | grep wlan

echo
echo "=== Bringing up Wi-Fi to enumerate monitor capability ==="
svc wifi disable
sleep 3
svc wifi enable
sleep 6

echo
echo "=== iw list (look for '* monitor' under 'Supported interface modes') ==="
iw list | grep -A30 "Supported interface modes"

echo
echo "=== Interface state ==="
ip link
iw dev

echo
echo "=== SNIFFER probe (does not enable monitor, just verifies parser) ==="
echo "0x03:0xff" > /proc/net/wlan/dbgLevel 2>/dev/null
echo "0x00:0xff" > /proc/net/wlan/dbgLevel 2>/dev/null
echo "0x1e:0xff" > /proc/net/wlan/dbgLevel 2>/dev/null
dmesg -C 2>/dev/null
echo "SNIFFER=2-1-0-0-2-0-0-0-0-0" > /proc/net/wlan/driver
sleep 2
dmesg | grep -iE 'sniffer|ics|promisc|RXM|wlanoidSetIcsSniffer|radiotap|monitor|PARAMETERS|Invalid|failed' | tail -n 30
echo "SNIFFER=2-0-0-0-2-0-0-0-0-0" > /proc/net/wlan/driver
