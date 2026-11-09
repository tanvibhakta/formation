import asyncio, logging, os
from pathlib import Path
from urllib.parse import urlsplit
from key_value.aio.stores.filetree import FileTreeStore, FileTreeV1CollectionSanitizationStrategy, FileTreeV1KeySanitizationStrategy
from fastmcp.client.auth import OAuth
from mcp.shared.auth import OAuthMetadata
HOME = Path.home() / ".mcp-gateway"
log = logging.getLogger("gateway")
def read_env(name):
    """Parse a mode-600 secrets file. Values are never logged."""
    out = {}
    for line in (HOME / "secrets" / f"{name}.env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip("\"'")
    return out
# Addresses kept out of the public repo.
PRIVATE = read_env("upstreams")
# name -> (url, fixed OAuth callback port). The name becomes the tool prefix: neon_list_projects.
UPSTREAMS = {
    "neon": ("https://mcp.neon.tech/mcp", 53791),
    "posthog": ("https://mcp.posthog.com/mcp", 53792),
    "todoist": ("https://ai.todoist.net/mcp", 53793),
    "into_v2": (PRIVATE["INTO_V2_URL"], 53796),
    "vibechk": (PRIVATE["VIBECHK_URL"], 53797),
}
async def discover_metadata(client, url):
    """Find the upstream's OAuth server metadata (RFC 9728, then RFC 8414)."""
    parts = urlsplit(url)
    origin = f"{parts.scheme}://{parts.netloc}"
    issuer = origin
    for prm in (f"{origin}/.well-known/oauth-protected-resource{parts.path}", f"{origin}/.well-known/oauth-protected-resource"):
        r = await client.get(prm)
        if r.status_code == 200 and r.json().get("authorization_servers"):
            issuer = str(r.json()["authorization_servers"][0]).rstrip("/")
            break
    i = urlsplit(issuer)
    base = f"{i.scheme}://{i.netloc}"
    for meta in (f"{base}/.well-known/oauth-authorization-server{i.path}", f"{base}/.well-known/openid-configuration{i.path}"):
        r = await client.get(meta)
        if r.status_code == 200:
            return OAuthMetadata.model_validate(r.json())
    raise RuntimeError(f"no OAuth metadata found for {url}")
class GatewayOAuth(OAuth):
    interactive = True
    upstream = ""
    async def _initialize(self):
        await super()._initialize()
        # The SDK only discovers the token endpoint during a browser login. Without this, refreshing
        # after a restart posts to <origin>/token, which is a 404 on Neon (its endpoint is /api/token).
        if not self.context.oauth_metadata:
            async with self.httpx_client_factory() as client:
                self.context.oauth_metadata = await discover_metadata(client, self.mcp_url)
    async def redirect_handler(self, authorization_url):
        if not self.interactive:
            raise RuntimeError(f"{self.upstream} login expired: run login.py {self.upstream}")
        path = HOME / "authorize" / f"{self.upstream}.txt"
        path.write_text(authorization_url + "\n")
        os.chmod(path, 0o600)
def auth_for(name, interactive=True):
    url, port = UPSTREAMS[name]
    tokens = HOME / "tokens"
    tokens.mkdir(mode=0o700, exist_ok=True)
    auth = GatewayOAuth(mcp_url=url, client_name="Tanvi MCP Gateway", callback_port=port, callback_timeout=14400.0,
                        token_storage=FileTreeStore(data_directory=tokens,
                            key_sanitization_strategy=FileTreeV1KeySanitizationStrategy(directory=tokens),
                            collection_sanitization_strategy=FileTreeV1CollectionSanitizationStrategy(directory=tokens)))
    auth.interactive = interactive
    auth.upstream = name
    return auth
def logged_in(name):
    """True when a token is stored. Upstreams without one are skipped so they can't break the others."""
    return asyncio.run(auth_for(name, False).token_storage_adapter.get_tokens()) is not None
