# 一键发布：换包名 -> 提交 -> 推送 -> 打印源地址
# 在项目根目录、用你自己的 PowerShell 窗口运行（不要在这个沙箱里跑）：
#   powershell -ExecutionPolicy Bypass -File scripts\publish.ps1 你的GitHub用户名
#
# 前提：先在 https://github.com/new 建一个空仓库（名字默认 glassify，不要勾 README/.gitignore/LICENSE）
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [string]$Repo = 'glassify'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "[1/4] 替换包名..." -ForegroundColor Cyan
& "$PSScriptRoot\rename.ps1" -Username $Username

Write-Host "[2/4] 提交..." -ForegroundColor Cyan
git add -A
$hasHead = (git rev-parse --verify HEAD 2>$null)
if ($LASTEXITCODE -eq 0 -and $hasHead) {
    git commit --amend --no-edit | Out-Null
    Write-Host "      已合并进首个提交" -ForegroundColor DarkGray
} else {
    git init -b main | Out-Null
    git add -A
    git commit -m "Glassify v0.3.0" | Out-Null
    Write-Host "      已创建首个提交" -ForegroundColor DarkGray
}

Write-Host "[3/4] 配置远端..." -ForegroundColor Cyan
$url = "https://github.com/$Username/$Repo.git"
$remotes = git remote
if ($remotes -contains 'origin') {
    git remote set-url origin $url
} else {
    git remote add origin $url
}
Write-Host "      $url" -ForegroundColor DarkGray

Write-Host "[4/4] 推送（第一次会弹浏览器登录 GitHub）..." -ForegroundColor Cyan
git push -u origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "推送失败。两个常见原因：" -ForegroundColor Yellow
    Write-Host "  1. 远端仓库不存在 -> 先去 https://github.com/new 建一个空仓库 '$Repo'"
    Write-Host "  2. 没登录 -> 重新运行，浏览器弹窗里授权即可"
    exit 1
}

Write-Host ""
Write-Host "完成。" -ForegroundColor Green
Write-Host "  仓库: https://github.com/$Username/$Repo"
Write-Host "  Actions: https://github.com/$Username/$Repo/actions  （第一次构建看这里）"
Write-Host ""
Write-Host "接下来手动做一次：" -ForegroundColor Yellow
Write-Host "  Settings -> Pages -> Source: Deploy from a branch -> gh-pages / (root) -> Save"
Write-Host ""
Write-Host "然后手机 Sileo 添加源：" -ForegroundColor Yellow
Write-Host "  https://$Username.github.io/$Repo/"
