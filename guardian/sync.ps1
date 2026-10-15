# ==============================================================================
# Antigravity Proxy 配置文件双向同步工具
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet("ToVault", "ToAntigravity", "Auto")]
    [string]$Direction = "Auto",
    [string]$TargetDir = ""
)

# 确保 UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Join-Path $env:LOCALAPPDATA "Programs\Antigravity"
}
$vaultDir = Join-Path $env:APPDATA "AntigravityProxy\vault"

$targetCfg = Join-Path $TargetDir "config.json"
$vaultCfg = Join-Path $vaultDir "config.json"

if (-not (Test-Path -LiteralPath $vaultDir)) {
    New-Item -ItemType Directory -Path $vaultDir -Force | Out-Null
}

switch ($Direction) {
    "ToVault" {
        if (Test-Path -LiteralPath $targetCfg) {
            Copy-Item -LiteralPath $targetCfg -Destination $vaultCfg -Force
            Write-Host "已同步配置: Antigravity -> Vault ($vaultCfg)" -ForegroundColor Green
        } else {
            Write-Error "源文件不存在: $targetCfg"
        }
    }
    "ToAntigravity" {
        if (Test-Path -LiteralPath $vaultCfg) {
            Copy-Item -LiteralPath $vaultCfg -Destination $targetCfg -Force
            Write-Host "已同步配置: Vault -> Antigravity ($targetCfg)" -ForegroundColor Green
        } else {
            Write-Error "源文件不存在: $vaultCfg"
        }
    }
    "Auto" {
        if ((Test-Path -LiteralPath $targetCfg) -and (Test-Path -LiteralPath $vaultCfg)) {
            $tTime = (Get-Item -LiteralPath $targetCfg).LastWriteTime
            $vTime = (Get-Item -LiteralPath $vaultCfg).LastWriteTime
            if ($tTime -gt $vTime) {
                Copy-Item -LiteralPath $targetCfg -Destination $vaultCfg -Force
                Write-Host "检测到 Antigravity 配置较新，已同步至 Vault。" -ForegroundColor Green
            } elseif ($vTime -gt $tTime) {
                Copy-Item -LiteralPath $vaultCfg -Destination $targetCfg -Force
                Write-Host "检测到 Vault 配置较新，已同步至 Antigravity。" -ForegroundColor Green
            } else {
                Write-Host "两处配置时间戳一致，无需同步。" -ForegroundColor Cyan
            }
        } elseif (Test-Path -LiteralPath $targetCfg) {
            Copy-Item -LiteralPath $targetCfg -Destination $vaultCfg -Force
            Write-Host "初始化 Vault 配置完毕。" -ForegroundColor Green
        } elseif (Test-Path -LiteralPath $vaultCfg) {
            Copy-Item -LiteralPath $vaultCfg -Destination $targetCfg -Force
            Write-Host "从 Vault 恢复配置到 Antigravity 完毕。" -ForegroundColor Green
        }
    }
}
