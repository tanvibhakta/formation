#!/bin/zsh
# Signs _opremote's 1Password CLI into Tanvi's account and saves the session for
# serve.sh. Run in a real terminal, then restart the gateway:
#   ssh -t Tanvis-MacBook-Pro.local 'sudo -u _opremote /opt/op-remote/signin.sh && ~/.local/bin/hermes gateway restart'
# Needed after every gateway restart or reboot. op-remote keeps the session alive
# between those.
set -euo pipefail
export HOME=/var/opremote
export PATH=/opt/op-remote/bin:/usr/bin:/bin
address=my.1password.com
email=tanvibhakta@gmail.com
cd $HOME   # sudo keeps the caller's directory, which _opremote can't read

# `op account list` stores the URL with a scheme ("https://my.1password.com").
account_shorthand() {
  op account list --format json | /usr/bin/python3 -I -c "
import json,sys
print(next((a['shorthand'] for a in json.load(sys.stdin) if a['url'].split('//')[-1]=='$address'), ''))"
}
shorthand=$(account_shorthand)
if [[ -z "$shorthand" ]]; then
  print "First run for this user: 1Password asks for your Secret Key and password."
  op account add --address "$address" --email "$email"
  shorthand=$(account_shorthand)
fi

token=$(op signin --account "$address" --raw)
umask 077
print -r -- "$shorthand"$'\n'"$token" > $HOME/session
unset token
print "Saved the session for op-remote."

# Rebuild the list of requestable secrets (references only). Hermes's user can read it,
# to name what it wants, but can't change it.
export "OP_SESSION_${shorthand}=$(sed -n 2p $HOME/session)"
umask 027
/usr/bin/python3 -I /opt/op-remote/gen-secrets.py $HOME/run/secrets.env.tpl alt.inc Private
