# n8n Compose 升级与加固方案

- 状态：**版本部分已实施并验证，其余待处理**
- 编写日期：2026-08-31
- 修订：第 3 版（2026-08-31，版本变更已落地，本文档转为后续待办清单）
- 适用目录：`docker-compose/withPostgresAndWorker/`
- 调查基准：Git `e75fd1faed249a322788dc33e1b62c76476edea4` + 当前工作区 + 2026-08-31 线上实测
- 目标平台：Linux `aarch64`（NanoPi-R6S）

---

# 第一部分：已完成（版本）

本轮只处理版本问题，已在工作区完成以下修改。**尚未提交、尚未部署。**

## 1.1 已落地的改动

| 文件 | 位置 | 改动 | 性质 |
|---|---|---|---|
| `docker-compose.yml` | `x-shared` | `n8nio/n8n:latest` → `2.36.8` | 钉版 |
| `docker-compose.yml` | `postgres` | `postgres:17` → `16.15-trixie` | **故障修复** |
| `docker-compose.yml` | `db-init` | `postgres:16` → `16.15-trixie` | 钉版 |
| `Dockerfile` | 基底 | `n8nio/runners:2.2.6` → `2.36.8` | **实质升级** |

> **读表基准**：上表“改动”列是**工作区相对**的（写作时工作区已存在 `latest` / `postgres:17`
> 等未提交改动）。提交后从 `git diff` 看到的是 **HEAD `e75fd1f` 相对**的版本：
> `n8n:2.2.6 → 2.36.8`、`postgres:16 → 16.15-trixie`。两者描述的是同一组最终状态，
> 不是两次不同的改动；且 1.3 已证实 n8n / postgres 两处是钉版而非升级。

## 1.2 与原方案的两处偏离

**偏离一：PostgreSQL 用 `16.15-trixie`，不用 `16.15-bookworm`。**

原方案写的是 `16.15-bookworm`。但实测线上 `postgres:16` 解析到的镜像是 Debian 13 trixie 基底：

```text
容器内 /etc/os-release      → Debian GNU/Linux 13 (trixie)
postgres:16      image ID   → sha256:43064e70a75c…
postgres:16.15-trixie       → sha256:43064e70a75c…   ← 完全相同
postgres:16.15-bookworm     → 不同镜像（另一套基础发行版）
```

选 bookworm 会在钉版的同时把基础发行版从 trixie 换回 bookworm，白白引入一次容器重建和一组无关的系统库变化。选 `16.15-trixie` 则是**与线上运行镜像逐位一致的钉版**。

**偏离二：`postgres:17` 直接回退，不作为待议项。**

原方案把 16→17 写成需要讨论的风险。实际它是工作区里已写好的未提交改动，而线上数据目录是 16.15，下一次 `up -d` 会直接让 postgres 起不来。已当作故障修复处理掉。

## 1.3 镜像内容一致性

n8n 与 postgres 的钉版指向的镜像，与线上**正在运行的镜像逐位相同**：

```text
运行中 n8n 容器            → sha256:e752871c34a1…
docker.n8n.io/…/n8n:latest → sha256:e752871c34a1…
docker.n8n.io/…/n8n:2.36.8 → sha256:e752871c34a1…   ← 三者同一

postgres:16                → sha256:43064e70a75c…
postgres:16.15-trixie      → sha256:43064e70a75c…   ← 同一
```

含义：这两处钉版**不改变任何运行中的二进制**，n8n 仍是 2.36.8、PostgreSQL 仍是 16.15。

## 1.4 部署时的实际行为（实测，勿凭直觉推断）

以 `docker compose up -d --dry-run` 实测当前工作区，结果如下：

```text
withpostgresandworker-postgres-1        Recreate
withpostgresandworker-db-init-1         Recreate
withpostgresandworker-n8n-1             Recreate
withpostgresandworker-n8n-worker-1      Recreate
withpostgresandworker-n8n-task-runners-1 Running   ← 不会重建
withpostgresandworker-redis-1           Running
```

两条与直觉相反、必须记住的结论：

**结论一：镜像内容相同 ≠ 容器不重建。**
Compose 比对的是服务配置哈希，其中包含**镜像引用字符串**本身。把 `latest` 写成
`2.36.8` 即使 digest 完全一致，配置哈希仍然改变，容器照样重建。所以 postgres、
db-init、n8n、n8n-worker 四个服务都会被重启一次。因为镜像内容一致，这只是"用同一个
镜像重启一遍"，不涉及版本变化，但**确实存在一次服务中断**，需要安排窗口。

