OpenResty GitHub Reverse Proxy

Overview

- Nginx + Lua configuration optimized for Git operations against GitHub.
- Streams large packfiles efficiently and stabilizes small control endpoints.

Key behavior

- Default path: streams requests/responses to `https://github.com` with `proxy_buffering` and `proxy_request_buffering` disabled.
- GET `*.git/info/refs`: drops `Accept-Encoding`, buffers the response, hides `Transfer-Encoding`, and adds `Connection: close` for deterministic framing.
- POST `*.git/(git-upload-pack|git-receive-pack)` with `command=ls-refs` and without `command=fetch`: internally routes to a buffered location that also drops `Accept-Encoding` and closes the connection.
- Redirect rewriting: uses `proxy_redirect https://github.com/ /;` to keep clients pinned to this proxy on redirects.

Run locally

Prerequisites: Install OpenResty (or Nginx with the ngx_lua module), or use Docker.

- Foreground run:
  - From repo root: `openresty -p "$PWD/openresty" -c nginx.conf -g 'daemon off;'`
  - Listens on `127.0.0.1:8001` by default; adjust in `openresty/nginx.conf` if needed.

Docker

- Build: `docker build -t openresty-github-proxy -f openresty/Dockerfile .`
- Run: `docker run --rm -p 8001:8001 --name gh-proxy openresty-github-proxy`
- Smoke test: `bash scripts/smoke_test_openresty.sh`

One-click deploy (Debian 12)

- Pull or build then run: `sudo bash scripts/deploy_debian12.sh`
- Use remote registry mirror: `IMAGE_REGISTRY=ghcr.nju.edu.cn sudo bash scripts/deploy_debian12.sh`
- Build locally: `BUILD_LOCAL=1 sudo bash scripts/deploy_debian12.sh`

Notes

- TLS/SNI: `proxy_ssl_server_name on;` is set; upstream host header is `github.com`.
- DNS: a resolver is configured; tailor to your environment if necessary.
- Performance: streaming is enabled for large packfiles; small control flows are buffered for stability.
