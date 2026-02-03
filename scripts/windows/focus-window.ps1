# Flash the correct Windows Terminal taskbar icon based on shell PID
# Reads shellPid from notify-data.json and traces process tree to find owning WT window

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class TaskbarFlash {
    [DllImport("user32.dll")]
    public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
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

    // Get all Windows Terminal windows with their process IDs
    public static List<Tuple<IntPtr, uint>> GetAllWindowsTerminalWindows() {
        var windows = new List<Tuple<IntPtr, uint>>();
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetClassName(hWnd, sb, 256);
                if (sb.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") {
                    uint pid;
                    GetWindowThreadProcessId(hWnd, out pid);
                    windows.Add(Tuple.Create(hWnd, pid));
                }
            }
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    public static void FlashWindow(IntPtr hwnd) {
        FLASHWINFO fwi = new FLASHWINFO();
        fwi.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
        fwi.hwnd = hwnd;
        fwi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
        fwi.uCount = 0;
        fwi.dwTimeout = 0;
        FlashWindowEx(ref fwi);
    }
}
"@

# Find plugin directory (two levels up from this script)
$pluginDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dataFile = Join-Path $pluginDir "notify-data.json"
$shellPid = $null

if (Test-Path $dataFile) {
    try {
        $data = Get-Content $dataFile -Raw | ConvertFrom-Json
        $shellPid = $data.shellPid
    } catch {}
}

# Get all Windows Terminal windows
$wtWindows = [TaskbarFlash]::GetAllWindowsTerminalWindows()

if ($wtWindows.Count -eq 0) {
    exit 0
}

if ($wtWindows.Count -eq 1) {
    [TaskbarFlash]::FlashWindow($wtWindows[0].Item1)
    exit 0
}

# Multiple WT windows - find the one that owns our shell process
if ($shellPid) {
    $procs = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name
    $parentMap = @{}
    foreach ($p in $procs) {
        $parentMap[$p.ProcessId] = $p.ParentProcessId
    }

    $wtPids = @{}
    foreach ($wt in $wtWindows) {
        $wtPids[$wt.Item2] = $wt.Item1
    }

    $currentPid = $shellPid
    $maxDepth = 20
    $depth = 0

    while ($currentPid -and $depth -lt $maxDepth) {
        if ($wtPids.ContainsKey($currentPid)) {
            [TaskbarFlash]::FlashWindow($wtPids[$currentPid])
            exit 0
        }
        $currentPid = $parentMap[$currentPid]
        $depth++
    }
}

# Fallback: flash the first WT window
[TaskbarFlash]::FlashWindow($wtWindows[0].Item1)
