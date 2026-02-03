/**
 * Claude Code Notification Hook - Cross-platform dispatcher
 *
 * Triggered on Stop event to show desktop notification with extracted message.
 * Supports Windows (BurntToast) and macOS (terminal-notifier).
 */

const { execSync, spawn } = require('child_process');
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

    // Use provided message if available
    if (json.message) {
      message = json.message;
    }
    // Extract <!-- notify: ... --> from transcript
    else if (json.transcript_path && fs.existsSync(json.transcript_path)) {
      const transcript = fs.readFileSync(json.transcript_path, 'utf8');
      const lines = transcript.trim().split('\n');

      // Find last assistant message and extract notify tag
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

    // Truncate long messages
    if (message.length > 60) {
      message = message.substring(0, 57) + '...';
    }

    // Find shell PID (for window focus on Windows)
    let shellPid = null;
    if (os.platform() === 'win32') {
      shellPid = findShellPid();
    }

    // Get working directory for context
    const cwd = json.cwd || process.cwd();

    // Write data for platform scripts
    fs.writeFileSync(DATA_FILE, JSON.stringify({ message, shellPid, cwd }));

    // Dispatch to platform-specific notification
    if (os.platform() === 'win32') {
      notifyWindows();
    } else if (os.platform() === 'darwin') {
      notifyMacOS(message);
    }

  } catch (e) {
    // Fallback: try basic notification
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
 * Find the shell process (pwsh/cmd) that's the ancestor of claude.exe
 */
function findShellPid() {
  try {
    const result = execSync('powershell -NoProfile -Command "Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name | ConvertTo-Json"', {
      encoding: 'utf8',
      windowsHide: true,
      timeout: 5000
    });

    const procs = JSON.parse(result);
    const procMap = {};
    for (const p of procs) procMap[p.ProcessId] = p;

    // Walk up process tree from current process
    let pid = process.pid;
    let foundClaude = false;

    while (pid && procMap[pid]) {
      const proc = procMap[pid];

      if (foundClaude && (proc.Name === 'pwsh.exe' || proc.Name === 'powershell.exe' || proc.Name === 'cmd.exe')) {
        return proc.ProcessId;
      }
      if (proc.Name === 'claude.exe') {
        foundClaude = true;
      }
      pid = proc.ParentProcessId;
    }
  } catch (e) {
    // Silently fail - focus will use fallback
  }
  return null;
}

/**
 * Show notification on Windows using BurntToast
 */
function notifyWindows() {
  const script = path.join(PLUGIN_DIR, 'scripts', 'windows', 'notify-toast.ps1');
  if (fs.existsSync(script)) {
    try {
      // Find PowerShell 7 or fall back to Windows PowerShell
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

/**
 * Show notification on macOS using terminal-notifier
 */
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
