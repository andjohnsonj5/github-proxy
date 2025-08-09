OpenResty 部署

- 配置文件：`openresty/nginx.conf`（默认监听 `0.0.0.0:7070`）。
- 本地前台运行（便于调试）：
  - 在仓库根目录执行：`openresty -p "$PWD/openresty" -c nginx.conf -g 'daemon off;'`
- 后台运行（仅限临时运维场景，由 Codex/操作者手动执行）：
  - 参考 `AGENTS.md` 中的 `systemd-run` 指南，例如：
    - `systemd-run --unit=gh-proxy --slice=system.slice --property=RemainAfterExit=no --description="OpenResty GitHub proxy" /usr/bin/env bash -c 'cd /path/to/repo/openresty && exec openresty -p "$PWD" -c nginx.conf -g "daemon off;"'`
- 行为说明：默认路径启用流式转发；`*.git/info/refs` 与 `ls-refs` 小响应路径开启缓冲并关闭连接，以避免中间设备截断/缓存问题。

Docker 使用

- 构建镜像：`docker build -t openresty-github-proxy -f openresty/Dockerfile .`
- 运行容器：`docker run --rm -p 7070:7070 --name gh-proxy openresty-github-proxy`
- 查看日志：`docker logs -f gh-proxy`
- 停止容器：`docker stop gh-proxy`

一键部署脚本（Debian 12）

- 自动安装 Docker（若缺失）并拉取/构建镜像：`sudo bash scripts/deploy_debian12.sh`
- 使用国内镜像前缀：`IMAGE_REGISTRY=ghcr.nju.edu.cn sudo bash scripts/deploy_debian12.sh`
- 强制本地构建：`BUILD_LOCAL=1 sudo bash scripts/deploy_debian12.sh`
- 覆盖容器名/端口：`CONTAINER_NAME=gh-proxy HOST_PORT=8080 CONTAINER_PORT=7070 sudo bash scripts/deploy_debian12.sh`

下面的说明只关注使用 Docker 部署本项目，并包含在中国境内替换 GitHub Container Registry 镜像地址的方法以及常用的 Docker 运行/构建/清理命令。

**仓库中构建/发布信息（可用 `gh` 验证）**
- Workflow: `Build and publish container`（文件：`.github/workflows/publish.yml`） — 该 workflow 会在 `main` 分支推送以及语义化 tag（例如 `v1.0.9`）推送时构建并发布容器镜像：
  - `main` 分支推送：发布 `:main` 与 `:${SHA}` 标签；
  - tag 推送：发布 `:vX.Y.Z` 与 `:${SHA}` 标签。
  - 列出 workflows: `gh api repos/andjohnsonj5/github-proxy/actions/workflows --jq '.workflows[] | {name,path}'`
  - 列出 packages（可能需权限）: `gh api repos/andjohnsonj5/github-proxy/packages`

**项目中与 Docker 相关的文件**
- `openresty/Dockerfile`（暴露端口 `7070`，运行 OpenResty 前台）。

**镜像拉取与中国镜像替换**
- workflow 发布的镜像示例: `ghcr.io/andjohnsonj5/github-proxy-action:v1.0.9`
- 中国镜像替换示例: `ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:v1.0.9`
- 拉取镜像示例:
  - `docker pull ghcr.io/andjohnsonj5/github-proxy-action:v1.0.9`
  - 注意：本仓库已移除 `:latest` 标签（registry 中不再维护 `latest`），请使用版本标签。

**本地构建（可选）**
- 在仓库根目录构建镜像（使用仓库内 `Dockerfile`）:
  - `docker build -t andjohnsonj5/github-proxy-action:local -f openresty/Dockerfile .`

-**运行容器（推荐 Docker 原生命令）**
- 直接运行镜像（后台模式）:
  - `docker run -d --name github-proxy -p 7070:7070 ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:v1.0.9`
  - 推荐在部署脚本中使用环境变量锁定镜像版本，例如：
    - `IMAGE_TAG=${IMAGE_TAG:-v1.0.9}`
    - `docker run -d --name github-proxy -p 8001:8001 ghcr.io/andjohnsonj5/github-proxy-action:${IMAGE_TAG}`
