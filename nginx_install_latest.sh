#!/bin/bash
#====================================================
#    Nginx 1.26.3 编译安装脚本
#    支持模块：
#      - HTTP/HTTPS（SSL、sub、gzip_static、stub_status）
#      - pcre、realip、flv、mp4、secure_link
#      - HTTP/2、DAV（含 nginx-dav-ext-module）
#      - stream 和 stream_ssl 模块
#      - jemalloc 内存优化
#====================================================

# 设置版本变量
NGINX_VERSION="1.26.3"
OPENSSL_VERSION="3.0.8"
JEMALLOC_VERSION="5.3.0"
INSTALL_DIR="/etc/nginx"
SOURCE_DIR="/usr/local/src"
THREAD=$(grep -c ^processor /proc/cpuinfo)

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户执行此脚本！"
    exit 1
fi

# 安装依赖（适用于 Debian/Ubuntu，CentOS 需使用 yum）
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y build-essential wget git libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev \
                       libxml2 libxml2-dev libxslt1-dev
else
    yum install -y gcc make wget git pcre pcre-devel zlib-devel openssl-devel
fi

# 创建源码存放目录
mkdir -p ${SOURCE_DIR}
cd ${SOURCE_DIR} || exit

# 下载 Nginx 源码
if [ ! -f "nginx-${NGINX_VERSION}.tar.gz" ]; then
    wget --no-check-certificate https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
fi
tar -zxvf nginx-${NGINX_VERSION}.tar.gz

# 下载 OpenSSL 源码
if [ ! -f "openssl-${OPENSSL_VERSION}.tar.gz" ]; then
    wget --no-check-certificate https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
fi
tar -zxvf openssl-${OPENSSL_VERSION}.tar.gz

# 下载 jemalloc 源码
if [ ! -f "jemalloc-${JEMALLOC_VERSION}.tar.bz2" ]; then
    wget --no-check-certificate https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2
fi
tar -xvf jemalloc-${JEMALLOC_VERSION}.tar.bz2

# 克隆 nginx-dav-ext-module
if [ -d "/root/nginx-dav-ext-module" ]; then
    rm -rf /root/nginx-dav-ext-module
fi
git clone https://github.com/arut/nginx-dav-ext-module.git /root/nginx-dav-ext-module

# 编译安装 jemalloc
cd jemalloc-${JEMALLOC_VERSION} || exit
./configure
make -j "${THREAD}" && make install
if [ $? -ne 0 ]; then
    echo "jemalloc 编译安装失败！"
    exit 1
fi
echo '/usr/local/lib' > /etc/ld.so.conf.d/local.conf
ldconfig

# 编译安装 Nginx
cd ../nginx-${NGINX_VERSION} || exit

./configure --prefix="${INSTALL_DIR}" \
    --with-http_ssl_module \
    --with-http_sub_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-pcre \
    --with-http_realip_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_secure_link_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_dav_module --add-module=/root/nginx-dav-ext-module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-cc-opt='-O3' \
    --with-ld-opt="-ljemalloc" \
    --with-openssl=../openssl-${OPENSSL_VERSION}

if [ $? -ne 0 ]; then
    echo "Nginx 配置失败！"
    exit 1
fi

make -j "${THREAD}" && make install
if [ $? -ne 0 ]; then
    echo "Nginx 编译安装失败！"
    exit 1
fi

# 添加 Nginx 到环境变量
ln -sf ${INSTALL_DIR}/sbin/nginx /usr/bin/nginx

# 修改 Nginx 配置（基本优化）
CONF_FILE="/etc/nginx/conf/nginx.conf"
if [ -f "${CONF_FILE}" ]; then
    sed -i 's/#user  nobody;/user  root;/' ${CONF_FILE}
    sed -i 's/worker_processes  1;/worker_processes  3;/' ${CONF_FILE}
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' ${CONF_FILE}
    sed -i '$i include conf.d/*.conf;' $CONF_FILE
fi

# 清理源码（可选）
rm -rf ${SOURCE_DIR}/nginx-${NGINX_VERSION}
rm -rf ${SOURCE_DIR}/openssl-${OPENSSL_VERSION}
rm -rf ${SOURCE_DIR}/nginx-${NGINX_VERSION}.tar.gz
rm -rf ${SOURCE_DIR}/openssl-${OPENSSL_VERSION}.tar.gz

echo "Nginx 1.26.3 编译安装完成，安装路径：${INSTALL_DIR}"

# 创建 systemd 服务
cat > /etc/systemd/system/nginx.service <<EOF
[Unit]
Description=Nginx - high-performance web server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/bin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/bin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/bin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$(cat /var/run/nginx.pid)
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 并启动 Nginx
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

echo "Nginx systemd 服务已创建，并设置为开机自启"

# 检查 Nginx 版本
nginx -v
