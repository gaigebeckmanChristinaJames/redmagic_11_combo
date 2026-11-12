#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 红魔 11 系列综合模块后台服务：独立实现
# 只依赖 sysfs/proc 节点路径与公开的 Android 设置项

MOD_DIR="/data/adb/modules/redmagic_11_combo"
STATE_DIR="/data/adb/redmagic_11_combo"
FAN_LEVEL_NODE="/sys/kernel/fan/fan_speed_level"
FAN_SWITCH_NODE="/sys/kernel/fan/fan_enable"
PUMP_DIR="/proc/driver/micropump"
BAT_DIR="/sys/class/power_supply/battery"
QCOM_DIR="/sys/class/qcom-battery"
TOUCH_DIR="/proc/touchscreen"
VIB_DIR="/sys/class/leds/vibrator"
THERM_LIST="$STATE_DIR/thermal_disabled.txt"

mkdir -p "$STATE_DIR" 2>/dev/null
[ -f "$MOD_DIR/config/fan" ] && [ ! -f "$STATE_DIR/fan" ] && cp -a "$MOD_DIR/config/." "$STATE_DIR/" 2>/dev/null

# 等系统启动完成再接管节点
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do sleep 5; done
sleep 8

# 单实例：记录 pid 与 boot_id，热更新时只杀同一次开机的旧进程
PID_FILE="$STATE_DIR/.service.pid"
BOOT_NOW=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ -s "$PID_FILE" ]; then
    OLD_PID=$(sed -n '1p' "$PID_FILE" 2>/dev/null)
    OLD_BOOT=$(sed -n '2p' "$PID_FILE" 2>/dev/null)
    if [ "$OLD_BOOT" = "$BOOT_NOW" ] && [ -n "$OLD_PID" ] && [ -d "/proc/$OLD_PID" ]; then
        kill "$OLD_PID" 2>/dev/null
        sleep 1
        kill -9 "$OLD_PID" 2>/dev/null
    fi
fi
printf '%s\n%s\n' "$$" "$BOOT_NOW" > "$PID_FILE" 2>/dev/null
trap 'rm -f "$PID_FILE" 2>/dev/null' EXIT INT TERM

# ---------- 基础工具 ----------
read_state() { cat "$STATE_DIR/$1" 2>/dev/null; }

enabled() { [ "$(read_state "$1")" = "1" ]; }

as_int() {
    # $1=值 $2=默认 $3=最小 $4=最大
    _v="$1"
    case "$_v" in ''|*[!0-9-]*) _v="$2" ;; esac
    [ "$_v" -lt "$3" ] 2>/dev/null && _v="$3"
    [ "$_v" -gt "$4" ] 2>/dev/null && _v="$4"
    printf '%s' "$_v"
}

node_write() {
    # $1=节点  $2=值  $3=写完是否 444 锁定
    [ -e "$1" ] || return 1
    chmod 644 "$1" 2>/dev/null
    printf '%s' "$2" > "$1" 2>/dev/null || return 1
    [ "$3" = "lock" ] && chmod 444 "$1" 2>/dev/null
    return 0
}

node_read() { cat "$1" 2>/dev/null; }

# ---------- 风扇 ----------
fan_set_level() {
    # $1=档位 1..6
    _lv=$(as_int "$1" 5 1 6)
    node_write "$FAN_SWITCH_NODE" 1 || return 1
    node_write "$FAN_LEVEL_NODE" "$_lv" lock
}

fan_off() {
    node_write "$FAN_SWITCH_NODE" 0
}

fan_current_level() {
    _l=$(node_read "$FAN_LEVEL_NODE")
    case "$_l" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$_l" ;; esac
}

# 计算曲线目标档位（含回滞），0 表示停转
fan_curve_target() {
    _temp="$1"      # 摄氏度
    _now="$2"       # 当前档位
    _t3=$(as_int "$(read_state fan_t3)" 30 20 60)
    _t4=$(as_int "$(read_state fan_t4)" 35 20 70)
    _t5=$(as_int "$(read_state fan_t5)" 40 20 80)
    _hy=$(as_int "$(read_state fan_hyst)" 2 0 8)

    _goal=0
    [ "$_temp" -ge "$_t3" ] && _goal=3
    [ "$_temp" -ge "$_t4" ] && _goal=4
    [ "$_temp" -ge "$_t5" ] && _goal=5

    if [ "$_now" -ge 3 ] && [ "$_goal" -lt "$_now" ]; then
        case "$_now" in
            5) _edge="$_t5" ;;
            4) _edge="$_t4" ;;
            *) _edge="$_t3" ;;
        esac
        [ "$_temp" -ge $((_edge - _hy)) ] && _goal="$_now"
    fi
    printf '%s' "$_goal"
}

