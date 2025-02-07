#!/bin/bash
#====================================================
#    Nginx 1.26.3 编译安装脚本 (Ubuntu 20.04)
#    保留原有模块，并新增：
#      - HTTP/3 + QUIC（用于代理）
#      - gRPC（代理 gRPC 流量）
#      - Brotli（更高效的压缩）
#      - Cache Purge（代理缓存清理）
#      - jemalloc 内存优化
#====================================================

# 版本变量
nginx_version="1.26.3"
openssl_version="3.2.0"
jemalloc_version="5.3.0"
nginx_dir="/etc/nginx"
nginx_src_dir="/usr/local/src"
THREAD=$(nproc)

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户执行此脚本！"
    exit 1
fi

# 安装依赖
apt update
apt install -y build-essential wget git libpcre3 libpcre3-dev zlib1g-dev libssl-dev \
               libxml2 libxml2-dev libxslt1-dev libgd-dev curl gnupg2 unzip

# 下载源码存放目录
mkdir -p ${nginx_src_dir}
cd ${nginx_src_dir} || exit

# 下载 Nginx 源码
if [ ! -f "nginx-${nginx_version}.tar.gz" ]; then
    wget --no-check-certificate http://nginx.org/download/nginx-${nginx_version}.tar.gz
fi
tar -zxvf nginx-${nginx_version}.tar.gz

# 下载 OpenSSL 源码（支持 HTTP/3、TLS 1.3）
if [ ! -f "openssl-${openssl_version}.tar.gz" ]; then
    wget --no-check-certificate https://www.openssl.org/source/openssl-${openssl_version}.tar.gz
fi
tar -zxvf openssl-${openssl_version}.tar.gz

# 下载 jemalloc 源码（优化内存管理）
if [ ! -f "jemalloc-${jemalloc_version}.tar.bz2" ]; then
    wget --no-check-certificate https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_version}/jemalloc-${jemalloc_version}.tar.bz2
fi
tar -xvf jemalloc-${jemalloc_version}.tar.bz2

# 克隆 nginx-dav-ext-module（WebDAV 扩展）
if [ -d "/root/nginx-dav-ext-module" ]; then
    rm -rf /root/nginx-dav-ext-module
fi
git clone https://github.com/arut/nginx-dav-ext-module.git /root/nginx-dav-ext-module

# 下载 Brotli 模块（更好的压缩）
if [ ! -d "ngx_brotli" ]; then
    git clone --recursive https://github.com/google/ngx_brotli.git
fi

# 下载 ngx_cache_purge（缓存清理）
if [ ! -d "ngx_cache_purge" ]; then
    git clone https://github.com/FRiCKLE/ngx_cache_purge.git
fi

# 编译安装 jemalloc
cd jemalloc-${jemalloc_version} || exit
./configure
make -j "${THREAD}" && make install
echo '/usr/local/lib' >/etc/ld.so.conf.d/local.conf
ldconfig

# 编译安装 Nginx
cd ../nginx-${nginx_version} || exit

./configure --prefix="${nginx_dir}" \
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
    --with-http_grpc_module \
    --with-threads \
    --with-file-aio \
    --with-http_quic_module \
    --add-module=../ngx_brotli \
    --add-module=../ngx_cache_purge \
    --with-cc-opt='-O3' \
    --with-ld-opt="-ljemalloc" \
    --with-openssl=../openssl-${openssl_version}

if [ $? -ne 0 ]; then
    echo "Nginx 配置失败！"
    exit 1
fi

make -j "${THREAD}" && make install
if [ $? -ne 0 ]; then
    echo "Nginx 编译安装失败！"
    exit 1
fi

# 修改 Nginx 基本配置
conf_file="${nginx_dir}/conf/nginx.conf"
if [ -f "${conf_file}" ]; then
    sed -i 's/#user  nobody;/user  root;/' "${conf_file}"
    sed -i 's/worker_processes  1;/worker_processes  auto;/' "${conf_file}"
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' "${conf_file}"
    echo "include conf.d/*.conf;" >> "${conf_file}"
fi

# 清理源码（可选）
rm -rf ${nginx_src_dir}/nginx-${nginx_version}
rm -rf ${nginx_src_dir}/openssl-${openssl_version}
rm -rf ${nginx_src_dir}/jemalloc-${jemalloc_version}
rm -rf ${nginx_src_dir}/nginx-${nginx_version}.tar.gz
rm -rf ${nginx_src_dir}/openssl-${openssl_version}.tar.gz

echo "Nginx 1.26.3 编译安装完成，安装路径：${nginx_dir}"

# 设置 systemd 服务
cat > /etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=${nginx_dir}/logs/nginx.pid
ExecStartPre=${nginx_dir}/sbin/nginx -t
ExecStart=${nginx_dir}/sbin/nginx -c ${nginx_dir}/conf/nginx.conf
ExecReload=${nginx_dir}/sbin/nginx -s reload
ExecStop=${nginx_dir}/sbin/nginx -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx

echo "Nginx systemd 服务文件已创建，并设置为开机自启"
