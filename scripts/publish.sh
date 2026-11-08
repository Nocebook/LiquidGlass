#!/usr/bin/env bash
# 一键发布：换包名 -> 提交 -> 推送 -> 打印源地址
# 用法：bash scripts/publish.sh <github用户名> [仓库名]
# 前提：先在 https://github.com/new 建一个空仓库（不要勾 README/LICENSE）
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "用法: bash scripts/publish.sh <github用户名> [仓库名]" >&2
  exit 1
fi

USER_NAME="$1"
REPO="${2:-glassify}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[1/4] 替换包名..."
bash scripts/rename.sh "$USER_NAME"

echo "[2/4] 提交..."
git add -A
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  git commit --amend --no-edit >/dev/null
else
  git init -b main >/dev/null
  git add -A
  git commit -m "Glassify v0.3.0" >/dev/null
fi

echo "[3/4] 配置远端..."
URL="https://github.com/${USER_NAME}/${REPO}.git"
if git remote | grep -qx origin; then
  git remote set-url origin "$URL"
else
  git remote add origin "$URL"
fi
echo "      $URL"

echo "[4/4] 推送..."
git push -u origin main

echo
echo "完成。"
echo "  仓库:   https://github.com/${USER_NAME}/${REPO}"
echo "  Actions: https://github.com/${USER_NAME}/${REPO}/actions"
echo
echo "手动做一次：Settings -> Pages -> Deploy from a branch -> gh-pages / (root)"
echo "手机 Sileo 添加源: https://${USER_NAME}.github.io/${REPO}/"
