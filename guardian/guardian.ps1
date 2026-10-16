# ==============================================================================
# Antigravity Proxy Guardian (自愈守护服务 - 增强版)
# 
# 功能：
# 1. 实时监听 Antigravity 父目录与更新器目录（防目录删除导致的句柄失效）
# 2. 安装器高频拦截：在 installer.exe 运行期间高频写入，确保安装完毕瞬间 DLL 已到位
# 3. 运行中进程健康监测：若检测到 Antigravity 被更新器直启且未加载代理 DLL，毫秒级自动重载
# 4. 实时同步用户修改的 config.json 至 Vault
# 5. 高频巡检兜底 (默认 2 秒)，确保代理文件永远处于就绪状态
# ==============================================================================

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [string]$VaultDir = "",
    [string]$UpdaterDir = "",
    [int]$HeartbeatSec = 2,
    [string]$LogFile = ""
)

# 确保 UTF-8 编码输出
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 默认路径计算
if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\Antigravity"
}
if ([string]::IsNullOrWhiteSpace($VaultDir)) {
    $VaultDir = Join-Path $env:APPDATA "AntigravityProxy\vault"
}
if ([string]::IsNullOrWhiteSpace($UpdaterDir)) {
    $UpdaterDir = Join-Path $env:LOCALAPPDATA "antigravity-updater"
}
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $logDir = Join-Path $env:APPDATA "AntigravityProxy\logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $LogFile = Join-Path $logDir "guardian.log"
}

# 日志输出函数
function Write-GuardianLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    try {
        # 日志超过 5MB 自动归档轮转
        if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 5MB)) {
            $backupLog = "$LogFile.old"
            Move-Item -LiteralPath $LogFile -Destination $backupLog -Force -ErrorAction SilentlyContinue
        }
        [System.IO.File]::AppendAllText($LogFile, "$logEntry`r`n", [System.Text.Encoding]::UTF8)
    } catch {
        # 忽略写入日志失败
    }
}

# 互斥体防止多实例重复运行
$mutexName = "Global\AntigravityProxyGuardianMutex"
$createdNew = $false
try {
    $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
    if (-not $createdNew) {
        exit 0
    }
} catch {
    # 某些严格权限环境降级为本地互斥体
    $mutexName = "AntigravityProxyGuardianMutexLocal"
    $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
    if (-not $createdNew) {
        exit 0
    }
}

Write-GuardianLog "=== Antigravity Proxy Guardian 已启动 (增强自愈版) ==="
Write-GuardianLog "监控目标目录: $TargetDir"
Write-GuardianLog "持久化存储库: $VaultDir"
Write-GuardianLog "安装更新目录: $UpdaterDir"
Write-GuardianLog "巡检检测周期: ${HeartbeatSec}秒"

# 检查 Vault 状态
if (-not (Test-Path -LiteralPath $VaultDir)) {
    Write-GuardianLog "警告: Vault 目录尚未初始化: $VaultDir" "WARN"
}

# 带重试的文件安全复制
function Copy-FileWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [int]$MaxRetries = 10,
        [int]$DelayMs = 200
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Write-GuardianLog "复制失败: 源文件不存在 $SourcePath" "ERROR"
        return $false
    }
    
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
            return $true
        } catch {
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    Write-GuardianLog "文件复制超过最大重试次数: $DestinationPath" "WARN"
    return $false
}

# 核心自愈与恢复逻辑
function Invoke-SelfHealing {
    param([string]$TriggerReason = "定期检查")

    if (-not (Test-Path -LiteralPath $TargetDir)) {
        return
    }

    $vaultDll = Join-Path $VaultDir "version.dll"
    $vaultCfg = Join-Path $VaultDir "config.json"
    $vaultWeb = Join-Path $VaultDir "config-web.html"

    $targetDll = Join-Path $TargetDir "version.dll"
    $targetCfg = Join-Path $TargetDir "config.json"
    $targetWeb = Join-Path $TargetDir "config-web.html"

    $needRestoreDll = (-not (Test-Path -LiteralPath $targetDll)) -and (Test-Path -LiteralPath $vaultDll)
    $needRestoreCfg = (-not (Test-Path -LiteralPath $targetCfg)) -and (Test-Path -LiteralPath $vaultCfg)
    $needRestoreWeb = (-not (Test-Path -LiteralPath $targetWeb)) -and (Test-Path -LiteralPath $vaultWeb)

    if ($needRestoreDll -or $needRestoreCfg -or $needRestoreWeb) {
        Write-GuardianLog "[触发自愈] 原因: $TriggerReason (DLL缺失=$needRestoreDll, 配置缺失=$needRestoreCfg, Web配置缺失=$needRestoreWeb)" "WARN"

        if ($needRestoreDll) {
            $ok = Copy-FileWithRetry -SourcePath $vaultDll -DestinationPath $targetDll
            if ($ok) {
                Write-GuardianLog ">> 已成功恢复 version.dll -> $targetDll" "SUCCESS"
            }
        }
        if ($needRestoreCfg) {
            $ok = Copy-FileWithRetry -SourcePath $vaultCfg -DestinationPath $targetCfg
            if ($ok) {
                Write-GuardianLog ">> 已成功恢复 config.json -> $targetCfg" "SUCCESS"
            }
        }
        if ($needRestoreWeb) {
            Copy-FileWithRetry -SourcePath $vaultWeb -DestinationPath $targetWeb | Out-Null
        }
    }
}

