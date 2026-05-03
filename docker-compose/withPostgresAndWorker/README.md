# n8n 高可用托管方案 (Postgres + Redis + Worker + Python Runner)

本项目提供了一个基于 Docker Compose 的高性能、可扩展的 n8n 部署方案。它包含了数据库自动初始化、任务队列、异步工作节点以及支持常用 Python 库的自定义代码执行环境。

## 🚀 架构特性

- **n8n Main**: 主节点，负责 UI 展现和工作流调度。
- **n8n Worker**: 独立的辅助节点，用于并行处理后台任务，分担主节点压力。
- **n8n Task Runner (Python)**: 基于 `n8nio/runners` 的自定义容器，预装了 `pandas`, `numpy`, `openai` 等常用 Python 库，用于高效执行代码节点。
- **PostgreSQL 16**: 核心数据库，采用非 root 用户权限隔离。
- **Redis**: 任务队列后端（Bull Queue），支撑主从节点的任务分发。
- **自动初始化**: 通过 `db-init` 容器自动处理数据库用户权限，简化部署。

## 🛠️ 快速开始

### 1. 准备环境变量

项目提供了一个便捷脚本来生成随机的安全密钥：

```bash
chmod +x generate-env.sh
./generate-env.sh
```

这会根据 `.env.template` 生成 `.env` 文件。你需要编辑 `.env` 文件并配置以下关键项：

- `WEBHOOK_URL`: 你的 n8n 访问域名（例如 `https://n8n.example.com/`）。
- `GENERIC_TIMEZONE`: 时区（例如 `Asia/Shanghai`）。

### 2. 启动服务

使用 Docker Compose 启动所有服务：

```bash
docker compose up -d
```

该命令会自动构建自定义的 Python Runner 镜像并启动所有相关容器。

### 3. 停止服务

```bash
docker compose down
```

## ⚙️ 环境变量说明

| 变量名 | 说明 |
| :--- | :--- |
| `N8N_VERSION` | n8n 主镜像版本；可选。**未设置时**主镜像与 runner 镜像均跑 `stable`（跟随上游）。**显式设置**时（如 `2.18.5`）主镜像与 runner 镜像同时锁到该 tag |
| `POSTGRES_NON_ROOT_USER` | n8n 使用的非管理员数据库用户名 |
| `ENCRYPTION_KEY` | 用于加密 n8n 凭据的密钥（**极其重要，请妥善备份**） |
| `REDIS_PASSWORD` | Redis 访问密码 |
| `WEBHOOK_URL` | 外部访问 URL，影响 Webhook 接收和 OAuth 回调 |
| `N8N_RUNNERS_AUTH_TOKEN` | 主节点与 Python Runner 之间的通讯令牌 |

## 🐍 Python Runner 自定义

本项目通过 `Dockerfile` 对 `n8nio/runners` 进行了增强，默认安装了以下库：

- 数据处理: `pandas`, `numpy`, `openpyxl`
- 网页解析: `beautifulsoup4`, `lxml`, `html2text`
- AI/API: `openai`, `tiktoken`, `requests`
- 工具类: `Pillow`, `python-dateutil`, `youtube-transcript-api`

如果需要添加更多库，请修改 `Dockerfile` 并重新运行 `docker compose build n8n-task-runners`。

## 💾 数据持久化

所有数据都存储在 Docker 卷中，确保容器更新时数据不丢失：

- `db_storage`: PostgreSQL 数据库数据。
- `n8n_storage`: n8n 的配置文件和本地二进制文件。
- `redis_storage`: Redis 的持久化数据。

## 🔒 安全建议

1. **入口防护**: 建议在 n8n 前方部署反向代理（如 Nginx, Traefik 或 Cloudflare Tunnel），并启用 HTTPS。
2. **强密码**: 确保 `.env` 中的所有密码均为强随机字符串。
3. **隔离性**: `backend` 网络设置为内部网络，仅允许必要的容器间通信。
4. **备份**: 定期备份 `db_storage` 挂载点或使用 `pg_dump` 备份数据库。

## 📄 开源协议

本项目遵循相关组件的开源协议。请参考各镜像官方文档。
