# n8n（taoziyoyo）运维说明

本目录在主机 taoziyoyo 上运行 n8n，对应 Git 分支 `taoziyoyo`。设计思路和决定记录在
[docs/plan-upstream-override-2026-10-29.md](docs/plan-upstream-override-2026-10-29.md)，
给 AI agent 的约束在 [AGENTS.md](AGENTS.md)。

## 结构：官方文件不动，自定义单独放

| 文件 | 来源 | 作用 |
|---|---|---|
| `docker-compose.yml`、`init-data.sh`、`README.md` | 官方，**不要修改** | 官方的部署定义 |
| `docker-compose.override.yml` | 自定义，进 Git | 本机的全部差异；`docker compose` 会自动和官方文件合并 |
| `.env` | 本机，**不进 Git**，权限 600 | 版本号、密码、加密密钥、域名、SMTP |
| `.env.template` | 自定义，进 Git | `.env` 里每个变量的说明（只有占位值） |

`docker-compose.override.yml` 里的自定义：

- n8n 只监听 `127.0.0.1:5678`（官方默认对所有网卡开放）；
- Postgres 固定在 17（和现有数据卷绑定）；
- Redis 设置密码；
- SMTP、对外网址、反向代理层数、时区、关闭诊断上报；
- 容器安全加固（`no-new-privileges`、以 1000 用户运行）；
- `backend`（内部）和 `ingress` 两个网络。发票应用（invoice_automation 项目）通过
  `backend` 网络访问 `http://n8n:5678`。

runner 用官方的 `n8nio/runners` 镜像：主服务和 worker 各配一个（`n8n-runner`、
`n8n-worker-runner`），不带额外的 Python 库。

## 访问

- 本机：`http://127.0.0.1:5678`，健康检查 `http://127.0.0.1:5678/healthz`。
- 从自己电脑：`ssh -L 5678:127.0.0.1:5678 <用户名>@<服务器地址>`，然后用 Chrome 或
  Firefox 打开 `http://localhost:5678`。
- 公网：`https://n8n.saberu.com`，经本机 cloudflared（tunnel `spt`，规则
  `n8n.saberu.com → http://127.0.0.1:5678`）。前面没有 Cloudflare Access，靠 n8n 账号
  密码和 MFA 保护，所以要及时升级 n8n。

## 日常操作

都在本目录执行：

```bash
cd ~/workspace/projects/n8n-hosting/docker-compose/withPostgresAndWorker
docker compose ps                        # 查看状态
docker compose logs --tail 50 n8n        # 查看日志（n8n-worker、n8n-runner、postgres、redis 同理）
docker compose restart n8n n8n-worker    # 重启 n8n
docker compose config --quiet            # 检查合并后的配置是否有效
```

`docker compose config`（不带 `--quiet`）会显示合并后的完整配置，其中含密码，不要外传。

runner 是否正常：

- `n8n-worker-runner` 的日志停在 `Waiting for launcher's task offer to be accepted`，
  `n8n-worker` 的日志里有 `Registered runner "launcher-javascript"` 和
  `"launcher-python"`，说明代码节点可以运行。
- `n8n-runner` 一直显示 `Waiting for task broker to be ready...` 是**正常的**：配置里
  `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true`，所有执行都交给 worker，主服务不启动 task
  broker（n8n 源码 `commands/start.js` 的判断）。这个容器是官方配置自带的，保留不动。

## 升级 n8n

1. 在 <https://github.com/n8n-io/n8n/releases> 确认新的稳定版（不要用 pre-release）。
2. **先备份数据库**（见"备份"）。升级可能改动数据库结构，出问题时要用这份备份恢复。
3. 只改 `.env` 里的 `N8N_VERSION=` 一处；同时把 `.env.template` 里的版本号改成一样并提交，
   作为记录。
4. `docker compose pull && docker compose up -d --remove-orphans`
5. 验证：`curl -s http://127.0.0.1:5678/healthz` 返回 `{"status":"ok"}`；
   `docker exec withpostgresandworker-n8n-1 n8n --version` 显示新版本；
   `docker compose logs --tail 50 n8n` 没有报错。

## 跟进官方更新

