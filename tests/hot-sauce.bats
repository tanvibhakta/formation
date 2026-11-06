#!/usr/bin/env bats
# Characterization tests for hot-sauce/setup.sh, run through ./slay with the
# hot-sauce prompt answered by its default (yes) unless a test says otherwise.
# Tests marked "BUG (pinned)" will fail once that bug is fixed: flip them on purpose.
#
# Prompt order on a provisioned home: SSH "enter it in GitHub?" (default no),
# "add hot sauce?" (default yes), then one per pre-existing link target, then
# the gh config.yml prompt (see test 17). Unanswered prompts take the default.

load test_helper

setup_file() { formation_setup_file; }

HS() { echo "$FORMATION/hot-sauce"; }

# Files and link targets under $HOME, excluding the repo copy, plus every file
# in the repo copy modified since $1 (a marker file).
snapshot() {
    (cd "$HOME" && find . -path ./Code/formation -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
        if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
        elif [ -f "$p" ]; then echo "F $p $(shasum -a 256 < "$p" | cut -c1-16)"
        else echo "D $p"; fi
    done)
    find "$FORMATION" -newer "$1" -print | LC_ALL=C sort | sed 's/^/M /'
}

@test "14. dotfiles: each linked to ~/.<name>; secrets.template copied to ~/.secrets only if absent" {
    run_slay
    [ "$status" -eq 0 ]
    for f in gitconfig gitignore npmrc zprofile zshenv zshrc; do
        links_to "$HOME/.$f" "$(HS)/dotfiles/$f"
    done
    [ ! -e "$HOME/.secrets.template" ]
    [ -f "$HOME/.secrets" ] && [ ! -L "$HOME/.secrets" ]
    cmp "$HOME/.secrets" "$(HS)/dotfiles/secrets.template"

    echo "MY_KEY=1" > "$HOME/.secrets"
    run_slay
    [ "$status" -eq 0 ]
    output_has "~/.secrets already exists"
    [ "$(cat "$HOME/.secrets")" = "MY_KEY=1" ]
}

@test "15. existing ~/.zshrc: 'n' leaves it alone, 'y' backs it up then links" {
    echo "# mine" > "$HOME/.zshrc"
    ANSWERS=$'\n\nn'
    run_slay
    [ "$status" -eq 0 ]
    [ ! -L "$HOME/.zshrc" ]
    [ "$(cat "$HOME/.zshrc")" = "# mine" ]
    [ ! -e "$HOME/.zshrc.backup" ]

    ANSWERS=$'\n\ny'
    run_slay
    [ "$status" -eq 0 ]
    links_to "$HOME/.zshrc" "$(HS)/dotfiles/zshrc"
    [ "$(cat "$HOME/.zshrc.backup")" = "# mine" ]
}

@test "16. fresh home: config dirs, ~/.claude, agent files and Hammerspoon all linked" {
    run_slay
    [ "$status" -eq 0 ]
    for d in gh ghostty zed; do links_to "$HOME/.config/$d" "$(HS)/config/$d"; done
    for d in skills commands hooks CLAUDE.md statusline-command.sh; do
        links_to "$HOME/.claude/$d" "$(HS)/claude/$d"
    done
    links_to "$HOME/.codex/AGENTS.md" "$(HS)/agents/AGENTS.md"
    links_to "$HOME/.gemini/GEMINI.md" "$(HS)/agents/AGENTS.md"
    links_to "$HOME/.hammerspoon/init.lua" "$(HS)/hammerspoon/init.lua"
}

@test "17. BUG (pinned): gh config.yml prompt appears on every fresh run; default leaves repo file intact" {
    # ~/.config/gh is already a link to the repo folder, so ~/.config/gh/config.yml
    # IS the tracked file. Answering yes would move it to .backup and replace it
    # with a link to itself, damaging the repo. Not tested: we only pin the default.
    before="$(shasum -a 256 < "$(HS)/config/gh/config.yml")"
    run_slay
    [ "$status" -eq 0 ]
    output_has "~/.config/gh/config.yml exists. Overwrite?"
    output_has "gh config.yml left unchanged"
    [ ! -L "$(HS)/config/gh/config.yml" ]
    [ "$(shasum -a 256 < "$(HS)/config/gh/config.yml")" = "$before" ]
}

