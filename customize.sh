#!/system/bin/sh
# 红魔11系列优化模块 · 安装脚本
# ①旧状态迁移 ②清理旧版指纹支付残留 ③亮度增强三步向导：风险告知 → 沿用/重校 → 亮度检测

OLD_MOD="/data/adb/modules/redmagic_11air_combo/config"
OLD_EXT="/data/adb/redmagic_11air_combo"
NEW="/data/adb/redmagic_11_combo"

echo " "
echo "================================"
echo "  红魔11综合提升 · 安装向导"
echo "================================"

# ===== 旧状态迁移 =====
mkdir -p "$NEW" 2>/dev/null
rm -rf /data/adb/modules/YHGames 2>/dev/null
if [ -d "/data/adb/modules/redmagic_11air_combo" ]; then
    rm -rf "/data/adb/modules/redmagic_11air_combo" 2>/dev/null
    echo "- 已清理旧模块目录"
fi
if [ -d "$OLD_EXT" ] && [ ! -f "$NEW/v40" ]; then
    cp -a "$OLD_EXT/." "$NEW/" 2>/dev/null
    echo "- 已迁移开关状态"
fi
if [ -d "$OLD_MOD" ] && [ ! -f "$NEW/v40" ]; then
    cp -a "$OLD_MOD/." "$NEW/" 2>/dev/null
    echo "- 已迁移旧版开关状态"
fi
echo "1" > "$NEW/v40" 2>/dev/null

# ===== 清理旧版指纹支付（v39 及以前内置的两套后端）=====
# 指纹支付相关组件在 v40 已整体移除，这里清理旧版本残留
rm -rf /data/adb/modules/wekit_zygisk 2>/dev/null
rm -rf /data/adb/fingerprintpay 2>/dev/null
rm -f "$NEW/fp" "$NEW/alipay" "$NEW/vol" "$NEW/music" 2>/dev/null
echo "- 已清理旧版指纹支付/音频增强残留"

# ===== 亮度增强三步向导 =====
LUM_BIN="$MODPATH/lumin/bin/luminpro"
LUM_BRI="/sys/class/backlight/panel0-backlight/brightness"
LUM_MAX="/sys/class/backlight/panel0-backlight/max_brightness"
LUM_DIR="$MODPATH/lumin"

key() {
    timeout 60 getevent -l 2>/dev/null | grep -m1 -oE "KEY_VOLUME(UP|DOWN)" | head -1
}

run_calib() {
    # ③ 亮度检测
    echo " "
    echo "======== 亮度增强 · 亮度检测 ========"
    echo "请先关闭自动亮度，然后把屏幕亮度拉到最高"
    echo "8 秒后自动检测当前最高亮度…"
    sleep 8
    cur="$(cat "$LUM_BRI" 2>/dev/null)"
    mx="$(cat "$LUM_MAX" 2>/dev/null)"
    case "$cur" in ''|0|*[!0-9]*) cur=1900 ;; esac
    case "$mx" in ''|0|*[!0-9]*) mx=2047 ;; esac
    peak=$((mx + 253))
    [ "$peak" -gt 2500 ] && peak=2500
    "$LUM_BIN" config patch "{\"ui_max_bri\":$cur,\"max_bri\":$peak}" >/dev/null 2>&1
    echo "$cur" > "$NEW/lum_th" 2>/dev/null
    echo "$peak" > "$NEW/lum_peak" 2>/dev/null
    echo " "
    echo "- 检测到最高亮度: $cur"
    echo "- 系统最大亮度: $mx"
    echo "- 已写入配置: 触发阈值 $cur / 峰值 $peak"
    echo "- 面板「亮度增强」页可看到并修改这些值"
}

chmod 755 "$LUM_BIN" 2>/dev/null

