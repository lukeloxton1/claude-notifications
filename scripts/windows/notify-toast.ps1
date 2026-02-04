# Claude Code notification with click-to-focus
# Reads message and HWND from session-specific notify-data file, embeds HWND in protocol URL

param(
    [Parameter(Mandatory=$true)]
    [string]$SessionId
)

try {
    Import-Module BurntToast -ErrorAction Stop

    # Read message from session-specific data file
    $pluginDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $dataFile = Join-Path $pluginDir "notify-data-$SessionId.json"

    if (-not (Test-Path $dataFile)) {
        # Fallback to default file if session-specific file doesn't exist
        $dataFile = Join-Path $pluginDir "notify-data.json"
    }

    $data = Get-Content $dataFile -Raw | ConvertFrom-Json
    $Message = $data.message
    $Title = "Claude Code"
    $hwnd = $data.wtWindowHandle

    # Create button with HWND embedded in protocol URL (avoids race condition with shared file)
    $focusUrl = if ($hwnd) { "claude-focus://focus/$hwnd" } else { "claude-focus://focus" }
    $button = New-BTButton -Content "Show me" -Arguments $focusUrl
    $expiration = (Get-Date).AddMinutes(10)
    New-BurntToastNotification -Text $Title, $Message -Button $button -UniqueIdentifier "claude-code-$hwnd" -ExpirationTime $expiration
}
catch {
    # Fallback notification without button
    try {
        Import-Module BurntToast -ErrorAction Stop
        $expiration = (Get-Date).AddMinutes(10)
        New-BurntToastNotification -Text "Claude Code", "Response complete" -UniqueIdentifier "claude-code" -ExpirationTime $expiration
    }
    catch {}
}