对照实验（同样以 dry-run 实测）：把 HEAD 原样的 compose 拿来跑，postgres / db-init /
n8n 同样显示 `Recreate`——说明线上容器早已与 HEAD 的声明漂移。重建不全是本次改动引入的。

**结论二：`docker compose up -d` 不会重新构建 Runner，Dockerfile 的版本提升会静默失效。**

`n8n-task-runners` 用的是 `build:` 而非 `image:`。本地已存在
`withpostgresandworker-n8n-task-runners` 镜像（构建于 2026-08-30，内含
`@n8n/task-runner` 2.2.3），Compose 认为无需构建，直接复用。实测：

```text
docker compose up -d           → 输出中 "Building" 出现 0 次
docker compose up -d --build   → 输出中 "Building" 出现 1 次
```

**因此部署这批改动必须使用 `docker compose up -d --build`。** 用不带 `--build` 的
命令会得到一个看起来成功、实际 Runner 仍停留在 2.2.3 的部署——而这恰恰是本轮唯一
真正需要生效的版本变更。

## 1.5 已执行的验证

- `docker compose --env-file .env config --quiet` → 通过
- `docker compose up -d --dry-run` → 重建范围已确认（见 1.4）
- 三个目标标签的 ARM64 manifest 均已确认存在
- n8n / postgres 钉版镜像 ID 与线上一致（见 1.3）
- `db-init.sh` 幂等性复核 → 通过（`IF NOT EXISTS` / `ALTER USER` / GRANT 均可重复执行），
  因此 1.4 中 db-init 的重建重跑是安全的
- Runner 无缓存 ARM64 构建 + 13 个 Python 包 import 测试 → 通过，见 1.6

## 1.6 Runner 构建验证

已在 aarch64 本机执行 `docker build --no-cache`，**通过**。

```text
基底         n8nio/runners:2.36.8 → Alpine 3.24.1 / Python 3.13.15 / 默认用户 runner(1000)
apk 手法     现有 apk-tools-static 取巧方式在新基底实测仍可用
              （apk 已从镜像移除，但 /etc/apk/repositories 保留并指向 v3.24）
构建结果     exit 0
最终用户     uid=1000(runner) —— 非 root，符合要求
```

13 个 Python 包在 Python 3.13 下逐一 import 测试全部通过：

```text
OK  requests  pandas  numpy  openpyxl  bs4  lxml  html2text
OK  openai  tiktoken  youtube_transcript_api  PIL  dateutil  pytz
```

依赖被 pip 解析到了较新的版本（如 `pandas-3.0.5`、`numpy-2.5.2`、`openai-3.6.0`、
`Pillow-12.3.0`）。由于 Dockerfile 没有钉任何 Python 包版本，**这些依赖仍是浮动的**，
下次构建可能拿到不同版本。该问题属于 2.5 的范畴，本轮未处理。

启动冒烟测试（独立容器、指向假 broker、未接触线上）：

```text
Status=running  Restarts=0  ExitCode=0
uid=1000(runner) —— 非 root
INFO  Starting launcher's health check server at port 5680
INFO  [launcher:py] Starting launcher goroutine... / Waiting for task broker to be ready...
INFO  [launcher:js] Starting launcher goroutine... / Waiting for task broker to be ready...
```

JS 与 Python 两个 launcher goroutine 均正常拉起并进入等待 broker 状态，无崩溃、无重启，
日志形态与线上现有 Runner 一致。

一处需要注意的命名差异：`n8nio/runners:2.36.8` 镜像内部的 `@n8n/task-runner`
包版本号是 `2.36.5` 而非 `2.36.8`。这是 n8n monorepo 的常态（旧的 `2.2.6` 镜像内部
同样是 `2.2.3`）。官方要求对齐的是**镜像标签**与 n8n 版本，此处已对齐。

## 1.7 部署这批版本改动时的注意事项

- **必须用 `docker compose up -d --build`**，否则 Runner 的版本提升不生效（1.4 结论二）。
- postgres、db-init、n8n、n8n-worker 会各重启一次（1.4 结论一）。镜像内容不变，
  但需要安排维护窗口，不是无感操作。
- `n8n-task-runners` 重建后旧镜像会失去标签，回退前应先记下当前镜像 ID
  `sha256:72c89b2076d6…`（内含 task-runner 2.2.3），必要时可用它回退。
