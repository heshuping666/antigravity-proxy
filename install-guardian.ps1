# ==============================================================================
# Antigravity Proxy Guardian - 快速安装入口
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

$installer = Join-Path $PSScriptRoot "guardian\install.ps1"
if (-not (Test-Path -LiteralPath $installer)) {
    Write-Error "未找到安装脚本: $installer"
    exit 1
}

$params = @{}
if ($TargetDir) { $params["TargetDir"] = $TargetDir }
if ($SourceDir) { $params["SourceDir"] = $SourceDir }
if ($NoShortcutPatch) { $params["NoShortcutPatch"] = $true }
if ($Force) { $params["Force"] = $true }

& $installer @params
