#!/bin/bash

# ==========================================
# n8n 全量迁移自动化脚本 V4 (同目录执行 & 智能读取 .env)
# ==========================================

# === 核心配置项 (基于当前目录的项目名) ===
# 只要你不改文件夹名字，这些通常不需要动
VOLUME_NAME="withpostgresandworker_n8n_storage"
DB_CONTAINER="withpostgresandworker-postgres-1"
DATE_STR=$(date +%Y%m%d_%H%M%S)
FINAL_BACKUP_NAME="n8n_full_migration_${DATE_STR}.tar.gz"

# === 颜色显示设置 ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  bash n8n_migrate.sh backup                 - 全量打包 (读取当前目录 .env)"
    echo "  bash n8n_migrate.sh restore <备份文件.tar.gz> - 全量恢复 (还原当前目录)"
}

# 辅助函数：安全读取 .env 文件并导出为系统环境变量
load_env() {
    if [ ! -f ".env" ]; then
        echo -e "${RED}❌ 错误: 当前目录下找不到 .env 文件！${NC}"
        exit 1
    fi
    # 忽略注释和空行，强制导出变量
    set -a
    source <(grep -v '^#' .env | sed -e '/^$/d')
    set +a
}

do_backup() {
    echo -e "${GREEN}🚀 开始执行 n8n 全量备份流程 (V4)...${NC}"

    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}❌ 错误: 当前目录下找不到 docker-compose.yml，请在配置文件同目录运行此脚本！${NC}"
        exit 1
    fi

    # 加载 .env 中的环境变量
    load_env
    
    # 确保数据库必要变量存在
    if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; then
        echo -e "${RED}❌ 错误: .env 文件中未找到 POSTGRES_USER 或 POSTGRES_PASSWORD。${NC}"
        exit 1
    fi

    TMP_DIR="/tmp/n8n_migration_tmp"
    mkdir -p "${TMP_DIR}"

    # 1. 无停机导出 Postgres 数据库
    echo -e "${YELLOW}🗄️ 正在导出 Postgres 数据库 (用户: ${POSTGRES_USER})...${NC}"
    docker start ${DB_CONTAINER} > /dev/null 2>&1
    
    # 核心黑科技：通过 -e PGPASSWORD 将外部 .env 密码安全传递给容器内的 pg_dump
    docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" ${DB_CONTAINER} pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-$POSTGRES_USER}" -F c > "${TMP_DIR}/n8n_db.dump"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 数据库导出失败，请检查数据库容器是否正常运行。${NC}"
        rm -rf "${TMP_DIR}"
        exit 1
    fi

    # 2. 暂停服务防止数据写入
    echo -e "${YELLOW}⏸️ 正在停止 n8n 服务集群...${NC}"
    docker compose stop

    # 3. 拷贝配置文件 (直接从当前目录拷贝)
    echo -e "${YELLOW}📄 正在拷贝配置文件...${NC}"
    cp docker-compose.yml "${TMP_DIR}/"
    cp .env "${TMP_DIR}/"

    # 4. 打包 n8n 本地数据卷
    echo -e "${YELLOW}🔑 正在打包加密密钥卷 [${VOLUME_NAME}]...${NC}"
    docker run --rm -v ${VOLUME_NAME}:/source -v ${TMP_DIR}:/backup alpine tar -czf /backup/volume_data.tar.gz -C /source .

    # 5. 生成最终压缩包
    echo -e "${YELLOW}🗜️ 正在生成最终的全量迁移包...${NC}"
    tar -czf "${FINAL_BACKUP_NAME}" -C "${TMP_DIR}" .
    chmod 600 "${FINAL_BACKUP_NAME}"

    # 6. 清理并重启老服务
    rm -rf "${TMP_DIR}"
    echo -e "${YELLOW}▶️ 正在恢复旧机器服务...${NC}"
    docker compose start

    echo -e "${GREEN}✅ 备份圆满完成！${NC}"
    echo -e "🎉 最终备份包已生成在当前目录: ${YELLOW}${FINAL_BACKUP_NAME}${NC}"
}

do_restore() {
    BACKUP_FILE=$1
    LOCAL_TIMEZONE=""

    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}❌ 错误: 找不到指定的备份文件 [${BACKUP_FILE}]！${NC}"
        exit 1
    fi

    echo -e "${GREEN}🚀 开始执行 n8n 全量恢复流程 (V4)...${NC}"

    if [ -f ".env" ]; then
        LOCAL_TIMEZONE=$(sed -n 's/^GENERIC_TIMEZONE=//p' .env | tail -n 1)
    fi

    TMP_DIR="/tmp/n8n_migration_restore"
    mkdir -p "${TMP_DIR}"
    tar -xzf "${BACKUP_FILE}" -C "${TMP_DIR}"

    # 1. 恢复秘密配置；保留目标机器上已经过适配的 Compose 配置
    echo -e "${YELLOW}📄 正在恢复配置文件到当前目录...${NC}"
    if [ ! -f "docker-compose.yml" ]; then
        cp "${TMP_DIR}/docker-compose.yml" .
    else
        echo -e "${YELLOW}ℹ️ 保留当前 docker-compose.yml，不使用备份中的旧版本覆盖。${NC}"
    fi
    # 覆盖前先另存本机 .env：其中的 ENCRYPTION_KEY 一旦丢失，本机已有 credential 将永久无法解密
    if [ -f ".env" ]; then
        ENV_BACKUP=".env.bak.${DATE_STR}"
        cp .env "${ENV_BACKUP}"
        chmod 600 "${ENV_BACKUP}"
        echo -e "${YELLOW}🔐 已将本机原有 .env 另存为 ${ENV_BACKUP}${NC}"
    fi
    cp "${TMP_DIR}/.env" .
    chmod 600 .env

    if [[ "${LOCAL_TIMEZONE}" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$ ]]; then
        sed -i "s|^GENERIC_TIMEZONE=.*$|GENERIC_TIMEZONE=${LOCAL_TIMEZONE}|" .env
    fi

    # 重新加载刚解压出来的 .env 文件以获取密码
    load_env

    # 2. 还原加密密钥卷
    echo -e "${YELLOW}🔑 正在还原加密密钥卷...${NC}"
    docker volume create "${VOLUME_NAME}" > /dev/null
    docker run --rm -v ${VOLUME_NAME}:/target -v ${TMP_DIR}:/backup alpine sh -c "cd /target && tar -xzf /backup/volume_data.tar.gz"

    # 3. 优先启动基础设施
    echo -e "${YELLOW}⏳ 正在启动基础设施 (Postgres & Redis) 并等待初始化...${NC}"
    docker compose up -d postgres redis
    
    echo "等待 15 秒让数据库完全启动..."
    sleep 15

    # 4. 导入数据库
    echo -e "${YELLOW}🗄️ 正在导入 Postgres 数据库...${NC}"
    docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" ${DB_CONTAINER} pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-$POSTGRES_USER}" --clean --if-exists < "${TMP_DIR}/n8n_db.dump"

    # 清理临时文件
    rm -rf "${TMP_DIR}"

    # 5. 全面启动
    echo -e "${GREEN}▶️ 数据库导入完毕！正在全面启动 n8n 服务...${NC}"
    docker compose up -d

    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}🎉 恭喜！完美的 1:1 恢复已完成。${NC}"
    echo -e "${GREEN}====================================================${NC}"
}

case "$1" in
    backup)
        do_backup
        ;;
    restore)
        do_restore "$2"
        ;;
    *)
        show_help
        exit 1
        ;;
esac