# ---------- 液冷 ----------
pump_set() {
    _lv=$(as_int "$1" 4 1 4)
    case "$_lv" in
        1) _spd=40 ;;
        2) _spd=60 ;;
        3) _spd=80 ;;
        *) _spd=90 ;;
    esac
    node_write "$PUMP_DIR/enable" 1
    node_write "$PUMP_DIR/freq" 4
    node_write "$PUMP_DIR/speed" "$_spd"
}

# ---------- 振动 ----------
vib_node=""
pick_vib() {
    if [ -e /sys/class/leds/zte_vibrator/gain ]; then
        vib_node="/sys/class/leds/zte_vibrator"
    else
        vib_node="$VIB_DIR"
    fi
}

vib_apply() {
    pick_vib
    _g=$(as_int "$(read_state vib_gain)" 168 0 255)
    _d=$(as_int "$(read_state vib_duration)" 18 1 100)
    _v=$(as_int "$(read_state vib_vmax)" 128 0 255)
    # 第一次应用前备份原值，关闭时还原
    for _n in gain duration duration_aw vmax; do
        [ -e "$vib_node/$_n" ] && [ ! -f "$STATE_DIR/.vib_orig_$_n" ] && \
            node_read "$vib_node/$_n" > "$STATE_DIR/.vib_orig_$_n" 2>/dev/null
    done
    [ -e "$vib_node/gain" ] && node_write "$vib_node/gain" "$(printf '0x%x' "$_g")"
    [ -e "$vib_node/vmax" ] && node_write "$vib_node/vmax" "$(printf '0x%x' "$_v")"
    [ -e "$vib_node/duration" ] && node_write "$vib_node/duration" "$_d"
    [ -e "$vib_node/duration_aw" ] && node_write "$vib_node/duration_aw" "$(printf '0x%x' "$_d")"
    [ -e "$vib_node/cont_brk_time" ] && node_write "$vib_node/cont_brk_time" "0x01"
    [ -e "$vib_node/cont_wait_num" ] && node_write "$vib_node/cont_wait_num" "0x03"
    settings put global vibration_strength_mode 2 2>/dev/null
    settings put global game_assist_trigger_space_vibrate 1 2>/dev/null
    settings put global tencent_game_haptic_state 1 2>/dev/null
    settings put global game_assist_enable_plugin_vibrate 1 2>/dev/null
    settings put system haptic_feedback_enabled 1 2>/dev/null
}

vib_restore() {
    pick_vib
    for _n in gain duration duration_aw vmax; do
        [ -f "$STATE_DIR/.vib_orig_$_n" ] && [ -e "$vib_node/$_n" ] && \
            node_write "$vib_node/$_n" "$(cat "$STATE_DIR/.vib_orig_$_n")"
    done
}

# ---------- 触控 ----------
touch_enable() {
    node_write "$TOUCH_DIR/tp_report_rate" 4
    node_write "$TOUCH_DIR/play_game" 1
    node_write "$TOUCH_DIR/follow_hand_level" 4
    settings put system touch_sampling_rate 960 2>/dev/null
}

touch_disable() {
    node_write "$TOUCH_DIR/tp_report_rate" 1
    node_write "$TOUCH_DIR/play_game" 0
    node_write "$TOUCH_DIR/follow_hand_level" 1
    settings delete system touch_sampling_rate 2>/dev/null
}

# ---------- 前台应用 ----------
foreground_pkg() {
    _a=$(dumpsys activity activities 2>/dev/null | grep -m1 -E 'mResumedActivity|topResumedActivity')
    _p=$(printf '%s' "$_a" | sed -n 's/.*[ ]\([A-Za-z0-9_.]*\)\/.*/\1/p' | head -1)
    if [ -z "$_p" ]; then
        _w=$(dumpsys window 2>/dev/null | grep -m1 'mCurrentFocus')
        _p=$(printf '%s' "$_w" | sed -n 's/.*[ ]\([A-Za-z0-9_.]*\)\/.*/\1/p' | head -1)
    fi
    printf '%s' "$_p"
}

