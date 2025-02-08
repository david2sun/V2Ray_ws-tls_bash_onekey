#!/bin/bash

# 设置安装路径
NGINX_VERSION="1.26.3"
INSTALL_DIR="/usr/local/nginx"
SRC_DIR="/usr/local/src/nginx"
PCRE_VERSION="8.45"
ZLIB_VERSION="1.3"
OPENSSL_VERSION="3.0.8"

# 更新系统并安装编译工具
echo "更新系统并安装依赖库..."
sudo apt update -y && sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev wget unzip curl

# 创建源码目录
mkdir -p ${SRC_DIR} && cd ${SRC_DIR}

# 下载必要的库
echo "下载 PCRE ${PCRE_VERSION}..."
wget -qO- https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz | tar xz
echo "下载 Zlib ${ZLIB_VERSION}..."
wget -qO- https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz | tar xz
echo "下载 OpenSSL ${OPENSSL_VERSION}..."
wget -qO- https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xz

# 下载并解压 Nginx 源码
echo "下载 Nginx ${NGINX_VERSION}..."
wget -qO- https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz

# 进入 Nginx 目录
cd nginx-${NGINX_VERSION}

# 下载 WebDAV 扩展模块 (ngx_http_dav_ext_module)
echo "下载 WebDAV 扩展模块..."
git clone https://github.com/arut/nginx-dav-ext-module.git ${SRC_DIR}/nginx-dav-ext-module

# 配置编译参数
echo "配置 Nginx 编译参数..."
./configure --prefix=${INSTALL_DIR} \
            --sbin-path=/usr/sbin/nginx \
            --conf-path=/etc/nginx/nginx.conf \
            --pid-path=/var/run/nginx.pid \
            --lock-path=/var/run/nginx.lock \
            --with-http_ssl_module \
            --with-http_v2_module \
            --with-http_dav_module \
            --add-module=${SRC_DIR}/nginx-dav-ext-module \
            --with-http_gzip_static_module \
            --with-http_sub_module \
            --with-http_stub_status_module \
            --with-http_realip_module \
            --with-http_addition_module \
            --with-http_geoip_module \
            --with-http_secure_link_module \
            --with-http_gunzip_module \
            --with-http_auth_request_module \
            --with-threads \
            --with-stream \
            --with-stream_ssl_module \
            --with-stream_ssl_preread_module \
            --with-http_slice_module \
            --with-pcre=${SRC_DIR}/pcre-${PCRE_VERSION} \
            --with-zlib=${SRC_DIR}/zlib-${ZLIB_VERSION} \
            --with-openssl=${SRC_DIR}/openssl-${OPENSSL_VERSION} \
            --with-openssl-opt="enable-tls1_3" \
            --with-cc-opt="-O2 -fstack-protector-strong -Wformat -Werror=format-security" \
            --with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro"

# 编译安装
echo "编译 Nginx..."
make -j$(nproc)
echo "安装 Nginx..."
sudo make install

# 创建 Nginx systemd 服务
echo "配置 Nginx systemd 服务..."
cat <<EOF | sudo tee /etc/systemd/system/nginx.service
[Unit]
Description=Nginx - high-performance web server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$(cat /var/run/nginx.pid)
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 并启动 Nginx
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx

# 检查 Nginx 版本
echo "Nginx 安装完成，当前版本："
nginx -v

echo "Nginx 1.26.3 编译安装完成，WebDAV 模块已启用！"
