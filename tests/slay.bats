#!/usr/bin/env bats
# Characterization tests for ./slay (preflight checks and install loops).
# These pin what the script does today. Tests marked "BUG (pinned)" record a
# known bug; fixing it fails that test, so flip it on purpose.

load test_helper

setup_file() { formation_setup_file; }

@test "1. run outside the repo: twirl not found, exit 1, nothing called" {
    cd "$HOME"
    run_clean "$FORMATION/slay"
    [ "$status" -eq 1 ]
    output_has "./twirl not found"
    [ ! -s "$STUB_LOG" ]
}

@test "2. repo elsewhere and ~/Code/formation absent: moves itself there and relaunches" {
    mkdir -p "$HOME/elsewhere"
    mv "$FORMATION" "$HOME/elsewhere/formation"
    cd "$HOME/elsewhere/formation"
    run_clean ./slay
    [ "$status" -eq 0 ]
    output_has "Moving formation to ~/Code/formation"
    output_has "Re-launching from new location"
    [ -x "$FORMATION/slay" ]
    [ ! -e "$HOME/elsewhere/formation" ]
}

@test "3. internet check: offline stops the run with exit 1; online passes" {
    run_slay FAKE_OFFLINE=1
    [ "$status" -eq 1 ]
    output_has "Please check your internet connection"
    called "ping -q -c1 -t2 google.com"
    none_called "brew"

    reset_log
    run_slay
    [ "$status" -eq 0 ]
    output_has "[✓] Internet connection"
}

@test "4. provisioned machine: Xcode, Bash-it, nvm, Homebrew skipped" {
    run_slay
    [ "$status" -eq 0 ]
    output_has "Xcode already installed. Skipping."
    output_has "Bash-it already installed. Skipping."
    output_has "NVM already installed. Skipping."
    output_has "Homebrew already installed. Skipping."
    not_called "xcode-select --install"
    none_called "git clone --depth=1 https://github.com/Bash-it/bash-it.git"
    none_called "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm"
}

@test "5. fresh machine: Xcode, Bash-it and nvm installers run" {
    rm -rf "$HOME/.bash_it" "$HOME/.nvm"
    run_slay FAKE_XCODE_MISSING=1
    [ "$status" -eq 0 ]
    called "xcode-select --install"
    called "git clone --depth=1 https://github.com/Bash-it/bash-it.git $HOME/.bash_it"
    called "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh"
    called "nvm install --lts"
    output_has "Using Node v22.0.0"
}

@test "6. brews: installed skipped, missing installed, one failure doesn't stop the rest" {
    grep -vx -e tmux -e wget "$FORMATION/swag/brews" > "$FAKE/brew-formulae"
    run_slay FAKE_BREW_FAIL=tmux
    [ "$status" -eq 0 ]
    output_has "git already installed. Skipped."
    not_called "brew install git"
    called "brew install tmux"
    output_has "tmux failed to install. Skipping."
    called "brew install wget"
}

@test "7. casks: installed skipped, missing installed to /Applications, failure skipped" {
    grep -vx -e vlc -e zoom "$FORMATION/swag/casks" > "$FAKE/brew-casks"
    run_slay FAKE_BREW_FAIL=vlc
    [ "$status" -eq 0 ]
    output_has "ghostty already installed. Skipped."
    not_called "brew install --cask ghostty --appdir=/Applications"
    called "brew install --cask vlc --appdir=/Applications"
    output_has "vlc failed to install. Skipping."
    called "brew install --cask zoom --appdir=/Applications"
}

@test "8. App Store id::Name: missing installed by id, installed skipped by name, spaces kept" {
    grep -v -e '^803453959 ' -e '^775737590 ' "$FAKE/mas-installed" > "$FAKE/mas-tmp" && mv "$FAKE/mas-tmp" "$FAKE/mas-installed"
    run_slay
    [ "$status" -eq 0 ]
    called "mas install 803453959"
    called "mas install 775737590"
    output_has "Installing iA Writer"
    not_called "mas install Writer"
    output_has "Keynote already installed. Skipped."
    not_called "mas install 409183694"
}

@test "9. App Store signed out: warns, installs nothing" {
    run_slay FAKE_MAS_SIGNED_OUT=1
    [ "$status" -eq 0 ]
    output_has "Please signin to App Store first. Skipping."
    none_called "mas install"
}

@test "10. mas missing from PATH: asks to install mas-cli; a file named mas in the repo doesn't matter" {
    without_stubs mas
    run_slay
    [ "$status" -eq 0 ]
    output_has "Please install mas-cli first: brew install mas. Skipping."
    output_lacks "Please signin to App Store first"

    STUBS="$BATS_TEST_DIRNAME/stubs"
    printf '#!/bin/sh\n' > "$FORMATION/mas" && chmod +x "$FORMATION/mas"
    reset_log
    run_slay
    [ "$status" -eq 0 ]
    output_lacks "Please install mas-cli first"
    called "mas account"
}

@test "11. pnpm pkg::binary: binary on PATH skipped, missing added; setup only without PNPM_HOME in ~/.zshrc" {
    rm "$HOME/Library/pnpm/netlify"
    run_slay
    [ "$status" -eq 0 ]
    called "pnpm setup"
    called "pnpm add -g netlify-cli --silent"
    output_has "imageoptim-cli already installed. Skipped."
    none_called "pnpm add -g imageoptim-cli"

    rm -f "$HOME/.zshrc"
    echo 'export PNPM_HOME="$HOME/Library/pnpm"' > "$HOME/.zshrc"
    reset_log
    run_slay
    [ "$status" -eq 0 ]
    not_called "pnpm setup"
    output_has "pnpm already configured in ~/.zshrc"
}

@test "12. brew update and cleanup run once; legacy brew-cask uninstalled" {
    echo brew-cask >> "$FAKE/brew-formulae"
    run_slay
    [ "$status" -eq 0 ]
    [ "$(call_count 'brew update')" -eq 1 ]
    [ "$(call_count 'brew cleanup')" -eq 1 ]
    called "brew uninstall --force brew-cask"
}

@test "13. declining hot sauce: no setup.sh steps, still finishes" {
    # Answers: SSH "enter it in GitHub?" → default (no); hot sauce → n.
    ANSWERS=$'\nn'
    run_slay
    [ "$status" -eq 0 ]
    output_has "Hot sauce declined. Skipped."
    output_lacks "── Dotfiles ──"
    [ ! -e "$HOME/.zshrc" ]
    [ ! -e "$HOME/Library/LaunchAgents" ]
    output_has "Congrats! You're in formation!"
}
