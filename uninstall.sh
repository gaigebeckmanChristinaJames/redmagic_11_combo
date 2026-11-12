#!/system/bin/sh
# 卸载清理：恢复被本模块改过的系统状态，删除注入的 persist 属性
CFG="/data/adb/redmagic_11_combo"

# 1) 恢复被禁用的热区
if [ -f "$CFG/thermal_zones" ]; then
    while read -r n; do
        [ -n "$n" ] && echo enabled > "/sys/class/thermal/thermal_zone$n/mode" 2>/dev/null
    done < "$CFG/thermal_zones"
fi
# 2) 解锁云控目录（保留已清空的目录，不恢复被删的云控文件）
for d in /data/system/cube /data/system/cube/SM8650 /data/system/cube/SM8650/app /data/system/cube/app /data/system/cubeusercfg; do
    [ -d "$d" ] && chattr -i "$d" 2>/dev/null
done
# 3) 关闭充电分离
settings put global charge_separation_switch 0 2>/dev/null
# 4) 还原触控参数
[ -e /proc/touchscreen/tp_report_rate ] && { echo 1 > /proc/touchscreen/tp_report_rate 2>/dev/null; echo 0 > /proc/touchscreen/play_game 2>/dev/null; echo 1 > /proc/touchscreen/follow_hand_level 2>/dev/null; }
settings delete system touch_sampling_rate 2>/dev/null
# 5) 还原振动参数（模块保存的原值）
VB=/sys/class/leds/vibrator
[ -e /sys/class/leds/zte_vibrator/gain ] && VB=/sys/class/leds/zte_vibrator
for n in gain duration duration_aw vmax; do
    [ -f "$CFG/.vibe_$n" ] && [ -e "$VB/$n" ] && cat "$CFG/.vibe_$n" > "$VB/$n" 2>/dev/null
done
# 6) 删除注入的 persist 属性
if command -v resetprop >/dev/null 2>&1; then
    resetprop --delete persist.vendor.camera.sat.useztealgo 2>/dev/null
fi
# 7) 清理旧版指纹残留
rm -rf /data/adb/fingerprintpay 2>/dev/null
exit 0
