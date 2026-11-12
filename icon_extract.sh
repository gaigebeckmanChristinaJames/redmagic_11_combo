#!/system/bin/sh
# 小霞应用图标提取器 · 从 APK 提取真实图标到模块 webroot/icons/
# 后台安全运行：进度写入 .progress，不会阻塞 WebUI
MODDIR="/data/adb/modules/redmagic_11_combo"
OUT="$MODDIR/webroot/icons"
mkdir -p "$OUT" 2>/dev/null
PROG="$OUT/.progress"

echo "running|0|0|0" > "$PROG" 2>/dev/null

pkgs=$(pm list packages -3 2>/dev/null | sed 's/package://')
total=$(printf '%s\n' "$pkgs" | grep -c .)
n=0
idx=0
skip=0

for pkg in $pkgs; do
    idx=$((idx + 1))
    echo "running|$idx|$total|$n" > "$PROG" 2>/dev/null
    if [ -f "$OUT/$pkg.png" ]; then
        skip=$((skip + 1))
        continue
    fi
    apk=$(pm path "$pkg" 2>/dev/null | head -1 | sed 's/package://')
    [ -f "$apk" ] || continue
    cand=$(unzip -l "$apk" 2>/dev/null \
        | grep -oE "res/[A-Za-z0-9_./-]*(ic_launcher|app_icon|launcher_icon|ic_app)[A-Za-z0-9_./-]*\.(png|webp)" \
        | grep -v "adaptive\|foreground\|background" \
        | head -1)
    [ -z "$cand" ] && continue
    unzip -p "$apk" "$cand" > "$OUT/$pkg.png" 2>/dev/null
    [ -s "$OUT/$pkg.png" ] && n=$((n + 1))
done

cnt=$(ls "$OUT" 2>/dev/null | grep -c "\.png$")
echo "done|$total|$total|$n|$cnt" > "$PROG" 2>/dev/null
exit 0
