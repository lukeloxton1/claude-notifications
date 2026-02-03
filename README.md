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
2. `notify.js` extracts the notification message and finds the shell PID
3. BurntToast shows a notification with a "Show me" button
4. Clicking the button triggers `claude-focus://focus`
5. The protocol handler runs `focus-window.ps1`
6. The script traces the process tree from shell PID to find the owning Windows Terminal window
7. That specific WT window's taskbar icon flashes

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

Check that `notify-data.json` in the plugin directory contains the correct `shellPid`. The process tree walk may fail if the shell process has exited.

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