- 部署前仍应按 2.8 生成一份可用备份（现有 4 个备份包已 5 个月未验证，不可作为回退素材）。
- 部署后确认：`n8n --version` 仍为 2.36.8、postgres 仍为 16.15、Runner 能连上 broker、
  invoice_automation 的 webhook 仍通。

---

# 第二部分：待处理

以下全部**未实施**，按建议顺序排列。

## 2.1 敏感备份的 Git 防护（建议优先级最高）

未跟踪状态里现有 4 个 `n8n_full_migration_*.tar.gz`，全部含 `.env`，其中 3 个含 PostgreSQL dump。它们目前只靠"没有 `git add`"挡着。

- 在仓库根目录建立 `.gitignore`，至少忽略 `.env` 和 `n8n_full_migration_*.tar.gz`。无前导斜杠的模式对任意子目录递归生效。
- 处理与已存在的 `docker-compose/withPostgresAndWorker/.gitignore` 的重复——后者当前只有一行 `.env`，应择一保留。
- 把 4 个迁移包移出仓库到受保护位置（目标由操作员确定），移动前后记录大小与 SHA-256。
- 权限保持 `0600`（现有 4 个文件已满足）；长期保存需用受控密钥加密，压缩不等于加密。
- 根目录旧版 V2 `n8n_migrate.sh` 在确认无独立用途后移出或删除；确认前保持不动且不提交。

**已确认无需处理**：Git 历史中不存在真实秘密。历史里的 `.env` 来自上游 `n8n-io` 仓库导入提交，内容为占位符（`changeUser` / `changePassword`）；3 个受跟踪的工作流导出只含 credential ID 引用，无内联密钥值。

## 2.2 清理废弃配置

线上 n8n 启动日志原文：

```text
- N8N_RUNNERS_ENABLED -> Remove this environment variable; it is no longer needed.
- N8N_RUNNERS_TASK_TIMEOUT -> The default for this variable will be reduced from
  300 (5 minutes) to 60 (1 minute) in a future version. Set it explicitly to keep
  your current task timeout.
```

- 删除 `docker-compose.yml` 中的 `N8N_RUNNERS_ENABLED=true`，保留 `N8N_RUNNERS_MODE=external`。
- **显式设置 `N8N_RUNNERS_TASK_TIMEOUT`**。不设的话，将来某次升级会把任务超时从 300 秒静默降到 60 秒。需要先确定合适的秒数（见 4.2）。

## 2.3 时区一致性

- `docker-compose.yml` 的 n8n 共享环境中增加 `TZ=${GENERIC_TIMEZONE}`。目前只设了 `GENERIC_TIMEZONE`，容器系统时区未跟随。
- `.env.template` 的 `GENERIC_TIMEZONE` 由 `Asia/Shanghai` 改为 `Asia/Tokyo`——**此项已在工作区改好但未提交**，属于本轮之外的既有改动。

## 2.4 容器网络收敛

实测拓扑与约束（详见附录 A.6）：

| 服务 | `ingress` | 结论 |
|---|---|---|
| `n8n` | 保留 | 需出网；且 `backend` 是 invoice_automation 的唯一入口，两者都不能动 |
| `n8n-worker` | **必须保留** | 线上有 `emailSend` 节点，SMTP 出站在 Worker 侧执行；`backend` 为 `internal: true`，实测断网 |
| `n8n-task-runners` | **可以移除** | 只需经 `backend` 连 `n8n-worker:5679`；现有 2 个 Code 节点为纯校验逻辑，无网络调用 |

收益：Code 节点即使发生沙箱逃逸也拿不到出网能力。
代价：**未来任何需要联网的 Code 节点会静默失败**，该约束必须写进 README，不能只落在 Compose 里。

对 invoice_automation 无影响——它以 `external: true` 接入 `withpostgresandworker_backend`，通过 `http://n8n:5678/webhook/<path>` 访问，完全不使用 `ingress`。

**真正会破坏跨项目协作的不是这项改动，而是任何导致 `withpostgresandworker_backend` 网络被删除或改名的操作**（invoice_automation 按名引用它）。执行 `docker compose down` 时需注意。

## 2.5 自建 Python Runner 的去留（需要先决策）

线上数据库实测：5 个工作流，Code 节点仅 2 个，`parameters.language` 均未设置即默认 JavaScript，**全库无任何 Python Code 节点**。在用节点类型完整清单：

```text
n8n-nodes-base.code / emailSend / formTrigger / respondToWebhook / webhook
```

