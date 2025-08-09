# 通过 OpenResty GitHub 代理时为何不弹出密码？

本文解释在使用本仓库提供的 OpenResty 反向代理（默认监听 `http://<host>:7070`）访问 GitHub 仓库时，客户端为何往往不会弹出“输入用户名/密码”的提示，并给出对应的解决方法与最佳实践。

## 现象与日志

- 访问私有仓库的 `info/refs` 等端点经常返回 `401`；
- Git Credential Manager（GCM）或 IDE 探测后直接断开连接，代理日志显示 `499`；
- 偶尔见到 `"invalid method ... \x16\x03\x03"` 与 `400`：这是把 TLS（HTTPS）请求打到代理的 HTTP 端口导致的；
- 之前可能遇到过 `upstream sent too big header` 触发 `502`，已通过增大响应头缓冲修复。

这些现象在 OpenResty 代理正常工作时也可能出现，关键在于客户端的认证与交互行为。

## 根因分析

1. 非交互上下文不弹窗：
   - 日志中的 UA 常见为 `Git-Credential-Manager/VS` 等（IDE/后台进程）。这类调用一般没有 TTY，GCM 默认不会弹出凭据对话框。
2. 明文 HTTP 远端被视为不安全：
   - 远端是 `http://<host>:7070/<owner>/<repo>.git`。多数 GCM（尤其 Windows 2.x）默认拒绝在非 HTTPS 主机上提示/发送凭据，避免 PAT 暴露在明文链路中。
3. 探测请求不触发交互：
   - Git/GCM 通常先发 `HEAD /` 或 `GET .../info/refs` 做探测。对这些请求，若无现成凭据，GCM 常直接中止，不会提示输入（于是你会看到 `499`）。
4. 错误的协议使用：
   - 若把 `https://` 的流量打到 `7070`（HTTP）端口，会出现 `invalid method` 与 `400`。应使用 `http://` 访问该代理端口，或为代理启用 TLS 改用 `https://`。

## 解决方案（按推荐顺序）

1) 启用 HTTPS 代理（推荐从根本解决）

- 给 OpenResty 配置证书/域名（或置于前置的 TLS 终止代理/CDN 之后），将远端改为 `https://your-domain/...`。
- GCM 把 HTTPS 视为安全端点，会正常弹出/使用凭据，避免明文风险。

2) 交互式终端中绕过 GCM 弹窗限制

- 让 Git 直接在 TTY 提示输入：

```
git -c credential.helper= -c core.askPass= clone http://<host>:7070/<owner>/<repo>.git
# 已有仓库拉取
git -c credential.helper= -c core.askPass= pull
```

3) 显式提供一次性凭据（不落盘）

- 通过 Header 注入 Basic 认证，避免凭据被缓存到磁盘：

```
git -c http.extraHeader="Authorization: Basic $(printf '%s' 'USERNAME:PAT' | base64 -w0)" \
    ls-remote http://<host>:7070/<owner>/<repo>.git

# 同理可用于 fetch/pull：
git -c http.extraHeader="Authorization: Basic $(printf '%s' 'USERNAME:PAT' | base64 -w0)" pull
```

4) 强制 GCM 进入交互模式（Windows）

- 适用于 GCM 2.x/3.x：

```
:: 持久化设置（新开终端生效）
setx GCM_INTERACTIVE always

:: 当前进程临时生效
set GCM_INTERACTIVE=always

:: 或（新版本支持）
git config --global credential.interactive always
```

5) 预先注入凭据（有风险）

- URL 携带（最不推荐，注意命令历史/日志泄露）：

```
git clone "http://USERNAME:PAT@<host>:7070/<owner>/<repo>.git"
```

- 明文存储（仅限受控环境）：

```
git config --global credential.helper store
git credential approve < <(printf "protocol=http\nhost=<host>:7070\nusername=USERNAME\npassword=PAT\n")
```

## 代理端使用注意

- 代理监听默认是 `HTTP 7070`，请用 `http://` 访问；若要 `https://`，需为代理启用 TLS。
- 私有仓库未带凭据时返回 `401` 是预期；携带正确凭据后会转 `200`。
- `499` 多见于 GCM/IDE 探测后主动断开，通常可忽略。
- 我们已在 `nginx.conf` 中增大了响应头缓冲，避免 `HEAD /` 触发 `upstream sent too big header` 导致的 `502`。

## 快速命令清单

```
# 新克隆（交互式输入凭据）
git -c credential.helper= -c core.askPass= clone http://<host>:7070/<owner>/<repo>.git

# 改 remote 并拉取
git remote set-url origin http://<host>:7070/<owner>/<repo>.git
git -c credential.helper= -c core.askPass= pull

# 一次性 Header（不落盘）
git -c http.extraHeader="Authorization: Basic $(printf '%s' 'USERNAME:PAT' | base64 -w0)" \
    ls-remote http://<host>:7070/<owner>/<repo>.git
```

## FAQ

- Q: 为什么没让我输入密码就失败了？
  - A: GCM 在非交互/HTTP 环境默认不弹窗且不发送凭据；探测请求也不会触发输入。

- Q: `invalid method ... \x16\x03\x03` 是什么？
  - A: 把 HTTPS（TLS）流量发到了 HTTP 端口（7070）。请使用 `http://`，或为代理启用 TLS 后使用 `https://`。

- Q: 如何验证代理是否正常？
  - A: `curl -I http://<host>:7070/`（应返回 200/301/302），`git ls-remote http://<host>:7070/<owner>/<repo>.git`（带凭据应 200）。

## 安全提示

- 优先使用 HTTPS 代理，避免 PAT 在明文链路中传输。
- 避免在 URL/日志/历史中泄露凭据；推荐一次性 Header 或受控的凭据存储策略。

