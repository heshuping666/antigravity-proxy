# ==============================================================================
# Antigravity Proxy Guardian 一键安装与配置脚本
# 
# 功能：
# 1. 初始化持久化 Vault 目录 (%APPDATA%\AntigravityProxy)
# 2. 部署 version.dll、config.json 到 Antigravity 目录
# 3. 创建并启动开机静默常驻的 Windows 计划任务
# 4. 增强桌面与开始菜单快捷方式（自愈双保险）
# ==============================================================================

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [string]$SourceDir = "",
    [switch]$NoShortcutPatch,
    [switch]$Force
)

# 确保 UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     Antigravity Proxy Guardian - 自动守护与自愈安装器    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. 解析目标目录
if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\Antigravity"
}
Write-Host "[1/6] 检查 Antigravity 安装目录: $TargetDir" -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $TargetDir)) {
    Write-Warning "未在默认路径检测到 Antigravity 目录: $TargetDir"
    $custom = Read-Host "请输入 Antigravity.exe 所在的主程序目录 (留空退出)"
    if ([string]::IsNullOrWhiteSpace($custom)) {
        Write-Error "已取消安装。"
        exit 1
    }
    $TargetDir = $custom.Trim('"', ' ')
}

if (-not (Test-Path -LiteralPath (Join-Path $TargetDir "Antigravity.exe"))) {
    Write-Warning "提示: 目标目录下暂未发现 Antigravity.exe，请确认路径是否正确。"
}

# 2. 寻找 source 文件 (version.dll, config.json)
Write-Host "[2/6] 寻找 proxy 核心文件 (version.dll, config.json)..." -ForegroundColor Yellow
$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptRoot

$searchCandidates = @(
    $SourceDir,
    (Join-Path $repoRoot "ide"),
    (Join-Path $repoRoot "output\ide"),
    (Join-Path $env:USERPROFILE "Desktop\antigravity-proxy*\ide"),
    $TargetDir
)

$srcDll = $null
$srcCfg = $null
$srcWeb = $null

foreach ($cand in $searchCandidates) {
    if ([string]::IsNullOrWhiteSpace($cand)) { continue }
    $resolved = Resolve-Path -Path $cand -ErrorAction SilentlyContinue
    if (-not $resolved) { continue }
    $candPath = $resolved.Path

    $testDll = Join-Path $candPath "version.dll"
    $testCfg = Join-Path $candPath "config.json"
    $testWeb = Join-Path $candPath "config-web.html"
    if (-not (Test-Path $testWeb)) {
        $testWeb = Join-Path (Split-Path -Parent $candPath) "config-web.html"
    }

    if (-not $srcDll -and (Test-Path -LiteralPath $testDll)) { $srcDll = $testDll }
    if (-not $srcCfg -and (Test-Path -LiteralPath $testCfg)) { $srcCfg = $testCfg }
    if (-not $srcWeb -and (Test-Path -LiteralPath $testWeb)) { $srcWeb = $testWeb }

    if ($srcDll -and $srcCfg) { break }
}

if (-not $srcDll -or -not $srcCfg) {
    Write-Error "未能定位到 version.dll 或 config.json！请通过 -SourceDir 参数指定包含这些文件的目录。"
    exit 1
}
Write-Host "  -> 找到核心文件: DLL=$srcDll, Config=$srcCfg" -ForegroundColor Green

# 3. 初始化持久化 Vault
$appDataProxy = Join-Path $env:APPDATA "AntigravityProxy"
$vaultDir = Join-Path $appDataProxy "vault"
$logDir = Join-Path $appDataProxy "logs"

Write-Host "[3/6] 初始化持久化库: $vaultDir" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $vaultDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Copy-Item -LiteralPath $srcDll -Destination (Join-Path $vaultDir "version.dll") -Force
Copy-Item -LiteralPath $srcCfg -Destination (Join-Path $vaultDir "config.json") -Force
if ($srcWeb -and (Test-Path -LiteralPath $srcWeb)) {
    Copy-Item -LiteralPath $srcWeb -Destination (Join-Path $vaultDir "config-web.html") -Force
}

# 复制 guardian 运行脚本到 APPDATA 长期常驻目录（标准化保证 CRLF 换行，防止 ANSI 解析异常）
Copy-Item -LiteralPath (Join-Path $scriptRoot "guardian.ps1") -Destination (Join-Path $appDataProxy "guardian.ps1") -Force
foreach ($vbsName in @("guardian.vbs", "launcher.vbs")) {
    $srcVbs = Join-Path $scriptRoot $vbsName
    $dstVbs = Join-Path $appDataProxy $vbsName
    $vbsContent = [System.IO.File]::ReadAllText($srcVbs, [System.Text.Encoding]::UTF8)
    $normalizedContent = $vbsContent -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText($dstVbs, $normalizedContent, [System.Text.Encoding]::ASCII)
}