@test "18. Ghostty shadow config: real files moved to .backup, symlinks left alone" {
    shadow="$HOME/Library/Application Support/com.mitchellh.ghostty"
    mkdir -p "$shadow"
    echo "font-size = 99" > "$shadow/config"
    ln -s /dev/null "$shadow/config.ghostty"
    run_slay
    [ "$status" -eq 0 ]
    [ ! -e "$shadow/config" ]
    [ "$(cat "$shadow/config.backup")" = "font-size = 99" ]
    [ -L "$shadow/config.ghostty" ] && [ ! -e "$shadow/config.ghostty.backup" ]

    run_slay
    output_has "No shadowing config; ~/.config/ghostty is authoritative"
}

@test "19. Alfred: prefs.json pointed at the repo, other keys kept; no-op once set (BUG pinned: absolute syncfolder)" {
    prefs="$HOME/Library/Application Support/Alfred/prefs.json"
    mkdir -p "$(dirname "$prefs")"
    echo '{"current": "/somewhere/else", "keep": 1}' > "$prefs"
    run_slay
    [ "$status" -eq 0 ]
    [ "$(jq -r .current "$prefs")" = "$(HS)/alfred/Alfred.alfredpreferences" ]
    # BUG (pinned): setup.sh means to store "~/Code/formation/hot-sauce/alfred"
    # via ${HOTSAUCE_DIR/#$HOME/~}, but bash >= 5.2 (patsub_replacement)
    # tilde-expands the replacement, so the absolute path is stored. Bash 3.2
    # and zsh store the "~" form; flip this when that changes.
    [ "$(jq -r '.syncfolders["5"]' "$prefs")" = "$(HS)/alfred" ]
    [ "$(jq -r .keep "$prefs")" = "1" ]
    called "osascript -e tell application id \"com.runningwithcrayons.Alfred\" to quit"
    called "defaults write com.runningwithcrayons.Alfred-Preferences syncfolder -string $(HS)/alfred"

    reset_log
    run_slay
    output_has "Alfred sync folder already $(HS)/alfred"
    none_called "osascript"
    none_called "defaults write com.runningwithcrayons.Alfred-Preferences"
}

@test "20. plists imported to their domains, unknown plist warned; WebStorm settings go to latest version" {
    echo '<plist/>' > "$(HS)/plists/mystery.plist"
    run_slay
    [ "$status" -eq 0 ]
    called "defaults import com.knollsoft.Rectangle $(HS)/plists/rectangle.plist"
    called "defaults import pro.betterdisplay.BetterDisplay $(HS)/plists/betterdisplay.plist"
    called "defaults import pro.writer.mac $(HS)/plists/ia-writer.plist"
    called "defaults import net.pornel.ImageOptim $(HS)/plists/imageoptim.plist"
    called "defaults import org.m0k.transmission $(HS)/plists/transmission.plist"
    output_has "Unknown plist: mystery.plist (no domain mapping)"
    output_has "No WebStorm installation found"

    jb="$HOME/Library/Application Support/JetBrains"
    mkdir -p "$jb/WebStorm2024.3" "$jb/WebStorm2025.1"
    run_slay
    [ -d "$jb/WebStorm2025.1/keymaps" ] && [ -d "$jb/WebStorm2025.1/options" ]
    [ ! -e "$jb/WebStorm2024.3/keymaps" ]
}

@test "21. ~/.claude/settings.json built as a real file; hand edits are kept, not overwritten" {
    run_slay
    [ "$status" -eq 0 ]
    dst="$HOME/.claude/settings.json"
    [ -f "$dst" ] && [ ! -L "$dst" ]
    [ "$(jq -S . "$dst")" = "$(jq -S . "$(HS)/claude/settings.json")" ]

    jq '.handEdited = true' "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    run_slay
    [ "$status" -eq 0 ]
    output_has "settings.json has unsaved edits; left unchanged"
    [ "$(jq .handEdited "$dst")" = "true" ]
}

