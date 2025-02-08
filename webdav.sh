#!/bin/bash

# 获取用户输入的端口、域名和用户名
read -p "请输入端口号: " port
read -p "请输入域名: " domain
read -p "请输入用户名: " username

# 创建WebDAV目录并设置权限
sudo mkdir -p /var/www/webdav
sudo chown -R www-data:www-data /var/www/webdav
sudo chmod -R 775 /var/www/webdav

# 生成Nginx配置文件
cat <<EOF | sudo tee /etc/nginx/conf/conf.d/webdav.conf   
server {
    listen $port ssl http2;
    listen [::]:$port ssl http2;
    server_name $domain;
    ssl_certificate        /data/v2ray.crt;
    ssl_certificate_key    /data/v2ray.key;
    ssl_protocols         TLSv1.2 TLSv1.3;
    ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:le_nginx_SSL:10m;
    ssl_session_timeout 1440m;
    add_header Strict-Transport-Security "max-age=31536000";
    charset utf-8;
       
    root /var/www/webdav;
    autoindex on;
    client_max_body_size 0;
    dav_methods PUT DELETE MKCOL COPY MOVE;
    dav_ext_methods PROPFIND OPTIONS;
    dav_access user:rw  group:r all:r;
    auth_basic "Restricted";              
    auth_basic_user_file /etc/nginx/webdav.passwd;  
}
EOF

# 创建密码文件并添加用户
sudo sh -c "echo -n '$username:' >> /etc/nginx/webdav.passwd"

echo "请为用户$username设置密码:"
sudo sh -c "openssl passwd -apr1 >> /etc/nginx/webdav.passwd"

# 重启或重新加载Nginx服务
sudo nginx -t && sudo systemctl reload nginx

