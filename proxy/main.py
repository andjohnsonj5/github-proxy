from typing import Optional

from fastapi import FastAPI, Request
from starlette.responses import StreamingResponse
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

    # stream request body
    async with httpx.AsyncClient(timeout=None, follow_redirects=False) as client:
        req = client.build_request(
            method=request.method,
            url=str(url),
            headers=client_headers,
            content=await request.body(),
        )

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
