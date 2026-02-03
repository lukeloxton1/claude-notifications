# Claude Code notification with click-to-focus
# Reads message from notify-data.json in plugin root

try {
    Import-Module BurntToast -ErrorAction Stop

    # Read message from data file
    $pluginDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $dataFile = Join-Path $pluginDir "notify-data.json"
    $data = Get-Content $dataFile -Raw | ConvertFrom-Json
    $Message = $data.message
    $Title = "Claude Code"

    # Create button that triggers focus protocol
    $button = New-BTButton -Content "Show me" -Arguments "claude-focus://focus"
    New-BurntToastNotification -Text $Title, $Message -Button $button -UniqueIdentifier "claude-code"
}
catch {
    # Fallback notification without button
    try {
        Import-Module BurntToast -ErrorAction Stop
        New-BurntToastNotification -Text "Claude Code", "Response complete" -UniqueIdentifier "claude-code"
    }
    catch {}
}
