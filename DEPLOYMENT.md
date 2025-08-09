**仅含 Docker 的部署说明（中文）

下面的说明只关注使用 Docker 部署本项目，并包含在中国境内替换 GitHub Container Registry 镜像地址的方法以及常用的 Docker 运行/构建/清理命令。

**仓库中发现的构建/发布信息（可用 `gh` 验证）**
- Workflow: `Build and publish container`（文件：`.github/workflows/publish.yml`） — 该 workflow 已更新为仅在语义化 tag（例如 `v1.0.0`）推送时发布镜像，并同时打上 `${{ github.sha }}` 的标签；不再在 `main` 分支自动发布 `:latest`。在生产环境中应始终使用语义化版本标签或镜像 digest（`@sha256:...`）来确保可复现的部署。你可以用 `gh` 重现这些查询：
  - 列出 workflows: `gh api repos/andjohnsonj5/github-proxy/actions/workflows --jq '.workflows[] | {name,path}'`
  - 列出 packages（可能需权限）: `gh api repos/andjohnsonj5/github-proxy/packages`

**项目中与 Docker 相关的文件**
- `proxy/Dockerfile`（暴露端口 `8000`，运行 `uvicorn main:app`）。

**镜像拉取与中国镜像替换**
- workflow 发布的镜像示例: `ghcr.io/andjohnsonj5/github-proxy-action:v1.0.0` 或 `ghcr.io/andjohnsonj5/github-proxy-action@sha256:<digest>`
- 中国镜像替换示例: `ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:<tag或digest>`
- 拉取镜像示例:
  - 按 tag: `docker pull ghcr.io/andjohnsonj5/github-proxy-action:v1.0.0`
  - 按 digest: `docker pull ghcr.io/andjohnsonj5/github-proxy-action@sha256:95063893188719e452f5fbbc5c0e286cb323d7658ff83c37b0be18a9b117f78f`

**本地构建（可选）**
- 在仓库根目录构建镜像（使用仓库内 `Dockerfile`）:
  - `docker build -t andjohnsonj5/github-proxy-action:local -f proxy/Dockerfile proxy`

**运行容器（推荐 Docker 原生命令）**
- 直接运行镜像（后台模式）:
  - `docker run -d --name github-proxy -p 8000:8000 ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:<tag或digest>`
  - 推荐在部署脚本中使用环境变量锁定镜像版本，例如：
    - `IMAGE_TAG=${IMAGE_TAG:-21b83713e56c}`
    - `docker run -d --name github-proxy -p 8000:8000 ghcr.io/andjohnsonj5/github-proxy-action:${IMAGE_TAG}`
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
- 在 `proxy/` 目录下添加一个 `run.sh`，作为运行/重启/清理容器的便利脚本，或
- 为 CI 提供一个带镜像前缀变量的示例脚本（用于替换 `ghcr.io` 为 `ghcr.nju.edu.cn`）。
