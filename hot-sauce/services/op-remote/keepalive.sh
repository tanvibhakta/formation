#!/bin/zsh
# Run every 10 minutes by the LaunchDaemon com.tanvi.op-remote-keepalive, as _opremote.
# 1. Keeps the 1Password CLI session alive (it expires after 30 minutes idle), so Hermes
#    restarts reuse it and only a reboot needs a new sign-in.
# 2. Rebuilds the list of requestable secrets once an hour, so a new 1Password item
#    becomes requestable without any command. op-remote reloads the list on its own.
# 3. If the session is gone (after a reboot), messages Tanvi once through the approval
#    bot with the sign-in command.
set -u
export HOME=/var/opremote
export PATH=/opt/op-remote/bin:/usr/bin:/bin
cd $HOME
flag=$HOME/needs-signin.notified

notify_once() {
  [[ -e $flag ]] && return
  [[ -r $HOME/telegram.cache ]] || return
  local tok chat
  { read -r tok; read -r chat } < $HOME/telegram.cache
  # curl reads the URL from stdin, so the bot token never shows in `ps`.
  print -r -- "url = \"https://api.telegram.org/bot$tok/sendMessage\"" |
    curl -s -m 20 -K - --data-urlencode "chat_id=$chat" --data-urlencode "text=$1" >/dev/null && touch $flag
}

session_ok=0
if [[ -r $HOME/session ]]; then
  { read -r shorthand; read -r token } < $HOME/session
  export "OP_SESSION_${shorthand}=${token}"
  unset token
  op whoami >/dev/null 2>&1 && session_ok=1
fi

if (( ! session_ok )); then
  notify_once "Hermes can't get secrets until the server's 1Password is signed in again (usually after a reboot). Run:
ssh -t Tanvis-MacBook-Pro.local 'sudo -u _opremote /opt/op-remote/signin.sh && ~/.local/bin/hermes gateway restart'"
  exit 0
fi
rm -f $flag

# Approval-bot credentials, kept so notify_once still works when the session is gone.
if [[ ! -s $HOME/telegram.cache ]]; then
  ( umask 077; { op read "$(sed -n 's/^REMOTE_OP_TELEGRAM_BOT_TOKEN=//p' /opt/op-remote/telegram.env)"; print
                 op read "$(sed -n 's/^REMOTE_OP_TELEGRAM_CHAT_ID=//p' /opt/op-remote/telegram.env)"; print
               } > $HOME/telegram.cache.tmp && mv $HOME/telegram.cache.tmp $HOME/telegram.cache )
fi

# Hourly list rebuild. Written to a temp file first so op-remote never reads half a list.
list=$HOME/run/secrets.env.tpl
if [[ ! -e $list || -n $(find $list -mmin +60 2>/dev/null) ]]; then
  ( umask 027
    /usr/bin/python3 -I /opt/op-remote/gen-secrets.py $list.tmp alt.inc Private >/dev/null 2>>$HOME/keepalive.log \
      && mv $list.tmp $list )
fi
exit 0
