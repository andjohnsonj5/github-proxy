SSH Git Proxy (TCP Forwarder)

概述

- 这是一个极简的 Go 实现的 SSH 转发服务，用于通过本机端口把 SSH 流量透明转发到 GitHub（或任意指定上游）。
- 典型用途：在网络对 22 端口或直连受限时，通过本地转发到 `github.com:22` 或 `ssh.github.com:443` 来使用 `git@github.com:org/repo.git`。
- 仅做 TCP 级别转发，不终止或解包 SSH。客户端仍与 GitHub 完整握手，密钥校验与认证保持不变。

特性

- 可配置监听地址与上游地址（默认监听 `0.0.0.0:7022`，上游 `github.com:22`）。
- 支持 `ssh.github.com:443` 作为上游以绕过 22 端口封锁。
- 可选连接/空闲超时、TCP KeepAlive、最大并发连接数限制。
- 优雅退出：处理 SIGINT/SIGTERM，完成中的连接可自然断开。

构建与运行

- 构建二进制：
  - 在仓库根目录执行：`cd ssh-forward && go build -o ssh-forwarder`。
- 直接运行（默认转发到 `github.com:22`，监听 `0.0.0.0:7022`）：
  - `./ssh-forwarder`
- 通过环境变量或参数定制：
  - 环境变量：`LISTEN_ADDR`, `UPSTREAM_ADDR`, `DIAL_TIMEOUT`, `IDLE_TIMEOUT`, `TCP_KEEPALIVE`, `MAX_CONNS`
  - 参数：`-listen`, `-upstream`, `-dial-timeout`, `-idle-timeout`
  - 示例（转发到 `ssh.github.com:443`，监听 0.0.0.0:7022）：
    - `LISTEN_ADDR=0.0.0.0:7022 UPSTREAM_ADDR=ssh.github.com:443 ./ssh-forwarder`

与 Git/SSH 的正确集成

直接把 `HostName` 改成本机地址会影响已知主机校验。建议在 `~/.ssh/config` 使用 `HostKeyAlias`，保持对 GitHub 主机密钥的校验，同时走本地转发：

```
Host github.com-via-proxy
  HostName 127.0.0.1
  Port 7022
  User git
  HostKeyAlias github.com
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

用法示例：

- `git clone git@github.com-via-proxy:owner/repo.git`
- 或将你项目的 `origin` 改为 `git@github.com-via-proxy:owner/repo.git`

如果你的网络限制 22 端口，可把上游切到 443：

```
UPSTREAM_ADDR=ssh.github.com:443 ./ssh-forwarder

Docker 运行

- 直接拉取并运行（默认监听 7022，使用版本号）：
  - `docker run -d --name gh-ssh-forward -p 7022:7022 ghcr.io/andjohnsonj5/github-ssh-forwarder:v1.0.11`
- 指向 443 上游：
  - `docker run -d --name gh-ssh-forward -p 7022:7022 -e UPSTREAM_ADDR=ssh.github.com:443 ghcr.io/andjohnsonj5/github-ssh-forwarder:v1.0.11`
- 自行构建（本地）：
  - `docker buildx build --load -t ssh-forward:local -f ssh-forward/Dockerfile .`
  - `docker run -d --name gh-ssh-forward -p 7022:7022 ssh-forward:local`

一键部署（Debian 12）

- 自动安装 Docker 并部署容器：
  - `sudo bash scripts/deploy_ssh_forward_debian12.sh`
- 可选参数：
  - `BUILD_LOCAL=1` 使用本地 Dockerfile 构建
  - `IMAGE=ghcr.nju.edu.cn/andjohnsonj5/github-ssh-forwarder:v1.0.11` 指定镜像（示例镜像源替换，推荐使用版本号而非 latest/main）
  - `UPSTREAM_ADDR=ssh.github.com:443 HOST_PORT=7022 sudo bash scripts/deploy_ssh_forward_debian12.sh`
```

systemd-run（仅限临时启动）

注意：以下仅为 Codex 代理在本仓库中需要临时拉起服务时的做法。不要把 `systemd-run` 固化到脚本、Docker、或 CI 配置里。

- 临时后台运行（监听 2222，转发到 github.com:22）：
  - `systemd-run --unit=gh-ssh-fwd --slice=system.slice --property=RemainAfterExit=no --description="GitHub SSH forwarder" /usr/bin/env bash -c 'cd /path/to/repo/ssh-forward && exec ./ssh-forwarder'`
- 指向 443 端口：
  - `systemd-run --unit=gh-ssh-fwd --slice=system.slice --description="GitHub SSH forwarder 443" /usr/bin/env bash -c 'cd /path/to/repo/ssh-forward && UPSTREAM_ADDR=ssh.github.com:443 exec ./ssh-forwarder'`

管理临时单元：

- 查看状态：`systemctl status gh-ssh-fwd`
- 查看日志：`journalctl -u gh-ssh-fwd -f`
- 停止并清理：
  - `systemctl kill --kill-who=main --signal=SIGTERM gh-ssh-fwd`
  - 必要时：`systemctl reset-failed gh-ssh-fwd`

参数与环境变量

- `-listen`/`LISTEN_ADDR`：监听地址（默认 `0.0.0.0:7022`）。
- `-upstream`/`UPSTREAM_ADDR`：上游 SSH 地址（默认 `github.com:22`）。
- `-dial-timeout`/`DIAL_TIMEOUT`：上游拨号超时（默认 `5s`）。
- `-idle-timeout`/`IDLE_TIMEOUT`：会话空闲超时，0 关闭。
- `TCP_KEEPALIVE`：TCP keepalive 周期（秒，默认 `30`，`0` 关闭）。
- `MAX_CONNS`：最大并发连接数（`0` 表示不限制）。

故障排查

- 连接握手失败：
  - 换用 `UPSTREAM_ADDR=ssh.github.com:443`；某些网络屏蔽 22 端口。
  - 确认本机端口未被占用；修改 `LISTEN_ADDR`。
- Host key 警告：
  - 确认已在 SSH 配置中使用 `HostKeyAlias github.com`（见上）。
- 查看运行日志：
  - 二进制前台运行直接输出日志；`systemd-run` 启动用 `journalctl -u gh-ssh-fwd`。

注意与限制

- 本工具只是透明 TCP 转发，不改变 SSH 安全属性；请使用强密钥，并根据需要限制访问来源。
- 不要在容器内用 `systemd-run` 管理此程序；容器应使用自身的进程模型与编排。
- 不要把 `systemd-run` 命令写入仓库脚本/CI；仅用于临时人工/代理启动。
