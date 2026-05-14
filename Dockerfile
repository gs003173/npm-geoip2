# 第一阶段：使用官方 Alpine 镜像作为编译车间

FROM alpine AS builder

# 1. 安装官方编译依赖库

RUN apk add --no-cache git bash curl build-base pcre2-dev zlib-dev openssl-dev libmaxminddb-dev

WORKDIR /build

# 2. 拉取 Nginx Proxy Manager 官方最新源码

RUN git clone --depth 1 https://github.com/NginxProxyManager/nginx-proxy-manager.git npm_source

# 3. 自动识别 NPM 官方底层使用的 Nginx 版本号

RUN NGINX_VERSION=$(grep -oP 'ARG NGINX_VERSION=\K.*' npm_source/docker/nginx/Dockerfile) && \

    echo "Found NPM using Nginx version: $NGINX_VERSION" && \

    # 4. 下载完全匹配的官方 Nginx 源码

    wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \

    tar -xzf nginx-${NGINX_VERSION}.tar.gz && \

    # 5. 拉取 GeoIP2 模块的官方源码

    git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git && \

    # 6. 拉取 MaxMind 官方依赖库源码

    git clone --depth 1 https://github.com/maxmind/libmaxminddb.git

# 7. 编译安装官方依赖库

RUN cd libmaxminddb && ./configure && make && make install && ldconfig && cd ..

# 8. 现场编译出完美兼容的 GeoIP2 动态模块

RUN cd nginx-${NGINX_VERSION} && \

    ./configure --with-compat --add-dynamic-module=../ngx_http_geoip2_module && \

    make modules

# --- 第二阶段：将编译好的模块注入到 NPM 官方最新镜像中 ---

FROM jc21/nginx-proxy-manager:latest

# 复制刚才在官方源码基础上编译出的模块

COPY --from=builder /build/nginx-*/objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/

# 安装运行所需的官方运行时库

RUN apk add --no-cache libmaxminddb

