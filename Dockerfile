# 第一阶段：使用官方 Alpine 镜像作为编译车间
FROM alpine AS builder

# 1. 安装官方编译依赖库 (去掉了不存在的 pcre2-utils)
RUN apk add --no-cache git bash curl build-base pcre2-dev zlib-dev openssl-dev libmaxminddb-dev

WORKDIR /build

# 2. 拉取 Nginx Proxy Manager 官方最新源码
RUN git clone --depth 1 https://github.com/NginxProxyManager/nginx-proxy-manager.git npm_source

# 3. 【核心修复】使用 sed 命令提取 Nginx 版本号 (完美兼容 Alpine 系统)
RUN NGINX_VERSION=$(sed -n 's/.*ARG NGINX_VERSION=\([0-9.]*\).*/\1/p' npm_source/docker/nginx/Dockerfile) && \
    echo "=== 正在编译 Nginx 版本: $NGINX_VERSION ===" && \
    # 4. 下载完全匹配的官方 Nginx 源码
    wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xzf nginx-${NGINX_VERSION}.tar.gz && \
    # 5. 拉取 GeoIP2 模块和 MaxMind 依赖库的官方源码
    git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git && \
    git clone --depth 1 https://github.com/maxmind/libmaxminddb.git

# --- 后续编译步骤保持不变 ---

# 第二阶段：打包最终成品

FROM alpine

# 安装运行所需的官方基础库

RUN apk add --no-cache libmaxminddb nginx

# 从 NPM 官方镜像中提取出 NPM 的核心业务文件（前端和后端程序）

# 这里我们临时借用一下官方镜像，只复制它的业务代码，不直接运行它

COPY --from=jc21/nginx-proxy-manager:latest /app /app

COPY --from=jc21/nginx-proxy-manager:latest /etc/nginx/nginx.conf /etc/nginx/nginx.conf

# 将刚才编译好的 GeoIP2 动态模块复制进来

COPY --from=builder /build/nginx-*/objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/

# 将完整的 Nginx 和 NPM 业务目录打包成离线压缩包，放在根目录下

RUN tar -czvf /npm-geoip2-offline.tar.gz /usr/lib/nginx/modules/ngx_http_geoip2_module.so /app /etc/nginx
