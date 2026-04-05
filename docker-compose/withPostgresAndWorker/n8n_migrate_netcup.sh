#!/bin/bash

# ==========================================
# n8n 全量迁移自动化脚本 V5 (自动传输到远程服务器)
# ==========================================

# === 核心配置项 ===
VOLUME_NAME="withpostgresandworker_n8n_storage"
DB_CONTAINER="withpostgresandworker-postgres-1"
DATE_STR=$(date +%Y%m%d_%H%M%S)
FINAL_BACKUP_NAME="n8n_full_migration_${DATE_STR}.tar.gz"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
# === 远程传输配置 ===
# 是否开启备份后自动传输 (true/false)
ENABLE_REMOTE_TRANSFER=true
# 你的 SSH 配置中的别名 (例如 ~/.ssh/config 中配置的 Host)
REMOTE_SERVER="netcup"
# 备份文件传输到远程服务器的哪个目录？(建议和本地保持一致)
REMOTE_DIR="~/workspace/n8n-hosting"

# === 颜色显示设置 ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_help() {
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  bash n8n_migrate.sh backup                 - 全量打包并自动传输到 ${REMOTE_SERVER}"
    echo "  bash n8n_migrate.sh restore <备份文件.tar.gz> - 在新服务器上执行恢复"
}

load_env() {
    if [ ! -f ".env" ]; then
        echo -e "${RED}❌ 错误: 当前目录下找不到 .env 文件！${NC}"
        exit 1
    fi
    set -a
    source <(grep -v '^#' .env | sed -e '/^$/d')
    set +a
}

do_backup() {
    echo -e "${GREEN}🚀 开始执行 n8n 全量备份流程 (V5)...${NC}"

    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}❌ 错误: 当前目录下找不到 docker-compose.yml！${NC}"
        exit 1
    fi

    load_env
    
    if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; then
        echo -e "${RED}❌ 错误: .env 文件中未找到 POSTGRES_USER 或 POSTGRES_PASSWORD。${NC}"
        exit 1
    fi

    TMP_DIR="/tmp/n8n_migration_tmp"
    mkdir -p "${TMP_DIR}"

    echo -e "${YELLOW}🗄️ 正在导出 Postgres 数据库...${NC}"
    docker start ${DB_CONTAINER} > /dev/null 2>&1
    docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" ${DB_CONTAINER} pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-$POSTGRES_USER}" -F c > "${TMP_DIR}/n8n_db.dump"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 数据库导出失败！${NC}"
        rm -rf "${TMP_DIR}"
        exit 1
    fi

    echo -e "${YELLOW}⏸️ 正在停止 n8n 服务集群...${NC}"
    docker compose stop

    echo -e "${YELLOW}📄 正在拷贝配置文件...${NC}"
    cp docker-compose.yml "${TMP_DIR}/"
    cp .env "${TMP_DIR}/"

    echo -e "${YELLOW}🔑 正在打包加密密钥卷 [${VOLUME_NAME}]...${NC}"
    docker run --rm -v ${VOLUME_NAME}:/source -v ${TMP_DIR}:/backup alpine tar -czf /backup/volume_data.tar.gz -C /source .

    echo -e "${YELLOW}🗜️ 正在生成最终的迁移压缩包...${NC}"
    tar -czf "${FINAL_BACKUP_NAME}" -C "${TMP_DIR}" .

    rm -rf "${TMP_DIR}"
    
    echo -e "${YELLOW}▶️ 正在恢复本地服务运行...${NC}"
    docker compose start

    echo -e "${GREEN}✅ 本地备份生成完毕: ${FINAL_BACKUP_NAME}${NC}"

    # === 新增：自动传输模块 ===
    if [ "$ENABLE_REMOTE_TRANSFER" = true ]; then
        echo -e "${YELLOW}📤 准备将备份传输至远程服务器 [${REMOTE_SERVER}]...${NC}"
        
        # 1. 确保远程服务器上的目标目录存在 (通过 ssh 执行 mkdir)
        echo -e "   -> 正在检查/创建远程目录: ${REMOTE_DIR}"
        ssh "${REMOTE_SERVER}" "mkdir -p ${REMOTE_DIR}"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 无法连接到远程服务器 ${REMOTE_SERVER} 或创建目录失败。请检查 SSH 配置。${NC}"
        else
            # 2. 执行 SCP 传输
            echo -e "   -> 正在全速传输文件 (可能需要几分钟)..."
            scp "${FINAL_BACKUP_NAME}" "${REMOTE_SERVER}:${REMOTE_DIR}/"
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ 传输成功！文件已安全抵达 ${REMOTE_SERVER}:${REMOTE_DIR}/${FINAL_BACKUP_NAME}${NC}"
                
                # 3. 顺便把脚本自己也传过去，方便你在新机器上直接执行恢复
                scp "$0" "${REMOTE_SERVER}:${REMOTE_DIR}/" > /dev/null 2>&1
                echo -e "   -> (迁移脚本本身也已同步至目标服务器)"
            else
                echo -e "${RED}❌ 传输过程中断，文件可能未完整上传。${NC}"
            fi
        fi
    fi
}

do_restore() {
    BACKUP_FILE=$1

    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}❌ 错误: 找不到指定的备份文件 [${BACKUP_FILE}]！${NC}"
        exit 1
    fi

    echo -e "${GREEN}🚀 开始执行 n8n 全量恢复流程 (V5)...${NC}"

    TMP_DIR="/tmp/n8n_migration_restore"
    mkdir -p "${TMP_DIR}"
    tar -xzf "${BACKUP_FILE}" -C "${TMP_DIR}"

    echo -e "${YELLOW}📄 正在恢复配置文件到当前目录...${NC}"
    cp "${TMP_DIR}/docker-compose.yml" .
    cp "${TMP_DIR}/.env" .

    load_env

    echo -e "${YELLOW}🔑 正在还原加密密钥卷...${NC}"
    docker volume create "${VOLUME_NAME}" > /dev/null
    docker run --rm -v ${VOLUME_NAME}:/target -v ${TMP_DIR}:/backup alpine sh -c "cd /target && tar -xzf /backup/volume_data.tar.gz"

    echo -e "${YELLOW}⏳ 正在启动基础设施 (Postgres & Redis)...${NC}"
    docker compose up -d postgres redis
    
    echo "等待 15 秒让数据库完全启动..."
    sleep 15

    echo -e "${YELLOW}🗄️ 正在导入 Postgres 数据库...${NC}"
    docker exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" ${DB_CONTAINER} pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-$POSTGRES_USER}" --clean --if-exists < "${TMP_DIR}/n8n_db.dump"

    rm -rf "${TMP_DIR}"

    echo -e "${GREEN}▶️ 数据库导入完毕！正在全面启动 n8n 服务...${NC}"
    docker compose up -d

    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}🎉 完美！一切就绪。${NC}"
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
