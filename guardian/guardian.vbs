' ==============================================================================
' Antigravity Proxy Guardian - Silent background launcher (VBScript)
' Purpose: Launch guardian.ps1 silently without console window
' ==============================================================================

Option Explicit

Dim WshShell, fso, scriptDir, psScript, cmd

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\guardian.ps1"

If Not fso.FileExists(psScript) Then
    ' Fallback to APPDATA default path
    psScript = WshShell.ExpandEnvironmentStrings("%APPDATA%") & "\AntigravityProxy\guardian.ps1"
End If

If fso.FileExists(psScript) Then
    cmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File """ & psScript & """"
    WshShell.Run cmd, 0, False
End If