也就是说 `Dockerfile` 里常驻的 `build-base`、`python3-dev`、`linux-headers`、静态 `apk`，以及 pandas / numpy / openai / Pillow / lxml 等依赖，**没有任何在用工作流需要**。

本轮已把基底版本对齐到 2.36.8（第一部分），但没有动它的结构。后续二选一：

**方案 A：退役自建镜像（推荐，除非有明确的 Python 计划）**
- `n8n-task-runners` 由 `build:` 改为 `image: n8nio/runners:2.36.8`
- 删除 `Dockerfile` 与 `entrypoint-with-python.sh`（确认无其他用途后）
- 收益：编译链与包管理器不再常驻运行时；版本一致性不再依赖手工维护 Dockerfile；无需 allowlist 工程
- 代价：将来要用 Python Code 节点时需重新引入

**方案 B：保留并加固**
- 改用多阶段构建，不把 `build-base` / `python3-dev` 留在最终层
- 按官方当前方式在 `/opt/runners/task-runner-python` 中用 `uv pip install` 安装
- 最终切回镜像自带的非 root `runner` 用户（现在写的是 `USER 1000`，2.36.8 基底已确认默认用户即 `runner`(1000)，可以直接用名字）
- 新增 `n8n-task-runners.json` 明确列出允许导入的标准库与第三方包——**安装依赖不等于授权 Code 节点导入**
- allowlist 内容不得照抄现有 pip 清单，那份清单没有任何在用工作流背书

## 2.6 加固迁移脚本 `n8n_migrate.sh`

1. `set -Eeuo pipefail`
2. 创建任何秘密或备份文件前 `umask 077`，避免先宽权限创建再 `chmod` 的暴露窗口
3. `mktemp -d` 创建唯一临时目录，禁止复用固定 `/tmp/n8n_migration_*`
4. trap 清理临时目录，备份中途失败时尽力恢复被停止的服务
5. 用 Compose 服务名执行数据库命令，减少对硬编码容器名的依赖
6. 检查每一个关键命令的结果；失败时不得删除唯一可用数据或打印"备份成功"
7. 备份后做完整性检查，生成不含秘密的 SHA-256 校验文件
8. 长期保存或传输前必须加密
9. 恢复前校验归档结构、校验和及目标卷状态；默认拒绝覆盖非空目标
10. 保留现有"存在本地 `docker-compose.yml` 时不覆盖"的改动（已在工作区，未提交）
11. 恢复 `.env` 后保持 `0600`，只保留经格式校验的目标机时区值
12. 数据库主版本迁移不复用普通恢复路径

`n8n_migrate_netcup.sh` 与主脚本已功能漂移且会执行远程写入。本轮不运行；后续应合并为一个显式传输选项，或确认无用途后退役。

## 2.7 Redis 6.2 已 EOL

`redis:6.2.14-alpine`。Redis 6.2 分支**已经结束官方支持**，不是"即将到期"。本轮不动是为控制变更面，但这属于**已知在用的过期组件**，应单独立项并设定期限，不能无限期停留在"待评估"。

## 2.8 备份可恢复性验证

现有 4 个迁移包生成于 2026-04-05，dump 由 `pg_dump 16.11` 导出，schema 属于 n8n 2.2.6 时代，距今约 5 个月。**用它恢复是一次 schema 降级而非回退，不能作为任何变更的回退素材。**

需要做的是：生成一份新备份，并在独立 Compose project、独立端口、全新命名卷中验证其可恢复性（确认 n8n 能启动并读到工作流）。禁止连接线上卷。

理由不是当前变更危险，而是 2.6 正在改动备份脚本本身——改完的脚本必须证明它产出的东西能用。

## 2.9 PostgreSQL 17 迁移（独立立项）

PostgreSQL 16 支持至 2028-11-09，不紧急。真要做时：跨主版本需 dump/restore 或 `pg_upgrade`，必须使用**新的目标卷**和经过验证的迁移/回退流程，不能原地换镜像。

---

# 第三部分：验证与部署

## 3.1 静态检查

```text
bash -n docker-compose/withPostgresAndWorker/*.sh
shellcheck docker-compose/withPostgresAndWorker/*.sh
docker compose --env-file .env config --quiet
git diff --check
```

- `shellcheck` 不可用时记录为未执行，不能写成通过
- Compose 校验不得把展开后的秘密打印到日志
- 秘密扫描的输出只能包含文件位置和规则，不得输出秘密值

## 3.2 部署前置条件