```bash
cd ~/workspace/projects/n8n-hosting
git fetch origin
git log --oneline taoziyoyo..origin/main -- docker-compose/withPostgresAndWorker   # 看官方改了什么
git tag pre-merge-$(date +%F)    # 记下合并前的位置，出问题时回到这里
git merge origin/main
```

- 官方改了示例 `.env` 时会出现冲突。先用 `git diff` 看它新增了哪些变量，加进本机 `.env` 和
  `.env.template`，再用 `git rm docker-compose/withPostgresAndWorker/.env` 保持删除。
- 检查 `docker-compose.yml` 的改动会不会和 override 冲突：服务改名、新的必填变量、
  Postgres 大版本变化。
- 用 `docker compose config --quiet` 检查后，再 `docker compose pull` 和
  `docker compose up -d --remove-orphans`。

## 修改自定义

- 只改 `docker-compose.override.yml`，不要改官方文件。
- 合并规则：环境变量按名字合并；列表默认是追加，要整体替换时写 `!override`（例如端口）。
- 改完先 `docker compose config --quiet`，再 `docker compose up -d`。
- 不要改 `networks` 的定义：会让 Compose 重建 `backend` 网络，发票应用会断开。

## 备份

- 数据库（建议定期做，文件含全部 n8n 数据，权限设为 600）：

  ```bash
  docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > ~/n8n-db-$(date +%F).dump
  chmod 600 ~/n8n-db-*.dump
  ```

- `.env` 要另外安全保存：里面的 `ENCRYPTION_KEY` 丢了，n8n 里保存的所有凭据都无法解密。

## 出问题时

先用 `docker compose ps` 和各服务的日志确认是哪个服务出了问题。

**升级 n8n 后出问题：** 新版本可能已经改了数据库结构，只把 `N8N_VERSION` 改回去不一定能启动。
用升级前的备份恢复数据库，再改回原来的版本（`YYYY-MM-DD` 换成备份文件的日期）：

```bash
cd ~/workspace/projects/n8n-hosting/docker-compose/withPostgresAndWorker
docker compose stop n8n n8n-worker
docker exec -i withpostgresandworker-postgres-1 sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' < ~/n8n-db-YYYY-MM-DD.dump
# 把 .env 里的 N8N_VERSION 改回升级前的版本，然后：
docker compose up -d --remove-orphans
```

这条恢复命令在 2026-10-29 用当时的数据库在临时容器里演练过：在已有数据上恢复，结果和原库一致。

**合并官方更新后出问题：** 回到合并前打的标签（`YYYY-MM-DD` 换成打标签的日期；会丢弃这次合并，
先确认没有其他未提交的改动）：

```bash
cd ~/workspace/projects/n8n-hosting
git reset --hard pre-merge-YYYY-MM-DD
cd docker-compose/withPostgresAndWorker && docker compose up -d --remove-orphans
```

## 注意事项

- Postgres 大版本和数据卷绑定：要升到官方的 18，必须先导出数据，用新的数据卷启动，再导入，
  不能直接改镜像版本。
- 不要移动本目录。容器里记着这个目录的绝对路径，移动后要从新路径重建；2026-09-22 的
  n8n 停机就是目录被移动导致的。
- 全新安装的 n8n 在建好管理员之前，不要挂公网域名。
- 这个仓库（GitHub 上的 fork）是**公开的**：推送前确认不含密码、密钥、webhook 路径，也尽量
  不写具体的主机信息（用户名、IP、tunnel ID）。

## 相关位置

| 项目 | 位置 |
|---|---|
| 部署目录 | `~/workspace/projects/n8n-hosting/docker-compose/withPostgresAndWorker` |
| 分支 | `taoziyoyo`（本机部署用）、`origin/main`（官方） |
| 公网域名 | `n8n.saberu.com`（cloudflared tunnel `spt`） |
| 发票 workflow | `Invoice-prod`（ID `ZGkSt8cnDPHViIj3`，已发布）、`Invoice-test`（ID `PTuWO9goJQP7WGZ3`），SMTP 凭据 `Taoziyoyo` |
| 发票应用的使用说明 | invoice_automation 仓库的 `README.md` |
