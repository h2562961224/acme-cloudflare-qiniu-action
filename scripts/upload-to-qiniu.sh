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

# 生成证书名称
CERT_NAME="${DOMAIN}-$(date +%Y%m%d)"

# 构建请求数据
REQUEST_DATA=$(jq -n \
    --arg name "$CERT_NAME" \
    --arg cert "$CERT_CONTENT" \
    --arg key "$KEY_CONTENT" \
    '{"name":$name,"common_name":$ENV.DOMAIN,"ca":$cert,"pri":$key}')

# 修复版本的七牛云认证Token生成函数
# 基于七牛云官方Node.js SDK的generateAccessTokenV2实现
# 修复了换行符处理问题
generate_qiniu_token() {
    local method="$1"
    local path="$2"
    local host="$3"
    local content_type="$4"
    local body="$5"
    
    # 方法名转大写
    local upper_method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
    
    # 构建签名字符串 - 使用临时文件确保换行符正确处理
    local temp_file=$(mktemp)
    
    # 写入签名字符串到临时文件，确保换行符正确
    echo -n "${upper_method} ${path}" > "$temp_file"
    echo "" >> "$temp_file"  # 添加换行符
    echo -n "Host: ${host}" >> "$temp_file"
    echo "" >> "$temp_file"  # 添加换行符
    
    # 添加Content-Type
    if [ -n "$content_type" ]; then
        echo -n "Content-Type: ${content_type}" >> "$temp_file"
    else
        echo -n "Content-Type: application/x-www-form-urlencoded" >> "$temp_file"
    fi
    echo "" >> "$temp_file"  # 添加换行符
    echo "" >> "$temp_file"  # 添加空行
    
    # 添加请求体（仅当不是application/octet-stream时）
    if [ -n "$body" ] && [ "$content_type" != "application/octet-stream" ]; then
        echo -n "$body" >> "$temp_file"
    fi
    
    # 读取文件内容用于调试
    local access_content=$(cat "$temp_file")
    local access_length=$(wc -c < "$temp_file")
    
    echo "[DEBUG] 修复版签名字符串长度: $access_length" >&2
    echo "[DEBUG] 修复版签名字符串内容:" >&2
    cat "$temp_file" | sed 's/$/\\n/g' | tr -d '\n' | sed 's/\\n$//' >&2
    echo "" >&2
    
    # 使用文件内容生成签名
    local signature=$(cat "$temp_file" | openssl dgst -sha1 -hmac "$QINIU_SECRET_KEY" -binary | base64)
    
    # 清理临时文件
    rm -f "$temp_file"
    
    # URL安全的Base64编码转换 - 只转换+/为-_，保留=
    local safe_signature=$(echo "$signature" | tr '+/' '-_')
    
    # 生成Qiniu格式的token
    local token="Qiniu ${QINIU_ACCESS_KEY}:${safe_signature}"
    
    echo "[DEBUG] 修复版原始签名: $signature" >&2
    echo "[DEBUG] 修复版URL安全签名: $safe_signature" >&2
    echo "[DEBUG] 修复版生成的Token: $token" >&2
    
    echo "$token"
}

# 上传证书到七牛云
echo "正在上传证书..."

# 生成上传证书的认证token
TOKEN=$(generate_qiniu_token "POST" "/sslcert" "api.qiniu.com" "application/json" "$REQUEST_DATA")

echo "[DEBUG] 请求数据: $REQUEST_DATA" >&2
echo "[DEBUG] 使用Token: $TOKEN" >&2

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Host: api.qiniu.com" \
    -d "$REQUEST_DATA" \
    "https://api.qiniu.com/sslcert")

echo "上传响应: $RESPONSE"

# 提取HTTP状态码
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo "HTTP状态码: $HTTP_CODE"
echo "响应体: $RESPONSE_BODY"

# 检查HTTP状态码
if [ "$HTTP_CODE" != "200" ]; then
    echo "证书上传失败，HTTP状态码: $HTTP_CODE"
    echo "错误信息: $RESPONSE_BODY"
    exit 1
fi

# 检查上传结果
if echo "$RESPONSE_BODY" | jq -e '.certID' > /dev/null 2>&1; then
    CERT_ID=$(echo "$RESPONSE_BODY" | jq -r '.certID')
    echo "证书上传成功，证书ID: $CERT_ID"
    
    # 配置域名使用新证书
    echo "正在为域名 $DOMAIN 配置证书..."
    
    DOMAIN_CONFIG_DATA=$(jq -n \
        --arg certId "$CERT_ID" \
        '{"certId":$certId,"forceHttps":true}')
    
    # 生成域名配置的认证token
    DOMAIN_TOKEN=$(generate_qiniu_token "PUT" "/domain/${DOMAIN}/httpsconf" "api.qiniu.com" "application/json" "$DOMAIN_CONFIG_DATA")
    
    echo "[DEBUG] 域名配置数据: $DOMAIN_CONFIG_DATA" >&2
    echo "[DEBUG] 域名配置Token: $DOMAIN_TOKEN" >&2
    
    DOMAIN_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT \
        -H "Authorization: $DOMAIN_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Host: api.qiniu.com" \
        -d "$DOMAIN_CONFIG_DATA" \
        "https://api.qiniu.com/domain/${DOMAIN}/httpsconf")
    
    echo "域名配置响应: $DOMAIN_RESPONSE"
    
    # 提取域名配置的HTTP状态码
    DOMAIN_HTTP_CODE=$(echo "$DOMAIN_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    DOMAIN_RESPONSE_BODY=$(echo "$DOMAIN_RESPONSE" | sed '/HTTP_CODE:/d')
    
    echo "域名配置HTTP状态码: $DOMAIN_HTTP_CODE"
    echo "域名配置响应体: $DOMAIN_RESPONSE_BODY"
    
    if [ "$DOMAIN_HTTP_CODE" != "200" ]; then
        echo "域名证书配置失败，HTTP状态码: $DOMAIN_HTTP_CODE"
        echo "错误信息: $DOMAIN_RESPONSE_BODY"
        exit 1
    else
        echo "域名证书配置成功"
    fi
else
    echo "证书上传失败"
    echo "错误信息: $RESPONSE_BODY"
    exit 1
fi

echo "证书上传和配置完成"