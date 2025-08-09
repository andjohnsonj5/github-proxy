**仅含 Docker 的部署说明（中文）

下面的说明只关注使用 Docker 部署本项目，并包含在中国境内替换 GitHub Container Registry 镜像地址的方法以及用 `systemd-run` 启动容器的建议。

**仓库中发现的构建/发布信息（使用 `gh` 获取）**
- Workflow: `Build and publish container` (文件：`.github/workflows/publish.yml`) — 该 workflow 会把镜像推送到 `ghcr.io/${{ github.repository_owner }}/github-proxy-action:latest`（并带 `${{ github.sha }}` 标签）。
- 包（Packages）查询: `gh api repos/andjohnsonj5/github-proxy/packages` 返回 404（可能需要权限或尚未列出）；workflow 中的镜像名为 `github-proxy-action`。

（你可以用下面命令重复我做的检查）
- 列出 workflows: `gh api repos/andjohnsonj5/github-proxy/actions/workflows --jq '.workflows[] | {name,path}'`
- 尝试列出 repo 的 packages: `gh api repos/andjohnsonj5/github-proxy/packages`

**项目中与 Docker 相关的文件**
- `proxy/Dockerfile`（暴露端口 `8000`，运行 `uvicorn main:app`）

**镜像拉取与中国镜像替换**
- workflow 中的镜像（原地址）: `ghcr.io/andjohnsonj5/github-proxy-action:latest`
- 在中国内网可替换为: `ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:latest`
- 拉取镜像示例:
  - 原始: `docker pull ghcr.io/andjohnsonj5/github-proxy-action:latest`
  - 中国镜像: `docker pull ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:latest`

**本地构建（可选）**
- 在仓库根目录构建镜像（使用仓库内 `Dockerfile`）:
  - `docker build -t andjohnsonj5/github-proxy-action:local -f proxy/Dockerfile proxy`

**用 `systemd-run` 启动容器（推荐）**
- 说明: 请勿使用 `nohup` 或 `... &`，推荐用 `systemd-run` 启动为 transient service，便于管理与日志收集。
- 示例（直接运行远端镜像）:
  - `systemd-run --unit=github-proxy --slice=system.slice --property=RemainAfterExit=no --description="github-proxy" /usr/bin/env bash -c 'exec docker run --rm --name github-proxy -p 8000:8000 ghcr.nju.edu.cn/andjohnsonj5/github-proxy-action:latest'`
  - 查看日志: `journalctl -u github-proxy -f`
  - 停止并清理: `systemctl kill --kill-who=main --signal=SIGTERM github-proxy`；如需，`systemctl reset-failed github-proxy`

**使用 `docker-compose`（如果需要）**
- 本仓库未包含 `docker-compose.yml`（已检测 `proxy/Dockerfile`），若你添加 `docker-compose.yml`，请先把 `image:` 字段替换为 `ghcr.nju.edu.cn/...`，或在 CI 中通过变量替换镜像前缀。

**私有镜像访问**
- 若镜像为私有：先登陆替换后的 registry：`docker login ghcr.nju.edu.cn`，或在 Kubernetes 中创建 `imagePullSecret`。

**总结与下一步**
- 我已用 `gh` 查到 workflow 会发布镜像 `ghcr.io/andjohnsonj5/github-proxy-action:latest`，建议在国内将 `ghcr.io` 替换为 `ghcr.nju.edu.cn`。
- 如果你希望我：
  - 把文档写入到 `proxy/` 目录下，或
  - 为该镜像生成一个可直接运行的 `systemd-run` 启动脚本（带具体 unit 名称/端口），
  请告诉我你希望的 unit 名称和是否需要使用镜像的 `latest` 或 `${{ github.sha }}` 标签，我会继续完善文件和示例命令.
