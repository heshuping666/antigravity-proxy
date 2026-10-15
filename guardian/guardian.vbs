' ==============================================================================
' Antigravity Proxy Guardian - 静默后台启动器 (VBScript)
' 用途：无黑框、静默在后台启动 guardian.ps1
' ==============================================================================

Option Explicit

Dim WshShell, fso, scriptDir, psScript, cmd

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\guardian.ps1"

If Not fso.FileExists(psScript) Then
    ' 回退查找 APPDATA 默认目录
    psScript = WshShell.ExpandEnvironmentStrings("%APPDATA%") & "\AntigravityProxy\guardian.ps1"
End If

If fso.FileExists(psScript) Then
    cmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File """ & psScript & """"
    ' 第二个参数 0 表示隐藏窗口，第三个参数 False 表示异步运行无需等待
    WshShell.Run cmd, 0, False
End If
