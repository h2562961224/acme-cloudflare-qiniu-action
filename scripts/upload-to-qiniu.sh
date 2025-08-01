#!/bin/bash

# 七牛云证书上传脚本
# 将SSL证书上传到七牛云并配置域名

set -e

# 检查必要的环境变量
if [ -z "$QINIU_ACCESS_KEY" ] || [ -z "$QINIU_SECRET_KEY" ] || [ -z "$DOMAIN" ]; then
    echo "错误: 缺少必要的环境变量"
    echo "需要设置: QINIU_ACCESS_KEY, QINIU_SECRET_KEY, DOMAIN"
    exit 1
fi

# 检查证书文件是否存在
if [ ! -f "/tmp/cert.pem" ] || [ ! -f "/tmp/key.pem" ]; then
    echo "错误: 证书文件不存在"
    echo "请先运行 get-cert.sh 获取证书"
    exit 1
fi

echo "开始上传证书到七牛云..."

# 安装必要的工具
if ! command -v curl &> /dev/null; then
    echo "安装curl..."
    apt-get update && apt-get install -y curl
fi

if ! command -v jq &> /dev/null; then
    echo "安装jq..."
    apt-get update && apt-get install -y jq
fi

# 读取证书内容
CERT_CONTENT=$(cat /tmp/cert.pem)
KEY_CONTENT=$(cat /tmp/key.pem)

# 生成时间戳
TIMESTAMP=$(date +%s)

# 生成证书名称
CERT_NAME="${DOMAIN}-$(date +%Y%m%d)"

# 构建请求数据
REQUEST_DATA=$(jq -n \
    --arg name "$CERT_NAME" \
    --arg cert "$CERT_CONTENT" \
    --arg key "$KEY_CONTENT" \
    '{
        "name": $name,
        "common_name": $ENV.DOMAIN,
        "cert": $cert,
        "pri": $key
    }')

# 生成签名函数
generate_qiniu_token() {
    local method="$1"
    local path="$2"
    local body="$3"
    local content_type="application/json"
    
    # 构建签名字符串
    local sign_str="${method} ${path}\nHost: api.qiniu.com\nContent-Type: ${content_type}\n\n${body}"
    
    # 生成签名
    local encoded_sign=$(echo -n "$sign_str" | openssl dgst -sha1 -hmac "$QINIU_SECRET_KEY" -binary | base64)
    
    # 生成token
    echo "Qiniu ${QINIU_ACCESS_KEY}:${encoded_sign}"
}

# 上传证书到七牛云
echo "正在上传证书..."

TOKEN=$(generate_qiniu_token "POST" "/sslcert" "$REQUEST_DATA")

RESPONSE=$(curl -s -X POST \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_DATA" \
    "https://api.qiniu.com/sslcert")

echo "上传响应: $RESPONSE"

# 检查上传结果
if echo "$RESPONSE" | jq -e '.certID' > /dev/null; then
    CERT_ID=$(echo "$RESPONSE" | jq -r '.certID')
    echo "证书上传成功，证书ID: $CERT_ID"
    
    # 配置域名使用新证书
    echo "正在为域名 $DOMAIN 配置证书..."
    
    DOMAIN_CONFIG_DATA=$(jq -n \
        --arg certId "$CERT_ID" \
        --arg domain "$DOMAIN" \
        '{
            "certId": $certId,
            "forceHttps": true
        }')
    
    DOMAIN_TOKEN=$(generate_qiniu_token "PUT" "/domain/${DOMAIN}/sslize" "$DOMAIN_CONFIG_DATA")
    
    DOMAIN_RESPONSE=$(curl -s -X PUT \
        -H "Authorization: $DOMAIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$DOMAIN_CONFIG_DATA" \
        "https://api.qiniu.com/domain/${DOMAIN}/sslize")
    
    echo "域名配置响应: $DOMAIN_RESPONSE"
    
    if echo "$DOMAIN_RESPONSE" | jq -e '.error' > /dev/null; then
        echo "域名证书配置失败"
        exit 1
    else
        echo "域名证书配置成功"
    fi
else
    echo "证书上传失败"
    echo "错误信息: $RESPONSE"
    exit 1
fi

echo "证书上传和配置完成"