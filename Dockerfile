# 第一阶段：编译车间 (必须用 FROM 开头！)
FROM alpine AS builder

# 安装官方编译依赖库
RUN apk add --no-cache git bash curl build-base pcre2-dev zlib-dev openssl-dev libmaxminddb-dev

# 设置工作目录
WORKDIR /build

# 拉取 Nginx Proxy Manager 官方最新源码
RUN git clone --depth 1 https://github.com/NginxProxyManager/nginx-proxy-manager.git npm_source

# 检查并提取 Nginx 版本号 (已修正为最新路径)
RUN if [ ! -f npm_source/backend/docker/nginx/Dockerfile ]; then \
      echo "错误：找不到 Dockerfile！请检查 NPM 仓库结构是否已变更。"; \
      exit 1; \
    fi && \
    NGINX_VERSION=$(sed -n 's/.*ARG NGINX_VERSION=\([0-9.]*\).*/\1/p' npm_source/backend/docker/nginx/Dockerfile) && \
    echo "=== 正在编译 Nginx 版本: $NGINX_VERSION ===" && \
    # 下载完全匹配的官方 Nginx 源码
    wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xzf nginx-${NGINX_VERSION}.tar.gz && \
    # 拉取 GeoIP2 模块和 MaxMind 依赖库的官方源码
    git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git && \
    git clone --depth 1 https://github.com/maxmind/libmaxminddb.git

# 编译安装 MaxMind 依赖库
RUN cd libmaxminddb && ./configure && make && make install && ldconfig && cd ..

# 现场编译出完美兼容的 GeoIP2 动态模块
RUN cd nginx-${NGINX_VERSION} && \
    ./configure --with-compat --add-dynamic-module=../ngx_http_geoip2_module && \
    make modules

# 第二阶段：打包最终成品
FROM alpine

# 安装运行所需的官方基础库
RUN apk add --no-cache libmaxminddb nginx

# 从 NPM 官方镜像中提取出 NPM 的核心业务文件
COPY --from=jc21/nginx-proxy-manager:latest /app /app
COPY --from=jc21/nginx-proxy-manager:latest /etc/nginx/nginx.conf /etc/nginx/nginx.conf

# 将刚才编译好的 GeoIP2 动态模块复制进来
COPY --from=builder /build/nginx-*/objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/

# 将完整的 Nginx 和 NPM 业务目录打包成离线压缩包，放在根目录下
RUN tar -czvf /npm-geoip2-offline.tar.gz /usr/lib/nginx/modules/ngx_http_geoip2_module.so /app /etc/nginx
