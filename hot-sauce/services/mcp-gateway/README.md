# MCP gateway

One HTTPS endpoint, `https://$GATEWAY_HOST:8790/mcp`, that proxies several MCP servers. Tools are prefixed by upstream, such as `neon_list_projects`. It runs from `~/.mcp-gateway` on the always-on Mac; this folder is the source, so copy changed files there and restart.

- `gateway.py`: the server. It mounts each upstream that has a login or a secrets file.
- `common.py`: the upstream list and OAuth handling.
- `login.py <upstream>`: one browser login. The URL lands in `authorize/<upstream>.txt`.
- `com.tanvi.mcp-gateway.plist`: starts the gateway at login. It lives here, not in `hot-sauce/launchagents/`, because `setup.sh` installs that folder on every machine.

## Private files

These stay on the host, outside git, because this repo is public: `secrets/upstreams.env` (private addresses and the host name, see `upstreams.env.example`), `secrets/*.env`, `gateway-token`, `tokens/`, `tls/` and `ca/`.

## Update

```sh
cd ~/.mcp-gateway
uv pip install --python .venv/bin/python -U fastmcp
uv pip freeze --python .venv/bin/python > requirements.txt
```

Restart the gateway, check `tools/list` from a client, then copy `requirements.txt` back here.
