#!/bin/bash
# Focus the terminal window/tab that triggered the notification
# Reads terminal info from notify-data.json

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_FILE="$PLUGIN_DIR/notify-data.json"

# Read terminal type from data file
TERM_APP=""
TTY=""
if [[ -f "$DATA_FILE" ]]; then
    TERM_APP=$(python3 -c "import json; print(json.load(open('$DATA_FILE')).get('terminal', ''))" 2>/dev/null)
    TTY=$(python3 -c "import json; print(json.load(open('$DATA_FILE')).get('tty', ''))" 2>/dev/null)
fi

case "$TERM_APP" in
    iTerm)
        # iTerm2: Can focus specific tab using AppleScript
        # Try to find and focus the session by tty
        osascript <<EOF
tell application "iTerm"
    activate
    -- Try to find the session with matching tty
    repeat with aWindow in windows
        repeat with aTab in tabs of aWindow
            repeat with aSession in sessions of aTab
                if tty of aSession is "$TTY" then
                    select aSession
                    return
                end if
            end repeat
        end repeat
    end repeat
end tell
EOF
        ;;

    Terminal)
        # Terminal.app: Basic window focus
        osascript <<EOF
tell application "Terminal"
    activate
    -- Focus the window containing our tty if possible
    repeat with aWindow in windows
        repeat with aTab in tabs of aWindow
            if tty of aTab is "$TTY" then
                set frontmost of aWindow to true
                set selected of aTab to true
                return
            end if
        end repeat
    end repeat
end tell
EOF
        ;;

    Wave)
        # Wave: App-level activation only (Electron app)
        osascript -e 'tell application "Wave" to activate'
        ;;

    *)
        # Unknown terminal: try generic activation
        # First try to detect frontmost terminal
        FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

        if [[ "$FRONT_APP" =~ (iTerm|Terminal|Wave) ]]; then
            osascript -e "tell application \"$FRONT_APP\" to activate"
        else
            # Last resort: activate Terminal.app
            osascript -e 'tell application "Terminal" to activate'
        fi
        ;;
esac