- 已生成部署前新备份，且已通过 2.8 的可恢复性验证
- 备份位于仓库外、已加密、权限正确、有校验和
- Compose 最终差异和镜像版本经过人工复核
- invoice_automation 回归清单（3.3）已确认，其负责人知晓变更窗口
- 已确定维护窗口、负责人和失败判定时间

部署不得与 Git 提交/推送捆绑为一次隐式授权。

## 3.3 跨项目回归（invoice_automation）

改动网络（2.4）或执行 `docker compose down` 后必须验证：

1. `withpostgresandworker_backend` 网络名未变
2. 从 `invoice-app` 容器内 `n8n:5678` 仍可解析并连通
3. 通过 invoice_automation 页面触发一次 test webhook，确认工作流被接收
4. `emailSend` 出站仍正常（依赖 Worker 保留 `ingress`）

任意一项失败立即回退网络改动，不得带病上线。

## 3.4 回退原则

1. 保留部署前的 Compose 文件、精确镜像版本、数据库逻辑备份和 n8n 数据卷备份
2. n8n 与 postgres 的钉版指向与线上逐位相同的镜像，不引入 schema migration；但容器仍会重建（1.4），回退即恢复旧 Compose 并再次 `up -d`
3. Runner 是唯一实质版本变更，无持久状态，回退即切回旧镜像
4. PostgreSQL 保持主版本 16，不涉及数据目录主版本回退
5. 网络改动的回退是给 `n8n-task-runners` 加回 `ingress`，无状态影响
6. 若因任何原因 postgres 曾以 17 启动并写入过数据目录，**不得尝试原地降级**，必须停栈并从部署前备份恢复数据库卷
7. 回退后重新验证健康状态、Worker 队列、Runner 连接、凭据解密，以及 invoice_automation 的 webhook 连通性

---

# 第四部分：待确认事项

1. **是否保留自建 Python Runner**（2.5）。当前零使用量。选方案 A（退役，推荐）还是方案 B（保留并加固）？此项决定后续提交的形态和验证工作量。
2. `N8N_RUNNERS_TASK_TIMEOUT` 应显式设为多少秒（2.2）。
3. 是否接受 Runner 摘除 `ingress` 的约束：Code 节点将无法联网（2.4）。已确认对 invoice_automation 无影响。
4. 敏感备份移出仓库后的目标存储位置和加密方式（2.1）。
5. 采用方案 B 时，实际需要允许的标准库及第三方包清单（不得照抄现有 pip 清单）。
6. 根目录 V2 脚本和 `n8n_migrate_netcup.sh` 的保留、合并或退役决定（2.6）。
7. Redis 6.2（已 EOL）的升级立项时间（2.7）。
8. 线上维护窗口，以及 invoice_automation 回归验证的责任人。

---

# 第五部分：参考资料

