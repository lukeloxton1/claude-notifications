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
  const msgDebugFile = path.join(os.homedir(), 'claude-notify-msg-debug.log');
  const msgDebug = (msg) => fs.appendFileSync(msgDebugFile, `${new Date().toISOString()} ${msg}\n`);

  try {
    const json = JSON.parse(data);
    msgDebug(`Event received: type=${json.type}, keys=${Object.keys(json).join(',')}`);
    msgDebug(`transcript_path=${json.transcript_path || 'NOT SET'}`);

    // Skip idle_prompt events
    if (json.type === 'idle_prompt') {
      return;
    }

    // Extract notification message
    let message = 'Response complete';

    if (json.message) {
      msgDebug(`Using json.message directly: ${json.message}`);
      message = json.message;
    } else if (json.transcript_path && fs.existsSync(json.transcript_path)) {
      msgDebug(`Reading transcript from: ${json.transcript_path}`);
      const transcript = fs.readFileSync(json.transcript_path, 'utf8');
      const lines = transcript.trim().split('\n');
      msgDebug(`Transcript has ${lines.length} lines`);

      // Search backwards through assistant entries for notify tag
      // Don't break early - transcript has multiple entries per turn (thinking, text, tool_use)
      let foundTag = false;
      for (let i = lines.length - 1; i >= 0 && !foundTag; i--) {
        try {
          const entry = JSON.parse(lines[i]);
          if (entry.type === 'assistant' && entry.message?.content) {
            const contentArr = Array.isArray(entry.message.content) ? entry.message.content : [entry.message.content];

            for (const c of contentArr) {
              const text = c.text || '';
              if (text.length > 0) {
                msgDebug(`Found text content, length=${text.length}`);
                const match = text.match(/<!--\s*notify:\s*(.+?)\s*-->/i);
                if (match) {
                  msgDebug(`Found notify tag: ${match[1]}`);
                  message = match[1].trim();
                  foundTag = true;
                  break;
                }
              }
            }
          }
        } catch (e) { /* skip malformed line */ }
      }
      if (!foundTag) {
        msgDebug(`No notify tag found in any assistant message`);
      }
    } else {
      msgDebug(`transcript_path not available or file doesn't exist`);
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

    debug('Falling back to Strategy 3 (title match via script)');
    // Strategy 3: Match by title or fallback to first WT window using external script
    const findScript = path.join(PLUGIN_DIR, 'scripts', 'windows', 'find-wt-window.ps1');
    if (fs.existsSync(findScript)) {
      const escapedDir = dirName.replace(/'/g, "''");
      const escapedPath = cwd ? cwd.replace(/'/g, "''") : '';
      const result = execSync(`powershell -ExecutionPolicy Bypass -NoProfile -File "${findScript}" -DirName '${escapedDir}' -FullPath '${escapedPath}'`, {
        encoding: 'utf8',
        windowsHide: true,
        timeout: 8000
      }).trim();

      if (result && !isNaN(parseInt(result))) {
        const hwnd = parseInt(result);
        debug(`Strategy 3 returned: ${hwnd}`);

        // Auto-register this HWND so we don't have to search next time
        if (cwd) {
          try {
            let sessions = {};
            if (fs.existsSync(sessionsFile)) {
              sessions = JSON.parse(fs.readFileSync(sessionsFile, 'utf8'));
            }
            sessions[cwd] = hwnd;
            fs.writeFileSync(sessionsFile, JSON.stringify(sessions, null, 2));
            debug(`Auto-registered HWND ${hwnd} for ${cwd}`);
          } catch (e) {
            debug(`Failed to auto-register: ${e.message}`);
          }
        }

        return hwnd;
      }
      debug('Strategy 3 returned nothing');
    } else {
      debug(`Script not found: ${findScript}`);
    }
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