- 查看容器日志:
  - `docker logs -f github-proxy`
- 停止并移除容器:
  - `docker stop github-proxy && docker rm github-proxy`

**使用 `docker-compose`（如果需要）**
- 本仓库当前未包含 `docker-compose.yml`。如果你添加 `docker-compose.yml`，在国内部署时请把 `image:` 字段替换为 `ghcr.nju.edu.cn/...`，或通过 CI 变量替换镜像前缀。

**私有镜像访问**
- 若镜像为私有：先登录替换后的 registry：`docker login ghcr.nju.edu.cn`。

**CI/CD 与自动化建议**
- 在 CI 环境中通过变量控制镜像前缀，例如：
  - `IMAGE_REGISTRY=${IMAGE_REGISTRY:-ghcr.io}`
  - 在中国环境设为 `ghcr.nju.edu.cn` 并在 build/push 脚本中使用 `${IMAGE_REGISTRY}` 作为前缀，避免硬编码。

**清理与维护**
- 清理未使用镜像: `docker image prune -a`（谨慎使用）。
- 列出镜像: `docker images`；列出容器: `docker ps -a`。

**常用命令速查**
- 拉取镜像: `docker pull <registry>/owner/image:tag`
- 本地构建: `docker build -t owner/image:tag -f path/to/Dockerfile .`
- 运行容器（后台）: `docker run -d --name name -p hostPort:containerPort registry/owner/image:tag`
- 查看日志: `docker logs -f name`
- 停止并移除: `docker stop name && docker rm name`

如果你需要，我可以：
- 在 `openresty/` 目录下添加一个 `run.sh`，作为运行/重启/清理容器的便利脚本，或
- 为 CI 提供一个带镜像前缀变量的示例脚本（用于替换 `ghcr.io` 为 `ghcr.nju.edu.cn`）。

SSH 转发器（ssh-forward）部署

- 容器镜像：`ghcr.io/andjohnsonj5/github-ssh-forwarder:v1.0.10`（由 `.github/workflows/publish-ssh-forward.yml` 构建，支持 amd64/arm64）。
- 运行容器（默认监听 7022 → 转发到 github.com:22）：
  - `docker run -d --name gh-ssh-forward -p 7022:7022 ghcr.io/andjohnsonj5/github-ssh-forwarder:v1.0.10`
- 指向 443 上游：
  - `docker run -d --name gh-ssh-forward -p 7022:7022 -e UPSTREAM_ADDR=ssh.github.com:443 ghcr.io/andjohnsonj5/github-ssh-forwarder:v1.0.10`
- 一键部署脚本（Debian 12）：
  - `sudo bash scripts/deploy_ssh_forward_debian12.sh`

版本发布（打 Tag 触发构建）

- 推荐使用语义化版本号，例如：`v1.0.11`。
- 仅打 tag 即可触发容器构建（不需要创建 GitHub Release）。
- 创建 tag 并推送：
  - `git tag v1.0.11 && git push origin v1.0.11`
- 或使用 gh API 创建 tag（不创建 release）：
  - `OWNER=$(gh repo view --json owner --jq .owner.login)`
  - `REPO=$(gh repo view --json name --jq .name)`
  - `SHA=$(git rev-parse HEAD)`
  - `gh api -X POST "/repos/$OWNER/$REPO/git/refs" -f ref=refs/tags/v1.0.11 -f sha=$SHA`
- 观察构建：
  - `gh run list --workflow 'Build and publish ssh-forward container' --limit 1`
  - `RUN_ID=$(gh run list --workflow 'Build and publish ssh-forward container' --limit 1 --json databaseId --jq '.[0].databaseId') && gh run watch "$RUN_ID" --exit-status`
- 拉取并验证版本化镜像：
  - SSH 转发器：`docker pull ghcr.io/$(gh repo view --json owner --jq .owner.login)/github-ssh-forwarder:v1.0.11`
  - OpenResty 代理（如有新版）：`docker pull ghcr.io/$(gh repo view --json owner --jq .owner.login)/github-proxy-action:v1.0.11`
  - 运行（SSH）：`docker run -d --name gh-ssh-forward -p 7022:7022 ghcr.io/<owner>/github-ssh-forwarder:v1.0.11`
