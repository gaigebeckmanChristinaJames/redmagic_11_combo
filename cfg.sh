#!/system/bin/sh
# 设置持久化：模块目录 settings.txt 与运行目录双向同步
case "$0" in */*) MODDIR=${0%/*} ;; *) MODDIR=$PWD ;; esac
CFG="/data/adb/redmagic_11_combo"
ST="$MODDIR/settings.txt"
KEYS="cam chg sep net cmcc unicom wifi bt vib fan fan_auto fan_auto_level fan_auto_temp fankeep pump bak gyro nav deep touch cloud thermal lum bat fan_level pump_level charge_threshold vib_gain vib_duration vib_vmax touch_mode touch_apps perf_custom lum_th lum_peak lum_steps fan_screen_keep sep_auto thermal_zones ui_skin ui_theme fan_t3 fan_t4 fan_t5 fan_hyst scene_auto scene_apps scene_fan scene_touch night_quiet night_start night_end temp_wall bat_limit"
mkdir -p "$CFG" 2>/dev/null
[ -f "$ST" ] || : > "$ST" 2>/dev/null

case "$1" in
  dump)
    for k in $KEYS; do
      v=$(cat "$CFG/$k" 2>/dev/null | tr -d '\r' | tr '\n' ',' | sed 's/,$//')
      if [ -z "$v" ]; then
        v=$(grep -m1 "^$k=" "$ST" 2>/dev/null | sed "s/^$k=//")
      fi
      printf '%s=%s\n' "$k" "$v"
    done
    ;;
  set)
    k="$2"
    shift 2
    v="$*"
    case "$k" in ''|*[!a-zA-Z0-9_]*) exit 2 ;; esac
    mkdir -p "$CFG" 2>/dev/null
    printf '%s' "$v" > "$CFG/$k" 2>/dev/null
    tmp="$ST.tmp"
    grep -v "^$k=" "$ST" > "$tmp" 2>/dev/null
    printf '%s=%s\n' "$k" "$v" >> "$tmp"
    mv "$tmp" "$ST" 2>/dev/null
    ;;
  restore)
    [ -s "$ST" ] || exit 0
    while IFS='=' read -r k v; do
      case "$k" in ''|\#*|*[!a-zA-Z0-9_]*) continue ;; esac
      [ -f "$CFG/$k" ] || printf '%s' "$v" > "$CFG/$k" 2>/dev/null
    done < "$ST"
    ;;
  sync)
    tmp="$ST.tmp"
    : > "$tmp"
    for k in $KEYS; do
      v=$(cat "$CFG/$k" 2>/dev/null | tr -d '\r' | tr '\n' ',' | sed 's/,$//')
      if [ -z "$v" ]; then
        v=$(grep -m1 "^$k=" "$ST" 2>/dev/null | sed "s/^$k=//")
      fi
      [ -n "$v" ] && printf '%s=%s\n' "$k" "$v" >> "$tmp"
    done
    mv "$tmp" "$ST" 2>/dev/null
    chmod 644 "$ST" 2>/dev/null
    ;;
esac

# 每次设置变动后重算管理器里的“已启用 N 项”描述（关掉的功能会立即减掉）
[ -f "$MODDIR/desc.sh" ] && sh "$MODDIR/desc.sh" >/dev/null 2>&1
exit 0
