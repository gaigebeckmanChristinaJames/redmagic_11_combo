#!/system/bin/sh
# 把"当前已启用的功能"写进 module.prop 的 description，供管理器模块界面显示
case "$0" in */*) MODDIR=${0%/*} ;; *) MODDIR=$PWD ;; esac
CFG="/data/adb/redmagic_11_combo"
PROP="$MODDIR/module.prop"
[ -f "$PROP" ] || exit 0

n=0
out=""
add() {
  [ "$1" = "1" ] || return 0
  n=$((n + 1))
  if [ -z "$out" ]; then out="$2"; else out="$out、$2"; fi
}
on() { [ "$(cat "$CFG/$1" 2>/dev/null | tr -d ' \n')" = "1" ] && echo 1 || echo 0; }

add "$(on cam)"       "相机画质"
add "$(on chg)"       "充电加速"
add "$(on sep)"       "充电分离"
add "$(on fan)"       "风扇极速"
add "$(on fan_auto)"  "智能风扇"
add "$(on fankeep)"   "熄屏保扇"
if [ -e /proc/driver/micropump/enable ]; then
  add "$(on pump)"    "液冷调速"
fi
add "$(on thermal)"   "温控移除"
add "$(on cloud)"     "云控屏蔽"
add "$(on touch)"     "触控优化"
add "$(on vib)"       "振动增强"
add "$(on bak)"       "后台保活"
add "$(on gyro)"      "陀螺仪"
add "$(on nav)"       "导航定位"
add "$(on deep)"      "深度休眠"
add "$(on net)"       "电信增强"
add "$(on cmcc)"      "移动增强"
add "$(on unicom)"    "联通增强"
add "$(on wifi)"      "WiFi增强"
add "$(on bt)"        "蓝牙音质"
add "$(on lum)"       "亮度增强"
add "$(on bat)"       "电池体检"
add "$(on scene_auto)" "场景策略"
_bl=$(cat "$CFG/bat_limit" 2>/dev/null)
case "$_bl" in 80|90|100) add 1 "充电养护 $_bl%" ;; esac

if [ "$n" = "0" ]; then
  desc="已启用 0 项：所有增强均已关闭"
else
  desc="已启用 $n 项：$out"
fi

tmp="$PROP.tmp"
grep -v '^description=' "$PROP" > "$tmp" 2>/dev/null
printf '%s\n' "description=$desc" >> "$tmp"
mv "$tmp" "$PROP" 2>/dev/null
chmod 644 "$PROP" 2>/dev/null
exit 0
