#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 红魔 11 系列综合模块：开机早期挂载与运营商属性（独立实现）

MOD_DIR="/data/adb/modules/redmagic_11_combo"
STATE_DIR="/data/adb/redmagic_11_combo"
MOUNT_LOG="$STATE_DIR/early_mount.log"

mkdir -p "$STATE_DIR" 2>/dev/null
[ -f "$MOD_DIR/config/fan" ] && [ ! -f "$STATE_DIR/fan" ] && cp -a "$MOD_DIR/config/." "$STATE_DIR/" 2>/dev/null

state_on() {
    _fallback=1
    [ "$1" = "cam" ] && _fallback=0
    _v=$(cat "$STATE_DIR/$1" 2>/dev/null)
    [ -z "$_v" ] && _v="$_fallback"
    [ "$_v" = "1" ]
}

put_prop() {
    # $1=key $2=value
    if command -v resetprop >/dev/null 2>&1; then
        resetprop -n "$1" "$2" 2>/dev/null
    else
        setprop "$1" "$2" 2>/dev/null
    fi
}

# ---------- 早期相机挂载 ----------
: > "$MOUNT_LOG" 2>/dev/null
printf 'early mount run: %s\n' "$(date)" >> "$MOUNT_LOG" 2>/dev/null

for _rel in \
    vendor/etc/camera/camxoverridesettings.txt \
    vendor/etc/camera/mfnr_network_denoise_config.xml \
    vendor/etc/camera/adaptive_shutter_config.xml
do
    _dst="/$_rel"
    [ -f "$_dst" ] || { printf 'missing target: %s\n' "$_rel" >> "$MOUNT_LOG"; continue; }
    case "$(getprop ro.product.model)" in
        NX799J*|NX809J*|NX79*|NX80*) ;;
        *) printf 'model skip: %s\n' "$_rel" >> "$MOUNT_LOG"; continue ;;
    esac
    if state_on cam; then
        _src="$MOD_DIR/$_rel"
    else
        _src="$MOD_DIR/orig/$(basename "$_rel")"
    fi
    [ -f "$_src" ] || { printf 'no source: %s\n' "$_rel" >> "$MOUNT_LOG"; continue; }
    if mount | grep -q " $_dst "; then
        printf 'already mounted: %s\n' "$_rel" >> "$MOUNT_LOG"
        continue
    fi
    _ctx=$(stat -c %C "$_dst" 2>/dev/null)
    case "$_ctx" in ''|'?'|'??') ;; *) chcon "$_ctx" "$_src" 2>/dev/null ;; esac
    if mount -o bind "$_src" "$_dst" 2>>"$MOUNT_LOG"; then
        printf 'mounted: %s\n' "$_rel" >> "$MOUNT_LOG"
    else
        printf 'mount failed: %s\n' "$_rel" >> "$MOUNT_LOG"
    fi
done

# ---------- SAT 多摄算法 ----------
put_prop persist.vendor.camera.sat.useztealgo 1

# ---------- 运营商属性 ----------
radio_profile() {
    # $1=5G 频段 $2=LTE 频段 $3=重选迟滞 $4=NR 重选门限 $5=NR 服务门限
    put_prop persist.vendor.radio.band_priority_5g "$1"
    put_prop persist.vendor.radio.band_priority_lte "$2"
    put_prop persist.vendor.radio.cell_reselect_hyst "$3"
    put_prop persist.vendor.radio.nr_resel_min_rssi "$4"
    put_prop persist.vendor.radio.nr_serving_cell_threshold "$5"
    put_prop persist.vendor.radio.lte_nr_handover_hysteresis 4
    put_prop persist.vendor.radio.signal_meas_period 3000
    put_prop persist.vendor.radio.lte_rx_gain_offset 3
}

if state_on net; then
    radio_profile "n78,n1,n5" "B1,B3,B5" 1 -120 -112
else
    radio_profile "n78,n41,n1" "B3,B1,B5" 2 -118 -110
fi
state_on cmcc && radio_profile "n41,n28,n79,n1" "B3,B8,B39,B41,B40" 1 -122 -114
state_on unicom && radio_profile "n1,n78,n8" "B1,B3,B8" 1 -122 -114

exit 0
