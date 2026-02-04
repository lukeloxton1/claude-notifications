# Register-Session.ps1
# Captures the current foreground window (Windows Terminal) and stores it in an environment variable.
# This variable is inherited by all child processes (including Claude), so it works regardless of cwd.
# Add to your PowerShell profile: . "$HOME\claude-notify\scripts\windows\Register-Session.ps1"

$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FGWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

$hwnd = [FGWindow]::GetForegroundWindow().ToInt64()

# Set environment variable for this session (inherited by child processes)
$env:CLAUDE_WT_HWND = $hwnd

# Also save to sessions file as backup (keyed by shell PID)
$sessionsFile = Join-Path $HOME ".claude-wt-sessions.json"
$sessions = @{}

if (Test-Path $sessionsFile) {
    try {
        $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        $sessions = @{}
    }
}

$sessions["pid:$PID"] = $hwnd

# Clean up old PIDs
$toRemove = @()
foreach ($key in $sessions.Keys) {
    if ($key -like "pid:*") {
        $oldPid = [int]($key -replace "pid:", "")
        if (-not (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
            $toRemove += $key
        }
    }
}
foreach ($key in $toRemove) { $sessions.Remove($key) }

$sessions | ConvertTo-Json | Set-Content $sessionsFile -Force
