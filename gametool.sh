#!/system/bin/sh
# 小霞游戏环境工具 · 核心脚本
# 用法：sh gametool.sh <命令> [参数]
#   clean <包名>     清理游戏环境（清数据 + 重置标识）
#   androidid        随机化 Android ID
#   spoof <模板>     机型伪装（redmagic11pro / redmagic11 / xiaomi14 / pixel8 / reset）
#   protect          设备标记保护（重置标识 + 清日志）
#   status           输出当前标识状态

STATE="/data/adb/redmagic_11_combo"
mkdir -p "$STATE" 2>/dev/null

randhex() {
    head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n'
}

cmd="$1"
case "$cmd" in
    clean)
        pkg="$2"
        [ -z "$pkg" ] && { echo "ERROR: 缺少包名"; exit 1; }
        echo "正在停止游戏进程…"
        am force-stop "$pkg" 2>/dev/null
        sleep 1
        echo "正在清理游戏数据…"
        pm clear "$pkg" 2>/dev/null || { echo "ERROR: 清理失败（包名错误或系统拒绝）"; exit 1; }
        echo "正在重置 Android ID…"
        newid=$(randhex)
        settings put secure android_id "$newid" 2>/dev/null
        echo "正在重置设备序列号…"
        resetprop -n ro.serialno "$(randhex)" 2>/dev/null
        resetprop -n ro.boot.serialno "$(randhex)" 2>/dev/null
        echo "正在刷新 DNS…"
        ndc resolver flushdefaultif 2>/dev/null
        logcat -c 2>/dev/null
        echo "清理完成：$pkg"
        echo "Android ID 已更新为 $newid"
        ;;
    androidid)
        newid=$(randhex)
        settings put secure android_id "$newid" 2>/dev/null
        echo "Android ID 已更新：$newid"
        echo "部分应用需要重启才能读到新 ID"
        ;;
    spoof)
        tpl="$2"
        if [ "$tpl" = "custom" ]; then
            M="$3"; B="$4"; D="${5:-$3}"
            [ -z "$M" ] && { echo "ERROR: 缺少型号"; exit 1; }
            [ -z "$B" ] && B="nubia"
            F="$B/$D/$D:15/AQ3A.240912.001/eng.custom.100000:user/release-keys"
            resetprop -n ro.product.model "$M" 2>/dev/null
            resetprop -n ro.product.brand "$B" 2>/dev/null
            resetprop -n ro.product.device "$D" 2>/dev/null
            resetprop -n ro.product.manufacturer "$B" 2>/dev/null
            resetprop -n ro.build.fingerprint "$F" 2>/dev/null
            resetprop -n ro.product.vendor.model "$M" 2>/dev/null
            resetprop -n ro.product.vendor.brand "$B" 2>/dev/null
            resetprop -n ro.product.vendor.device "$D" 2>/dev/null
            echo "custom" > "$STATE/spoof_template" 2>/dev/null
            echo "$M|$B" > "$STATE/spoof_custom" 2>/dev/null
            echo "自定义机型已应用：$M（$B）"
            echo "需要强制停止游戏再重新启动才能读到新机型"
            exit 0
        fi
        case "$tpl" in
            redmagic11pro)
                M="NX809J"; B="nubia"; D="NX809J"; MF="nubia"
                F="nubia/NX809J/NX809J:15/AQ3A.240912.001/eng.20251015.100000:user/release-keys" ;;
            redmagic11)
                M="NX799J"; B="nubia"; D="NX799J"; MF="nubia"
                F="nubia/NX799J/NX799J:15/AQ3A.240912.001/eng.20251015.100000:user/release-keys" ;;
            xiaomi14)
                M="23127PN0CC"; B="Xiaomi"; D="houji"; MF="Xiaomi"
                F="Xiaomi/houji/houji:15/AQ3A.240912.001/OS2.0.1.0:user/release-keys" ;;
            pixel8)
                M="Pixel 8"; B="google"; D="shiba"; MF="Google"
                F="google/shiba/shiba:15/AP4A.250105.002/1234567:user/release-keys" ;;
            reset)
                M="NX799J"; B="nubia"; D="NX799J"; MF="nubia"
                F="nubia/NX799J/NX799J:15/AQ3A.240912.001/eng.20251015.100000:user/release-keys" ;;
            *)
                echo "ERROR: 未知模板（redmagic11pro / redmagic11 / xiaomi14 / pixel8 / reset）"; exit 1 ;;
        esac
        resetprop -n ro.product.model "$M" 2>/dev/null
        resetprop -n ro.product.brand "$B" 2>/dev/null
        resetprop -n ro.product.device "$D" 2>/dev/null
        resetprop -n ro.product.manufacturer "$MF" 2>/dev/null
        resetprop -n ro.build.fingerprint "$F" 2>/dev/null
        resetprop -n ro.product.vendor.model "$M" 2>/dev/null
        resetprop -n ro.product.vendor.brand "$B" 2>/dev/null
        resetprop -n ro.product.vendor.device "$D" 2>/dev/null
        echo "$tpl" > "$STATE/spoof_template" 2>/dev/null
        echo "机型伪装已应用：$M（$B）"
        echo "需要强制停止游戏再重新启动才能读到新机型"
        ;;
    protect)
        echo "正在保护设备标记…"
        newid=$(randhex)
        settings put secure android_id "$newid" 2>/dev/null
        resetprop -n ro.serialno "$(randhex)" 2>/dev/null
        resetprop -n ro.boot.serialno "$(randhex)" 2>/dev/null
        logcat -c 2>/dev/null
        rm -rf /data/local/tmp/*.log 2>/dev/null
        echo "设备标记保护完成"
        echo "Android ID → $newid"
        ;;
    status)
        aid=$(settings get secure android_id 2>/dev/null)
        sn=$(getprop ro.serialno 2>/dev/null)
        model=$(getprop ro.product.model 2>/dev/null)
        brand=$(getprop ro.product.brand 2>/dev/null)
        tpl=$(cat "$STATE/spoof_template" 2>/dev/null)
        echo "型号: $model"
        echo "品牌: $brand"
        echo "序列号: $sn"
        echo "AndroidID: $aid"
        if [ "$tpl" = "custom" ]; then echo "伪装模板: 自定义 $(cat "$STATE/spoof_custom" 2>/dev/null)"; else echo "伪装模板: ${tpl:-未设置}"; fi
        ;;
    apps)
        # 单行输出（| 分隔），规避 KSU exec 多行截断
        pm list packages -3 2>/dev/null | sed 's/^package://' | sort | tr '\n' '|'
        ;;
    *)
        echo "用法: sh gametool.sh clean <包名> | androidid | spoof <模板> | protect | status | apps"
        ;;
esac
exit 0