# 4. 同步写入目标目录
Write-Host "[4/6] 部署到 Antigravity 安装目录..." -ForegroundColor Yellow
$destDll = Join-Path $TargetDir "version.dll"
$destCfg = Join-Path $TargetDir "config.json"
$destWeb = Join-Path $TargetDir "config-web.html"

if (-not (Test-Path -LiteralPath $destDll) -or $Force) {
    try {
        Copy-Item -LiteralPath (Join-Path $vaultDir "version.dll") -Destination $destDll -Force -ErrorAction Stop
    } catch {
        Write-Host "  -> version.dll 已存在且当前正被运行中的 Antigravity 锁定使用" -ForegroundColor Cyan
    }
}
if (-not (Test-Path -LiteralPath $destCfg) -or $Force) {
    Copy-Item -LiteralPath (Join-Path $vaultDir "config.json") -Destination $destCfg -Force
}
if (Test-Path -LiteralPath (Join-Path $vaultDir "config-web.html")) {
    Copy-Item -LiteralPath (Join-Path $vaultDir "config-web.html") -Destination $destWeb -Force
}
Write-Host "  -> version.dll 与 config.json 已就绪！" -ForegroundColor Green

# 5. 注册并启动 Windows 计划任务
Write-Host "[5/6] 配置 Windows 后台守护任务..." -ForegroundColor Yellow
$taskName = "AntigravityProxyGuardian"
$guardianVbsPath = Join-Path $appDataProxy "guardian.vbs"

try {
    # 停止已有同名任务
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$guardianVbsPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Priority 7

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Antigravity 代理文件防更新清理自愈守护任务" | Out-Null
    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  -> 计划任务 [$taskName] 注册并启动成功 (开机静默启动，无黑框)" -ForegroundColor Green
} catch {
    Write-Warning "注册计划任务失败: $($_.Exception.Message)。正在尝试加入当前用户启动文件夹..."
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut((Join-Path $startupFolder "AntigravityProxyGuardian.lnk"))
    $shortcut.TargetPath = "wscript.exe"
    $shortcut.Arguments = "`"$guardianVbsPath`""
    $shortcut.WindowStyle = 7 # Minimized
    $shortcut.Save()
    Write-Host "  -> 已添加到用户启动文件夹: $startupFolder" -ForegroundColor Green
}

# 6. 快捷方式增强（双保险机制）
if (-not $NoShortcutPatch) {
    Write-Host "[6/6] 增强桌面快捷方式（启动前毫秒级自愈双保险）..." -ForegroundColor Yellow
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktopPath "Antigravity.lnk"
    $launcherVbsPath = Join-Path $appDataProxy "launcher.vbs"
    $exePath = Join-Path $TargetDir "Antigravity.exe"

    if (Test-Path -LiteralPath $lnkPath) {
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $origLnk = Join-Path $desktopPath "Antigravity.original.lnk"
            if (-not (Test-Path -LiteralPath $origLnk)) {
                Copy-Item -LiteralPath $lnkPath -Destination $origLnk -Force
            }

            $shortcut = $wsh.CreateShortcut($lnkPath)
            $shortcut.TargetPath = "wscript.exe"
            $shortcut.Arguments = "`"$launcherVbsPath`""
            $shortcut.WorkingDirectory = $TargetDir
            $shortcut.IconLocation = "$exePath,0"
            $shortcut.Description = "Antigravity (Proxy Guarded)"
            $shortcut.Save()
            Write-Host "  -> 桌面快捷方式已强化保护 (原快捷方式已备份为 Antigravity.original.lnk)" -ForegroundColor Green
        } catch {
            Write-Warning "修改桌面快捷方式跳过: $($_.Exception.Message)"
        }
    } else {
        Write-Host "  -> 桌面未检测到 Antigravity.lnk，跳过快捷方式修补" -ForegroundColor Gray
    }
} else {
    Write-Host "[6/6] 用户选择跳过快捷方式修补" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " 🎉 Antigravity Proxy Guardian 安装配置成功！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "1. 后台守护已启动：每当 Antigravity 自动更新重装时，Guardian 将自动补齐 version.dll 与 config.json。"
Write-Host "2. 快捷方式已强化：每次点击桌面图标启动，都会在 5ms 内自检补齐文件，彻底告别失效痛点。"
Write-Host "3. 配置文件目录: $vaultDir\config.json"
Write-Host "4. 守护日志文件: $logDir\guardian.log"
Write-Host "5. 状态检查命令: powershell -File `"$scriptRoot\status.ps1`""
Write-Host ""
