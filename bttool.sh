#!/system/bin/sh
# 小霞蓝牙音频工具 · 读取编码/连接状态 + 增强开关
# 用法：sh bttool.sh status | on | off

STATE="/data/adb/redmagic_11_combo"
mkdir -p "$STATE" 2>/dev/null

case "$1" in
    status)
        # 连接状态与当前编码（root 下 dumpsys 可用）
        dump=$(dumpsys bluetooth_manager 2>/dev/null)
        if printf '%s' "$dump" | grep -q "STATE_CONNECTED"; then
            echo "已连接"
        else
            echo "未连接"
        fi
        codec=$(printf '%s\n' "$dump" | grep -ioE "codec=[a-zA-Z0-9_]+" | head -1 | cut -d= -f2)
        if [ -z "$codec" ]; then
            codec=$(printf '%s\n' "$dump" | grep -ioE "(LDAC|aptX[- ]?(HD|Adaptive|TWS)?|AAC|SBC)" | head -1)
        fi
        [ -n "$codec" ] && echo "当前编码：$codec" || echo "当前编码：未连接或未协商"
        cap=$(getprop persist.bluetooth.a2dp_offload.cap 2>/dev/null)
        echo "支持编码：${cap:-未知}"
        ;;
    on)
        # 确保高清编码能力 + 语音 aptX
        resetprop -n persist.bluetooth.a2dp_offload.cap "sbc-aac-aptx-aptxhd-ldac" 2>/dev/null
        resetprop -n persist.vendor.qcom.bluetooth.a2dp_offload_cap "sbc-aac-aptx-aptxhd-ldac-aptxadaptiver2" 2>/dev/null
        resetprop -n bluetooth.hfp.codec_aptx_voice.enabled true 2>/dev/null
        resetprop -n persist.bluetooth.a2dp_offload.disabled false 2>/dev/null
        echo 1 > "$STATE/bluetooth" 2>/dev/null
        echo "蓝牙音质增强已开启"
        echo "支持：SBC / AAC / aptX / aptX HD / LDAC"
        ;;
    off)
        resetprop -n persist.bluetooth.a2dp_offload.cap "sbc-aac-aptx-aptxhd-ldac" 2>/dev/null
        resetprop -n persist.vendor.qcom.bluetooth.a2dp_offload_cap "sbc-aptx-aptxhd-aptxtws-aac-ldac-aptxadaptiver2" 2>/dev/null
        echo 0 > "$STATE/bluetooth" 2>/dev/null
        echo "蓝牙音质增强已关闭"
        ;;
    *)
        echo "用法: sh bttool.sh status | on | off"
        ;;
esac
exit 0
