# Claude Notify

Cross-platform desktop notifications for Claude Code with click-to-focus support.

When Claude finishes responding, you get a desktop notification. Click it to jump back to the correct terminal window/tab.

## Quick Start

**Windows:**
```powershell
git clone https://github.com/lukeloxton1/claude-notifications.git $HOME\claude-notify
cd $HOME\claude-notify
.\scripts\windows\install.ps1
```

**macOS:**
```bash
git clone https://github.com/lukeloxton1/claude-notifications.git ~/claude-notify
cd ~/claude-notify
./scripts/macos/install.sh
```

Then add the hook to `~/.claude/settings.json` (the installer will show the exact command).

## Prerequisites

- **Node.js** (v16 or later) - Required for the hook script
- **Windows:** PowerShell 5.1+ (included with Windows 10/11)
- **macOS:** Homebrew (for installing terminal-notifier)

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
3. **Add to your PowerShell profile** (`$PROFILE`):
   ```powershell
   . "$HOME\claude-notify\scripts\windows\Register-Session.ps1"
   ```
4. **Use `Start-Claude` to launch Claude** (instead of `claude` directly):
   ```powershell
   Start-Claude           # launches claude with session registration
   c                      # shortcut alias
   Start-Claude --help    # passes arguments through
   ```

This installs:
- BurntToast PowerShell module (for notifications)
- `claude-focus://` protocol handler (for click-to-focus)

**Important:** The `Start-Claude` function registers your current directory and window handle before launching Claude. This is required for notifications to flash the correct window when you have multiple terminal sessions.

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

**Windows** (assuming you cloned to your home directory):
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node C:/Users/YOUR_USERNAME/claude-notify/hooks/register-window.js"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node C:/Users/YOUR_USERNAME/claude-notify/hooks/notify.js"
          }
        ]
      }
    ]
  }
}
```

**Important:** The `SessionStart` hook registers your session's window handle for correct multi-session support. Without it, notifications may flash the wrong window if you have multiple Claude sessions running.

**macOS/Linux:**
```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node ~/claude-notify/hooks/notify.js"
          }
        ]
      }
    ]
  }
}
```

Replace `YOUR_USERNAME` or adjust the path to match where you cloned the repository.

## Custom Notification Messages

By default, notifications show "Response complete". To get custom messages that describe what Claude just did, add notification tag instructions to your CLAUDE.md.

### Option 1: Add to your global CLAUDE.md

Add this to your `~/.claude/CLAUDE.md`:

```markdown
## Notification Summary

End EVERY response with a blank line, then: `<!-- notify: [under 50 chars] -->`
- MUST have a blank line before the tag (otherwise parser may miss it)
- Keep under 50 characters
- Describes what you did

Examples:
- `<!-- notify: Created user service -->`
- `<!-- notify: Fixed login bug -->`
- `<!-- notify: Tests passing -->`
```

### Option 2: Add to project-specific instructions

Add the same instructions to your project's `.claude/CLAUDE.md` file.

### Example notification tags

```markdown
<!-- notify: Implemented authentication -->
<!-- notify: Refactored database layer -->
<!-- notify: All tests passing -->
<!-- notify: PR created #123 -->
```

The notification will show your custom message instead of "Response complete", making it easy to see what Claude accomplished without switching windows.

## How It Works

### Windows

1. When you run `Start-Claude`, `Register-Session.ps1` captures:
   - The foreground window handle (HWND) of your Windows Terminal
   - The current working directory
   - Stores both in `~/.claude-wt-sessions.json`
2. The Stop hook triggers `notify.js` after each Claude response
3. `notify.js` extracts the notification message from `<!-- notify: ... -->` tag
4. `notify.js` looks up the correct window handle from the sessions file using the cwd
5. Stores the HWND in `notify-data.json`
6. BurntToast shows a notification with a "Show me" button
7. Clicking the button triggers `claude-focus://focus` protocol handler
8. `focus-window.ps1` reads the stored HWND and flashes that specific WT window

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

This happens when the session wasn't registered properly. Check:

1. **Did you use `Start-Claude`?** If you ran `claude` directly, the session wasn't registered.
   - Fix: Use `Start-Claude` or the `c` alias instead of `claude`

2. **Is `Register-Session.ps1` in your profile?** Check your `$PROFILE`:
   ```powershell
   Get-Content $PROFILE | Select-String "Register-Session"
   ```
   If not found, add: `. "$HOME\claude-notify\scripts\windows\Register-Session.ps1"`

3. **Check `notify-data.json`:** If `wtWindowHandle` is null, the lookup failed:
   ```powershell
   Get-Content $HOME\claude-notify\notify-data.json
   ```

4. **Check sessions file:** Verify your cwd is registered:
   ```powershell
   Get-Content $HOME\.claude-wt-sessions.json
   ```
   Your current directory should appear as a key with an HWND value.

5. **Debug log:** Check `$HOME\claude-notify-debug.log` for detailed lookup info.

### macOS: No notification appears

1. Check terminal-notifier is installed: `which terminal-notifier`
2. Check notification permissions in System Preferences > Notifications
3. Try running directly: `terminal-notifier -title "Test" -message "Hello"`

### macOS: Click doesn't focus correct tab

Tab-level focus only works in iTerm2. Other terminals get app-level activation.

## Testing

To verify the plugin is working:

1. **Check the hook runs:** After Claude responds, check that `notify-data.json` in the plugin directory was updated recently

2. **Check window detection (Windows):** The `wtWindowHandle` field in `notify-data.json` should be a number, not `null`
   ```powershell
   Get-Content $HOME\claude-notify\notify-data.json
   ```

3. **Test notification manually:**

   **Windows:**
   ```powershell
   Import-Module BurntToast
   New-BurntToastNotification -Text "Test", "It works!"
   ```

   **macOS:**
   ```bash
   terminal-notifier -title "Test" -message "It works!"
   ```

4. **Test with multiple terminals:** Open 2+ terminal windows, run Claude in one, and verify the notification flashes/focuses the correct window

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

This is free and unencumbered software released into the public domain. See [LICENSE](LICENSE) for details.
