# Shared harness for the formation characterization tests.
#
# Every test gets a throwaway $HOME holding a copy of the repo at
# ~/Code/formation, plus fake brew/mas/git/launchctl/... first on PATH. The
# scripts run as black-box subprocesses under `env -i`, so nothing from the
# real shell environment (NVM_DIR, PNPM_HOME, ...) leaks in. Stubs append
# "<command> <args>" to $STUB_LOG; tests assert on that log, on output, and on
# files under the fake $HOME.

REPO_SRC="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# `run --separate-stderr` (update-mode tests) needs bats 1.5.
bats_require_minimum_version 1.5.0

# Copy the repo's tracked files (with working-tree contents) once per test file.
# Untracked and gitignored files stay out, so private settings never leak in.
formation_setup_file() {
    # Physical path: /var is a symlink to /private/var, and bsdcpio refuses to
    # extract through a symlinked directory.
    export REPO_CACHE="$(cd "$BATS_FILE_TMPDIR" && pwd -P)/formation"
    mkdir -p "$REPO_CACHE"
    (cd "$REPO_SRC" && git ls-files -z | cpio -0pdm --quiet "$REPO_CACHE")
    # Alfred's synced prefs are ~960 of the repo's files; setup.sh only checks
    # the folder exists, so keep an empty one and skip copying them per test.
    rm -rf "$REPO_CACHE/hot-sauce/alfred/Alfred.alfredpreferences"
    mkdir -p "$REPO_CACHE/hot-sauce/alfred/Alfred.alfredpreferences"
}

setup() {
    local tmp; tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    export HOME="$tmp/home"
    FORMATION="$HOME/Code/formation"
    FAKE="$tmp/fake"
    STUB_LOG="$FAKE/calls.log"
    # Used in place, not copied: macOS vets each never-seen executable on first
    # launch (~150ms), so fresh per-test copies made every test ~3s slower.
    STUBS="$BATS_TEST_DIRNAME/stubs"
    REALBIN="$tmp/realbin"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"

    mkdir -p "$HOME/Code" "$FAKE" "$REALBIN"
    cp -Rc "$REPO_CACHE" "$FORMATION"  # -c: APFS clone, near-instant
    : > "$STUB_LOG"
    # The scripts say `#!/usr/bin/env bash`; give them Homebrew bash, as on the
    # real machine (macOS /bin/bash 3.2 lacks the `declare -A` setup.sh uses).
    ln -s "$(command -v bash)" "$REALBIN/bash"

    provision_machine
}

# Default state: a machine that has already been set up once by slay.
provision_machine() {
    mkdir -p "$HOME/.ssh" "$HOME/.bash_it" "$HOME/.nvm" "$HOME/Library/pnpm"
    echo "ssh-rsa FAKE" > "$HOME/.ssh/id_rsa.pub"
    cp "$FIXTURES/nvm.sh" "$HOME/.nvm/nvm.sh"
    cp "$FORMATION/swag/brews" "$FAKE/brew-formulae"
    cp "$FORMATION/swag/casks" "$FAKE/brew-casks"
    sed 's/::/ /' "$FORMATION/swag/apps" > "$FAKE/mas-installed"
    local pkg
    for pkg in $(cat "$FORMATION/swag/pnpm"); do
        printf '#!/bin/sh\n' > "$HOME/Library/pnpm/${pkg##*::}"
        chmod +x "$HOME/Library/pnpm/${pkg##*::}"
    done
}

# Run a command with a clean environment. Extra VAR=value args go first.
# Prompt answers come from $ANSWERS, one per line; once they run out, every
# prompt takes its default (read hits EOF and returns an empty reply).
run_clean() {
    local -a vars=()
    while [[ "${1:-}" == *=* ]]; do vars+=("$1"); shift; done
    # RUN_SEPARATE_STDERR=1: keep stderr out of $output, in $stderr instead.
    run ${RUN_SEPARATE_STDERR:+--separate-stderr} env -i \
        HOME="$HOME" \
        PATH="$STUBS:$REALBIN:/usr/bin:/bin:/usr/sbin:/sbin" \
        TERM=xterm-256color LANG=en_US.UTF-8 \
        FAKE="$FAKE" STUB_LOG="$STUB_LOG" FIXTURES="$FIXTURES" \
        FORMATION_TTY=/dev/stdin FORMATION_APPDIR="$HOME/Applications" \
        "${vars[@]}" "$@" <<< "${ANSWERS-}"
}

# Run ./slay from the repo copy, the way a user does.
run_slay() {
    cd "$FORMATION"
    run_clean "$@" ./slay
}

reset_log() { : > "$STUB_LOG"; }

# Make `#!/usr/bin/env bash` find a different bash, e.g. macOS /bin/bash 3.2.
use_bash() { ln -sf "$1" "$REALBIN/bash"; }

# Point $STUBS at a dir of symlinks to every stub except the named ones, so
# those commands are absent from PATH (symlinks avoid the first-launch cost).
without_stubs() {
    local dir="$BATS_TEST_TMPDIR/stubs-without" f
    mkdir -p "$dir"
    for f in "$BATS_TEST_DIRNAME"/stubs/* "$BATS_TEST_DIRNAME"/stubs/_log; do
        case " $* " in *" ${f##*/} "*) continue ;; esac
        ln -sf "$f" "$dir/${f##*/}"
    done
    STUBS="$dir"
}

called() {
    grep -qxF -- "$1" "$STUB_LOG" || {
        echo "expected call: $1"; echo "--- calls ---"; cat "$STUB_LOG"; return 1
    }
}

not_called() {
    if grep -qxF -- "$1" "$STUB_LOG"; then echo "unexpected call: $1"; return 1; fi
}

# Fail if any logged call starts with the given prefix.
none_called() {
    if grep -qF -- "$1" <(cut -c1-${#1} "$STUB_LOG"); then
        echo "unexpected call starting with: $1"; grep -F -- "$1" "$STUB_LOG"; return 1
    fi
}

call_count() { grep -cxF -- "$1" "$STUB_LOG" || true; }

output_has() {
    [[ "$output" == *"$1"* ]] || { echo "expected output to contain: $1"; echo "--- output ---"; echo "$output"; return 1; }
}

output_lacks() {
    [[ "$output" != *"$1"* ]] || { echo "expected output NOT to contain: $1"; return 1; }
}

# $1 is a symlink that resolves to the same place as $2.
links_to() {
    [ -L "$1" ] || { echo "not a symlink: $1"; return 1; }
    [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ] || {
        echo "$1 -> $(readlink "$1"), expected $2"; return 1
    }
}