pkg_in_list() {
    # $1=包名  $2=逗号/空格分隔列表
    _hay=$(printf '%s' "$2" | tr ',' ' ')
    for _item in $_hay; do
        [ -n "$_item" ] && [ "$1" = "$_item" ] && return 0
        case "$1" in *"$_item"*) return 0 ;; esac
    done
    return 1
}

# ---------- 温控 ----------
thermal_disable() {
    : > "$THERM_LIST" 2>/dev/null
    for _zone in /sys/class/thermal/thermal_zone*; do
        _type=$(node_read "$_zone/type")
        case "$_type" in
            *bcl*|*ibat*|*gpuss*|*socd*|*aoss*|*pm8550*|*pm7325*|*cpu-*|*gpu*)
                if [ "$(node_read "$_zone/mode")" != "disabled" ]; then
                    node_write "$_zone/mode" disabled && \
                        printf '%s\n' "${_zone##*thermal_zone}" >> "$THERM_LIST"
                fi ;;
        esac
    done
    for _f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq \
              /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq \
              /sys/class/kgsl/kgsl-3d0/devfreq/max_freq \
              /sys/class/kgsl/kgsl-3d0/devfreq/min_freq; do
        chmod 644 "$_f" 2>/dev/null
    done
}

thermal_restore() {
    [ -f "$THERM_LIST" ] || return 0
    while read -r _id; do
        [ -n "$_id" ] && node_write "/sys/class/thermal/thermal_zone$_id/mode" enabled
    done < "$THERM_LIST"
    rm -f "$THERM_LIST"
}

# ---------- 云控 ----------
cloud_block() {
    for _d in /data/system/cube /data/system/cube/SM8650 /data/system/cube/SM8650/app \
              /data/system/cube/app /data/system/cubeusercfg; do
        [ -d "$_d" ] || continue
        chattr -i "$_d" 2>/dev/null
        for _f in "$_d"/*; do
            [ -e "$_f" ] || continue
            chattr -i "$_f" 2>/dev/null
            rm -rf "$_f"
        done
        chattr +i "$_d" 2>/dev/null
    done
}

# ---------- 网络 ----------
tcp_tune() {
    node_write /proc/sys/net/ipv4/tcp_fastopen 3
    node_write /proc/sys/net/ipv4/tcp_low_latency 1
    node_write /proc/sys/net/ipv4/tcp_moderate_rcvbuf 1
    node_write /proc/sys/net/ipv4/tcp_rmem "4096 87380 8388608"
    node_write /proc/sys/net/ipv4/tcp_wmem "4096 65536 8388608"
}

vm_tune() {
    node_write /proc/sys/vm/dirty_ratio 20
    node_write /proc/sys/vm/dirty_background_ratio 10
    node_write /proc/sys/vm/swappiness 60
    for _q in /sys/block/sd*/queue/read_ahead_kb; do
        node_write "$_q" 128
    done
}

# ---------- 相机 ----------
camera_bind() {
    case "$(getprop ro.product.model)" in
        NX799J*|NX809J*|NX79*|NX80*) ;;
        *) return 0 ;;
    esac
    for _rel in vendor/etc/camera/camxoverridesettings.txt \
                vendor/etc/camera/mfnr_network_denoise_config.xml \
                vendor/etc/camera/adaptive_shutter_config.xml; do
        [ -f "/$_rel" ] || continue
        mount | grep -q " /$_rel " && continue
        if enabled cam; then
            _src="$MOD_DIR/$_rel"
        else
            _src="$MOD_DIR/orig/$(basename "$_rel")"
        fi
        [ -f "$_src" ] || continue
        _ctx=$(stat -c %C "/$_rel" 2>/dev/null)
        case "$_ctx" in ''|'?'|'??') ;; *) chcon "$_ctx" "$_src" 2>/dev/null ;; esac
        mount -o bind "$_src" "/$_rel" 2>/dev/null
    done
}

