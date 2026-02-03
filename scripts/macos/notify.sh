#!/bin/bash
# Claude Code notification for macOS using terminal-notifier
# Usage: notify.sh "message"

MESSAGE="${1:-Response complete}"
PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FOCUS_SCRIPT="$PLUGIN_DIR/scripts/macos/focus.sh"

# Check if terminal-notifier is installed
if ! command -v terminal-notifier &> /dev/null; then
    # Fallback to osascript notification
    osascript -e "display notification \"$MESSAGE\" with title \"Claude Code\""
    exit 0
fi

# Detect current terminal app for focus action
TERM_APP=""
if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    TERM_APP="iTerm"
elif [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
    TERM_APP="Terminal"
elif [[ -n "$WAVETERM" ]] || [[ "$TERM_PROGRAM" == "WaveTerminal" ]]; then
    TERM_APP="Wave"
else
    # Try to detect from parent process
    PARENT_APP=$(ps -p $PPID -o comm= 2>/dev/null | xargs basename 2>/dev/null)
    case "$PARENT_APP" in
        iTerm2|iTerm) TERM_APP="iTerm" ;;
        Terminal) TERM_APP="Terminal" ;;
        Wave*) TERM_APP="Wave" ;;
    esac
fi

# Store terminal info for focus script
echo "{\"terminal\": \"$TERM_APP\", \"tty\": \"$(tty)\"}" > "$PLUGIN_DIR/notify-data.json"

# Show notification with click action
terminal-notifier \
    -title "Claude Code" \
    -message "$MESSAGE" \
    -execute "bash '$FOCUS_SCRIPT'" \
    -group "claude-code" \
    -ignoreDnD