- [n8n：配置 Task Runners](https://docs.n8n.io/hosting/configuration/task-runners/)
- [n8n：使用 Docker 安装与更新](https://docs.n8n.io/hosting/installation/docker/)
- [n8n GitHub Security Advisories](https://github.com/n8n-io/n8n/security/advisories)
- [GHSA-8398-gmmx-564h：Python sandbox escape](https://github.com/advisories/GHSA-8398-gmmx-564h)
- [GHSA-rcv6-pvrj-4xcg：Git node authenticated code execution](https://github.com/advisories/GHSA-rcv6-pvrj-4xcg)
- [PostgreSQL Versioning Policy](https://www.postgresql.org/support/versioning/)
- [PostgreSQL 17：Upgrading a PostgreSQL Cluster](https://www.postgresql.org/docs/17/upgrading.html)
- [Docker Official Image：PostgreSQL](https://github.com/docker-library/docs/blob/master/postgres/README.md)
- [Docker：internal 网络](https://docs.docker.com/reference/compose-file/networks/)

---

# 附录 A：2026-08-31 线上实测记录

全部为只读查询，未修改任何容器、卷或数据。查询数据库时密码经 shell 变量传入，未输出任何秘密值。

## A.1 容器与镜像

```text
withpostgresandworker-n8n-1              docker.n8n.io/n8nio/n8n:latest   Up 34 hours
withpostgresandworker-n8n-worker-1       docker.n8n.io/n8nio/n8n:latest   Up 34 hours
withpostgresandworker-n8n-task-runners-1 (自建)                           Up 34 hours
withpostgresandworker-postgres-1         postgres:16                      Up 34 hours (healthy)
withpostgresandworker-db-init-1          postgres:16                      Exited (0)
withpostgresandworker-redis-1            redis:6.2.14-alpine              Up 34 hours (healthy)
invoice_automation-invoice-app-1         invoice_automation-invoice-app   Up 16 hours (healthy)
```

## A.2 版本

- `n8n --version` → `2.36.8`（经由 `latest` 标签，即改动前线上已是该版本）
- `postgres --version` → `PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2)`，容器基底 Debian 13 trixie
- Runner → `@n8n/task-runner` `2.2.3`（基底 `n8nio/runners:2.2.6`），与 n8n 2.36.8 跨大版本不一致
- 宿主架构 → `aarch64`

## A.3 镜像标签（Docker Hub API）

- `n8nio/n8n:latest` / `:stable` / `:2.36.8` → 同一 digest `sha256:cfe2704f…`，含 arm64
- `n8nio/runners:2.36.8` → 含 arm64
- `postgres:16.15-trixie` 与 `postgres:16` → 同一 digest `sha256:f1c3376c…`，含 arm64
- `postgres:16.15-bookworm` → 不同 digest `sha256:bb3e1a57…`

## A.4 `n8nio/runners:2.36.8` 基底特征

```text
基础发行版   Alpine Linux 3.24.1
Python       3.13.15（/usr/local/bin/python3）
pip          存在（/usr/local/bin/pip）
apk          已移除（但 /etc/apk/repositories 保留并指向 v3.24）
默认用户     runner (uid=1000, gid=1000)
ENTRYPOINT   tini -- /usr/local/bin/task-runner-launcher
CMD          javascript python
/opt/runners task-runner-javascript, task-runner-python
```

现有 Dockerfile 从 `alpine:3.20` 取 `apk-tools-static` 的手法在该基底上实测仍可用。

## A.5 工作流与节点

- 工作流总数：5
- Code 节点：2 个（`Invoice-prod` / `Invoice-test` 的 `Validate Files and Extract Month`），`language` 未设置即 JavaScript
- Python Code 节点：**0**
- Code 节点中匹配 `fetch|httpRequest|axios|require\(|https?://` 的：**0**
- 在用节点类型：`code`、`emailSend`、`formTrigger`、`respondToWebhook`、`webhook`

## A.6 网络

```text
withpostgresandworker_backend  (internal: true)
  n8n            172.19.0.4   aliases=[… n8n]
  task-runners   172.19.0.5
  n8n-worker     172.19.0.6   aliases=[… n8n-worker]
  invoice-app    172.19.0.7   ← 跨项目接入
withpostgresandworker_ingress
  n8n 172.18.0.2 / n8n-worker 172.18.0.3 / task-runners 172.18.0.4
invoice_automation_default
  invoice-app 172.20.0.2      ← invoice_automation 自身出网路径
```

出网实测：

- 仅接 `backend` 的 postgres 容器 → `Network is unreachable`（确认 `internal: true` 生效）
- 同时接 `ingress` 的 task-runners 容器 → 外部 TCP 可达、DNS 可解析

invoice_automation 接入方式（`~/workspace/projects/invoice_automation/compose.yaml`）：

```yaml
networks:
  n8n-backend:
    name: withpostgresandworker_backend
    external: true
```

其 `.env.example` 记录的访问地址为 `http://n8n:5678/webhook/<webhook-path>`，即经由 `backend` 的服务别名，不涉及 `ingress`。

## A.7 废弃警告（n8n 容器日志原文）

```text
- N8N_RUNNERS_ENABLED -> Remove this environment variable; it is no longer needed.
- N8N_RUNNERS_TASK_TIMEOUT -> The default for this variable will be reduced from
  300 (5 minutes) to 60 (1 minute) in a future version. Set it explicitly to keep
  your current task timeout.
```

## A.8 备份包

- 4 个 `n8n_full_migration_*.tar.gz`，权限均为 `0600`
- 均含 `./.env`；位于本目录的 3 个另含 `./n8n_db.dump`
- dump 格式 `PostgreSQL custom database dump`，由 `pg_dump 16.11` 生成
- 生成日期 2026-04-05，对应 n8n 2.2.6 时代 schema

## A.9 Git 历史秘密扫描

- 历史中新增过的 `.env` 均来自上游 `n8n-io` 仓库导入提交，内容为占位符（`changeUser` / `changePassword`）
- 受跟踪的 3 个工作流导出含 credential 引用块，但无内联密钥值