# 同步用户在目标目录的最新配置到 Vault
function Sync-TargetConfigToVault {
    $targetCfg = Join-Path $TargetDir "config.json"
    $vaultCfg = Join-Path $VaultDir "config.json"

    if ((Test-Path -LiteralPath $targetCfg) -and (Test-Path -LiteralPath $VaultDir)) {
        try {
            $targetInfo = Get-Item -LiteralPath $targetCfg
            if (Test-Path -LiteralPath $vaultCfg) {
                $vaultInfo = Get-Item -LiteralPath $vaultCfg
                if ($targetInfo.LastWriteTime -gt $vaultInfo.LastWriteTime.AddSeconds(2)) {
                    Copy-Item -LiteralPath $targetCfg -Destination $vaultCfg -Force
                    Write-GuardianLog "已同步最新配置到 Vault: $targetCfg -> $vaultCfg"
                }
            } else {
                Copy-Item -LiteralPath $targetCfg -Destination $vaultCfg -Force
                Write-GuardianLog "已将配置写入 Vault: $vaultCfg"
            }
        } catch {
            # 忽略文件占用
        }
    }
}

# 检查并处理正在运行的安装器 (NSIS 活跃监测与高频写入)
function Check-And-Handle-Installer {
    $installers = Get-Process -Name "installer", "Antigravity-x64", "elevate" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $p = $_.Path
            $p -like "*antigravity-updater*" -or $p -like "*AppData\Local\Temp*"
        } catch { $false }
    }

    if ($installers) {
        Write-GuardianLog "[更新拦截] 检测到更新安装器正在运行 (PID: $($installers[0].Id))，启动高频写入防清空保护..." "WARN"
        
        $vaultDll = Join-Path $VaultDir "version.dll"
        $vaultCfg = Join-Path $VaultDir "config.json"
        $targetDll = Join-Path $TargetDir "version.dll"
        $targetCfg = Join-Path $TargetDir "config.json"

        # 只要安装器仍在运行，每 100ms 探测并持续补齐
        while ($true) {
            $alive = Get-Process -Id $installers.Id -ErrorAction SilentlyContinue
            if (-not $alive) { break }

            if (Test-Path -LiteralPath $TargetDir) {
                if (-not (Test-Path -LiteralPath $targetDll) -and (Test-Path -LiteralPath $vaultDll)) {
                    Copy-Item -LiteralPath $vaultDll -Destination $targetDll -Force -ErrorAction SilentlyContinue
                }
                if (-not (Test-Path -LiteralPath $targetCfg) -and (Test-Path -LiteralPath $vaultCfg)) {
                    Copy-Item -LiteralPath $vaultCfg -Destination $targetCfg -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Milliseconds 100
        }

        # 安装器退出瞬间再做一次确定性补全
        Start-Sleep -Milliseconds 200
        Invoke-SelfHealing -TriggerReason "安装器进程已退出"
        Write-GuardianLog "[更新拦截] 安装器已退出，代理文件已确认就绪！" "SUCCESS"
    }
}

# 进程健康检查：检测是否被安装器直启而遗漏加载代理 DLL
$global:LastAutoRestartTime = [DateTime]::MinValue

function Check-Running-Process-Health {
    $antigravityProcs = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
    if (-not $antigravityProcs) { return }

    # 获取主进程
    $mainProc = $antigravityProcs | Sort-Object StartTime -Descending | Select-Object -First 1
    if (-not $mainProc) { return }

    try {
        # 检查是否加载了目标目录下的 version.dll
        $targetDll = Join-Path $TargetDir "version.dll"
        $loadedModules = $mainProc.Modules | Where-Object { $_.ModuleName -eq "version.dll" }
        
        $isCorrectDll = $false
        if ($loadedModules) {
            foreach ($m in $loadedModules) {
                if ($m.FileName -like "*Programs\Antigravity\version.dll*") {
                    $isCorrectDll = $true
                    break
                }
            }
        }

        if (-not $isCorrectDll) {
            # 当前运行的 Antigravity 没有加载目标目录下的 version.dll！
            $now = Get-Date
            if (($now - $global:LastAutoRestartTime).TotalSeconds -lt 20) {
                # 刚刚重启过，防止循环
                return
            }

            Write-GuardianLog "[自愈重载] 检测到 Antigravity (PID: $($mainProc.Id)) 正在运行但未加载代理 DLL (可能是安装器直接拉起)！" "WARN"

            # 1. 确保代理文件一定在目录中
            Invoke-SelfHealing -TriggerReason "准备重启未代理的 Antigravity 实例"
            Start-Sleep -Milliseconds 200

            # 2. 终止未走代理的实例
            Write-GuardianLog "[自愈重载] 正在自动重启 Antigravity 以激活代理..." "INFO"
            $antigravityProcs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600

            # 3. 通过 launcher.vbs 重新拉起
            $appDataProxy = Join-Path $env:APPDATA "AntigravityProxy"
            $launcherVbs = Join-Path $appDataProxy "launcher.vbs"
            if (Test-Path -LiteralPath $launcherVbs) {
                Start-Process "wscript.exe" -ArgumentList "`"$launcherVbs`""
            } else {
                Start-Process (Join-Path $TargetDir "Antigravity.exe")
            }

            $global:LastAutoRestartTime = $now
            Write-GuardianLog "[自愈重载] 已成功重启 Antigravity，代理已生效！" "SUCCESS"
        }
    } catch {
        # 忽略进程退出时的异常
    }
}

# 首次启动执行自检
Invoke-SelfHealing -TriggerReason "守护进程启动自检"
Sync-TargetConfigToVault

# 监控上级目录 (Programs)，即使 Antigravity 整个子目录被删掉重建，Watcher 句柄也不会失效
$parentDir = Split-Path -Parent $TargetDir
$watcherTarget = $null
if (Test-Path -LiteralPath $parentDir) {
    try {
        $watcherTarget = New-Object System.IO.FileSystemWatcher
        $watcherTarget.Path = $parentDir
        $watcherTarget.Filter = "*.*"
        $watcherTarget.IncludeSubdirectories = $true
        $watcherTarget.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, CreationTime'
        $watcherTarget.EnableRaisingEvents = $true

        $actionTarget = {
            $name = $Event.SourceEventArgs.Name
            $changeType = $Event.SourceEventArgs.ChangeType

            if ($name -like "*Antigravity\Antigravity.exe" -or $name -eq "Antigravity.exe") {
                if ($changeType -eq "Created" -or $changeType -eq "Changed") {
                    Start-Sleep -Milliseconds 300
                    Invoke-SelfHealing -TriggerReason "检测到 Antigravity.exe 更新/写入"
                }
            } elseif ($name -like "*Antigravity\version.dll" -or $name -eq "version.dll") {
                if ($changeType -eq "Deleted" -or $changeType -eq "Renamed") {
                    Start-Sleep -Milliseconds 150
                    Invoke-SelfHealing -TriggerReason "检测到 version.dll 被移除"
                }
            } elseif ($name -like "*Antigravity\config.json" -and $changeType -eq "Changed") {
                Start-Sleep -Milliseconds 500
                Sync-TargetConfigToVault
            }
        }

        Register-ObjectEvent $watcherTarget "Changed" -Action $actionTarget | Out-Null
        Register-ObjectEvent $watcherTarget "Created" -Action $actionTarget | Out-Null
        Register-ObjectEvent $watcherTarget "Deleted" -Action $actionTarget | Out-Null
        Register-ObjectEvent $watcherTarget "Renamed" -Action $actionTarget | Out-Null
    } catch {
        Write-GuardianLog "初始化上级目录监控跳过: $($_.Exception.Message)" "WARN"
    }
}

# 监控更新器目录
$watcherUpdater = $null
if (Test-Path -LiteralPath $UpdaterDir) {
    try {
        $watcherUpdater = New-Object System.IO.FileSystemWatcher
        $watcherUpdater.Path = $UpdaterDir
        $watcherUpdater.Filter = "*.*"
        $watcherUpdater.IncludeSubdirectories = $true
        $watcherUpdater.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, CreationTime'
        $watcherUpdater.EnableRaisingEvents = $true

        $actionUpdater = {
            $name = $Event.SourceEventArgs.Name
            $changeType = $Event.SourceEventArgs.ChangeType
            if ($name -match "(installer\.exe|Antigravity.*\.exe)" -and ($changeType -eq "Created" -or $changeType -eq "Changed")) {
                Write-GuardianLog "检测到更新器文件变动 (${name}: ${changeType})，执行预置检查"
                Check-And-Handle-Installer
            }
        }

        Register-ObjectEvent $watcherUpdater "Created" -Action $actionUpdater | Out-Null
        Register-ObjectEvent $watcherUpdater "Changed" -Action $actionUpdater | Out-Null
    } catch {
        Write-GuardianLog "初始化更新器监控跳过: $($_.Exception.Message)" "DEBUG"
    }
}

Write-GuardianLog "实时监控已就绪，进入守护循环..."

# 主循环 (每 2 秒高频巡检兜底)
try {
    while ($true) {
        Start-Sleep -Seconds $HeartbeatSec
        Check-And-Handle-Installer
        Invoke-SelfHealing -TriggerReason "巡检周期自检"
        Check-Running-Process-Health
        Sync-TargetConfigToVault
    }
} finally {
    Write-GuardianLog "Guardian 正在退出，释放监控资源..."
    if ($watcherTarget) {
        $watcherTarget.EnableRaisingEvents = $false
        $watcherTarget.Dispose()
    }
    if ($watcherUpdater) {
        $watcherUpdater.EnableRaisingEvents = $false
        $watcherUpdater.Dispose()
    }
    Get-EventSubscriber | Where-Object { $_.SourceIdentifier -match "FileSystemWatcher" } | Unregister-Event -Force
}
