# ==============================================================================
# Antigravity Proxy Guardian (自愈守护服务)
# 
# 功能：
# 1. 实时监听 Antigravity 安装目录及更新器目录
# 2. 当 Antigravity 更新重装导致根目录的 version.dll / config.json 被清理时，自动从 Vault 持久化库恢复
# 3. 实时同步用户在应用中修改的 config.json 至 Vault
# 4. 心跳定时巡检兜底，确保代理文件永远处于就绪状态
# ==============================================================================

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [string]$VaultDir = "",
    [string]$UpdaterDir = "",
    [int]$HeartbeatSec = 30,
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

Write-GuardianLog "=== Antigravity Proxy Guardian 已启动 ==="
Write-GuardianLog "监控目标目录: $TargetDir"
Write-GuardianLog "持久化存储库: $VaultDir"
Write-GuardianLog "安装更新目录: $UpdaterDir"
Write-GuardianLog "心跳检测周期: ${HeartbeatSec}秒"

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
        [int]$DelayMs = 500
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
            Write-GuardianLog "写入 $DestinationPath 冲突 (尝试 $i/$MaxRetries): $($_.Exception.Message)" "WARN"
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    Write-GuardianLog "文件复制超过最大重试次数: $DestinationPath" "ERROR"
    return $false
}

# 核心自愈与恢复逻辑
function Invoke-SelfHealing {
    param([string]$TriggerReason = "定期检查")

    if (-not (Test-Path -LiteralPath $TargetDir)) {
        # 目标目录尚不存在，可能尚未安装 Antigravity
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
            Write-GuardianLog "同步配置到 Vault 失败: $($_.Exception.Message)" "WARN"
        }
    }
}

# 首次启动执行一次自愈检查与配置同步
Invoke-SelfHealing -TriggerReason "守护进程启动自检"
Sync-TargetConfigToVault

# 创建目标目录 FileSystemWatcher
$watcherTarget = New-Object System.IO.FileSystemWatcher
$watcherTarget.Path = $TargetDir
$watcherTarget.Filter = "*.*"
$watcherTarget.IncludeSubdirectories = $false
$watcherTarget.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, CreationTime'
$watcherTarget.EnableRaisingEvents = $true

# 绑定事件处理
$actionTarget = {
    $path = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    $name = $Event.SourceEventArgs.Name

    if ($name -eq "Antigravity.exe" -and ($changeType -eq "Created" -or $changeType -eq "Changed")) {
        # Antigravity 主程序变动，表明正在发生更新或安装
        Start-Sleep -Milliseconds 1200
        Invoke-SelfHealing -TriggerReason "检测到 Antigravity.exe 更新/写入"
    } elseif ($name -eq "version.dll" -and ($changeType -eq "Deleted" -or $changeType -eq "Renamed")) {
        # version.dll 被删除或重命名
        Start-Sleep -Milliseconds 500
        Invoke-SelfHealing -TriggerReason "检测到 version.dll 被移除"
    } elseif ($name -eq "config.json" -and $changeType -eq "Changed") {
        # 用户可能保存了配置
        Start-Sleep -Milliseconds 500
        Sync-TargetConfigToVault
    }
}

Register-ObjectEvent $watcherTarget "Changed" -Action $actionTarget | Out-Null
Register-ObjectEvent $watcherTarget "Created" -Action $actionTarget | Out-Null
Register-ObjectEvent $watcherTarget "Deleted" -Action $actionTarget | Out-Null
Register-ObjectEvent $watcherTarget "Renamed" -Action $actionTarget | Out-Null

# 若存在更新器目录，同样监控更新器变动
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
                Write-GuardianLog "检测到更新器正在准备新版本 (${name}: ${changeType})，预置恢复待命"
            }
        }

        Register-ObjectEvent $watcherUpdater "Created" -Action $actionUpdater | Out-Null
        Register-ObjectEvent $watcherUpdater "Changed" -Action $actionUpdater | Out-Null
    } catch {
        Write-GuardianLog "初始化更新器监控跳过: $($_.Exception.Message)" "DEBUG"
    }
}

Write-GuardianLog "实时监控已就绪，进入守护循环..."

# 运行主循环 (定期心跳检测兜底)
try {
    while ($true) {
        Start-Sleep -Seconds $HeartbeatSec
        Invoke-SelfHealing -TriggerReason "心跳周期自检"
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
