' ==============================================================================
' Antigravity Proxy Launcher - Self-healing launch wrapper (VBScript)
' Purpose: Intercept desktop shortcut, verify and restore version.dll & config.json
' ==============================================================================

Option Explicit

Dim WshShell, fso
Dim localAppData, appData, targetDir, exePath, dllPath, cfgPath, vaultDir, guardianVbs
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

' 1. Pre-launch check and self-healing (< 5ms)
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

' 2. Ensure background guardian process is active
guardianVbs = appData & "\AntigravityProxy\guardian.vbs"
If fso.FileExists(guardianVbs) Then
    WshShell.Run "wscript.exe """ & guardianVbs & """", 0, False
End If

' 3. Forward command-line arguments and launch main program
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next

If fso.FileExists(exePath) Then
    WshShell.CurrentDirectory = targetDir
    WshShell.Run """" & exePath & """" & args, 1, False
Else
    MsgBox "Antigravity main executable not found:" & vbCrLf & exePath, vbCritical, "Antigravity Proxy Launcher Error"
End If
