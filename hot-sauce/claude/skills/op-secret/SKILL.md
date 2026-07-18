---
name: op-secret
description: Use when you need API keys, credentials, or secrets for Alt Inc services - provides 1Password URI reference and rules for inline secret access without storing plaintext
---

# 1Password Secret Access

Fetch secrets from 1Password CLI inline, never storing them in plaintext.

## Rules

1. **Never assign secrets to variables.** Use `$(op read '...')` inline within the command that needs it.
2. **Never write secrets to files, env vars, or command history.**
3. **Chain commands in a single Bash call** so they execute within 1Password's biometric cache window (one fingerprint prompt).
4. **Use the URI table below** — never run `op item list` or `op item get` to discover items.

## Example

```bash
# GOOD: inline, single command, one fingerprint prompt
curl -s -H "Authorization: Bearer $(op read 'op://Alt inc/Render API key/credential')" \
  "https://api.render.com/v1/services/$(op read 'op://Alt inc/Render Service IDs/notesPlain' | head -1)/deploys?limit=1"

# BAD: assigns to variable = plaintext in shell memory
RENDER_API_KEY=$(op read 'op://Alt inc/Render API key/credential')
```

## Alt Inc Vault — URI Reference

| Item | Field | URI |
|------|-------|-----|
| Render API key | credential | `op://Alt inc/Render API key/credential` |
| Render Service IDs | notesPlain | `op://Alt inc/Render Service IDs/notesPlain` |
| Render (dashboard login) | username | `op://Alt inc/Render/username` |
| Render (dashboard login) | password | `op://Alt inc/Render/password` |
| alt.inc service secret | credential | `op://Alt inc/alt.inc service secret/credential` |
| Dover api key production | credential | `op://Alt inc/Dover api key production (and local I guess)/credential` |
| PostHog | credential | `op://Alt inc/PostHog/credential` |
| posthog analytics tanvi | credential | `op://Alt inc/posthog analytics tanvi API Credentials/credential` |
| Anthropic staging key | credential | `op://Alt inc/anthropic staging key/credential` |
| OpenAI (deploy/render) | credential | `op://Alt inc/Open AI API Credentials for alt.inc deploy on render for llm service/credential` |
| OpenAI (alt.inc) | credential | `op://Alt inc/OpenAI API Credentials for alt.inc/credential` |
| OpenAI (web on render) | credential | `op://Alt inc/open AI API Credentials for web on render/credential` |
| Firecrawl (local) | credential | `op://Alt inc/firecrawl local api key/credential` |
| Firecrawl (production) | credential | `op://Alt inc/firecrawl production api key (letta)/credential` |
| Cloudflare | credential | `op://Alt inc/Cloudflare/credential` |
| Slack hiring agent app | credential | `op://Alt inc/Slack hiring agent app credentials/credential` |
| Letta prescreen local | credential | `op://Alt inc/letta prescreen local API Credentials/credential` |
| claude code alt.inc | credential | `op://Alt inc/claude code alt.inc API Credentials/credential` |
| Resend | credential | `op://Alt inc/Resend/credential` |
| Cartesia (tanvi local) | credential | `op://Alt inc/Cartesia tanvi local/credential` |
| Cartesia | credential | `op://Alt inc/Cartesia/credential` |
| Tavus (tanvi local) | credential | `op://Alt inc/Tavus tanvi local API Credentials/credential` |
| Tavus (paid) | credential | `op://Alt inc/Tavus paid API Credentials/credential` |
| Mem0 | credential | `op://Alt inc/Mem0/credential` |
| Mem0 (local) | credential | `op://Alt inc/Mem0 local API Credentials/credential` |
| ludo.ai (tanvi local) | credential | `op://Alt inc/ludo.ai tanvi local api key/credential` |
| Ludo | credential | `op://Alt inc/Ludo/credential` |
| RapidAPI Abhishek (paid) | credential | `op://Alt inc/RapidAPI Abhishek (paid)/credential` |
| Eval admin login | username | `op://Alt inc/Eval admin login/username` |
| Eval admin login | password | `op://Alt inc/Eval admin login/password` |
| gcal cli | credential | `op://Alt inc/gcal cli API Credentials/credential` |
| LinkedIn local oauth | credential | `op://Alt inc/Linkedin local oauth config/credential` |
| Mootion | credential | `op://Alt inc/Mootion/credential` |
| PixelLab | credential | `op://Alt inc/PixelLab/credential` |
| Rokoko | credential | `op://Alt inc/Rokoko/credential` |
| Neon Vibechk tanvi-dev | connection_string | `op://Alt inc/Neon Vibechk tanvi-dev/connection_string` |
| Neon Vibechk production | connection_string | `op://Alt inc/Neon Vibechk production/connection_string` |

## If an item is missing

Ask the user for the item name — do NOT run `op item list`.
