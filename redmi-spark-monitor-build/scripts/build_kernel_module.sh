#!/usr/bin/env bash
# build_kernel_module.sh
# Builds wlan_drv_gen4m.ko with radiotap monitor-mode support for
# Redmi Pad SE 8.7 4G (spark) 24076RP19I.
#
# Prerequisites:
#   - Linux build host (Ubuntu 22.04+ recommended)
#   - Android prebuilt clang 14+ (Google clang-r468909b or AOSP clang-r487747c)
#   - Stock kernel config: kernel_config.txt (from your redmi-patch extract)
#   - Stock module: wlan_drv_gen4m.ko (for vermagic comparison)
#
# Output: out/wlan_drv_gen4m.ko (patched)

set -euo pipefail

# ---- Paths (override via env if needed) ----
WORK="${WORK:-$HOME/redmi_monitor_build}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-spark-s-oss}"
MTK_REPO="${MTK_REPO:-https://github.com/MiCode/MTK_kernel_modules.git}"
MTK_BRANCH="${MTK_BRANCH:-spark-s-oss}"

# Stock kernel config from your extract
KERNEL_CONFIG="${KERNEL_CONFIG:-$WORK/kernel_config.txt}"
# Stock module for vermagic comparison
STOCK_MODULE="${STOCK_MODULE:-$WORK/stock_wlan_drv_gen4m.ko}"

# Android clang location (set this!)
CLANG_DIR="${CLANG_DIR:-$HOME/toolchains/clang-r487747c}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-arm-linux-gnueabi-}"

OUT_DIR="$WORK/out"

echo "[*] Workdir: $WORK"

# ---- 1. Clone sources (shallow) ----
if [ ! -d "$WORK/kernel_spark" ]; then
    echo "[*] Cloning kernel source ($KERNEL_BRANCH)..."
    git clone --depth=1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$WORK/kernel_spark"
fi

if [ ! -d "$WORK/vendor/mediatek/kernel_modules" ]; then
    echo "[*] Cloning MTK kernel_modules source ($MTK_BRANCH)..."
    mkdir -p "$WORK/vendor/mediatek"
    git clone --depth=1 --branch "$MTK_BRANCH" "$MTK_REPO" "$WORK/vendor/mediatek/kernel_modules"
fi

# ---- 2. Symlink gen4m -> gen4-mt79xx ----
GEN4_DIR="$WORK/vendor/mediatek/kernel_modules/connectivity/wlan/core"
if [ ! -e "$GEN4_DIR/gen4m" ]; then
    echo "[*] Creating gen4m -> gen4-mt79xx symlink..."
    ln -sfn gen4-mt79xx "$GEN4_DIR/gen4m"
fi

# ---- 3. Apply radiotap monitor patch ----
GEN4M_MAKEFILE="$GEN4_DIR/gen4-mt79xx/Makefile"
if ! grep -q "Force MediaTek radiotap monitor-mode support" "$GEN4M_MAKEFILE"; then
    echo "[*] Applying radiotap-monitor patch to Makefile..."
    cp "$GEN4M_MAKEFILE" "$GEN4M_MAKEFILE.bak"
    python3 - <<'PY'
from pathlib import Path
p = Path("out/gen4m/Makefile")
# python invocation uses CWD
PY
    # Use the actual file with a more reliable in-place edit
    python3 - <<'PY'
import re, sys
p = "$GEN4M_MAKEFILE"
PY
    # Inline sed for reliability
    python3 <<PYEOF
