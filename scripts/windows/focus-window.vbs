' Silent launcher for focus-window.ps1 (avoids PowerShell window flash)
' Called by claude-focus:// protocol handler
' Passes the protocol URL to the PowerShell script for HWND extraction

Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the protocol URL passed as argument (e.g., claude-focus://focus/18615308)
protocolUrl = ""
If WScript.Arguments.Count > 0 Then
    protocolUrl = WScript.Arguments(0)
End If

' Get script directory
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "focus-window.ps1")

' Try PowerShell 7 first, fall back to Windows PowerShell
pwsh7 = "C:\Program Files\PowerShell\7\pwsh.exe"
If fso.FileExists(pwsh7) Then
    cmd = """" & pwsh7 & """ -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & psScript & """ -Url """ & protocolUrl & """"
Else
    cmd = "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & psScript & """ -Url """ & protocolUrl & """"
End If

' Run hidden (0 = vbHide), don't wait (False)
objShell.Run cmd, 0, False
