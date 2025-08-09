#!/usr/bin/env python3
import threading
import time
import anyio
import uvicorn
import httpx
import sys
import os


def run_server():
    # Ensure repo root is on sys.path
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)
    from proxy.main import app

    config = uvicorn.Config(app, host="127.0.0.1", port=8001, log_level="info")
    server = uvicorn.Server(config)
    # Run blocking; this thread will be daemonized so process exit stops it
    server.run()


def main():
    t = threading.Thread(target=run_server, daemon=True)
    t.start()
    time.sleep(1.0)

    async def do_requests():
        # A simple GET to info/refs should work (streaming optional)
        async with httpx.AsyncClient(timeout=30.0) as client:
            url = "http://127.0.0.1:8001/openai/codex.git/info/refs?service=git-upload-pack"
            r = await client.get(url)
            print("GET status:", r.status_code, "len:", len(r.content))

            # Try POST with a small body (won't be a valid git upload, but should not crash)
            post_url = "http://127.0.0.1:8001/openai/codex.git/git-upload-pack"
            headers = {"Content-Type": "application/x-git-upload-pack-request"}
            # Send a small dummy payload and let upstream reject gracefully
            try:
                resp = await client.post(post_url, headers=headers, content=b"0000")
                print("POST status:", resp.status_code)
            except Exception as e:
                print("POST raised:", repr(e))

    anyio.run(do_requests)


if __name__ == "__main__":
    main()
