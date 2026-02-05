/**
 * Claude Code SessionStart Hook - Session-based window registration
 *
 * Triggered on SessionStart event to map session_id -> HWND.
 * This enables reliable window flashing even when multiple Claude sessions
 * are running in the same directory.
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Plugin directory (assume this script is in PLUGIN_DIR/hooks/)
const PLUGIN_DIR = path.dirname(__dirname);

// Read stdin (hook event data)
let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
  const debugFile = path.join(PLUGIN_DIR, 'logs', 'register-debug.log');
  const debug = (msg) => fs.appendFileSync(debugFile, `${new Date().toISOString()} ${msg}\n`);

  try {
    const json = JSON.parse(data);
    debug(`Start event received: type=${json.type}, session_id=${json.session_id}, cwd=${json.cwd}`);

    // Extract session info
    const sessionId = json.session_id;
    const cwd = json.cwd || process.cwd();

    if (!sessionId) {
      debug('ERROR: No session_id in event, cannot register');
      return;
    }

    // Primary strategy: Read HWND from environment variable (set by Register-ClaudeSession)
    let hwnd = null;
    let source = 'unknown';

    if (process.env.CLAUDE_WT_HWND) {
      hwnd = parseInt(process.env.CLAUDE_WT_HWND);
      source = 'env';
      debug(`Strategy 1 (env var): Found HWND=${hwnd}`);
    } else {
      // Fallback: Capture foreground window (less reliable but better than nothing)
      debug('Strategy 1 failed: CLAUDE_WT_HWND not set, falling back to GetForegroundWindow()');
      try {
        const psScript = `
          Add-Type @"
          using System;
          using System.Runtime.InteropServices;
          public class FGWindow {
              [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
          }
"@
          [FGWindow]::GetForegroundWindow().ToInt64()
        `;
        const result = execSync(`powershell -NoProfile -Command "${psScript}"`, {
          encoding: 'utf8',
          windowsHide: true,
          timeout: 3000
        }).trim();

        if (result && !isNaN(parseInt(result))) {
          hwnd = parseInt(result);
          source = 'foreground';
          debug(`Strategy 2 (foreground): Found HWND=${hwnd}`);
        } else {
          debug(`Strategy 2 failed: Invalid result: ${result}`);
        }
      } catch (e) {
        debug(`Strategy 2 error: ${e.message}`);
      }
    }

    if (!hwnd) {
      debug('ERROR: Could not determine HWND from any strategy');
      return;
    }

    // Load existing registry
    const registryFile = path.join(PLUGIN_DIR, '.session-registry.json');
    let registry = {};

    if (fs.existsSync(registryFile)) {
      try {
        registry = JSON.parse(fs.readFileSync(registryFile, 'utf8'));
        debug(`Loaded existing registry with ${Object.keys(registry).length} entries`);
      } catch (e) {
        debug(`Failed to parse registry, starting fresh: ${e.message}`);
        registry = {};
      }
    } else {
      debug('No existing registry, creating new one');
    }

    // Register this session
    const now = new Date().toISOString();

    if (registry[sessionId]) {
      // Session already registered - only update lastSeen, DO NOT overwrite hwnd
      registry[sessionId].lastSeen = now;
      debug(`Session ${sessionId} already registered with HWND ${registry[sessionId].hwnd}, updated lastSeen only`);
    } else {
      // New session - register it
      registry[sessionId] = {
        hwnd: hwnd,
        cwd: cwd,
        firstSeen: now,
        lastSeen: now,
        source: source
      };
      debug(`Registered NEW session ${sessionId} -> HWND ${hwnd} (source: ${source})`);
    }

    // Write updated registry
    fs.writeFileSync(registryFile, JSON.stringify(registry, null, 2));

    // Cleanup: Remove stale entries (older than 7 days)
    const sevenDaysAgo = Date.now() - (7 * 24 * 60 * 60 * 1000);
    let removed = 0;
    for (const [sid, entry] of Object.entries(registry)) {
      const lastSeenTime = new Date(entry.lastSeen).getTime();
      if (lastSeenTime < sevenDaysAgo) {
        delete registry[sid];
        removed++;
      }
    }

    if (removed > 0) {
      fs.writeFileSync(registryFile, JSON.stringify(registry, null, 2));
      debug(`Cleaned up ${removed} stale entries`);
    }

  } catch (e) {
    const debugFile = path.join(PLUGIN_DIR, 'logs', 'register-debug.log');
    fs.appendFileSync(debugFile, `${new Date().toISOString()} ERROR: ${e.message}\n${e.stack}\n`);
  }
});
