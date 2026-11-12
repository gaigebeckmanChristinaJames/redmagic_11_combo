#!/system/bin/sh
# 红魔调校台（ling_凌 & 粥总靓仔）· 诊断日志生成器
# 用法：sh log.sh   → 在 /sdcard/Download 生成 redmagic_log_<时间>.txt
MODDIR=${MODDIR:-${0%/*}}
CFG="/data/adb/redmagic_11_combo"
TS=$(date +%Y%m%d_%H%M%S)
LOG="${LOG:-/sdcard/Download/redmagic_log_$TS.txt}"
[ -n "$1" ] && LOG="$1"

{
echo "========== 红魔调校台 · 诊断日志 =========="
echo "生成时间  : $(date '+%Y-%m-%d %H:%M:%S')"
echo "模块版本  : $(grep -m1 '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)"
echo "模块目录  : $MODDIR"
echo "设备型号  : $(getprop ro.product.model)"
echo "市场名称  : $(getprop ro.product.marketname)"
echo "系统版本  : Android $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
echo "内核版本  : $(uname -r)"
echo "KSU       : $(getprop ro.kernel.version 2>/dev/null)"
echo "启动ID    : $(getprop ro.boot.boot_id 2>/dev/null)"
EN=0
for k in cam chg sep net cmcc unicom wifi bt vib fan fan_auto fankeep pump bak gyro nav deep touch cloud thermal lum bat; do
  [ "$(cat "$CFG/$k" 2>/dev/null | tr -d ' \n')" = "1" ] && EN=$((EN + 1))
done
TR=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
case "$TR" in ''|*[!0-9-]*) TR=-10 ;; esac
TT=$((TR / 10))
FL=$(cat /sys/kernel/fan/fan_speed_level 2>/dev/null)
echo "摘要      : $(getprop ro.product.model) | 电池 ${TT}℃ | 风扇 ${FL:-0} 档 | 已启用 ${EN} 项"
echo ""
echo "========== 开关状态 =========="
for k in cam chg sep net cmcc unicom wifi bt vib fan fankeep pump bak gyro nav deep touch cloud thermal; do
  v=$(cat "$CFG/$k" 2>/dev/null)
  [ -z "$v" ] && v="<无>"
  printf '  %-10s = %s\n' "$k" "$v"
done
echo ""
echo "========== 充电/温控/触控 =========="
echo "  充电分离阈值   = $(cat "$CFG/charge_threshold" 2>/dev/null)"
echo "  qcom restrict_cur = $(cat /sys/class/qcom-battery/restrict_cur 2>/dev/null)"
echo "  qcom restrict_chg = $(cat /sys/class/qcom-battery/restrict_chg 2>/dev/null)"
echo "  tp_report_rate = $(cat /proc/touchscreen/tp_report_rate 2>/dev/null)"
echo "  follow_hand    = $(cat /proc/touchscreen/follow_hand_level 2>/dev/null)"
echo "  sampling_rate  = $(settings get system touch_sampling_rate 2>/dev/null)"
echo "  已禁用热区     = $(tr '\n' ',' < "$CFG/thermal_zones" 2>/dev/null)"
echo ""
echo "========== 液冷/微泵 =========="
for n in enable freq speed; do
  echo "  $n = $(cat /proc/driver/micropump/$n 2>/dev/null)"
done
echo ""
echo "========== vendor 配置挂载 =========="
mount 2>/dev/null | grep 'vendor/etc' || echo "  (未检测到 bind 挂载)"
echo ""
echo "========== 风扇状态 =========="
echo "  fan_enable      = $(cat /sys/kernel/fan/fan_enable 2>/dev/null)"
echo "  fan_speed_level = $(cat /sys/kernel/fan/fan_speed_level 2>/dev/null)"
echo "  fan_speed_count = $(cat /sys/kernel/fan/fan_speed_count 2>/dev/null)"
ls -l /sys/kernel/fan 2>/dev/null | sed 's/^/  /'
echo ""
echo "========== 振动状态 =========="
echo "  gain     = $(cat /sys/class/leds/vibrator/gain 2>/dev/null)"
echo "  duration = $(cat /sys/class/leds/vibrator/duration 2>/dev/null)"
echo "  vmax     = $(cat /sys/class/leds/vibrator/vmax 2>/dev/null)"
echo ""
echo "========== 关键属性 =========="
echo "  sat.useztealgo           = $(getprop persist.vendor.camera.sat.useztealgo)"
echo "  radio.band_priority_5g   = $(getprop persist.vendor.radio.band_priority_5g)"
echo "  radio.cell_reselect_hyst = $(getprop persist.vendor.radio.cell_reselect_hyst)"
echo ""
echo "========== 守护进程 =========="
ps -A -o PID,ARGS 2>/dev/null | grep -E 'sh /dev/tmp|sh /data/local/tmp' | grep -v grep | sed 's/^/  /' || echo "  (未检测到)"
echo ""
echo "========== 解密脚本文件 =========="
ls -l /dev/tmp/*.s /data/local/tmp/*.s 2>/dev/null | sed 's/^/  /' || echo "  (无)"
echo ""
echo "========== 风扇调试日志（最近 40 行）=========="
tail -40 "$CFG/fan_debug.log" 2>/dev/null | sed 's/^/  /' || echo "  (无调试日志)"
echo ""
echo "========== 内核参数 =========="
echo "  dirty_ratio    = $(cat /proc/sys/vm/dirty_ratio 2>/dev/null)"
echo "  swappiness     = $(cat /proc/sys/vm/swappiness 2>/dev/null)"
echo ""
echo "========== KSU 最近错误（20 行）=========="
tail -20 /data/adb/ksu/log/logcat.log 2>/dev/null | grep -iE 'redmagic|rmc|error|失败' | sed 's/^/  /' || echo "  (无)"
echo ""
echo "================ 日志结束 ================"
} > "$LOG" 2>&1

chmod 644 "$LOG" 2>/dev/null
chown 1023:1023 "$LOG" 2>/dev/null
sync 2>/dev/null
echo "$LOG"
