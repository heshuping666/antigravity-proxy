# ==============================================================================
# Antigravity Proxy Guardian 状态与诊断检查工具
# ==============================================================================

[CmdletBinding()]
param(
    [string]$TargetDir = ""
)

# 确保 UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     Antigravity Proxy Guardian - 运行状态与诊断          " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\Antigravity"
}
$appDataProxy = Join-Path $env:APPDATA "AntigravityProxy"
$vaultDir = Join-Path $appDataProxy "vault"
$logDir = Join-Path $appDataProxy "logs"
$guardianLog = Join-Path $logDir "guardian.log"
$taskName = "AntigravityProxyGuardian"

# 1. 目标程序状态
Write-Host "`n[1] Antigravity 目标程序状态:" -ForegroundColor Yellow
$exePath = Join-Path $TargetDir "Antigravity.exe"
if (Test-Path -LiteralPath $exePath) {
    $exeItem = Get-Item -LiteralPath $exePath
    Write-Host "  ✅ 主程序存在: $exePath" -ForegroundColor Green
    Write-Host "     最后修改时间: $($exeItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) (大小: $([math]::Round($exeItem.Length / 1MB, 2)) MB)"
} else {
    Write-Host "  ❌ 未找到 Antigravity.exe 路径: $exePath" -ForegroundColor Red
}

# 2. 核心劫持文件状态
Write-Host "`n[2] 安装目录代理文件状态:" -ForegroundColor Yellow
$targetDll = Join-Path $TargetDir "version.dll"
$targetCfg = Join-Path $TargetDir "config.json"

if (Test-Path -LiteralPath $targetDll) {
    $dllItem = Get-Item -LiteralPath $targetDll
    Write-Host "  ✅ version.dll 存在: $($dllItem.Length) 字节 (最后修改: $($dllItem.LastWriteTime))" -ForegroundColor Green
} else {
    Write-Host "  ❌ version.dll 缺失！当前不会走代理！" -ForegroundColor Red
}

if (Test-Path -LiteralPath $targetCfg) {
    Write-Host "  ✅ config.json 存在" -ForegroundColor Green
} else {
    Write-Host "  ❌ config.json 缺失！" -ForegroundColor Red
}

# 3. 持久化存储库 (Vault) 状态
Write-Host "`n[3] 持久化存储库 (Vault) 状态:" -ForegroundColor Yellow
$vaultDll = Join-Path $vaultDir "version.dll"
$vaultCfg = Join-Path $vaultDir "config.json"
if ((Test-Path -LiteralPath $vaultDll) -and (Test-Path -LiteralPath $vaultCfg)) {
    Write-Host "  ✅ Vault 完好就绪: $vaultDir" -ForegroundColor Green
} else {
    Write-Host "  ⚠️ Vault 未完整初始化: $vaultDir" -ForegroundColor Yellow
}

# 4. 后台守护任务状态
Write-Host "`n[4] 守护计划任务状态:" -ForegroundColor Yellow
try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $stateColor = if ($task.State -eq "Running") { "Green" } else { "Yellow" }
    Write-Host "  ✅ 计划任务 [$taskName] 已注册，当前状态: $($task.State)" -ForegroundColor $stateColor
} catch {
    Write-Host "  ❌ 计划任务 [$taskName] 未注册" -ForegroundColor Red
}

# 5. 后台 Guardian 进程状态
Write-Host "`n[5] Guardian 后台常驻进程:" -ForegroundColor Yellow
$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "guardian\.ps1" }
if ($procs) {
    foreach ($p in $procs) {
        Write-Host "  ✅ 守护进程运行中 (PID: $($p.ProcessId))" -ForegroundColor Green
    }
} else {
    Write-Host "  ⚠️ 未检测到运行中的 guardian.ps1 进程" -ForegroundColor Yellow
}

# 6. 桌面快捷方式自愈状态
Write-Host "`n[6] 桌面快捷方式保护状态:" -ForegroundColor Yellow
$desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "Antigravity.lnk"
if (Test-Path -LiteralPath $desktopLnk) {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($desktopLnk)
    if ($shortcut.Arguments -match "launcher\.vbs") {
        Write-Host "  ✅ 桌面快捷方式已强化 (由 launcher.vbs 启动前秒级自愈保护)" -ForegroundColor Green
    } else {
        Write-Host "  ℹ️ 桌面快捷方式为常规启动方式: $($shortcut.TargetPath)" -ForegroundColor Gray
    }
} else {
    Write-Host "  ℹ️ 桌面未找到 Antigravity.lnk" -ForegroundColor Gray
}

# 7. 代理连通性检测
Write-Host "`n[7] 本地代理网络连通性:" -ForegroundColor Yellow
if (Test-Path -LiteralPath $targetCfg) {
    try {
        $json = Get-Content -LiteralPath $targetCfg -Raw -Encoding UTF8 | ConvertFrom-Json
        $pType = $json.proxy.type
        $pHost = $json.proxy.host
        $pPort = $json.proxy.port
        Write-Host "  配置信息: ${pType}://${pHost}:${pPort}" -ForegroundColor Cyan

        $tcp = Test-NetConnection -ComputerName $pHost -Port $pPort -WarningAction SilentlyContinue
        if ($tcp.TcpTestSucceeded) {
            Write-Host "  ✅ 代理端口可达 (TcpTestSucceeded: True)" -ForegroundColor Green
        } else {
            Write-Host "  ❌ 无法连接到代理端口 ${pHost}:${pPort}！请检查代理客户端是否已启动。" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ⚠️ 读取代理配置失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 8. 守护日志摘要
Write-Host "`n[8] 最近 Guardian 守护日志 (最新 5 条):" -ForegroundColor Yellow
if (Test-Path -LiteralPath $guardianLog) {
    Get-Content -LiteralPath $guardianLog -Tail 5 -Encoding UTF8 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
} else {
    Write-Host "  暂无 Guardian 日志记录" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
