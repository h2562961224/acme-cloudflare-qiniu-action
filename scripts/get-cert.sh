#!/bin/bash

# SSL证书获取脚本
# 使用acme.sh从Let's Encrypt获取证书，通过Cloudflare DNS验证

set -e

# 检查必要的环境变量
if [ -z "$CLOUDFLARE_EMAIL" ] || [ -z "$CLOUDFLARE_API_KEY" ] || [ -z "$DOMAIN" ]; then
    echo "错误: 缺少必要的环境变量"
    echo "需要设置: CLOUDFLARE_EMAIL, CLOUDFLARE_API_KEY, DOMAIN"
    exit 1
fi

echo "开始为域名 $DOMAIN 获取SSL证书..."

# 设置acme.sh环境变量
export CF_Email="$CLOUDFLARE_EMAIL"
export CF_Key="$CLOUDFLARE_API_KEY"

# 设置默认CA为Let's Encrypt
~/.acme.sh --set-default-ca --server letsencrypt

# 使用acme.sh获取证书
~/.acme.sh/acme.sh --issue \
    --dns dns_cf \
    -d "$DOMAIN" \
    --force

# 检查证书是否成功获取
if [ $? -eq 0 ]; then
    echo "证书获取成功"
    
    # 复制证书文件到临时目录
    cp ~/.acme.sh/${DOMAIN}_ecc/$DOMAIN.cer /tmp/cert.pem
    cp ~/.acme.sh/${DOMAIN}_ecc/$DOMAIN.key /tmp/key.pem
    cp ~/.acme.sh/${DOMAIN}_ecc/fullchain.cer /tmp/fullchain.pem
    
    echo "证书文件已准备就绪:"
    echo "- 证书: /tmp/cert.pem"
    echo "- 私钥: /tmp/key.pem"
    echo "- 完整链: /tmp/fullchain.pem"
    
    # 显示证书信息
    echo "证书详细信息:"
    openssl x509 -in /tmp/cert.pem -text -noout | grep -E "Subject:|Not Before|Not After|DNS:"
else
    echo "证书获取失败"
    exit 1
fi

echo "证书获取脚本执行完成"