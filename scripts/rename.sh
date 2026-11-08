#!/usr/bin/env bash
# 把包名里的 yourname 换成你自己的 GitHub 用户名（全小写）。
# 用法：bash scripts/rename.sh <github用户名>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "用法: bash scripts/rename.sh <github用户名>" >&2
  exit 1
fi

NAME="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! echo "$NAME" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
  echo "用户名只能是小写字母、数字、中划线：$NAME" >&2
  exit 1
fi

cd "$ROOT"

sed -i "s/com\.yourname\.glassify/com.${NAME}.glassify/g" control Tweak.xm prefs/GSPRootListController.m
sed -i "s/yourname/${NAME}/g" control Tweak.xm prefs/GSPRootListController.m LICENSE

echo "已替换为: com.${NAME}.glassify"
grep -rn "glassify" control Tweak.xm prefs/GSPRootListController.m | grep "com\." | head -5
