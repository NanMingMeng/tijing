#!/usr/bin/env bash
# 题镜 · 一键生成正式签名（macOS / Linux）
# 生成的 jks 与 key.properties 必须自己备份，丢了就无法发布更新。
set -e
cd "$(dirname "$0")/.."

KS="android/app/tijing-release.jks"
KP="android/key.properties"

if [ ! -f "$KS" ]; then
  echo "正在生成 keystore..."
  keytool -genkeypair -v \
    -keystore "$KS" \
    -alias tijing \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storetype JKS
else
  echo "[跳过] 已存在 $KS"
fi

read -rsp "请输入 keystore 密码: " STOREPASS
echo
cat > "$KP" <<EOF
storePassword=$STOREPASS
keyPassword=$STOREPASS
keyAlias=tijing
storeFile=tijing-release.jks
EOF

echo "[完成] 已写入 $KP"
echo "下一步： flutter build apk --release"
echo
echo "== 务必备份 =="
echo "  $KS"
echo "  android/key.properties"
