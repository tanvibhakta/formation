#!/usr/bin/env bash

###############################################################################
# HOT SAUCE 🔥
# Symlinks dotfiles, copies configs, imports plists, and sets up app prefs.
# Called by `slay` or run standalone.
###############################################################################

set -e

HOTSAUCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source twirl helpers if available (when called from slay)
if type print_success &>/dev/null; then
    HAS_HELPERS=true
else
    HAS_HELPERS=false
    # Minimal fallback helpers
    print_success() { printf "  [✓] $1\n"; }
    print_success_muted() { printf "  [✓] $1 (skipped)\n"; }
    print_warning() { printf "  [!] $1\n"; }
    print_error() { printf "  [✗] $1\n"; }
    ask() {
        local prompt default reply
        if [ "${2:-}" = "Y" ]; then prompt="Y/n"; default=Y;
        elif [ "${2:-}" = "N" ]; then prompt="y/N"; default=N;
        else prompt="y/n"; default=; fi
        echo -n "  [?] $1 [$prompt] "
        read reply </dev/tty
        [ -z "$reply" ] && reply=$default
        case "$reply" in Y*|y*) return 0 ;; *) return 1 ;; esac
    }
fi

###############################################################################
# SYMLINK DOTFILES
# Links hot-sauce/dotfiles/<name> → ~/.<name>
###############################################################################
link_dotfile() {
    local src="$1"
    local name="$(basename "$src")"
    local dst="$HOME/.$name"

    # Skip the secrets template
    [[ "$name" == "secrets.template" ]] && return

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        print_success_muted "$dst already linked"
    elif [ -e "$dst" ]; then
        if ask "$dst already exists. Overwrite with symlink?" N; then
            mv "$dst" "${dst}.backup"
            print_warning "Backed up $dst → ${dst}.backup"
            ln -s "$src" "$dst"
            print_success "Linked $src → $dst"
        else
            print_success_muted "$dst left unchanged"
        fi
    else
        ln -s "$src" "$dst"
        print_success "Linked $src → $dst"
    fi
}

echo ""
echo "  ── Dotfiles ──"
for file in "$HOTSAUCE_DIR"/dotfiles/*; do
    [ -f "$file" ] && link_dotfile "$file"
done

###############################################################################
# SECRETS TEMPLATE
# Creates ~/.secrets from template if it doesn't exist
###############################################################################
echo ""
echo "  ── Secrets ──"
if [ ! -f "$HOME/.secrets" ]; then
    cp "$HOTSAUCE_DIR/dotfiles/secrets.template" "$HOME/.secrets"
    print_warning "Created ~/.secrets from template — fill in your API keys!"
else
    print_success_muted "~/.secrets already exists"
fi

###############################################################################
# CONFIG DIRECTORIES
# Links hot-sauce/config/<app> → ~/.config/<app>
###############################################################################
link_config_dir() {
    local src="$1"
    local name="$(basename "$src")"
    local dst="$HOME/.config/$name"

    mkdir -p "$HOME/.config"

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        print_success_muted "$dst already linked"
    elif [ -e "$dst" ]; then
        if ask "~/.config/$name already exists. Overwrite with symlink?" N; then
            mv "$dst" "${dst}.backup"
            print_warning "Backed up $dst → ${dst}.backup"
            ln -s "$src" "$dst"
            print_success "Linked $name → $dst"
        else
            print_success_muted "~/.config/$name left unchanged"
        fi
    else
        ln -s "$src" "$dst"
        print_success "Linked $name → $dst"
    fi
}

echo ""
echo "  ── Config directories ──"
for dir in "$HOTSAUCE_DIR"/config/*/; do
    [ -d "$dir" ] && link_config_dir "$dir"
done

###############################################################################
# GH CLI CONFIG
# gh stores auth separately in hosts.yml, so config.yml is safe to symlink
###############################################################################
echo ""
echo "  ── gh CLI ──"
if [ -d "$HOTSAUCE_DIR/config/gh" ]; then
    mkdir -p "$HOME/.config/gh"
    src="$HOTSAUCE_DIR/config/gh/config.yml"
    dst="$HOME/.config/gh/config.yml"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        print_success_muted "gh config.yml already linked"
    elif [ -e "$dst" ]; then
        if ask "~/.config/gh/config.yml exists. Overwrite?" N; then
            mv "$dst" "${dst}.backup"
            ln -s "$src" "$dst"
            print_success "Linked gh config.yml"
        else
            print_success_muted "gh config.yml left unchanged"
        fi
    else
        ln -s "$src" "$dst"
        print_success "Linked gh config.yml"
    fi
fi

