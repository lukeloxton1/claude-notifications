# Flash the Windows Terminal window
# HWND can be passed via protocol URL (claude-focus://focus/HWND) or read from notify-data.json
param([string]$Url)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class TaskbarFlash {
    [DllImport("user32.dll")]
    public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct FLASHWINFO {
        public uint cbSize;
        public IntPtr hwnd;
        public uint dwFlags;
        public uint uCount;
        public uint dwTimeout;
    }

    public const uint FLASHW_ALL = 3;
    public const uint FLASHW_TIMERNOFG = 12;

    public static void FlashWindow(IntPtr hwnd) {
        FLASHWINFO fwi = new FLASHWINFO();
        fwi.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
        fwi.hwnd = hwnd;
        fwi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
        fwi.uCount = 0;
        fwi.dwTimeout = 0;
        FlashWindowEx(ref fwi);
    }

    public static IntPtr FindFirstWTWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetClassName(hWnd, sb, 256);
                if (sb.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") {
                    found = hWnd;
                    return false; // stop enumeration
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

# Find plugin directory (two levels up from this script)
$pluginDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dataFile = Join-Path $pluginDir "notify-data.json"

$hwnd = [IntPtr]::Zero

# Strategy 1: Parse HWND from protocol URL (e.g., claude-focus://focus/18615308)
if ($Url -match 'claude-focus://focus/(\d+)') {
    $hwnd = [IntPtr]::new([long]$Matches[1])
}

# Strategy 2: Fall back to reading from data file
if ($hwnd -eq [IntPtr]::Zero -and (Test-Path $dataFile)) {
    try {
        $data = Get-Content $dataFile -Raw | ConvertFrom-Json
        if ($data.wtWindowHandle) {
            $hwnd = [IntPtr]::new([long]$data.wtWindowHandle)
        }
    } catch {}
}

# Validate the stored handle is still a valid WT window
if ($hwnd -ne [IntPtr]::Zero) {
    if ([TaskbarFlash]::IsWindow($hwnd)) {
        $sb = New-Object System.Text.StringBuilder 256
        [void][TaskbarFlash]::GetClassName($hwnd, $sb, 256)
        if ($sb.ToString() -eq "CASCADIA_HOSTING_WINDOW_CLASS") {
            [TaskbarFlash]::FlashWindow($hwnd)
            exit 0
        }
    }
}

# Fallback: flash the first WT window we find
$fallback = [TaskbarFlash]::FindFirstWTWindow()
if ($fallback -ne [IntPtr]::Zero) {
    [TaskbarFlash]::FlashWindow($fallback)
}
