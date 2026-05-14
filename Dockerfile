# 第一阶段：编译车间
FROM alpine AS builder

# 安装官方编译依赖库 (增加了 tar 用于解压)
RUN apk add --no-cache git bash curl build-base pcre2-dev zlib-dev openssl-dev libmaxminddb-dev tar

WORKDIR /build

# 主动指定一个稳定的主流 Nginx 版本号
ENV NGINX_VERSION=1.25.5

# 1. 下载官方 Nginx 源码
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xzf nginx-${NGINX_VERSION}.tar.gz && \
    # 2. 拉取 GeoIP2 模块源码
    git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git && \
    # 3. 【核心修复】改为下载带有 configure 脚本的官方发行版压缩包
    wget https://github.com/maxmind/libmaxminddb/releases/download/1.12.2/libmaxminddb-1.12.2.tar.gz && \
    tar -xzf libmaxminddb-1.12.2.tar.gz

# 编译安装 MaxMind 依赖库 (进入解压后的带版本号的目录)
RUN cd libmaxminddb-1.12.2 && ./configure && make && make install && ldconfig && cd ..

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

# 将刚才编译好的 GeoIP2 动态模块复制进来
COPY --from=builder /build/nginx-*/objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/

# 将完整的 Nginx 模块和 NPM 业务目录打包成离线压缩包
RUN tar -czvf /npm-geoip2-offline.tar.gz /usr/lib/nginx/modules/ngx_http_geoip2_module.so /app

# 第二阶段：打包最终成品
FROM alpine

# 安装运行所需的官方基础库（Nginx 和 MaxMind 运行时库）
RUN apk add --no-cache libmaxminddb nginx

# 从 NPM 官方镜像中提取出 NPM 的核心业务文件（前端和后端程序）
COPY --from=jc21/nginx-proxy-manager:latest /app /app

# 将刚才编译好的 GeoIP2 动态模块复制进来
COPY --from=builder /build/nginx-*/objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/

# 将完整的 Nginx 模块和 NPM 业务目录打包成离线压缩包
RUN tar -czvf /npm-geoip2-offline.tar.gz /usr/lib/nginx/modules/ngx_http_geoip2_module.so /app
