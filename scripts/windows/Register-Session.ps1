# Register-Session.ps1
# Captures the current foreground window (Windows Terminal) and registers it for claude-notify.
# This enables notifications to flash the correct terminal window.
#
# Usage: Source this in your profile, then use Start-Claude to launch claude:
#   . "$HOME\claude-notify\scripts\windows\Register-Session.ps1"
#   Start-Claude  # or just 'claude' if you set up the alias

$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FGWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

function Register-ClaudeSession {
    <#
    .SYNOPSIS
    Registers the current terminal window for claude-notify.
    Called automatically by Start-Claude, but can be called manually if needed.
    #>
    $hwnd = [FGWindow]::GetForegroundWindow().ToInt64()
    $cwd = $PWD.Path

    # Set environment variable (inherited by child processes)
    $env:CLAUDE_WT_HWND = $hwnd

    # Save to sessions file keyed by cwd (primary lookup method)
    $sessionsFile = Join-Path $HOME ".claude-wt-sessions.json"
    $sessions = @{}

    if (Test-Path $sessionsFile) {
        try {
            $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            $sessions = @{}
        }
    }

    # Store by current working directory (primary key for notify.js lookup)
    $sessions[$cwd] = $hwnd

    # Also store by PID as backup
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

    return $hwnd
}

function Start-Claude {
    <#
    .SYNOPSIS
    Registers the current terminal window and launches Claude Code.
    This ensures notifications will flash the correct window.

    .EXAMPLE
    Start-Claude
    Start-Claude -ArgumentList "--help"
    #>
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ArgumentList
    )

    # Register this window/cwd before launching claude
    $null = Register-ClaudeSession

    # Launch claude with any provided arguments
    if ($ArgumentList) {
        & claude @ArgumentList
    } else {
        & claude
    }
}

# Create alias for convenience
Set-Alias -Name c -Value Start-Claude -Scope Global

# Auto-register on profile load (captures the window when terminal opens)
$null = Register-ClaudeSession
