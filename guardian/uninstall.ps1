# ==============================================================================
# Antigravity Proxy Guardian 卸载与清理脚本
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$RemoveVault,
    [switch]$RemoveProxyFiles
)

# 确保 UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     Antigravity Proxy Guardian - 卸载与清理向导         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$taskName = "AntigravityProxyGuardian"
$appDataProxy = Join-Path $env:APPDATA "AntigravityProxy"
$targetDir = Join-Path $env:LOCALAPPDATA "Programs\Antigravity"

# 1. 停止并注销计划任务
Write-Host "[1/4] 注销 Windows 计划任务..." -ForegroundColor Yellow
try {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  -> 计划任务 [$taskName] 已注销" -ForegroundColor Green
} catch {
    Write-Host "  -> 计划任务未找到或注销跳过" -ForegroundColor Gray
}

# 2. 清理开机启动文件夹残余
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) "AntigravityProxyGuardian.lnk"
if (Test-Path -LiteralPath $startupLnk) {
    Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue
    Write-Host "  -> 启动项快捷方式已清理" -ForegroundColor Green
}

# 3. 停止当前运行中的 guardian 进程
Write-Host "[2/4] 终止后台 Guardian 守护进程..." -ForegroundColor Yellow
Get-CimInstance Win32_Process | Where-Object { 
    $_.CommandLine -match "guardian\.ps1" 
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "  -> 已终止 Guardian 进程 (PID: $($_.ProcessId))" -ForegroundColor Green
}

# 4. 恢复桌面快捷方式
Write-Host "[3/4] 还原桌面快捷方式..." -ForegroundColor Yellow
$desktopPath = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktopPath "Antigravity.lnk"
$origLnk = Join-Path $desktopPath "Antigravity.original.lnk"

if (Test-Path -LiteralPath $origLnk) {
    Move-Item -LiteralPath $origLnk -Destination $lnkPath -Force
    Write-Host "  -> 已还原原始桌面快捷方式" -ForegroundColor Green
} else {
    Write-Host "  -> 未发现备份快捷方式，保留现有桌面图标" -ForegroundColor Gray
}

# 5. 可选清理
Write-Host "[4/4] 检查文件清理选项..." -ForegroundColor Yellow
if ($RemoveProxyFiles -and (Test-Path -LiteralPath $targetDir)) {
    Remove-Item -LiteralPath (Join-Path $targetDir "version.dll") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $targetDir "config.json") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $targetDir "config-web.html") -Force -ErrorAction SilentlyContinue
    Write-Host "  -> 已移除 Antigravity 目录下的 proxy 劫持文件" -ForegroundColor Green
}

if ($RemoveVault -and (Test-Path -LiteralPath $appDataProxy)) {
    Remove-Item -LiteralPath $appDataProxy -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  -> 已删除 Vault 持久化库: $appDataProxy" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " 🎉 Antigravity Proxy Guardian 已成功卸载！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
