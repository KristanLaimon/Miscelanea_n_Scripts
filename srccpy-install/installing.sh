#!/usr/bin/env bash
# Installs necessary components to view/control Android with scrcpy and forward a
# physical controller as a native phone HID gamepad.
#
# PHONE SETUP (first time only):
# 1. Open Settings > About phone and tap "Build number" 7 times
#    to enable Developer options (if they don't already appear).
# 2. Open Settings > System > Developer options and enable "USB
#    debugging". The name and location may vary depending on phone brand.
# 3. Connect phone to PC with a USB data cable. When Android asks
#    "Allow USB debugging?", check "Always allow from this computer"
#    and accept the RSA fingerprint.
# 4. Connect controller to PC BEFORE starting scrcpy. No need to install a
#    mapping app or configure buttons on Android: --gamepad=uhid presents it
#    as a physical/HID controller for games with native controller support.
# 5. If the RSA prompt does not appear, unlock the phone and try another cable or
#    USB port. As a last resort: Developer options > "Revoke
#    USB debugging authorizations", reconnect and accept the prompt again.
#
# Usage: ./installing.sh
# Afterwards: scrcpy --gamepad=uhid --stay-awake

set -Eeuo pipefail

readonly REQUIRED_PACKAGES=(
  scrcpy
  android-tools
  android-udev
  jq
  gcc
)

say() {
    printf '\033[1;34m==>\033[0m %s\n' "$*"
}

die() {
    printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
    exit 1
}

if (( EUID == 0 )); then
    die "Run this script as your normal user, not as root. Omarchy will ask for sudo only if needed."
fi

command -v pacman >/dev/null 2>&1 || die "This installer is intended for Omarchy/Arch Linux (pacman missing)."
command -v omarchy >/dev/null 2>&1 || die "Command 'omarchy' not found."

missing_packages=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! pacman -Q "$package" >/dev/null 2>&1; then
        missing_packages+=("$package")
    fi
done

if ((${#missing_packages[@]})); then
    say "Installing: ${missing_packages[*]}"
    # omarchy pkg add uses pacman with --needed, making it safe to run the script again.
    omarchy pkg add "${missing_packages[@]}"
else
    say "The required packages are already installed."
fi

command -v scrcpy >/dev/null 2>&1 || die "scrcpy was not available after installation."

# A pipeline is not used here: with "pipefail", grep -q could close the pipe
# before scrcpy finishes printing its help and cause a false error.
scrcpy_help="$(scrcpy --help 2>&1)"
if [[ $scrcpy_help != *'--gamepad=mode'* ]]; then
    die "The installed version of scrcpy does not support native controller forwarding (--gamepad=uhid). Update the system and try again."
fi

say "Done. Connect the phone via USB, enable USB Debugging, and accept the RSA key."
printf '\n'
printf 'Connect the controller to the PC and run:\n'
printf '  scrcpy --gamepad=uhid --stay-awake\n'
printf '\n'
printf 'The phone will recognize the controller as a physical/HID gamepad; games with native controller support should detect it without touch mapping.\n'
printf 'If the phone does not appear in scrcpy, disconnect and reconnect it after installing android-udev, and check with: adb devices\n'