@test "22. external skill repos: cloned when absent, skipped when cloned, non-git folder left alone" {
    mkdir -p "$HOME/Code/formation-private"
    run_slay
    [ "$status" -eq 0 ]
    called "git clone --quiet git@github.com:tanvibhakta/tanvi-learning.git $HOME/Code/tanvi-learning"
    none_called "git clone --quiet git@github.com:tanvibhakta/formation-private.git"
    output_has "$HOME/Code/formation-private exists but is not a git repo. Leaving it alone."

    reset_log
    run_slay
    output_has "tanvi-learning already cloned"
    none_called "git clone --quiet"
}

@test "23. Muesli: copied when absent; refuses while running; merges tracked over live; then no-op" {
    src="$(HS)/muesli/config.json"
    live="$HOME/Library/Application Support/Muesli/config.json"
    run_slay
    [ "$status" -eq 0 ]
    cmp "$live" "$src"

    jq '.active_post_processor_id = "changed" | .api_key = "secret"' "$src" > "$live"
    before="$(cat "$live")"
    run_slay FAKE_RUNNING=Muesli
    [ "$status" -eq 0 ]
    output_has "Muesli is running. Quit it and rerun to apply its settings."
    [ "$(cat "$live")" = "$before" ]

    run_slay
    output_has "Applied Muesli settings"
    [ "$(jq -r .active_post_processor_id "$live")" = "$(jq -r .active_post_processor_id "$src")" ]
    [ "$(jq -r .api_key "$live")" = "secret" ]
    [ "$(cat "$live.backup")" = "$before" ]

    run_slay
    output_has "Muesli settings already applied"
}

@test "24. launch agents: rendered with real paths and loaded; unchanged not reloaded; load failure doesn't abort" {
    dst="$HOME/Library/LaunchAgents/com.tanvi.gitpull-repos.plist"
    run_slay
    [ "$status" -eq 0 ]
    grep -qF "$(HS)/jobs/gitpull-repos.sh" "$dst"
    grep -qF "$HOME/Library/Logs/gitpull-repos.log" "$dst"
    ! grep -q '__HOME__\|__HOTSAUCE__' "$dst"
    called "launchctl bootstrap gui/$(id -u) $dst"

    reset_log
    run_slay
    output_has "com.tanvi.gitpull-repos already loaded"
    none_called "launchctl bootstrap"

    echo "<!-- drift -->" >> "$dst"
    run_slay FAKE_LAUNCHCTL_FAIL=1
    [ "$status" -eq 0 ]
    output_has "Could not load com.tanvi.gitpull-repos"
    output_has "Hot sauce applied!"
}

@test "25. setup.sh run standalone (no twirl helpers) completes, including macOS defaults" {
    cd "$HOME"
    run_clean "$(HS)/setup.sh"
    [ "$status" -eq 0 ]
    output_has "Hot sauce applied!"
    links_to "$HOME/.zshrc" "$(HS)/dotfiles/zshrc"
    called "sudo pmset -a displaysleep 0"
    called "killall Dock"
    [ "$(grep -c '^defaults write' "$STUB_LOG")" -gt 10 ]
}

@test "26. idempotency: a second run changes no files and installs or loads nothing" {
    run_slay
    [ "$status" -eq 0 ]
    marker="$BATS_TEST_TMPDIR/marker"; touch "$marker"
    before="$(snapshot "$marker")"
    reset_log
    run_slay
    [ "$status" -eq 0 ]
    after="$(snapshot "$marker")"
    diff <(echo "$before") <(echo "$after")
    none_called "brew install"
    none_called "mas install"
    none_called "pnpm add"
    none_called "git clone"
    none_called "launchctl bootstrap"
}
