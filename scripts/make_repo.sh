#!/usr/bin/env bash
# 把 packages/*.deb 打包成一个静态 apt 源，输出到 repo/。
# GitHub Actions 会自动跑；本地想预览也可以直接跑（需要 dpkg-dev）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$ROOT/repo"
DEBS="$REPO/debs"

rm -rf "$REPO"
mkdir -p "$DEBS"

shopt -s nullglob
count=0
for deb in "$ROOT"/packages/*.deb; do
  cp "$deb" "$DEBS/"
  count=$((count + 1))
done
shopt -u nullglob

if [ "$count" -eq 0 ]; then
  echo "没有找到 packages/*.deb，先跑 make package" >&2
  exit 1
fi

cd "$REPO"

# Packages / Packages.gz：Cydia / Sileo / Zebra 读的索引
dpkg-scanpackages -m . > Packages
gzip -9c Packages > Packages.gz

# Release：源的基本信息
cat > Release <<EOF
Origin: Glassify
Label: Glassify
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm64
Components: main
Description: Glassify 个人软件源
EOF

cat > index.html <<'HTML'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Glassify Repo</title>
<style>
  body{font-family:-apple-system,sans-serif;background:#0b0b0f;color:#eee;
       display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}
  .card{background:#1a1a22;padding:32px 28px;border-radius:20px;max-width:420px;
        box-shadow:0 20px 60px rgba(0,0,0,.5);text-align:center}
  a{color:#0a84ff;text-decoration:none}
  .url{font-family:ui-monospace,monospace;font-size:13px;background:#000;padding:10px;
       border-radius:10px;word-break:break-all;margin:14px 0;color:#8ab4ff}
</style>
</head>
<body>
<div class="card">
  <h1>Glassify</h1>
  <p>把下面这个地址加进 Sileo / Zebra 的「软件源」：</p>
  <div class="url" id="repo"></div>
  <p><a id="open" href="#">用 Sileo 打开</a></p>
</div>
<script>
  var url = location.origin + location.pathname;
  url = url.replace(/index\.html$/, '');
  document.getElementById('repo').textContent = url;
  document.getElementById('open').href = 'sileo://source/' + url;
</script>
</body>
</html>
HTML

echo "repo ready: $REPO ($count deb)"
