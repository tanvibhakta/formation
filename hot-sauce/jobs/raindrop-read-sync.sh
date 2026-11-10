#!/bin/bash

###############################################################################
# Tags Raindrop bookmarks `read` once their article is read in Inoreader.
# Run hourly by launchagents/com.tanvi.raindrop-read-sync.plist; safe to run
# by hand.
#
# Inoreader subscribes to each public Raindrop collection's RSS feed (added
# via Miniflux, grouped in the Inoreader folder "raindrop"). The job reads
# that folder's stream, keeps the items Inoreader has marked read, and tags
# the Raindrop bookmark with the same URL.
#
# Secrets live in the login Keychain, not 1Password: launchd runs with nobody
# at the keyboard to approve `op`. Seed them once, interactively:
#   raindrop-read-sync.sh --auth
#
# Inoreader caps an app at 100 API calls a day. One run costs ~2 (the folder
# holds ~150 items, 100 per page), so hourly stays well under it.
###############################################################################

set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

KC_SERVICE="raindrop-read-sync"
INOREADER_FOLDER="raindrop"
REDIRECT_URI="http://localhost"
OP_RAINDROP="op://Private/raindrop custom app/test token"
OP_INOREADER_ITEM="Inoreader API app"

kc_get() { security find-generic-password -s "$KC_SERVICE" -a "$1" -w 2>/dev/null; }
kc_set() { security add-generic-password -U -s "$KC_SERVICE" -a "$1" -w "$2"; }

if [ "${1:-}" = "--auth" ]; then
    kc_set raindrop-token "$(op read "$OP_RAINDROP")" || exit 1
    client_id="$(op read "op://Private/$OP_INOREADER_ITEM/app id")" || exit 1
    client_secret="$(op read "op://Private/$OP_INOREADER_ITEM/app key")" || exit 1
    kc_set inoreader-client-id "$client_id"
    kc_set inoreader-client-secret "$client_secret"

    # The redirect lands on a dead localhost page; the code is in its URL.
    open "https://www.inoreader.com/oauth2/auth?client_id=$client_id&redirect_uri=$REDIRECT_URI&response_type=code&scope=read&state=sync"
    read -rp "Paste the code= value from the localhost URL: " code
    refresh="$(curl -s https://www.inoreader.com/oauth2/token \
        --data-urlencode "code=$code" --data-urlencode "redirect_uri=$REDIRECT_URI" \
        --data-urlencode "client_id=$client_id" --data-urlencode "client_secret=$client_secret" \
        --data-urlencode "grant_type=authorization_code" | jq -r '.refresh_token // empty')"
    [ -n "$refresh" ] || { echo "Inoreader did not return a refresh token" >&2; exit 1; }
    kc_set inoreader-refresh-token "$refresh"
    echo "Keychain seeded. Test with: $0"
    exit 0
fi

echo "── $(date '+%Y-%m-%d %H:%M:%S %z')"

RAINDROP_TOKEN="$(kc_get raindrop-token)"
CLIENT_ID="$(kc_get inoreader-client-id)"
CLIENT_SECRET="$(kc_get inoreader-client-secret)"
REFRESH_TOKEN="$(kc_get inoreader-refresh-token)"
if [ -z "$RAINDROP_TOKEN" ] || [ -z "$REFRESH_TOKEN" ]; then
    echo "Missing Keychain secrets; run: $0 --auth" >&2
    exit 1
fi

# Inoreader rotates the refresh token on use, so store the new one each run.
token_json="$(curl -s https://www.inoreader.com/oauth2/token \
    --data-urlencode "client_id=$CLIENT_ID" --data-urlencode "client_secret=$CLIENT_SECRET" \
    --data-urlencode "grant_type=refresh_token" --data-urlencode "refresh_token=$REFRESH_TOKEN")"
ACCESS_TOKEN="$(jq -r '.access_token // empty' <<<"$token_json")"
[ -n "$ACCESS_TOKEN" ] || { echo "Inoreader token refresh failed: $token_json" >&2; exit 1; }
new_refresh="$(jq -r '.refresh_token // empty' <<<"$token_json")"
[ -n "$new_refresh" ] && kc_set inoreader-refresh-token "$new_refresh"

# URLs of read items in the Inoreader folder, one per line.
read_urls=""
continuation=""
while :; do
    page="$(curl -s -G -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://www.inoreader.com/reader/api/0/stream/contents/user/-/label/$INOREADER_FOLDER" \
        --data-urlencode "n=100" ${continuation:+--data-urlencode "c=$continuation"})"
    jq -e '.items' <<<"$page" >/dev/null || { echo "Inoreader stream failed: $page" >&2; exit 1; }
    read_urls+="$(jq -r '.items[]
        | select(.categories | index("user/-/state/com.google/read"))
        | (.canonical[0].href // .alternate[0].href)' <<<"$page")"$'\n'
    continuation="$(jq -r '.continuation // empty' <<<"$page")"
    [ -n "$continuation" ] || break
done

# Every bookmark not yet tagged read, as id<TAB>link<TAB>tags-json.
untagged=""
p=0
while :; do
    page="$(curl -s -H "Authorization: Bearer $RAINDROP_TOKEN" \
        "https://api.raindrop.io/rest/v1/raindrops/0?perpage=50&page=$p")"
    jq -e '.items' <<<"$page" >/dev/null || { echo "Raindrop list failed: $page" >&2; exit 1; }
    [ "$(jq '.items | length' <<<"$page")" -gt 0 ] || break
    untagged+="$(jq -r '.items[] | select(.tags | index("read") | not)
        | [._id, .link, (.tags | tojson)] | @tsv' <<<"$page")"$'\n'
    p=$((p + 1))
done

tagged=0
failed=0
while IFS=$'\t' read -r id link tags; do
    [ -n "$id" ] || continue
    grep -qxF "$link" <<<"$read_urls" || continue
    body="$(jq -nc --argjson t "$tags" '{tags: ($t + ["read"])}')"
    if curl -sf -X PUT -H "Authorization: Bearer $RAINDROP_TOKEN" -H "Content-Type: application/json" \
        -d "$body" "https://api.raindrop.io/rest/v1/raindrop/$id" >/dev/null; then
        echo "tagged $link"
        tagged=$((tagged + 1))
    else
        echo "FAILED $link" >&2
        failed=$((failed + 1))
    fi
done <<<"$untagged"

echo "tagged=$tagged failed=$failed"
[ "$failed" -eq 0 ]
