# Fake nvm.sh: slay sources this, so it must be plain POSIX sh (works in bash and zsh).
# Update mode reads $FAKE/nvm-version, $FAKE/node-current, $FAKE/node-remote-<major>
# and $FAKE/node-remote-lts; absent files mean "no answer".
nvm() {
    printf '%s\n' "nvm $*" >> "$STUB_LOG"
    case "$1" in
        --version) cat "$FAKE/nvm-version" 2>/dev/null ;;
        current) cat "$FAKE/node-current" 2>/dev/null ;;
        version-remote)
            if [ "$2" = "--lts" ]; then cat "$FAKE/node-remote-lts" 2>/dev/null
            else cat "$FAKE/node-remote-$2" 2>/dev/null; fi ;;
    esac
    return 0
}
