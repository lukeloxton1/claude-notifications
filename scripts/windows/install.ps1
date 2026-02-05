# Claude Notify - Windows Installer
# Installs BurntToast module and registers claude-focus:// protocol handler

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

Write-Host "Claude Notify - Windows Installer" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

# Get plugin directory (two levels up from this script)
$scriptDir = Split-Path -Parent $PSScriptRoot
$pluginDir = Split-Path -Parent $scriptDir

if ($Uninstall) {
    Write-Host "Uninstalling..." -ForegroundColor Yellow

    # Remove protocol handler
    if (Test-Path "HKCU:\Software\Classes\claude-focus") {
        Remove-Item -Path "HKCU:\Software\Classes\claude-focus" -Recurse -Force
        Write-Host "[OK] Removed claude-focus:// protocol handler" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Uninstall complete. BurntToast module was left installed." -ForegroundColor Cyan
    Write-Host "To remove BurntToast: Uninstall-Module BurntToast" -ForegroundColor Gray
    exit 0
}

# Step 1: Install BurntToast if needed
Write-Host "Step 1: Checking BurntToast module..." -ForegroundColor White

$bt = Get-Module -ListAvailable -Name BurntToast
if ($bt) {
    Write-Host "[OK] BurntToast is already installed (v$($bt.Version))" -ForegroundColor Green
} else {
    Write-Host "Installing BurntToast from PowerShell Gallery..." -ForegroundColor Yellow
    try {
        Install-Module -Name BurntToast -Scope CurrentUser -Force -AllowClobber
        Write-Host "[OK] BurntToast installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to install BurntToast: $_" -ForegroundColor Red
        Write-Host "Try running: Install-Module -Name BurntToast -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
}

# Step 2: Register protocol handler
Write-Host ""
Write-Host "Step 2: Registering claude-focus:// protocol handler..." -ForegroundColor White

$vbsPath = Join-Path $pluginDir "scripts\windows\focus-window.vbs"

if (-not (Test-Path $vbsPath)) {
    Write-Host "[ERROR] focus-window.vbs not found at: $vbsPath" -ForegroundColor Red
    exit 1
}

try {
    # Create protocol handler registry entries
    $regPath = "HKCU:\Software\Classes\claude-focus"

    # Remove existing if present
    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force
    }

    # Create new entries
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Claude Focus Protocol"
    Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""

    New-Item -Path "$regPath\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "$regPath\shell\open\command" -Name "(Default)" -Value "wscript.exe `"$vbsPath`""

    Write-Host "[OK] Protocol handler registered" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to register protocol handler: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Test notification
Write-Host ""
Write-Host "Step 3: Testing notification..." -ForegroundColor White

try {
    Import-Module BurntToast
    New-BurntToastNotification -Text "Claude Notify", "Installation successful!" -UniqueIdentifier "claude-install-test"
    Write-Host "[OK] Test notification sent - check your notification area" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Test notification failed: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green

# Step 4: Auto-configure Claude Code settings
Write-Host ""
Write-Host "Step 4: Configuring Claude Code..." -ForegroundColor White

$settingsFile = "$HOME\.claude\settings.json"
$settingsConfigured = $false

if (Test-Path $settingsFile) {
    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json

        # Check if hooks already exist
        $hasSessionStart = $settings.hooks.SessionStart | Where-Object {
            $_.hooks | Where-Object { $_.command -like "*register-window.js*" }
        }
        $hasStop = $settings.hooks.Stop | Where-Object {
            $_.hooks | Where-Object { $_.command -like "*notify.js*" }
        }

        if ($hasSessionStart -and $hasStop) {
            Write-Host "[OK] Hooks already configured in settings.json" -ForegroundColor Green
            $settingsConfigured = $true
        } else {
            Write-Host "Adding hooks to settings.json..." -ForegroundColor Yellow

            # Ensure hooks object exists
            if (-not $settings.hooks) {
                $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value @{} -Force
            }

            # Add SessionStart hook if missing
            if (-not $hasSessionStart) {
                if (-not $settings.hooks.SessionStart) {
                    $settings.hooks | Add-Member -MemberType NoteProperty -Name "SessionStart" -Value @() -Force
                }
                $settings.hooks.SessionStart += @{
                    hooks = @(
                        @{
                            type = "command"
                            command = "node $pluginDir\hooks\register-window.js"
                        }
                    )
                }
            }

            # Add Stop hook if missing
            if (-not $hasStop) {
                if (-not $settings.hooks.Stop) {
                    $settings.hooks | Add-Member -MemberType NoteProperty -Name "Stop" -Value @() -Force
                }
                $settings.hooks.Stop += @{
                    hooks = @(
                        @{
                            type = "command"
                            command = "node $pluginDir\hooks\notify.js"
                        }
                    )
                }
            }

            # Save updated settings
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
            Write-Host "[OK] Hooks added to settings.json" -ForegroundColor Green
            $settingsConfigured = $true
        }
    } catch {
        Write-Host "[WARNING] Could not auto-configure settings.json: $_" -ForegroundColor Yellow
        Write-Host "You'll need to add hooks manually - see README.md" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARNING] settings.json not found at $settingsFile" -ForegroundColor Yellow
    Write-Host "Run Claude Code at least once to create it, then re-run this installer" -ForegroundColor Yellow
}

# Step 5: Configure PowerShell profile
Write-Host ""
Write-Host "Step 5: Configuring PowerShell profile..." -ForegroundColor White

$profileConfigured = $false
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw
    if ($profileContent -like "*Register-Session.ps1*") {
        Write-Host "[OK] PowerShell profile already configured" -ForegroundColor Green
        $profileConfigured = $true
    } else {
        Write-Host "Adding session registration to profile..." -ForegroundColor Yellow
        Add-Content $PROFILE "`n# Claude notifications - register window on startup`n. `"`$HOME\claude-notify\scripts\windows\Register-Session.ps1`"`n"
        Write-Host "[OK] PowerShell profile updated" -ForegroundColor Green
        $profileConfigured = $true
    }
} else {
    Write-Host "Creating PowerShell profile..." -ForegroundColor Yellow
    $profileDir = Split-Path $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    Set-Content $PROFILE "# Claude notifications - register window on startup`n. `"`$HOME\claude-notify\scripts\windows\Register-Session.ps1`"`n"
    Write-Host "[OK] PowerShell profile created" -ForegroundColor Green
    $profileConfigured = $true
}

# Step 6: Configure CLAUDE.md for notification tags
Write-Host ""
Write-Host "Step 6: Configuring CLAUDE.md for custom notification messages..." -ForegroundColor White

$claudeMdFile = "$HOME\.claude\CLAUDE.md"
$claudeMdConfigured = $false

$notificationInstructions = @"

## Notification Summary

End EVERY response with a blank line, then: ``<!-- notify: [under 50 chars] -->``
- MUST have a blank line before the tag (otherwise parser may miss it)
- Keep under 50 characters
- Describes what you did

Examples:
- ``<!-- notify: Created user service -->``
- ``<!-- notify: Fixed login bug -->``
- ``<!-- notify: Tests passing -->``

"@

if (Test-Path $claudeMdFile) {
    $claudeMdContent = Get-Content $claudeMdFile -Raw
    if ($claudeMdContent -like "*<!-- notify:*") {
        Write-Host "[OK] CLAUDE.md already has notification instructions" -ForegroundColor Green
        $claudeMdConfigured = $true
    } else {
        $response = Read-Host "Add notification tag instructions to CLAUDE.md? (Y/n)"
        if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
            Add-Content $claudeMdFile $notificationInstructions
            Write-Host "[OK] Notification instructions added to CLAUDE.md" -ForegroundColor Green
            $claudeMdConfigured = $true
        } else {
            Write-Host "[SKIP] You can add them manually later - see README.md" -ForegroundColor Yellow
        }
    }
} else {
    $response = Read-Host "CLAUDE.md not found. Create it with notification instructions? (Y/n)"
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        Set-Content $claudeMdFile "# Global Claude Instructions$notificationInstructions"
        Write-Host "[OK] CLAUDE.md created with notification instructions" -ForegroundColor Green
        $claudeMdConfigured = $true
    } else {
        Write-Host "[SKIP] You can create it manually later - see README.md" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($settingsConfigured -and $profileConfigured -and $claudeMdConfigured) {
    Write-Host "All components configured successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "1. Restart your PowerShell session (or run: . `$PROFILE)" -ForegroundColor Gray
    Write-Host "2. Launch Claude with: Start-Claude  (or use alias: c)" -ForegroundColor Gray
    Write-Host "3. Notifications will flash the correct window automatically!" -ForegroundColor Gray
} else {
    Write-Host "Some components need manual configuration:" -ForegroundColor Yellow
    if (-not $settingsConfigured) {
        Write-Host "  - Add hooks to ~/.claude/settings.json (see README.md)" -ForegroundColor Yellow
    }
    if (-not $profileConfigured) {
        Write-Host "  - Add Register-Session to PowerShell profile (see README.md)" -ForegroundColor Yellow
    }
    if (-not $claudeMdConfigured) {
        Write-Host "  - Add notification tags to CLAUDE.md (see README.md)" -ForegroundColor Yellow
    }
}

Write-Host ""