# ---------- 充电 ----------
charge_unlock() {
    [ "$(settings get global charge_separation_switch 2>/dev/null)" = "1" ] && return 0
    [ "$(node_read "$QCOM_DIR/charging_enabled")" = "0" ] && return 0
    [ "$(node_read "$QCOM_DIR/battery_charging_enabled")" = "0" ] && return 0
    node_write "$QCOM_DIR/restrict_cur" 0
    node_write "$QCOM_DIR/restrict_chg" 0
    node_write "$QCOM_DIR/charging_enabled" 1
    node_write "$QCOM_DIR/battery_charging_enabled" 1
    [ -e "$QCOM_DIR/screen_is_on" ] && node_write "$QCOM_DIR/screen_is_on" 0
}

battery_percent() {
    _c=$(node_read "$BAT_DIR/capacity")
    case "$_c" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$_c" ;; esac
}

external_power() {
    _dump=$(dumpsys battery 2>/dev/null)
    printf '%s' "$_dump" | grep -qE 'AC powered: true|USB powered: true|Wireless powered: true'
}

charge_window() {
    _cap=$(as_int "$(read_state bat_limit)" 100 80 100)
    [ "$_cap" -ge 100 ] && return 0
    for _n in "$BAT_DIR/charge_control_end_threshold" "$BAT_DIR/charge_stop_threshold"; do
        node_write "$_n" "$_cap"
    done
}

sep_policy() {
    enabled sep || { rm -f "$STATE_DIR/sep_auto"; return 0; }
    _th=$(as_int "$(read_state charge_threshold)" 100 20 100)
    _lv=$(battery_percent)
    _cur=$(settings get global charge_separation_switch 2>/dev/null)
    [ "$_cur" != "1" ] && rm -f "$STATE_DIR/sep_auto"
    external_power || return 0
    if [ "$_lv" -ge "$_th" ]; then
        [ "$_cur" != "1" ] && { settings put global charge_separation_switch 1 2>/dev/null; : > "$STATE_DIR/sep_auto"; }
    elif [ "$_lv" -le $((_th - 3)) ]; then
        [ "$_cur" = "1" ] && [ -f "$STATE_DIR/sep_auto" ] && {
            settings put global charge_separation_switch 0 2>/dev/null
            rm -f "$STATE_DIR/sep_auto"
        }
    fi
}

# ---------- 频率 ----------
cpu_gpu_paths() {
    printf '%s\n' \
        /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq \
        /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq \
        /sys/class/kgsl/kgsl-3d0/devfreq/max_freq \
        /sys/class/kgsl/kgsl-3d0/devfreq/min_freq \
        /sys/class/kgsl/kgsl-3d0/max_clock_mhz
}

perf_custom_apply() {
    _f="$STATE_DIR/perf_custom"
    [ -f "$_f" ] || return 0
    _c0=$(cut -d'|' -f1 "$_f")
    _c4=$(cut -d'|' -f2 "$_f")
    _c7=$(cut -d'|' -f3)
    _gpu=$(cut -d'|' -f4 "$_f")
    _gov=$(cut -d'|' -f5 "$_f")
    for _p in $(cpu_gpu_paths); do chmod 644 "$_p" 2>/dev/null; done
    [ -n "$_c0" ] && node_write /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq "$_c0" && \
        node_write /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq "$_c0"
    [ -n "$_c4" ] && node_write /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq "$_c4" && \
        node_write /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq "$_c4"
    [ -n "$_c7" ] && node_write /sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq "$_c7" && \
        node_write /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq "$_c7"
    if [ -n "$_gpu" ]; then
        node_write /sys/class/kgsl/kgsl-3d0/devfreq/max_freq "$_gpu"
        node_write /sys/class/kgsl/kgsl-3d0/devfreq/min_freq "$_gpu"
        node_write /sys/class/kgsl/kgsl-3d0/max_clock_mhz "$((_gpu / 1000000))"
        node_write /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel 0
    fi
    [ -n "$_gov" ] && for _c in /sys/devices/system/cpu/cpu*/cpufreq; do
        node_write "$_c/scaling_governor" "$_gov"
    done
}

perf_preset_apply() {
    _mode=$(read_state perf)
    [ -n "$_mode" ] || return 0
    case "$(getprop ro.product.model)" in
        NX799J*|NX809J*|NX789J*) _hz=144 ;;
        NX769J*) _hz=120 ;;
        *) _hz=144 ;;
    esac
    case "$_mode" in
        turbo) _gov=performance; _ref="$_hz" ;;
        save) _gov=powersave; _ref=60 ;;
        *) _gov=walt; _ref="$_hz" ;;
    esac
    for _c in /sys/devices/system/cpu/cpu*/cpufreq; do
        node_write "$_c/scaling_governor" "$_gov"
    done
    settings put system peak_refresh_rate "$_ref" 2>/dev/null
}

