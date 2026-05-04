#!/usr/bin/env bash

###############################################################################
# macOS Defaults
# Applies system-level preferences using `defaults write`.
# Generated from Tanvi's machine — edit intentionally.
###############################################################################

set -e

if type print_success &>/dev/null; then
    HAS_HELPERS=true
else
    print_success() { printf "  [✓] $1\n"; }
    print_success_muted() { printf "  [✓] $1 (skipped)\n"; }
fi

echo ""
echo "  ── Trackpad ──"
# Tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
# Tracking speed (0=slow, 3=fast)
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 1
# Right-click (two-finger tap)
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
# Smart zoom (two-finger double tap)
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerDoubleTapGesture -int 1
print_success "Trackpad preferences set"

echo ""
echo "  ── Dock ──"
# Position on screen
defaults write com.apple.dock orientation -string "right"
# Icon size
defaults write com.apple.dock tilesize -int 35
# Magnification
defaults write com.apple.dock magnification -bool true
defaults write com.apple.dock largesize -int 128
# Auto-hide
defaults write com.apple.dock autohide -bool true
# Minimize effect
defaults write com.apple.dock mineffect -string "scale"
# No launch animation bounce
defaults write com.apple.dock launchanim -bool false
# Don't show recent apps
defaults write com.apple.dock show-recents -bool false
# Don't auto-rearrange spaces based on recent use
defaults write com.apple.dock mru-spaces -bool false
# Group apps in Exposé
defaults write com.apple.dock expose-group-apps -bool true
print_success "Dock preferences set"

echo ""
echo "  ── Hot Corners ──"
# Possible values:
#  0: no-op  2: Mission Control  3: App Windows  4: Desktop
#  5: Screen Saver  10: Sleep Display  11: Launchpad
#  12: Notification Center  13: Lock Screen  14: Quick Note
# Top-left → Start Screen Saver
defaults write com.apple.dock wvous-tl-corner -int 5
defaults write com.apple.dock wvous-tl-modifier -int 0
# Top-right → Lock Screen
defaults write com.apple.dock wvous-tr-corner -int 13
defaults write com.apple.dock wvous-tr-modifier -int 0
# Bottom-right → disabled
defaults write com.apple.dock wvous-br-corner -int 1
defaults write com.apple.dock wvous-br-modifier -int 0
print_success "Hot corners set"

echo ""
echo "  ── Finder ──"
# Show path bar at bottom
defaults write com.apple.finder ShowPathbar -bool true
# Default to list view (nlsv=list, icnv=icon, clmv=column, glyv=gallery)
defaults write com.apple.finder FXPreferredViewStyle -string "glyv"
print_success "Finder preferences set"

echo ""
echo "  ── Keyboard ──"
# Fast key repeat (lower = faster; macOS default is 6)
defaults write NSGlobalDomain KeyRepeat -int 2
# Short delay before repeat starts (lower = shorter; macOS default is 25)
defaults write NSGlobalDomain InitialKeyRepeat -int 15
print_success "Keyboard preferences set"

echo ""
echo "  ── Apply changes ──"
# Restart affected apps to pick up changes
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
print_success "Dock and Finder restarted"
