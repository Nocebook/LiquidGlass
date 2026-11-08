# 把包名里的 yourname 换成你自己的 GitHub 用户名（全小写）。
# 用法（在项目根目录）：powershell -ExecutionPolicy Bypass -File scripts\rename.ps1 你的用户名
param(
    [Parameter(Mandatory = $true)]
    [string]$Username
)

$name = $Username.ToLower()
if ($name -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$') {
    throw "用户名只能是小写字母、数字、中划线：$name"
}

$root = Split-Path -Parent $PSScriptRoot
$targets = @('control', 'Tweak.xm', 'prefs\GSPRootListController.m', 'LICENSE')
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($rel in $targets) {
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "跳过不存在的文件: $rel"
        continue
    }
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $text = $text -replace 'com\.yourname\.glassify', "com.$name.glassify"
    $text = $text -replace 'yourname', $name
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "已更新 $rel"
}

Write-Host ""
Write-Host "包名: com.$name.glassify" -ForegroundColor Green
Write-Host "下一步: git init && git add . && git commit -m 'Glassify v0.3.0'"
