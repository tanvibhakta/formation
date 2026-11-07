#!/usr/bin/env bats
# Characterization tests for update mode: `./slay update [<name>|--check|--changelogs]`
# and the update loop that ends a plain `./slay`.
#
# In update mode slay skips every install chapter, so the only prompts are the
# per-item "Update <name>?" questions (default no), in record order: formulae,
# casks, App Store, pnpm, nvm, node, Bash-it.

load test_helper

setup_file() { formation_setup_file; }

json() { mkdir -p "$(dirname "$FAKE/$1")"; cat > "$FAKE/$1"; }

# zsh prints `name=value` when a bare `local name` re-declares an existing
# local (e.g. inside a loop); fail if any such line reaches the output.
no_var_leaks() {
    if printf '%s\n' "$output" | grep -E '^[a-z_][a-z0-9_]*=' ; then
        echo "variable listing leaked into output (zsh local re-declare?)"; return 1
    fi
}

# An app on disk, as the cask check reads it: <appdir>/<App>.app/Contents/Info.plist.
# fake_app <App>.app <version> [<Sparkle feed URL>]
fake_app() {
    local feed=""
    [ -n "${3:-}" ] && feed="<key>SUFeedURL</key><string>$3</string>"
    mkdir -p "$HOME/Applications/$1/Contents"
    cat > "$HOME/Applications/$1/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>$2</string>$feed</dict></plist>
EOF
}

# Outdated: formulae gh (2.1.0 → 2.2.0) and tmux; cask zed (brew record only,
# major bump); App Store Slack; pnpm netlify-cli (major). Not outdated: git
# (revision-only bump), ghostty (the app already self-updated), an App Store
# app that isn't in swag/apps. alfred's cask was renamed upstream.
outdated_world() {
    json brew-outdated.json <<'EOF'
{"formulae":[
  {"name":"gh","installed_versions":["2.1.0"],"current_version":"2.2.0"},
  {"name":"git","installed_versions":["2.40.0_1"],"current_version":"2.40.0_2"},
  {"name":"tmux","installed_versions":["3.3"],"current_version":"3.4"}],
 "casks":[
  {"name":"zed","installed_versions":["0.9.0"],"current_version":"1.0.0"},
  {"name":"ghostty","installed_versions":["1.1.0,abc"],"current_version":"1.2.0,def"}]}
EOF
    json brew-info-gh.json <<'EOF'
{"formulae":[{"urls":{"stable":{"url":"https://github.com/cli/cli/archive/refs/tags/v2.2.0.tar.gz"}},"homepage":"https://cli.github.com"}]}
EOF
    json brew-info-cask-zed.json <<'EOF'
{"casks":[{"token":"zed","url":"https://zed.dev/Zed.dmg","homepage":"https://zed.dev","artifacts":[{"app":["Zed.app"]}]}]}
EOF
    json brew-info-cask-ghostty.json <<'EOF'
{"casks":[{"token":"ghostty","url":"https://ghostty.org/Ghostty.dmg","homepage":"https://ghostty.org","artifacts":[{"app":["Ghostty.app"]}]}]}
EOF
    json brew-info-cask-alfred.json <<'EOF'
{"casks":[{"token":"alfred@5","artifacts":[]}]}
EOF
    fake_app Ghostty.app 1.2.0
    json gh/repos_cli_cli_releases_per_page_50 <<'EOF'
[{"tag_name":"v2.3.0","draft":false,"prerelease":false,"body":"Too new notes"},
 {"tag_name":"v2.2.0","draft":false,"prerelease":false,"body":"Two point two notes"},
 {"tag_name":"v2.1.5-rc","draft":false,"prerelease":true,"body":"Prerelease notes"},
 {"tag_name":"v2.1.0","draft":false,"prerelease":false,"body":"Already installed notes"}]
EOF
    json mas-outdated.jsonl <<'EOF'
{"adamID":803453959,"name":"Slack","version":"4.0","newVersion":"4.1"}
{"adamID":111111111,"name":"NotInSwag","version":"1.0","newVersion":"2.0"}
EOF
    json pnpm-outdated.json <<'EOF'
{"netlify-cli":{"current":"17.0.0","latest":"18.0.0"}}
EOF
}

# nvm 0.39.0 → 0.40.1; node 22.1.0 with a newer 22.x and a newer LTS major;
# Bash-it behind its remote.
toolchain_world() {
    echo "0.39.0" > "$FAKE/nvm-version"
    echo "v22.1.0" > "$FAKE/node-current"
    echo "v22.5.0" > "$FAKE/node-remote-22"
    echo "v24.1.0" > "$FAKE/node-remote-lts"
    json gh/repos_nvm-sh_nvm_releases_latest <<< '{"tag_name":"v0.40.1"}'
    mkdir -p "$HOME/.bash_it/.git"
    echo "aaaaaaa1111111" > "$FAKE/bashit-local-sha"
    echo "bbbbbbb2222222" > "$FAKE/bashit-remote-sha"
}

