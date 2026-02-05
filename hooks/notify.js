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

// Read stdin (hook event data)
let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
  const msgDebugFile = path.join(PLUGIN_DIR, 'logs', 'notify-debug.log');
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

      // Simple approach: Wait for transcript to be written, then extract tag
      // The Stop hook fires before transcript is fully written, so we need a delay
      msgDebug('Waiting 300ms for transcript to be written...');
      const start = Date.now();
      while (Date.now() - start < 300) { /* wait */ }

      const transcript = fs.readFileSync(json.transcript_path, 'utf8');
      const lines = transcript.trim().split('\n');
      msgDebug(`Transcript has ${lines.length} lines after delay`);

      // Search backwards through assistant entries for notify tag
      for (let i = lines.length - 1; i >= 0; i--) {
        try {
          const entry = JSON.parse(lines[i]);
          if (entry.type === 'assistant' && entry.message?.content) {
            const contentArr = Array.isArray(entry.message.content) ? entry.message.content : [entry.message.content];

            for (const c of contentArr) {
              const text = c.text || '';
              if (text.length > 0) {
                const match = text.match(/<!--\s*notify:\s*(.+?)\s*-->/i);
                if (match) {
                  message = match[1].trim();
                  msgDebug(`Found notify tag: ${message}`);
                  break;
                }
              }
            }
            if (message !== 'Response complete') break; // Found a tag, stop searching
          }
        } catch (e) { /* skip malformed line */ }
      }
    } else {
      msgDebug(`transcript_path not available or file doesn't exist`);
    }

    if (message.length > 60) {
      message = message.substring(0, 57) + '...';
    }

    const cwd = json.cwd || process.cwd();
    const sessionId = json.session_id || 'default';

    // On Windows: look up HWND from session registry
    let wtWindowHandle = null;
    if (os.platform() === 'win32') {
      wtWindowHandle = lookupWindowHandle(cwd, sessionId);
    }

    // Use session-specific data file to avoid race conditions between multiple sessions
    const dataFile = path.join(PLUGIN_DIR, `notify-data-${sessionId}.json`);
    fs.writeFileSync(dataFile, JSON.stringify({ message, wtWindowHandle, cwd, sessionId }));

    if (os.platform() === 'win32') {
      notifyWindows(sessionId);
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
 * Find the Windows Terminal window for this session using session-based registry.
 *
 * This is a simplified lookup that relies on the Start hook (register-window.js)
 * to have already captured the session_id -> HWND mapping.
 *
 * @param {string} cwd - Current working directory (kept for compatibility, not used)
 * @param {string} sessionId - Claude session ID (primary lookup key)
 * @returns {number|null} - Window handle (HWND) or null if not found
 */
function lookupWindowHandle(cwd, sessionId) {
  const debugFile = path.join(PLUGIN_DIR, 'logs', 'lookup-debug.log');
  const debug = (msg) => fs.appendFileSync(debugFile, `${new Date().toISOString()} ${msg}\n`);

  try {
    debug(`lookupWindowHandle called with sessionId: ${sessionId}, cwd: ${cwd}`);

    // Read session registry
    const registryFile = path.join(PLUGIN_DIR, '.session-registry.json');

    if (!fs.existsSync(registryFile)) {
      debug('ERROR: Session registry file does not exist. Was the Start hook registered?');
      return null;
    }

    const registry = JSON.parse(fs.readFileSync(registryFile, 'utf8'));
    debug(`Registry loaded with ${Object.keys(registry).length} sessions`);

    // Look up by session ID
    if (registry[sessionId]) {
      const entry = registry[sessionId];
      debug(`Found session: hwnd=${entry.hwnd}, source=${entry.source}, firstSeen=${entry.firstSeen}`);

      // Update lastSeen timestamp
      entry.lastSeen = new Date().toISOString();
      fs.writeFileSync(registryFile, JSON.stringify(registry, null, 2));
      debug('Updated lastSeen timestamp');

      return entry.hwnd;
    } else {
      debug(`ERROR: Session ${sessionId} not found in registry. Available sessions: ${Object.keys(registry).join(', ')}`);
      return null;
    }

  } catch (e) {
    debug(`lookupWindowHandle error: ${e.message}\n${e.stack}`);
    return null;
  }
}

function notifyWindows(sessionId) {
  const script = path.join(PLUGIN_DIR, 'scripts', 'windows', 'notify-toast.ps1');
  if (fs.existsSync(script)) {
    try {
      const pwsh = fs.existsSync('C:\\Program Files\\PowerShell\\7\\pwsh.exe')
        ? '"C:\\Program Files\\PowerShell\\7\\pwsh.exe"'
        : 'powershell';

      execSync(`${pwsh} -ExecutionPolicy Bypass -File "${script}" -SessionId "${sessionId}"`, {
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
