# Usage: login.py <upstream>. Runs one browser login; the URL lands in authorize/<upstream>.txt.
import asyncio, sys
from fastmcp import Client
from common import UPSTREAMS, auth_for
name = sys.argv[1]
async def main():
    async with Client(UPSTREAMS[name][0], auth=auth_for(name)) as c:
        print("LOGIN_OK", name, "tools=", len(await c.list_tools()), flush=True)
asyncio.run(main())