# ---------- 夜间 ----------
in_night_window() {
    _s=$(read_state night_start); _e=$(read_state night_end)
    _s=${_s:-23:00}; _e=${_e:-07:00}
    _s=${_s//:/}; _e=${_e//:/}
    _s=$(as_int "$_s" 2300 0 2359)
    _e=$(as_int "$_e" 700 0 2359)
    _now=$(date +%H%M)
    if [ "$_s" -le "$_e" ]; then
        [ "$_now" -ge "$_s" ] && [ "$_now" -lt "$_e" ]
    else
        [ "$_now" -ge "$_s" ] || [ "$_now" -lt "$_e" ]
    fi
}

# ================= 启动一次性应用 =================
vm_tune
camera_bind
if enabled net || enabled cmcc || enabled unicom; then tcp_tune; fi
if enabled fan; then fan_set_level "$(read_state fan_level)"; fi
if enabled pump; then pump_set "$(read_state pump_level)"; fi
if enabled cloud; then cloud_block; fi
if enabled thermal; then thermal_disable; else thermal_restore; fi
if enabled vib; then vib_apply; else vib_restore; fi
if enabled touch; then
    if [ "$(read_state touch_mode)" = "perapp" ]; then touch_disable; else touch_enable; fi
fi
charge_window
perf_custom_apply
perf_preset_apply

enabled bak && settings put global app_standby_enabled 0 2>/dev/null
enabled gyro && settings put global game_assist_enable_plugin_sensor_operation 1 2>/dev/null
if enabled nav; then
    settings put global assisted_gps_enabled 1 2>/dev/null
    settings put global enable_gnss_raw_meas_full_tracking 1 2>/dev/null
fi
if enabled bt; then sh "$MOD_DIR/bttool.sh" on >/dev/null 2>&1; fi
if enabled deep; then
    settings put global device_idle_constants "inactive_to=30000,light_after_inactive_to=30000,light_idle_to=60000" 2>/dev/null
fi

# 亮度守护（LuminPro，MIT，见 NOTICE）
LUM_BIN="$MOD_DIR/lumin/bin/luminpro"
if [ -x "$LUM_BIN" ] && [ ! -f "$MOD_DIR/lumin/skip" ]; then
    chmod 755 "$LUM_BIN" 2>/dev/null
    _lum=$(read_state lum_th)
    _peak=$(read_state lum_peak)
    _steps=$(read_state lum_steps)
    _lum=$(as_int "$_lum" 1900 500 4000)
    _peak=$(as_int "$_peak" 2300 500 5000)
    _steps=$(as_int "$_steps" 50 1 100)
    _cur=$("$LUM_BIN" config read 2>/dev/null | sed -n 's/.*"ui_max_bri":[0-9]*/&/p')
    case "$_cur" in *:0|"") "$LUM_BIN" config patch "{\"ui_max_bri\":$_lum,\"max_bri\":$_peak,\"steps_num\":$_steps}" >/dev/null 2>&1 ;; esac
    ( sleep 240; pgrep -f "luminpro daemon" >/dev/null 2>&1 || "$LUM_BIN" daemon >/dev/null 2>&1 & ) &
fi

# ================= 周期调度 =================
_sec=0
_scene_on=0
_scene_touch=0
_touch_on=0
_prev_fan_saved=0

