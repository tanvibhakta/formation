# Fake nvm.sh: slay sources this, so it must be plain POSIX sh (works in bash and zsh).
nvm() { printf '%s\n' "nvm $*" >> "$STUB_LOG"; }
