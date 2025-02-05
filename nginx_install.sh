#!/bin/bash
#====================================================
#    Nginx 编译安装脚本
#    支持模块：
#      - HTTP/HTTPS（ssl、sub、gzip_static、stub_status）
#      - pcre、realip、flv、mp4、secure_link
#      - HTTP/2、DAV（含 nginx-dav-ext-module）
#      - stream 和 stream_ssl 模块
#    同时使用 jemalloc 优化内存分配
#====================================================

# 设置版本变量
nginx_version="1.20.1"
openssl_version="1.1.1k"
jemalloc_version="5.2.1"
nginx_dir="/etc/nginx"
nginx_openssl_src="/usr/local/src"
THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请以root用户执行此脚本！"
    exit 1
fi

# 安装依赖（以 apt 为例，CentOS请自行修改为 yum）
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y build-essential wget git libpcre3 libpcre3-dev zlib1g-dev libssl-dev libxml2 libxml2-dev libxslt1-dev
else
    yum install -y gcc make wget git pcre pcre-devel zlib-devel openssl-devel
fi

# 下载源码存放目录
mkdir -p ${nginx_openssl_src}
cd ${nginx_openssl_src} || exit

# 下载 Nginx 源码
if [ ! -f "nginx-${nginx_version}.tar.gz" ]; then
    wget --no-check-certificate http://nginx.org/download/nginx-${nginx_version}.tar.gz
fi
tar -zxvf nginx-${nginx_version}.tar.gz

# 下载 OpenSSL 源码
if [ ! -f "openssl-${openssl_version}.tar.gz" ]; then
    wget --no-check-certificate https://www.openssl.org/source/openssl-${openssl_version}.tar.gz
fi
tar -zxvf openssl-${openssl_version}.tar.gz

# 下载 jemalloc 源码
if [ ! -f "jemalloc-${jemalloc_version}.tar.bz2" ]; then
    wget --no-check-certificate https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_version}/jemalloc-${jemalloc_version}.tar.bz2
fi
tar -xvf jemalloc-${jemalloc_version}.tar.bz2

# 克隆 nginx-dav-ext-module
if [ -d "/root/nginx-dav-ext-module" ]; then
    rm -rf /root/nginx-dav-ext-module
fi
git clone https://github.com/arut/nginx-dav-ext-module.git /root/nginx-dav-ext-module

# 编译安装 jemalloc
cd jemalloc-${jemalloc_version} || exit
./configure
make -j "${THREAD}" && make install
if [ $? -ne 0 ]; then
    echo "jemalloc 编译安装失败！"
    exit 1
fi
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
    --with-http_dav_module --add-module=/root/nginx-dav-ext-module \
    --with-stream \
    --with-stream_ssl_module \
    --with-cc-opt='-O3' \
    --with-ld-opt="-ljemalloc" \
    --with-openssl=../openssl-${openssl_version}

if [ $? -ne 0 ]; then
    echo "Nginx 配置检测失败！"
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
    sed -i 's/worker_processes  1;/worker_processes  3;/' "${conf_file}"
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' "${conf_file}"
    # 引入 conf.d 目录（如果需要）
    echo "include conf.d/*.conf;" >> "${conf_file}"
fi

# 清理源码（可选）
rm -rf ${nginx_openssl_src}/nginx-${nginx_version}
rm -rf ${nginx_openssl_src}/openssl-${openssl_version}
rm -rf ${nginx_openssl_src}/nginx-${nginx_version}.tar.gz
rm -rf ${nginx_openssl_src}/openssl-${openssl_version}.tar.gz

echo "Nginx 编译安装完成，安装路径：${nginx_dir}"

# （可选）设置 systemd 管理 Nginx 服务
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
