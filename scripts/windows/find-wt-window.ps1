# find-wt-window.ps1
# Finds Windows Terminal window by directory name in title, or returns first WT window
param(
    [string]$DirName,
    [string]$FullPath
)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class WTWindowFinder {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int nMaxCount);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static List<long[]> WTWindows = new List<long[]>();
    public static List<string> WTTitles = new List<string>();

    public static void FindWTWindows() {
        WTWindows.Clear();
        WTTitles.Clear();

        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var className = new StringBuilder(256);
                GetClassName(hWnd, className, 256);

                if (className.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") {
                    var title = new StringBuilder(512);
                    GetWindowText(hWnd, title, 512);
                    WTWindows.Add(new long[] { hWnd.ToInt64() });
                    WTTitles.Add(title.ToString());
                }
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@

# Find all Windows Terminal windows
[WTWindowFinder]::FindWTWindows()

$windows = [WTWindowFinder]::WTWindows
$titles = [WTWindowFinder]::WTTitles

if ($windows.Count -eq 0) {
    exit 1
}

# Strategy 1: Match by full path in title
if ($FullPath) {
    for ($i = 0; $i -lt $windows.Count; $i++) {
        if ($titles[$i] -like "*$FullPath*") {
            Write-Output $windows[$i][0]
            exit 0
        }
    }
}

# Strategy 2: Match by directory name in title
if ($DirName) {
    for ($i = 0; $i -lt $windows.Count; $i++) {
        if ($titles[$i] -like "*$DirName*") {
            Write-Output $windows[$i][0]
            exit 0
        }
    }
}

# Strategy 3: Return first WT window as fallback
Write-Output $windows[0][0]
exit 0
