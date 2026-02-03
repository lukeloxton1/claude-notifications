/**
 * Claude Code Notification Hook - Cross-platform dispatcher
 *
 * Triggered on Stop event to show desktop notification with extracted message.
 * Supports Windows (BurntToast) and macOS (terminal-notifier).
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PLUGIN_DIR = path.dirname(__dirname);
const DATA_FILE = path.join(PLUGIN_DIR, 'notify-data.json');

// Read stdin (hook event data)
let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
  try {
    const json = JSON.parse(data);

    // Skip idle_prompt events
    if (json.type === 'idle_prompt') {
      return;
    }

    // Extract notification message
    let message = 'Response complete';

    if (json.message) {
      message = json.message;
    } else if (json.transcript_path && fs.existsSync(json.transcript_path)) {
      const transcript = fs.readFileSync(json.transcript_path, 'utf8');
      const lines = transcript.trim().split('\n');

      for (let i = lines.length - 1; i >= 0; i--) {
        try {
          const entry = JSON.parse(lines[i]);
          if (entry.type === 'assistant' && entry.message?.content) {
            const content = Array.isArray(entry.message.content)
              ? entry.message.content.map(c => c.text || '').join('')
              : entry.message.content;

            const match = content.match(/<!--\s*notify:\s*(.+?)\s*-->/i);
            if (match) {
              message = match[1].trim();
            }
            break;
          }
        } catch (e) { /* skip malformed line */ }
      }
    }

    if (message.length > 60) {
      message = message.substring(0, 57) + '...';
    }

    const cwd = json.cwd || process.cwd();

    // On Windows: look up HWND from sessions file using shell PID
    let wtWindowHandle = null;
    if (os.platform() === 'win32') {
      wtWindowHandle = lookupWindowHandle();
    }

    fs.writeFileSync(DATA_FILE, JSON.stringify({ message, wtWindowHandle, cwd }));

    if (os.platform() === 'win32') {
      notifyWindows();
    } else if (os.platform() === 'darwin') {
      notifyMacOS(message);
    }

  } catch (e) {
    if (os.platform() === 'win32') {
      try {
        execSync('pwsh -Command "New-BurntToastNotification -Text \\"Claude Code\\", \\"Response complete\\""', {
          windowsHide: true,
          timeout: 5000
        });
      } catch (e2) { /* silent */ }
    }
  }
});

/**
 * Find the Windows Terminal window that hosts our shell process.
 * Works by finding the conhost that belongs to our shell, then finding
 * which WT process owns that conhost.
 */
function lookupWindowHandle() {
  try {
    // PowerShell script that:
    // 1. Walks up from current PID to find the shell (pwsh/powershell/cmd)
    // 2. Finds all Windows Terminal windows
    // 3. Returns the HWND of the WT window whose process tree contains our shell
    const psScript = `
$ErrorActionPreference = 'SilentlyContinue'

# Get process tree info
$procs = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name

# Build lookup maps
$procMap = @{}
$childMap = @{}
foreach ($p in $procs) {
    $procMap[$p.ProcessId] = $p
    if (-not $childMap.ContainsKey($p.ParentProcessId)) {
        $childMap[$p.ParentProcessId] = @()
    }
    $childMap[$p.ParentProcessId] += $p.ProcessId
}

# Walk up from this process to find shell PID
$shellPid = $null
$currentPid = ${process.pid}
while ($currentPid -and $procMap.ContainsKey($currentPid)) {
    $proc = $procMap[$currentPid]
    $name = $proc.Name
    if ($name -eq 'pwsh.exe' -or $name -eq 'powershell.exe' -or $name -eq 'cmd.exe') {
        $shellPid = $proc.ProcessId
        break
    }
    $currentPid = $proc.ParentProcessId
}

if (-not $shellPid) { exit 1 }

# Now find which WindowsTerminal.exe is the ancestor of our shell
# Walk up from shell to find WindowsTerminal
$wtPid = $null
$currentPid = $shellPid
while ($currentPid -and $procMap.ContainsKey($currentPid)) {
    $proc = $procMap[$currentPid]
    if ($proc.Name -eq 'WindowsTerminal.exe') {
        $wtPid = $proc.ProcessId
        break
    }
    $currentPid = $proc.ParentProcessId
}

if (-not $wtPid) { exit 1 }

# Find the window handle for this WT process
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class WTFinder {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int nMaxCount);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public static List<long[]> WTWindows = new List<long[]>();
    public static void FindWTWindows() {
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetClassName(hWnd, sb, 256);
                if (sb.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") {
                    uint pid;
                    GetWindowThreadProcessId(hWnd, out pid);
                    WTWindows.Add(new long[] { hWnd.ToInt64(), pid });
                }
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@
[WTFinder]::FindWTWindows()

# Find the window that belongs to our WT process
foreach ($wt in [WTFinder]::WTWindows) {
    if ($wt[1] -eq $wtPid) {
        Write-Output $wt[0]
        exit 0
    }
}
exit 1
`;

    const result = execSync(`powershell -NoProfile -Command "${psScript.replace(/"/g, '\\"').replace(/\n/g, ' ')}"`, {
      encoding: 'utf8',
      windowsHide: true,
      timeout: 8000
    }).trim();

    if (result && !isNaN(parseInt(result))) {
      return parseInt(result);
    }
  } catch (e) {
    // Silent fail - will fallback to first WT window
  }
  return null;
}

function notifyWindows() {
  const script = path.join(PLUGIN_DIR, 'scripts', 'windows', 'notify-toast.ps1');
  if (fs.existsSync(script)) {
    try {
      const pwsh = fs.existsSync('C:\\Program Files\\PowerShell\\7\\pwsh.exe')
        ? '"C:\\Program Files\\PowerShell\\7\\pwsh.exe"'
        : 'powershell';

      execSync(`${pwsh} -ExecutionPolicy Bypass -File "${script}"`, {
        windowsHide: true,
        timeout: 5000,
        cwd: PLUGIN_DIR
      });
    } catch (e) { /* silent */ }
  }
}

function notifyMacOS(message) {
  const script = path.join(PLUGIN_DIR, 'scripts', 'macos', 'notify.sh');
  if (fs.existsSync(script)) {
    try {
      execSync(`bash "${script}" "${message.replace(/"/g, '\\"')}"`, {
        timeout: 5000,
        cwd: PLUGIN_DIR
      });
    } catch (e) { /* silent */ }
  }
}