###############################################################################
# ALFRED
# Set Alfred's sync folder to point at our repo copy
###############################################################################
echo ""
echo "  ── Alfred ──"
if [ -d "$HOTSAUCE_DIR/alfred/Alfred.alfredpreferences" ]; then
    if command -v defaults &>/dev/null; then
        defaults write com.runningwithcrayons.Alfred-Preferences syncfolder -string "$HOTSAUCE_DIR/alfred"
        print_success "Alfred sync folder set to $HOTSAUCE_DIR/alfred"
    else
        print_warning "defaults command not found — set Alfred sync folder manually"
    fi
else
    print_warning "Alfred preferences not found in hot-sauce/alfred/"
fi

###############################################################################
# PLISTS (macOS preferences)
# Import app preferences via `defaults import`
###############################################################################
echo ""
echo "  ── macOS Preferences ──"
declare -A PLIST_DOMAINS=(
    ["rectangle.plist"]="com.knollsoft.Rectangle"
    ["betterdisplay.plist"]="pro.betterdisplay.BetterDisplay"
    ["ia-writer.plist"]="pro.writer.mac"
    ["imageoptim.plist"]="net.pornel.ImageOptim"
    ["transmission.plist"]="org.m0k.transmission"
)

for plist_file in "$HOTSAUCE_DIR"/plists/*.plist; do
    [ -f "$plist_file" ] || continue
    name="$(basename "$plist_file")"
    domain="${PLIST_DOMAINS[$name]}"
    if [ -n "$domain" ]; then
        defaults import "$domain" "$plist_file"
        print_success "Imported $name → $domain"
    else
        print_warning "Unknown plist: $name (no domain mapping)"
    fi
done

###############################################################################
# WEBSTORM / JETBRAINS
# Copy settings into the latest installed WebStorm version
###############################################################################
echo ""
echo "  ── WebStorm ──"
LATEST_WS=$(ls -d "$HOME/Library/Application Support/JetBrains/WebStorm"* 2>/dev/null | sort -V | tail -1)
if [ -n "$LATEST_WS" ]; then
    for settings_dir in keymaps codestyles options; do
        if [ -d "$HOTSAUCE_DIR/jetbrains/$settings_dir" ]; then
            cp -R "$HOTSAUCE_DIR/jetbrains/$settings_dir" "$LATEST_WS/"
            print_success "Copied $settings_dir → $(basename "$LATEST_WS")"
        fi
    done
else
    print_warning "No WebStorm installation found"
fi

###############################################################################
# CLAUDE CODE
# Symlinks skills, commands, hooks, and config into ~/.claude
###############################################################################
echo ""
echo "  ── Claude Code ──"
CLAUDE_SRC="$HOTSAUCE_DIR/claude"
CLAUDE_DST="$HOME/.claude"

if [ -d "$CLAUDE_SRC" ]; then
    mkdir -p "$CLAUDE_DST"

    # Symlink directories — new skills/commands/hooks created in ~/.claude will
    # live inside formation and be version-controlled automatically
    for dir in skills commands hooks; do
        src="$CLAUDE_SRC/$dir"
        dst="$CLAUDE_DST/$dir"
        [ -d "$src" ] || continue
        if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
            print_success_muted "~/.claude/$dir already linked"
        elif [ -e "$dst" ]; then
            if ask "~/.claude/$dir already exists. Replace with symlink?" N; then
                mv "$dst" "${dst}.backup"
                print_warning "Backed up $dst → ${dst}.backup"
                ln -s "$src" "$dst"
                print_success "Linked ~/.claude/$dir"
            else
                print_success_muted "~/.claude/$dir left unchanged"
            fi
        else
            ln -s "$src" "$dst"
            print_success "Linked ~/.claude/$dir"
        fi
    done

    # Symlink individual files
    for file in CLAUDE.md settings.json statusline-command.sh; do
        src="$CLAUDE_SRC/$file"
        dst="$CLAUDE_DST/$file"
        [ -f "$src" ] || continue
        if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
            print_success_muted "~/.claude/$file already linked"
        elif [ -e "$dst" ]; then
            if ask "~/.claude/$file already exists. Replace with symlink?" N; then
                mv "$dst" "${dst}.backup"
                print_warning "Backed up $dst → ${dst}.backup"
                ln -s "$src" "$dst"
                print_success "Linked ~/.claude/$file"
            else
                print_success_muted "~/.claude/$file left unchanged"
            fi
        else
            ln -s "$src" "$dst"
            print_success "Linked ~/.claude/$file"
        fi
    done
else
    print_warning "hot-sauce/claude not found. Skipping Claude Code setup."
fi

###############################################################################
# MACOS SYSTEM DEFAULTS
###############################################################################
echo ""
echo "  ── macOS System Defaults ──"
if [ -f "$HOTSAUCE_DIR/macos-defaults.sh" ]; then
    bash "$HOTSAUCE_DIR/macos-defaults.sh"
else
    print_warning "macos-defaults.sh not found. Skipping."
fi

###############################################################################
# DONE
###############################################################################
echo ""
print_success "Hot sauce applied! 🔥"