run_update() { cd "$FORMATION"; run_clean "${VARS[@]}" ./slay update "$@"; }

@test "U1. --check, nothing outdated: survey only, no install chapters, no brew update, no sudo" {
    run_update --check
    [ "$status" -eq 0 ]
    no_var_leaks
    output_has "Update survey (--check, no changes made)"
    output_has "Everything listed in swag/ is installed."
    output_lacks "Caching password"
    output_lacks "── Dotfiles ──"
    none_called "brew update"
    none_called "brew install"
    none_called "brew upgrade"
    none_called "sudo"
}

@test "U2. --check lists outdated items by source, flags MAJOR, renames and missing items" {
    outdated_world
    grep -vx wget "$FORMATION/swag/brews" > "$FAKE/brew-formulae"
    grep -vx vlc "$FORMATION/swag/casks" > "$FAKE/brew-casks"
    grep -v '^302584613 ' "$FAKE/mas-installed" > "$FAKE/mas-tmp" && mv "$FAKE/mas-tmp" "$FAKE/mas-installed"
    json pnpm-ls.json <<< '[{"dependencies":{"netlify-cli":{"version":"17.0.0"}}}]'
    run_update --check
    [ "$status" -eq 0 ]
    no_var_leaks
    output_has "gh: 2.1.0 -> 2.2.0"
    output_has "tmux: 3.3 -> 3.4"
    output_lacks "git: 2.40"
    output_has "zed: 0.9.0 -> 1.0.0 [MAJOR]"
    output_lacks "ghostty:"
    output_has "Slack: 4.0 -> 4.1"
    output_lacks "NotInSwag"
    output_has "netlify-cli: 17.0.0 -> 18.0.0 [MAJOR]"
    output_has "renamed in Homebrew: alfred -> alfred@5"
    output_has "Homebrew formulae: wget"
    output_has "Homebrew casks: vlc"
    output_has "Mac App Store: Kindle (302584613)"
    output_has "pnpm: imageoptim-cli"
    none_called "brew upgrade"
    none_called "sudo"
}

@test "U3. --check covers nvm, both Node candidates and Bash-it (no MAJOR on commit SHAs)" {
    toolchain_world
    run_update --check
    [ "$status" -eq 0 ]
    no_var_leaks
    output_has "nvm: 0.39.0 -> 0.40.1"
    output_has "node (same major): 22.1.0 -> 22.5.0"
    output_has "node (new LTS): 22.1.0 -> 24.1.0 [MAJOR]"
    output_has "bash-it: aaaaaaa -> bbbbbbb"
    output_lacks "bbbbbbb [MAJOR]"
}

@test "U4. --check --fresh runs brew update exactly once" {
    run_update --check --fresh
    [ "$status" -eq 0 ]
    [ "$(call_count 'brew update')" -eq 1 ]
}

@test "U5. interactive update: asks per item (default no), upgrades only the yeses, shows notes" {
    outdated_world
    # gh y, tmux default, zed y, Slack y, netlify-cli default
    ANSWERS=$'y\n\ny\ny'
    run_update
    [ "$status" -eq 0 ]
    no_var_leaks
    [ "$(call_count 'brew update')" -eq 1 ]
    called "brew upgrade gh"
    not_called "brew upgrade tmux"
    called "brew upgrade --cask zed"
    called "sudo mas update 803453959"
    none_called "pnpm add"
    output_has "gh updated."
    output_has "tmux skipped."
    output_has "netlify-cli skipped."
    output_has "https://github.com/cli/cli/releases"
    output_has "Two point two notes"
    output_lacks "Too new notes"
    output_has "(version from brew record)"
    output_has "MAJOR"
    output_has "https://zed.dev"
    output_has "https://apps.apple.com/app/id803453959"
    output_has "https://www.npmjs.com/package/netlify-cli"
    none_called "brew install"
    output_lacks "── Dotfiles ──"
}

@test "U6. scoped update: only the named item is offered; App Store apps match by name or id" {
    outdated_world
    ANSWERS=y
    run_update tmux
    [ "$status" -eq 0 ]
    called "brew upgrade tmux"
    output_lacks "Update gh?"

    reset_log
    ANSWERS=y
    run_update Slack
    called "sudo mas update 803453959"
    output_lacks "Update gh?"

    reset_log
    ANSWERS=y
    run_update 803453959
    called "sudo mas update 803453959"
}

@test "U7. unknown update target: error, exit 1, nothing upgraded" {
    outdated_world
    run_update no-such-thing
    [ "$status" -eq 1 ]
    output_has "Unknown update target: no-such-thing"
    none_called "brew upgrade"
}

@test "U8. SLAY_DRY_RUN=1: prints the command instead of running it" {
    outdated_world
    VARS=(SLAY_DRY_RUN=1)
    ANSWERS=y
    run_update gh
    [ "$status" -eq 0 ]
    output_has "[DRY RUN] would run:"
    output_has "brew upgrade gh"
    none_called "brew upgrade"
}

