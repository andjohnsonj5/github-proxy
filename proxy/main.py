from typing import Optional

from fastapi import FastAPI, Request
from starlette.responses import StreamingResponse, Response
import asyncio
import logging
import httpx

app = FastAPI(title="GitHub Reverse Proxy")
logger = logging.getLogger("proxy")

UPSTREAM = "https://github.com"


def _filter_request_headers(headers):
    # remove hop-by-hop headers
    hop_by_hop = {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        "host",
    }
    return {k: v for k, v in headers.items() if k.lower() not in hop_by_hop}


def _filter_response_headers(headers):
    # remove hop-by-hop response headers
    hop_by_hop = {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        # Avoid propagating upstream content-length when we stream and may truncate on error
        "content-length",
    }
    return [(k, v) for k, v in headers.items() if k.lower() not in hop_by_hop]


@app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])
async def proxy(full_path: str, request: Request):
    """Proxy any request path to https://github.com/{full_path}"""
    # build upstream URL as string
    base = UPSTREAM.rstrip("/")
    url = f"{base}/{full_path}"
    if request.url.query:
        url = f"{url}?{request.url.query}"

    client_headers = _filter_request_headers(dict(request.headers))
    body_bytes = await request.body()

    # stream request body
    async with httpx.AsyncClient(timeout=None, follow_redirects=False) as client:
        req = client.build_request(
            method=request.method,
            url=str(url),
            headers=client_headers,
            content=body_bytes,
        )

        # Special-case: info/refs listing is small; buffer to send with Content-Length
        if request.method.upper() == "GET" and full_path.endswith(".git/info/refs"):
            # For info/refs, avoid upstream content transforms; drop Accept-Encoding
            no_ce_headers = dict(client_headers)
            no_ce_headers.pop("accept-encoding", None)
            req = client.build_request(
                method=request.method,
                url=str(url),
                headers=no_ce_headers,
                content=await request.body(),
            )
            resp = await client.send(req, stream=False)

            headers = _filter_response_headers(resp.headers)

            # Rewrite Location header similarly
            new_headers = {}
            upstream = UPSTREAM.rstrip("/")
            base = str(request.base_url).rstrip("/")
            for k, v in headers:
                if k.lower() == "location" and v.startswith(upstream):
                    new_v = base + v[len(upstream) :]
                    new_headers[k] = new_v
                else:
                    new_headers[k] = v

            body = resp.content
            # Ensure deterministic framing to avoid truncation by intermediaries
            new_headers.pop("transfer-encoding", None)
            new_headers["Content-Length"] = str(len(body))
            # Close the connection deterministically to avoid mid-path buffering quirks
            new_headers["Connection"] = "close"

            # Stream out the full body, then linger briefly before closing to help NAT flush
            async def body_iter():
                chunk_size = 64 * 1024
                for i in range(0, len(body), chunk_size):
                    yield body[i : i + chunk_size]
                # small delay to allow tail packets to drain through middleboxes
                try:
                    await asyncio.sleep(0.2)
                except Exception:
                    pass

            return StreamingResponse(body_iter(), status_code=resp.status_code, headers=new_headers)

        # Special-case: POST ls-refs (git protocol v2) — small response; buffer + Content-Length
        if (
            request.method.upper() == "POST"
            and (full_path.endswith(".git/git-upload-pack") or full_path.endswith(".git/git-receive-pack"))
            and body_bytes
            and b"command=ls-refs" in body_bytes
            and b"command=fetch" not in body_bytes
        ):
            # Drop Accept-Encoding for stability
            no_ce_headers = dict(client_headers)
            no_ce_headers.pop("accept-encoding", None)
            req = client.build_request(
                method=request.method,
                url=str(url),
                headers=no_ce_headers,
                content=body_bytes,
            )
            resp = await client.send(req, stream=False)

            headers = _filter_response_headers(resp.headers)
            new_headers = {}
            upstream = UPSTREAM.rstrip("/")
            base = str(request.base_url).rstrip("/")
            for k, v in headers:
                if k.lower() == "location" and v.startswith(upstream):
                    new_headers[k] = base + v[len(upstream) :]
                else:
                    new_headers[k] = v

            body = resp.content
            new_headers.pop("transfer-encoding", None)
            new_headers["Content-Length"] = str(len(body))
            new_headers["Connection"] = "close"

            async def body_iter2():
                chunk_size = 64 * 1024
                for i in range(0, len(body), chunk_size):
                    yield body[i : i + chunk_size]
                try:
                    await asyncio.sleep(0.2)
                except Exception:
                    pass

            return StreamingResponse(body_iter2(), status_code=resp.status_code, headers=new_headers)

        # Default path: stream body (e.g., git-upload-pack fetch/packfile)
        resp = await client.send(req, stream=True)

        # build streaming response using a guarded async generator
        headers = _filter_response_headers(resp.headers)

        # rewrite Location header so clients don't follow redirects to upstream directly
        new_headers = {}
        upstream = UPSTREAM.rstrip("/")
        base = str(request.base_url).rstrip("/")
        for k, v in headers:
            if k.lower() == "location" and v.startswith(upstream):
                new_v = base + v[len(upstream) :]
                new_headers[k] = new_v
            else:
                new_headers[k] = v

        async def body_iter():
            try:
                async for chunk in resp.aiter_raw():
                    # If the client disconnected, stop early to avoid raising
                    if await request.is_disconnected():
                        break
                    yield chunk
            except httpx.ReadError as exc:
                # Upstream closed unexpectedly; log and end stream gracefully
                logger.warning("Upstream read error while streaming %s: %s", url, exc)
            except Exception as exc:  # noqa: BLE001
                # Avoid crashing the ASGI app on stream errors
                logger.exception("Unexpected error while streaming %s: %s", url, exc)
            finally:
                try:
                    await resp.aclose()
                except Exception:
                    pass

        return StreamingResponse(body_iter(), status_code=resp.status_code, headers=new_headers)
