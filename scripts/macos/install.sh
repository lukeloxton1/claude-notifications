#!/bin/bash
# Claude Notify - macOS Installer
# Installs terminal-notifier via Homebrew

set -e

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Claude Notify - macOS Installer"
echo "================================="
echo ""

# Check for uninstall flag
if [[ "$1" == "--uninstall" ]] || [[ "$1" == "-u" ]]; then
    echo "Uninstalling..."
    echo ""
    echo "Note: terminal-notifier was left installed."
    echo "To remove: brew uninstall terminal-notifier"
    echo ""
    echo "Uninstall complete."
    exit 0
fi

# Step 1: Check/install Homebrew
echo "Step 1: Checking Homebrew..."

if command -v brew &> /dev/null; then
    echo "[OK] Homebrew is installed"
else
    echo "[ERROR] Homebrew is not installed"
    echo ""
    echo "Install Homebrew first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo ""
    exit 1
fi

# Step 2: Install terminal-notifier
echo ""
echo "Step 2: Checking terminal-notifier..."

if command -v terminal-notifier &> /dev/null; then
    VERSION=$(terminal-notifier -help 2>&1 | head -1 || echo "unknown")
    echo "[OK] terminal-notifier is already installed"
else
    echo "Installing terminal-notifier via Homebrew..."
    brew install terminal-notifier
    echo "[OK] terminal-notifier installed"
fi

# Step 3: Make scripts executable
echo ""
echo "Step 3: Setting script permissions..."

chmod +x "$PLUGIN_DIR/scripts/macos/notify.sh"
chmod +x "$PLUGIN_DIR/scripts/macos/focus.sh"
echo "[OK] Scripts are executable"

# Step 4: Test notification
echo ""
echo "Step 4: Testing notification..."

terminal-notifier \
    -title "Claude Notify" \
    -message "Installation successful!" \
    -group "claude-install-test" \
    -ignoreDnD || echo "[WARNING] Test notification may have failed"

echo "[OK] Test notification sent - check your notification area"

echo ""
echo "Installation complete!"
echo ""
echo "To enable in Claude Code, add to your settings.json:"
echo ""
echo '  "hooks": {'
echo '    "Stop": [{'
echo '      "hooks": [{'
echo '        "type": "command",'
echo "        \"command\": \"node '$PLUGIN_DIR/hooks/notify.js'\""
echo '      }]'
echo '    }]'
echo '  }'
echo ""

# Detect terminal and show specific instructions
if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    echo "Detected: iTerm2"
    echo "Click-to-focus will activate the specific iTerm2 tab."
elif [[ -n "$WAVETERM" ]] || [[ "$TERM_PROGRAM" == "WaveTerminal" ]]; then
    echo "Detected: Wave"
    echo "Click-to-focus will activate the Wave app (tab-level focus not supported)."
else
    echo "Tip: For best click-to-focus support, use iTerm2."
fi
echo ""
