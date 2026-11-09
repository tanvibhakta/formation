import os, secrets
from fastmcp import Client, FastMCP
from fastmcp.client.transports import StdioTransport, StreamableHttpTransport
from fastmcp.server import create_proxy
from fastmcp.server.auth.providers.jwt import StaticTokenVerifier
from common import HOME, UPSTREAMS, auth_for, logged_in, read_env
PORT = 8790
# FastMCP proxies forward the caller's headers. Pin these two: Cloudflare blocks some user agents, and httpx
# cannot decode the brotli a caller's accept-encoding invites.
UPSTREAM_HEADERS = {"user-agent": "tanvi-mcp-gateway", "accept-encoding": "gzip"}
path = HOME / "gateway-token"
if not path.exists():
    path.write_text(secrets.token_urlsafe(32)); os.chmod(path, 0o600)
token = path.read_text().strip()
root = FastMCP("tanvi-gateway",
               instructions="Tools are prefixed by upstream (neon_, posthog_, todoist_ ...). For tools with destructiveHint: true, "
                            "never invoke autonomously; always ask the user first. For neon_ tools with project_id, always pass it.",
               auth=StaticTokenVerifier(tokens={token: {"client_id": "tanvi", "scopes": []}}))
for name, (url, _) in UPSTREAMS.items():
    if logged_in(name):
        root.mount(create_proxy(Client(StreamableHttpTransport(url, headers=UPSTREAM_HEADERS, auth=auth_for(name, interactive=False))), name=name), namespace=name)
        print("mounted", name, flush=True)
    else:
        print("skipped (no login)", name, flush=True)
# Raindrop: the docs allow a bearer token instead of OAuth.
if (HOME / "secrets/raindrop.env").exists():
    bearer = read_env("raindrop")["RAINDROP_API_TOKEN"]
    root.mount(create_proxy(Client(StreamableHttpTransport("https://api.raindrop.io/rest/v2/ai/mcp",
               headers={**UPSTREAM_HEADERS, "authorization": f"Bearer {bearer}"})), name="raindrop"), namespace="raindrop")
    print("mounted raindrop", flush=True)
# Miniflux: tssujt/miniflux-mcp v0.8.0, image digest built from commit e99b7e9. Stdio only, so no port is published.
MINIFLUX_IMAGE = "jwonder/miniflux-mcp@sha256:bfe785ba2918f2f12073e8fde1ef1a72c0e5d61c3655e228a3b041312d24d836"
# An allow-list, so a new upstream tool stays hidden until added. Left out: user and API-key admin tools.
MINIFLUX_TOOLS = {
    "get_feeds", "get_feed", "create_feed", "update_feed", "delete_feed", "refresh_feed", "refresh_all_feeds",
    "get_feed_entries", "get_feed_entry", "get_feed_icon", "mark_feed_as_read", "get_entries", "get_entry",
    "update_entry_status", "toggle_starred", "save_entry", "fetch_original_content", "mark_all_as_read",
    "get_categories", "create_category", "update_category", "delete_category", "get_category_feeds",
    "get_category_entries", "get_category_entry", "mark_category_as_read", "refresh_category", "get_me",
    "get_version", "healthcheck", "fetch_counters", "discover", "export", "flush_history", "get_icon", "get_enclosure",
}
if (HOME / "secrets/miniflux.env").exists():
    miniflux = create_proxy(Client(StdioTransport("/usr/local/bin/docker",
               ["run", "-i", "--rm", "--env-file", str(HOME / "secrets/miniflux.env"), MINIFLUX_IMAGE])), name="miniflux")
    miniflux.enable(names=MINIFLUX_TOOLS, components={"tool"}, only=True)
    root.mount(miniflux, namespace="miniflux")
    print("mounted miniflux", flush=True)
root.run(transport="http", host="0.0.0.0", port=PORT, path="/mcp",
         uvicorn_config={"ssl_certfile": str(HOME / "tls/server.pem"), "ssl_keyfile": str(HOME / "tls/server-key.pem")})
