' Silent launcher for focus-window.ps1 (avoids PowerShell window flash)
' Called by claude-focus:// protocol handler

Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get script directory
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "focus-window.ps1")

' Try PowerShell 7 first, fall back to Windows PowerShell
pwsh7 = "C:\Program Files\PowerShell\7\pwsh.exe"
If fso.FileExists(pwsh7) Then
    cmd = """" & pwsh7 & """ -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & psScript & """"
Else
    cmd = "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & psScript & """"
End If

' Run hidden (0 = vbHide), don't wait (False)
objShell.Run cmd, 0, False
