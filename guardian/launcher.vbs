' ==============================================================================
' Antigravity Proxy Launcher - 自愈启动包装器 (VBScript)
' 用途：接管桌面/开始菜单快捷方式，启动前毫秒级确认并补全 version.dll / config.json
' ==============================================================================

Option Explicit

Dim WshShell, fso
Dim localAppData, appData, targetDir, exePath, dllPath, cfgPath, vaultDir
Dim i, args, cmd

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

localAppData = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
appData = WshShell.ExpandEnvironmentStrings("%APPDATA%")

targetDir = localAppData & "\Programs\Antigravity"
exePath = targetDir & "\Antigravity.exe"
dllPath = targetDir & "\version.dll"
cfgPath = targetDir & "\config.json"
vaultDir = appData & "\AntigravityProxy\vault"

' 1. 启动前自检与自愈 (耗时 < 5ms)
If fso.FolderExists(targetDir) And fso.FolderExists(vaultDir) Then
    If (Not fso.FileExists(dllPath)) And fso.FileExists(vaultDir & "\version.dll") Then
        fso.CopyFile vaultDir & "\version.dll", dllPath, True
    End If
    If (Not fso.FileExists(cfgPath)) And fso.FileExists(vaultDir & "\config.json") Then
        fso.CopyFile vaultDir & "\config.json", cfgPath, True
    End If
    If (Not fso.FileExists(targetDir & "\config-web.html")) And fso.FileExists(vaultDir & "\config-web.html") Then
        fso.CopyFile vaultDir & "\config-web.html", targetDir & "\config-web.html", True
    End If
End If

' 2. 检查守护进程是否在跑，若未在跑则拉起
Dim guardianVbs
guardianVbs = appData & "\AntigravityProxy\guardian.vbs"
If fso.FileExists(guardianVbs) Then
    ' 异步轻量检测/拉起
    WshShell.Run "wscript.exe """ & guardianVbs & """", 0, False
End If

' 3. 透传命令行参数并启动主程序
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next

If fso.FileExists(exePath) Then
    WshShell.CurrentDirectory = targetDir
    WshShell.Run """" & exePath & """" & args, 1, False
Else
    MsgBox "未找到 Antigravity 主程序: " & exePath, vbCritical, "Antigravity Proxy Launcher 错误"
End If
