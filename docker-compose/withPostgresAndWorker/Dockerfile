# --- 第一阶段：寻宝者 ---
FROM alpine:3.20 AS fetcher
RUN apk update && apk fetch apk-tools-static
RUN tar -xzf apk-tools-static-*.apk

# --- 第二阶段：组装 Runner ---
# N8N_VERSION must match the main n8n image (passed via build.args from compose).
# Default '2' mirrors compose's ${N8N_VERSION:-2}: pin in .env when you
# want a specific tag, otherwise track upstream major version 2.
ARG N8N_VERSION=2
FROM n8nio/runners:${N8N_VERSION}

USER root

# 1. 复制静态 apk
COPY --from=fetcher sbin/apk.static /sbin/apk

# 2. 安装编译环境
RUN mkdir -p /var/cache/apk && \
    /sbin/apk update && \
    /sbin/apk add --no-cache \
    build-base \
    jpeg-dev \
    zlib-dev \
    libxml2-dev \
    libxslt-dev \
    linux-headers \
    python3-dev

# 3. 安装 Python 库 (去除了 aliyun 配置，使用官方源)
RUN pip install --no-cache-dir \
    requests \
    pandas \
    numpy \
    openpyxl \
    beautifulsoup4 \
    lxml \
    html2text \
    openai \
    tiktoken \
    youtube-transcript-api \
    Pillow \
    python-dateutil \
    pytz

# 4. 【修改点】切回 UID 1000
# 使用 ID 而不是名字，规避 "unable to find user" 错误
USER 1000