# 强制所有脚本可执行（KSU 解压后可能丢失执行权限）
chmod 755 "$MODPATH"/*.sh 2>/dev/null
chmod 755 "$MODPATH/lumin/bin/luminpro" 2>/dev/null
if [ -x "$LUM_BIN" ]; then
    # ① 风险告知（总是显示）
    echo " "
    echo "======== 亮度增强 · 风险告知 ========"
    echo "本功能会让屏幕亮度突破系统上限，"
    echo "长期使用可能加速 OLED 老化、烧屏、发热增加。"
    echo ""
    echo "按 音量+ ：我已知晓并继续"
    echo "按 音量- ：不清楚/不同意，不启用亮度功能"

    c1="$(key)"
    if [ "$c1" = "KEY_VOLUMEDOWN" ]; then
        mkdir -p "$LUM_DIR" 2>/dev/null
        echo 1 > "$LUM_DIR/skip" 2>/dev/null
        echo "- 已选择不启用亮度功能（守护不会启动）"
        echo "- 以后想用：删除模块目录下 lumin/skip 后重启"
    else
        OLD_TH="$(cat "$NEW/lum_th" 2>/dev/null)"
        OLD_PK="$(cat "$NEW/lum_peak" 2>/dev/null)"
        # 优先用用户已经在面板里改过的值（已安装模块的 config.json）
        CUR_JSON="/data/adb/modules/redmagic_11_combo/lumin/config/config.json"
        CUR_TH="$(grep -o '"ui_max_bri":[0-9]*' "$CUR_JSON" 2>/dev/null | grep -o '[0-9]*$')"
        CUR_PK="$(grep -o '"max_bri":[0-9]*' "$CUR_JSON" 2>/dev/null | grep -o '[0-9]*$')"
        case "$CUR_TH" in ''|0|*[!0-9]*) ;; *) OLD_TH="$CUR_TH" ;; esac
        case "$CUR_PK" in ''|0|*[!0-9]*) ;; *) OLD_PK="$CUR_PK" ;; esac
        if [ -n "$OLD_TH" ] && [ "$OLD_TH" != "0" ]; then
            # ② 已有校准值（沿用 / 重测）
            echo " "
            echo "======== 亮度增强 · 已有校准值 ========"
            echo "检测到之前校准过的亮度："
            echo "  触发阈值 $OLD_TH / 峰值 ${OLD_PK:-2300}"
            echo ""
            echo "按 音量+ ：沿用这个值（保持原样）"
            echo "按 音量- ：重新校准（去拉最高亮度重新检测）"
            c2="$(key)"
            if [ "$c2" = "KEY_VOLUMEDOWN" ]; then
                echo "- 开始重新校准…"
                run_calib
            else
                # 把沿用的值写回外部文件（重启后 service.sh 恢复用它，避免用旧值）
                echo "$OLD_TH" > "$NEW/lum_th" 2>/dev/null
                echo "${OLD_PK:-2300}" > "$NEW/lum_peak" 2>/dev/null
                echo "- 已沿用旧校准值（触发阈值 $OLD_TH / 峰值 ${OLD_PK:-2300}）"
            fi
        else
            # ③ 首次检测
            run_calib
        fi
    fi
fi

# 安装时刷新模块简介（管理器模块界面显示已启用功能）
[ -f "$MODPATH/desc.sh" ] && sh "$MODPATH/desc.sh" >/dev/null 2>&1

# ===== 免重启：安装后自动拉起服务 =====
if [ -f "$MODPATH/apply_now.sh" ]; then
    mkdir -p "$NEW" 2>/dev/null
    cp -f "$MODPATH/apply_now.sh" "$NEW/apply_now.sh" 2>/dev/null
    chmod 755 "$NEW/apply_now.sh" 2>/dev/null
    nohup sh "$NEW/apply_now.sh" "$MODPATH" "$PPID" >/dev/null 2>&1 &
    echo "- 已排入免重启应用，约 10 秒后自动生效"
fi

echo " "
echo "================================"
echo "  安装完成 · 无需重启"
echo "  约 10 秒后自动应用，刷新模块列表查看状态"
echo "================================"
exit 0
