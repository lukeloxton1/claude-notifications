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
Write-Host ""
Write-Host "To enable in Claude Code, add to your settings.json:" -ForegroundColor Cyan
Write-Host ""
Write-Host '  "hooks": {' -ForegroundColor Gray
Write-Host '    "Stop": [{' -ForegroundColor Gray
Write-Host '      "hooks": [{' -ForegroundColor Gray
Write-Host '        "type": "command",' -ForegroundColor Gray
Write-Host "        `"command`": `"node `"$pluginDir\hooks\notify.js`"`"" -ForegroundColor Gray
Write-Host '      }]' -ForegroundColor Gray
Write-Host '    }]' -ForegroundColor Gray
Write-Host '  }' -ForegroundColor Gray
Write-Host ""
