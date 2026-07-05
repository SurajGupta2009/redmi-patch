# Redmi Pad SE 8.7 4G (`spark`) — Built-in Wi-Fi Monitor Mode (RX)

> **Status:** Cloud build pipeline + Magisk overlay module for the **internal MediaTek
> CONNAC Wi-Fi chip (MT8786 / `wlan_drv_gen4m.ko`)** on the
> **Redmi Pad SE 8.7 4G India (24076RP19I, codename `spark`)**.
> Enables **radiotap monitor-mode RX** for authorized lab/owned-network testing.
> Injection (TX) is a separate, second-stage task.

## What this does

The stock `wlan_drv_gen4m.ko` on the `spark` device is built without
`CFG_SUPPORT_SNIFFER_RADIOTAP`. As a result, `iw list` reports:

```
Supported interface modes:
    * IBSS
    * managed
    * AP
    * P2P-client
    * P2P-GO
```

with no `* monitor`. The internal MediaTek sniffer command path
(`priv_driver_sniffer` / `wlanoidSetIcsSniffer`) is present in the
module but unreachable from Linux cfg80211.

This project rebuilds the module from the official MiCode source
(`MiCode/MTK_kernel_modules` branch `spark-s-oss`) with
`CFG_SUPPORT_SNIFFER_RADIOTAP=1` forced on, then ships it as a
**Magisk overlay** so `/vendor/lib/modules/wlan_drv_gen4m.ko` is
replaced without touching the vendor partition.

After install:

```
iw list | grep -A30 "Supported interface modes"
* monitor
```

and a real monitor capture produces a pcap with
Wireshark link type **`IEEE802_11_RADIO`** (radiotap).

## Repo layout

```
.
├── .github/workflows/build-monitor-module.yml   # one-click cloud build
├── patches/
│   └── 0001-force-radiotap-monitor.patch        # the actual source patch
├── magisk-module/
│   ├── module.prop
│   ├── sepolicy.rule
│   └── customize.sh
├── scripts/
│   ├── build_kernel_module.sh                   # local PC build
│   ├── package_magisk_module.sh                 # zip the .ko into a Magisk module
│   └── on_device_verify.sh                      # post-install checks (run on tablet)
└── README.md
```

## Two build paths

### Path A — Cloud (recommended, one click)

1. Fork or import this directory into a new GitHub repo.
2. Push to GitHub.
3. **Actions → Build wlan_drv_gen4m.ko (radiotap monitor) → Run workflow.**
4. Download the artifact `redmi-wifi-monitor-spark-build.zip` which contains:
   - `wlan_drv_gen4m.ko` (the patched module)
   - `redmi-wifi-monitor-spark-YYYYMMDD.zip` (ready-to-flash Magisk module)
5. Push the Magisk zip to the tablet:
   ```sh
   adb push redmi-wifi-monitor-spark-*.zip /sdcard/Download/
   ```
6. **Magisk app → Modules → Install from storage → select zip → Reboot.**

### Path B — Local Linux build

```bash
sudo apt install -y git bc bison flex make python3 python3-pip \
  libssl-dev libelf-dev dwarves build-essential unzip rsync cpio xz-utils

# Get Android prebuilt clang
mkdir -p ~/toolchains && cd ~/toolchains
curl -L -o clang.tgz \
  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r487747c.tar.gz
tar -xzf clang.tgz

# Put your stock kernel_config.txt next to where the build expects it
mkdir -p ~/redmi_monitor_build
cp /path/to/your/kernel_config.txt ~/redmi_monitor_build/

# Build
chmod +x scripts/*.sh
./scripts/build_kernel_module.sh
./scripts/package_magisk_module.sh out/wlan_drv_gen4m.ko
```

## On-device verification (after install + reboot)

```sh
su
sh /path/to/on_device_verify.sh
```

Look for:

```
* monitor
```

under `Supported interface modes` in `iw list`.

## Enabling monitor mode and capturing

```sh
su
svc wifi disable
sleep 2
ip link set wlan0 down
iw dev wlan0 set type monitor        # this is the moment of truth
ip link set wlan0 up
iw dev wlan0 set channel 6 HT20

tcpdump -i wlan0 -s 0 -w /sdcard/Download/spark_monitor_ch6.pcap
```

Pull and inspect in Wireshark:

```sh
adb pull /sdcard/Download/spark_monitor_ch6.pcap
```

**Success:** Wireshark shows `Link-layer type: IEEE802_11_RADIO` (radiotap header
present with rate/SSI/antenna fields).

**Failure modes:**

- `Operation not supported on transport endpoint (-95)` — the overlay did not load
  the patched module. Verify with
  `strings /vendor/lib/modules/wlan_drv_gen4m.ko | grep -i radiotap` and
  `lsmod | grep wlan`.
- pcap link type is `Ethernet` instead of `IEEE802_11_RADIO` — the build
  enabled monitor at the cfg80211 level but the RX path is still using
  the Ethernet translation. Need to inspect `nic/nic_rx.c` and
  `nic/radiotap.c` for the conditional path that wasn't taken.
- Module fails to load with `disagrees about version of symbol` or
  `invalid module format` — vermagic mismatch. Re-check kernel
  config / kernel version.

## Rollback

```sh
su
rm -rf /data/adb/modules/redmi-wifi-monitor-spark
reboot
```

## Legal

For **authorized security testing on your own networks / lab** only.
Capturing Wi-Fi traffic on networks you do not own or have explicit
written permission to test is illegal in most jurisdictions.