@test "U9. a failed upgrade is reported and the loop carries on" {
    outdated_world
    VARS=(FAKE_BREW_FAIL=gh)
    ANSWERS=$'y\ny'
    run_update
    [ "$status" -eq 0 ]
    output_has "gh failed to update."
    output_has "tmux updated."
    called "brew upgrade tmux"
}

@test "U10. --changelogs: stdout is plain Markdown (no colour, no banner); progress on stderr" {
    outdated_world
    RUN_SEPARATE_STDERR=1
    run_update --changelogs gh
    [ "$status" -eq 0 ]
    no_var_leaks
    [ "${lines[0]}" = "## gh (Homebrew formula) 2.1.0 -> 2.2.0" ]
    output_has "Release notes: https://github.com/cli/cli/releases"
    output_has "### v2.2.0"
    output_has "Two point two notes"
    output_lacks "Too new notes"
    output_lacks "Prerelease notes"
    output_lacks "Already installed notes"
    output_lacks $'\e'
    output_lacks "formation"
    [[ "$stderr" == *"Collecting outdated items…"* ]]
    [[ "$stderr" == *"Fetching changelog for gh"* ]]

    run_update --changelogs
    [ "$status" -eq 0 ]
    no_var_leaks
    [ "$(printf '%s\n' "$output" | grep -c '^## ')" -eq 5 ]
    output_has "## zed (Homebrew cask) 0.9.0 -> 1.0.0"
    output_has "**MAJOR**"
    none_called "brew upgrade"
}

@test "U11. plain ./slay ends with the update loop, reusing the install run's brew update" {
    run_slay
    [ "$status" -eq 0 ]
    no_var_leaks
    output_has "Checking for updates…"
    output_has "Nothing to update."
    [ "$(call_count 'brew update')" -eq 1 ]

    outdated_world
    reset_log
    run_slay
    [ "$status" -eq 0 ]
    no_var_leaks
    output_has "gh skipped."
    none_called "brew upgrade"
    output_has "Congrats! You're in formation!"
}

@test "U12. toolchain upgrades: nvm checks out the latest tag, node reinstalls, bash-it pulls" {
    toolchain_world
    # nvm y, node same-major y, node new LTS y, bash-it y
    ANSWERS=$'y\ny\ny\ny'
    run_update
    [ "$status" -eq 0 ]
    no_var_leaks
    called "nvm install v22.5.0 --reinstall-packages-from=current"
    called "nvm install v24.1.0 --reinstall-packages-from=current"
    called "nvm alias default v24.1.0"
    called "git fetch --tags origin"
    called "git -C $HOME/.bash_it pull --ff-only"
}

@test "U13. release-note sources: Sparkle appcast, App Store notes, Node security badge" {
    outdated_world
    toolchain_world
    # zed: real app 0.9.0 on disk with a Sparkle feed; notes for 1.0.0 only.
    fake_app Zed.app 0.9.0 "https://zed.dev/appcast.xml"
    json curl/https___zed.dev_appcast.xml <<'EOF'
<rss><channel>
<sparkle:releaseNotesLink>https://zed.dev/releases</sparkle:releaseNotesLink>
<item><sparkle:shortVersionString>1.1.0</sparkle:shortVersionString><description>Too new</description></item>
<item><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString><description><![CDATA[<p>Zed one &amp; only</p>]]></description></item>
<item><sparkle:shortVersionString>0.9.0</sparkle:shortVersionString><description>Installed already</description></item>
</channel></rss>
EOF
    json curl/https___itunes.apple.com_lookup_id_803453959_country_in <<< '{"results":[{"releaseNotes":"Slack bug fixes"}]}'
    json curl/https___nodejs.org_dist_index.json <<< '[{"version":"v22.5.0","security":true},{"version":"v24.1.0","security":false}]'
    json gh/repos_nodejs_node_releases_tags_v22.5.0 <<< '{"body":"Node 22.5 notes"}'
    RUN_SEPARATE_STDERR=1
    run_update --changelogs
    [ "$status" -eq 0 ]
    no_var_leaks
    output_has "## zed (Homebrew cask) 0.9.0 -> 1.0.0"
    output_lacks "(version from brew record)"
    output_has "Release notes: https://zed.dev/releases"
    output_has "### 1.0.0"
    output_has "Zed one & only"
    output_lacks "Too new"
    output_lacks "Installed already"
    output_has "Slack bug fixes"
    output_has "_(latest version only - Apple does not expose historical release notes)_"
    output_has "## node (same major) (node) 22.1.0 -> 22.5.0"
    output_has "**SECURITY RELEASE**"
    output_has "Node 22.5 notes"
}

@test "U14. ./slay update from a clone elsewhere: relocates, then still runs update mode" {
    mkdir -p "$HOME/elsewhere"
    mv "$FORMATION" "$HOME/elsewhere/formation"
    cd "$HOME/elsewhere/formation"
    run_clean ./slay update --check
    [ "$status" -eq 0 ]
    output_has "Moving formation to ~/Code/formation"
    output_has "Update survey (--check, no changes made)"
    output_lacks "Caching password"
    none_called "brew install"
}
