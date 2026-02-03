# Claude Notify

Cross-platform desktop notifications for Claude Code with click-to-focus support.

When Claude finishes responding, you get a desktop notification. Click it to jump back to the correct terminal window/tab.

## Features

- Desktop notifications when Claude completes a response
- Custom messages via `<!-- notify: your message -->` tags in Claude's output
- Click-to-focus brings you to the correct terminal instance
- Works with multiple terminal windows/tabs

## Platform Support

| Platform | Notification | Click-to-Focus |
|----------|--------------|----------------|
| Windows (Windows Terminal) | BurntToast | Flashes correct WT window |
| macOS (iTerm2) | terminal-notifier | Focuses correct tab |
| macOS (Wave) | terminal-notifier | Activates app |
| macOS (Terminal.app) | terminal-notifier | Focuses window |

## Installation

### Windows

1. Clone or download this repository
2. Run the installer:
   ```powershell
   .\scripts\windows\install.ps1
   ```

This installs:
- BurntToast PowerShell module (for notifications)
- `claude-focus://` protocol handler (for click-to-focus)

### macOS

1. Clone or download this repository
2. Run the installer:
   ```bash
   ./scripts/macos/install.sh
   ```

This installs:
- terminal-notifier via Homebrew

## Configuration

Add the hook to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"/path/to/claude-notify/hooks/notify.js\""
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/claude-notify` with the actual path where you installed the plugin.

## Custom Notification Messages

Add a comment at the end of your CLAUDE.md or system prompt instructions:

```markdown
End EVERY response with: `<!-- notify: [brief description] -->`
```

Claude will then include custom messages like:
```
<!-- notify: Fixed the login bug -->
```

The notification will show "Fixed the login bug" instead of "Response complete".

## How It Works

### Windows

1. The Stop hook triggers `notify.js` after each Claude response
2. `notify.js` extracts the notification message from `<!-- notify: ... -->` tag
3. `notify.js` walks the process tree: `node.exe` -> `claude.exe` -> `pwsh.exe` -> `WindowsTerminal.exe`
4. Finds the HWND of that specific WT window and stores it in `notify-data.json`
5. BurntToast shows a notification with a "Show me" button
6. Clicking the button triggers `claude-focus://focus` protocol handler
7. `focus-window.ps1` reads the stored HWND and flashes that specific WT window

### macOS

1. The Stop hook triggers `notify.js` after each Claude response
2. `notify.js` detects macOS and calls `notify.sh`
3. `notify.sh` detects the terminal type and stores TTY info
4. terminal-notifier shows the notification
5. Clicking runs `focus.sh`
6. For iTerm2: AppleScript finds and focuses the session with matching TTY
7. For other terminals: App-level activation

## Troubleshooting

### Windows: "BurntToast not found"

Run: `Install-Module -Name BurntToast -Scope CurrentUser -Force`

### Windows: Wrong terminal window flashes

The plugin dynamically finds the correct WT window by walking the process tree from the notification hook to find which `WindowsTerminal.exe` is the ancestor. If this fails:
1. Check `notify-data.json` - if `wtWindowHandle` is null, the process tree walk failed
2. This can happen if running from a non-standard terminal (not Windows Terminal)
3. The fallback will flash the first WT window found

### macOS: No notification appears

1. Check terminal-notifier is installed: `which terminal-notifier`
2. Check notification permissions in System Preferences > Notifications
3. Try running directly: `terminal-notifier -title "Test" -message "Hello"`

### macOS: Click doesn't focus correct tab

Tab-level focus only works in iTerm2. Other terminals get app-level activation.

## Uninstall

### Windows

```powershell
.\scripts\windows\install.ps1 -Uninstall
```

### macOS

```bash
./scripts/macos/install.sh --uninstall
```

Then remove the hook from your Claude Code settings.

## License

MIT
