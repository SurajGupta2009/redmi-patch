#!/usr/bin/env bash
# package_magisk_module.sh
# Packages the patched wlan_drv_gen4m.ko into a Magisk module zip
# that can be flashed from the Magisk app.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
PATCHED_KO="${1:-$ROOT/out/wlan_drv_gen4m.ko}"
STAGE="$ROOT/magisk-stage"
OUT_ZIP="$ROOT/redmi-wifi-monitor-spark-$(date +%Y%m%d).zip"

if [ ! -f "$PATCHED_KO" ]; then
    echo "Usage: $0 <patched_wlan_drv_gen4m.ko>"
    echo "Build it first with scripts/build_kernel_module.sh"
    exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE/system/vendor/lib/modules"
cp "$ROOT/magisk-module/module.prop"          "$STAGE/"
cp "$ROOT/magisk-module/sepolicy.rule"        "$STAGE/" 2>/dev/null || true
cp "$ROOT/magisk-module/customize.sh"         "$STAGE/"
cp "$PATCHED_KO"                              "$STAGE/system/vendor/lib/modules/wlan_drv_gen4m.ko"
chmod 0644 "$STAGE/system/vendor/lib/modules/wlan_drv_gen4m.ko"

# Build zip
(cd "$STAGE" && zip -r "$OUT_ZIP" .)
echo "[*] Magisk module packaged: $OUT_ZIP"
echo ""
echo "Install steps:"
echo "  adb push $OUT_ZIP /sdcard/Download/"
echo "  # In Magisk app: Modules -> Install from storage -> select zip -> Reboot"
