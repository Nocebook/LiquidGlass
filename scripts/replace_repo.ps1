# 用本地内容整体覆盖 Nocebook/LiquidGlass 的 main 分支。
#
# 做的事：
#   1) 把远端现有 main 存成 tag legacy-7.4.0（后悔了能找回来）
#   2) 强制推送本地的 main
#
# 用法（在你自己的 PowerShell 里跑，需要能出网）：
#   powershell -ExecutionPolicy Bypass -File scripts\replace_repo.ps1
param(
    [string]$Remote = 'https://github.com/Nocebook/LiquidGlass.git',
    [string]$BackupTag = 'legacy-7.4.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "[1/4] 配置远端 $Remote" -ForegroundColor Cyan
$remotes = git remote
if ($remotes -contains 'origin') {
    git remote set-url origin $Remote
} else {
    git remote add origin $Remote
}

Write-Host "[2/4] 备份远端 main -> $BackupTag" -ForegroundColor Cyan
git fetch origin
git tag -f $BackupTag origin/main
git push origin $BackupTag --force
if ($LASTEXITCODE -ne 0) {
    Write-Host "备份失败，已中止（没有做任何覆盖）。" -ForegroundColor Yellow
    exit 1
}

Write-Host "[3/4] 提交本地内容" -ForegroundColor Cyan
git add -A
$pending = git status --porcelain
if ($pending) {
    git commit -m "8.0.0: 整体替换为 Glassify（角标玻璃 + 呼吸动画 + Dock/文件夹/控制中心）"
} else {
    Write-Host "      没有新改动，直接推当前提交" -ForegroundColor DarkGray
}

Write-Host "[4/4] 强制推送 main" -ForegroundColor Cyan
git push --force origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "推送失败。先确认：" -ForegroundColor Yellow
    Write-Host "  1. 浏览器已登录 Nocebook 账号"
    Write-Host "  2. 仓库地址正确: $Remote"
    exit 1
}

Write-Host ""
Write-Host "完成。旧版本已备份到 tag: $BackupTag" -ForegroundColor Green
Write-Host "  Actions: https://github.com/Nocebook/LiquidGlass/actions"
Write-Host "  回滚：  git push --force origin $BackupTag:main"
