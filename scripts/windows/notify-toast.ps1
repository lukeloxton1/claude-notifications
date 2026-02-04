# Claude Code notification with click-to-focus
# Reads message and HWND from notify-data.json, embeds HWND in protocol URL

try {
    Import-Module BurntToast -ErrorAction Stop

    # Read message from data file
    $pluginDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $dataFile = Join-Path $pluginDir "notify-data.json"
    $data = Get-Content $dataFile -Raw | ConvertFrom-Json
    $Message = $data.message
    $Title = "Claude Code"
    $hwnd = $data.wtWindowHandle

    # Create button with HWND embedded in protocol URL (avoids race condition with shared file)
    $focusUrl = if ($hwnd) { "claude-focus://focus/$hwnd" } else { "claude-focus://focus" }
    $button = New-BTButton -Content "Show me" -Arguments $focusUrl
    New-BurntToastNotification -Text $Title, $Message -Button $button -UniqueIdentifier "claude-code-$hwnd"
}
catch {
    # Fallback notification without button
    try {
        Import-Module BurntToast -ErrorAction Stop
        New-BurntToastNotification -Text "Claude Code", "Response complete" -UniqueIdentifier "claude-code"
    }
    catch {}
}