while true; do
    _sec=$((_sec + 1))

    # 熄屏保持风扇 / 关机停扇
    if [ $((_sec % 5)) -eq 0 ]; then
        _sd=$(getprop sys.shutdown.requested 2>/dev/null)
        if [ -n "$_sd" ] || [ "$(getprop sys.powerctl 2>/dev/null)" = "shutdown" ]; then
            fan_off
        else
            _bl=$(node_read /sys/class/backlight/panel0-backlight/brightness)
            if [ "$_bl" = "0" ] && { [ -f "$STATE_DIR/fan_screen_keep" ] || enabled fankeep; } && enabled fan; then
                fan_set_level "$(read_state fan_level)"
            fi
        fi
    fi

    # 触控按应用
    if [ $((_sec % 2)) -eq 0 ] && enabled touch && [ "$(read_state touch_mode)" = "perapp" ]; then
        _fg=$(foreground_pkg)
        if [ -n "$_fg" ] && pkg_in_list "$_fg" "$(read_state touch_apps)"; then
            [ "$_touch_on" = "1" ] || { touch_enable; _touch_on=1; }
        else
            [ "$_touch_on" = "1" ] && { touch_disable; _touch_on=0; }
        fi
    fi

    # 场景识别（8 秒）
    if [ $((_sec % 8)) -eq 0 ] && enabled scene_auto; then
        _fg=$(foreground_pkg)
        if [ -n "$_fg" ] && pkg_in_list "$_fg" "$(read_state scene_apps)"; then
            if [ "$_scene_on" != "1" ]; then
                _scene_on=1
                fan_current_level > "$STATE_DIR/scene_prev_fan" 2>/dev/null
                _prev_fan_saved=1
                if [ "$(read_state scene_touch)" = "1" ]; then touch_enable; _scene_touch=1; fi
            fi
        elif [ "$_scene_on" = "1" ]; then
            _scene_on=0
            if [ "$_scene_touch" = "1" ]; then
                _scene_touch=0
                if enabled touch && [ "$(read_state touch_mode)" = "perapp" ]; then
                    if [ -n "$_fg" ] && pkg_in_list "$_fg" "$(read_state touch_apps)"; then touch_enable; else touch_disable; fi
                elif enabled touch; then
                    touch_enable
                fi
            fi
        fi
    elif ! enabled scene_auto; then
        _scene_on=0
    fi

    # 风扇决策（5 秒）
    if [ $((_sec % 5)) -eq 0 ] && [ -e "$FAN_LEVEL_NODE" ]; then
        _t=$(node_read "$BAT_DIR/temp")
        _t=$(as_int "$_t" 300 0 900)
        _t=$((_t / 10))
        _now=$(fan_current_level)

        _goal=""
        [ "$_scene_on" = "1" ] && _goal=$(as_int "$(read_state scene_fan)" 5 3 6)
        if [ -z "$_goal" ] && enabled night_quiet && in_night_window; then _goal=0; fi
        _wall=$(as_int "$(read_state temp_wall)" 0 0 80)
        if [ "$_wall" -gt 0 ] && [ "$_t" -ge "$_wall" ]; then _goal=5; fi
        if [ -z "$_goal" ] && enabled fan_auto; then
            _goal=$(fan_curve_target "$_t" "$_now")
        fi
        if [ -z "$_goal" ] && [ "$_prev_fan_saved" = "1" ]; then
            _pf=$(cat "$STATE_DIR/scene_prev_fan" 2>/dev/null)
            case "$_pf" in 1|2|3|4|5|6) _goal="$_pf" ;; esac
            _prev_fan_saved=0
        fi

        printf '%s\n' "${_goal:-0}" > "$STATE_DIR/fan_auto_level" 2>/dev/null
        printf '%s\n' "$_t" > "$STATE_DIR/fan_auto_temp" 2>/dev/null

        if [ -n "$_goal" ]; then
            if [ "$_goal" = "0" ]; then
                [ "$(node_read "$FAN_SWITCH_NODE")" = "1" ] && fan_off
            elif [ "$(node_read "$FAN_SWITCH_NODE")" != "1" ] || [ "$_now" != "$_goal" ]; then
                fan_set_level "$_goal"
                [ "$(node_read "$FAN_LEVEL_NODE")" = "$_goal" ] || \
                    su system -c "echo 1 > $FAN_SWITCH_NODE; echo $_goal > $FAN_LEVEL_NODE; chmod 444 $FAN_LEVEL_NODE" 2>/dev/null
            fi
        fi
    fi

    # 充电加速（30 秒）
    [ $((_sec % 30)) -eq 0 ] && enabled chg && charge_unlock

    # 充电分离（6 秒）
    [ $((_sec % 6)) -eq 0 ] && sep_policy

    # 频率回写（30 秒）
    [ $((_sec % 30)) -eq 0 ] && perf_custom_apply

    # 充电上限（60 秒）
    [ $((_sec % 60)) -eq 0 ] && charge_window

    sleep 1
done