from pathlib import Path
p = Path("$GEN4M_MAKEFILE")
s = p.read_text()
old = """ifeq (\$(CONFIG_SUPPORT_SNIFFER_RADIOTAP), y)
    ccflags-y += -DCFG_SUPPORT_SNIFFER_RADIOTAP=1
    ccflags-y += -DCFG_SUPPORT_PDMA_SCATTER=1
else
    ccflags-y += -DCFG_SUPPORT_SNIFFER_RADIOTAP=0
    ccflags-y += -DCFG_SUPPORT_PDMA_SCATTER=0
endif"""
new = """# Force radiotap monitor support for Redmi Pad SE spark research build
ccflags-y += -DCFG_SUPPORT_SNIFFER_RADIOTAP=1
ccflags-y += -DCFG_SUPPORT_PDMA_SCATTER=1"""
if old not in s:
    print("WARNING: exact ifeq block not found, appending forced flags")
    s += "\n" + new + "\n"
else:
    s = s.replace(old, new)
p.write_text(s)
print("[*] Makefile patched.")
PYEOF
fi

# ---- 4. Prepare kernel build output dir ----
mkdir -p "$WORK/kernel_spark/out"
if [ -f "$KERNEL_CONFIG" ]; then
    cp "$KERNEL_CONFIG" "$WORK/kernel_spark/out/.config"
else
    echo "[!] WARNING: kernel_config.txt not found at $KERNEL_CONFIG"
    echo "    You MUST provide the stock kernel config for vermagic match."
    exit 1
fi

# ---- 5. Set up environment for Android kernel build ----
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export PATH="$CLANG_DIR/bin:$PATH"
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE="$CROSS_COMPILE"
export CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32"

# ---- 6. Prepare kernel headers (no full kernel build needed) ----
cd "$WORK/kernel_spark"
make O=out ARCH=arm64 olddefconfig
make O=out ARCH=arm64 prepare modules_prepare

# ---- 7. Build the module ----
echo "[*] Building wlan_drv_gen4m.ko..."
make -C "$WORK/kernel_spark" O="$WORK/kernel_spark/out" \
    M="$WORK/vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m" \
    KERNEL_OUT="$WORK/kernel_spark/out" \
    CONFIG_MTK_COMBO_WIFI_HIF=axi \
    MTK_COMBO_CHIP=CONNAC \
    WLAN_CHIP_ID=6765 \
    MTK_ANDROID_WMT=y \
    CONFIG_SUPPORT_SNIFFER_RADIOTAP=y \
    modules

# ---- 8. Locate output ----
PATCHED=$(find "$WORK/vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m" \
    -name 'wlan_drv_gen4m.ko' -type f | head -n1)

if [ -z "$PATCHED" ]; then
    echo "[!] ERROR: patched module not found in expected paths."
    exit 1
fi

mkdir -p "$OUT_DIR"
cp "$PATCHED" "$OUT_DIR/wlan_drv_gen4m.ko"
echo "[*] Patched module copied to $OUT_DIR/wlan_drv_gen4m.ko"

# ---- 9. Verify ----
echo "[*] Verification:"
strings "$OUT_DIR/wlan_drv_gen4m.ko" | grep vermagic
echo "---"
echo "Radiotap-related strings present in patched module:"
strings "$OUT_DIR/wlan_drv_gen4m.ko" | grep -iE 'radiotap|NL80211_IFTYPE_MONITOR|CFG_SUPPORT_SNIFFER_RADIOTAP|wlanoidSetIcsSniffer' | head -20

if [ -f "$STOCK_MODULE" ]; then
    echo "---"
    echo "Vermagic comparison:"
    STOCK_VM=$(strings "$STOCK_MODULE" | grep -o 'vermagic=[^ ]*' | head -1)
    PATCHED_VM=$(strings "$OUT_DIR/wlan_drv_gen4m.ko" | grep -o 'vermagic=[^ ]*' | head -1)
    echo "  Stock:    $STOCK_VM"
    echo "  Patched:  $PATCHED_VM"
    if [ "$STOCK_VM" = "$PATCHED_VM" ]; then
        echo "  [OK] Vermagic matches."
    else
        echo "  [WARN] Vermagic mismatch - module will fail to insmod."
    fi
fi

echo "[*] Done."
