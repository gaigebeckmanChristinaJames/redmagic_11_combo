#!/system/bin/sh
# 安装/更新后免重启：接管 modules_update 暂存目录，替换模块并重启服务
STAGE="$1"
PARENT="${2:-$PPID}"
i=0
while [ -n "$PARENT" ] && [ -d "/proc/$PARENT" ] && [ $i -lt 180 ]; do
    sleep 0.5
    i=$((i + 1))
done
sleep 2

MOD="/data/adb/modules/redmagic_11_combo"
CFG="/data/adb/redmagic_11_combo"
[ -d "$STAGE" ] || STAGE="/data/adb/modules_update/redmagic_11_combo"

# 等真正的模块目录出现（首次安装时管理器会自己放好）
n=0
while [ ! -f "$MOD/module.prop" ] && [ $n -lt 60 ]; do
    sleep 1
    n=$((n + 1))
done

# 停掉同一开机周期里的旧循环
LOCK="$CFG/.svc.pid"
if [ -s "$LOCK" ]; then
    _op=$(sed -n 1p "$LOCK" 2>/dev/null)
    _ob=$(sed -n 2p "$LOCK" 2>/dev/null)
    _cb=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    if [ "$_ob" = "$_cb" ] && [ -n "$_op" ] && [ -d "/proc/$_op" ]; then
        kill "$_op" 2>/dev/null
        sleep 1
        kill -9 "$_op" 2>/dev/null
    fi
fi
rm -f "$LOCK" 2>/dev/null

# 关键：管理器把更新放到 modules_update，这里直接并进正式目录并删掉暂存
if [ -f "$STAGE/module.prop" ] && [ "$STAGE" != "$MOD" ]; then
    sleep 1
    rm -rf "$MOD" 2>/dev/null
    mkdir -p "$MOD" 2>/dev/null
    cp -a "$STAGE/." "$MOD/" 2>/dev/null
    rm -rf "$STAGE" 2>/dev/null
    sync
fi
[ -f "$MOD/module.prop" ] || exit 0

# 清掉 KSU 的“待更新”标记；用户主动禁用（disable）不动
rm -f "$MOD/update" "$MOD/remove" 2>/dev/null

chmod 755 "$MOD"/*.sh 2>/dev/null
chmod 755 "$MOD/lumin/bin/luminpro" 2>/dev/null
mkdir -p "$CFG" 2>/dev/null
[ -f "$MOD/desc.sh" ] && sh "$MOD/desc.sh" >/dev/null 2>&1

setsid sh "$MOD/service.sh" >/dev/null 2>&1 &
echo "$(date '+%H:%M:%S') apply_now: staged=$STAGE -> $MOD, service relaunched" >> "$MOD/apply_now.log" 2>/dev/null
exit 0
