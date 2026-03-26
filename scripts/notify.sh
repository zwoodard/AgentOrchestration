#!/usr/bin/env bash
set -euo pipefail

# Cross-platform notification script
# Usage: notify.sh <title> <body>
# Flags:
#   --dry-run          Print what would be sent, don't actually notify
#   --detect-platform  Print detected platform and exit

detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*)  echo "windows" ;;
        Linux*)
            # Check if running in WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "windows"
            else
                echo "linux"
            fi
            ;;
        *)  echo "unknown" ;;
    esac
}

notify_macos() {
    local title="$1" body="$2"
    osascript -e "display notification \"$body\" with title \"$title\" sound name \"Ping\""
}

notify_windows() {
    local title="$1" body="$2"
    powershell.exe -Command "
        Add-Type -AssemblyName System.Windows.Forms
        \$notify = New-Object System.Windows.Forms.NotifyIcon
        \$notify.Icon = [System.Drawing.SystemIcons]::Information
        \$notify.Visible = \$true
        \$notify.ShowBalloonTip(5000, '$title', '$body', [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 1
        \$notify.Dispose()
    " 2>/dev/null || {
        # Fallback: simple message box
        powershell.exe -Command "
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show('$body', '$title')
        " 2>/dev/null || echo "NOTIFICATION: [$title] $body"
    }
}

notify_linux() {
    local title="$1" body="$2"
    if command -v notify-send &>/dev/null; then
        notify-send "$title" "$body"
    else
        echo "NOTIFICATION: [$title] $body"
    fi
}

# --- Main ---
DRY_RUN=false

if [[ "${1:-}" == "--detect-platform" ]]; then
    detect_platform
    exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

if $DRY_RUN; then
    echo "Would notify on $(detect_platform): [$TITLE] $BODY"
    exit 0
fi

PLATFORM=$(detect_platform)
case "$PLATFORM" in
    macos)   notify_macos "$TITLE" "$BODY" ;;
    windows) notify_windows "$TITLE" "$BODY" ;;
    linux)   notify_linux "$TITLE" "$BODY" ;;
    *)       echo "NOTIFICATION: [$TITLE] $BODY" ;;
esac
