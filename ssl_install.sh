#!/bin/bash
# 检查是否已安装 acme.sh，如果没有，则安装
if ! command -v ~/.acme.sh/acme.sh &> /dev/null
then
    echo "acme.sh 未安装，正在安装..."
    curl https://get.acme.sh | sh
    # 加载 acme.sh 的环境变量
    . "$HOME/.acme.sh/acme.sh.env"
else
    echo "acme.sh 已安装"
fi

# 询问用户输入域名
read -p "请输入您的域名: " DOMAIN

# 设置默认的 webroot 路径
DEFAULT_WEBROOT="/var/www/html"

# 询问用户输入 webroot 路径，允许直接回车选择默认路径
read -p "请输入您的 webroot 路径 (直接回车将使用默认路径 $DEFAULT_WEBROOT): " WEBROOT
WEBROOT=${WEBROOT:-$DEFAULT_WEBROOT}

# 检查 webroot 路径是否存在
while [[ ! -d "$WEBROOT" ]]; do
    echo "指定的 webroot 路径不存在"
    read -p "是否要创建此路径? (y/n): " yn
    case $yn in
        [Yy]* ) mkdir -p "$WEBROOT"; echo "已创建路径: $WEBROOT"; break;;
        [Nn]* ) 
            read -p "请重新输入 webroot 路径 (直接回车将使用默认路径 $DEFAULT_WEBROOT): " WEBROOT
            WEBROOT=${WEBROOT:-$DEFAULT_WEBROOT};;
        * ) echo "请输入 'y' 或 'n'。";;
    esac
done

# SSL 证书和密钥的保存路径
SSL_CERT="/etc/nginx/ssl/$DOMAIN/cert.pem"
SSL_KEY="/etc/nginx/ssl/$DOMAIN/key.pem"
SSL_FULLCHAIN="/etc/nginx/ssl/$DOMAIN/fullchain.pem"

# Nginx 配置文件的路径
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"

# 使用 acme.sh 获取证书
"$HOME"/.acme.sh/acme.sh --issue -d $DOMAIN -w $WEBROOT

# 安装证书到指定位置
"$HOME"/.acme.sh/acme.sh --install-cert -d $DOMAIN \
    --cert-file      $SSL_CERT \
    --key-file       $SSL_KEY \
    --fullchain-file $SSL_FULLCHAIN \
    --reloadcmd     "sudo systemctl reload nginx"

# 更新 Nginx 配置以使用 SSL
cat << EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     $SSL_FULLCHAIN;
    ssl_certificate_key $SSL_KEY;
 
}
EOF

# 重启 Nginx 以应用更改
sudo systemctl reload nginx

echo "SSL 证书安装并配置完成！"
