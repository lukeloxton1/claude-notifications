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

    // On Windows: look up HWND from sessions file
    let wtWindowHandle = null;
    if (os.platform() === 'win32') {
      wtWindowHandle = lookupWindowHandle(cwd);
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
 * Find the Windows Terminal window for this session.
 *
 * Strategy:
 * 1. Check if we have a registered HWND for this working directory
 * 2. If not, try to match by window title containing the directory name
 * 3. Fallback to first WT window
 *
 * Note: Due to WT's architecture, shells are NOT children of WindowsTerminal.exe,
 * so we can't use process tree walking. Session registration is the most reliable.
 */
function lookupWindowHandle(cwd) {
  const debugFile = path.join(os.homedir(), 'claude-notify-debug.log');
  const debug = (msg) => fs.appendFileSync(debugFile, `${new Date().toISOString()} ${msg}\n`);

  try {
    debug(`lookupWindowHandle called with cwd: ${cwd}`);
    const dirName = cwd ? path.basename(cwd) : '';
    const sessionsFile = path.join(os.homedir(), '.claude-wt-sessions.json');

    // Strategy 1: Check CLAUDE_WT_HWND environment variable (fastest - inherited from shell)
    if (process.env.CLAUDE_WT_HWND) {
      debug(`Found HWND from env: ${process.env.CLAUDE_WT_HWND}`);
      return parseInt(process.env.CLAUDE_WT_HWND);
    }

    // Strategy 2: Check registered sessions by cwd
    if (fs.existsSync(sessionsFile)) {
      try {
        const sessions = JSON.parse(fs.readFileSync(sessionsFile, 'utf8'));
        debug(`Sessions loaded, keys: ${Object.keys(sessions).join(', ')}`);

        // Lookup by cwd
        if (cwd && sessions[cwd]) {
          debug(`Found HWND by cwd: ${sessions[cwd]}`);
          return parseInt(sessions[cwd]);
        }
        debug(`No match for cwd "${cwd}"`);
      } catch (e) {
        debug(`Strategy 2 failed: ${e.message}`);
      }
    }

    debug('Falling back to Strategy 2/3 (title match or first WT)');
    // Strategy 2 & 3: Match by title or fallback to first WT window
    const psScript = `
param($DirName)
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class WTMatcher {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int n);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public static List<object[]> WTWindows = new List<object[]>();
    public static void FindWTWindows() {
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var cls = new StringBuilder(256);
                GetClassName(hWnd, cls, 256);
                if (cls.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") {
                    var title = new StringBuilder(512);
                    GetWindowText(hWnd, title, 512);
                    WTWindows.Add(new object[] { hWnd.ToInt64(), title.ToString() });
                }
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@

[WTMatcher]::FindWTWindows()

# Try to match by directory name in title
if ($DirName) {
    foreach ($wt in [WTMatcher]::WTWindows) {
        if ($wt[1] -like "*$DirName*") {
            Write-Output $wt[0]
            exit 0
        }
    }
}

# Fallback: return first WT window
if ([WTMatcher]::WTWindows.Count -gt 0) {
    Write-Output ([WTMatcher]::WTWindows[0][0])
    exit 0
}
exit 1
`;

    const escapedDir = dirName.replace(/'/g, "''");
    const result = execSync(`powershell -NoProfile -Command "& { ${psScript.replace(/"/g, '\\"').replace(/\n/g, ' ')} } -DirName '${escapedDir}'"`, {
      encoding: 'utf8',
      windowsHide: true,
      timeout: 8000
    }).trim();

    if (result && !isNaN(parseInt(result))) {
      debug(`Strategy 2/3 returned: ${result}`);
      return parseInt(result);
    }
    debug('Strategy 2/3 returned nothing');
  } catch (e) {
    debug(`lookupWindowHandle error: ${e.message}`);
  }
  debug('Returning null');
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
