#!/usr/bin/env node

/**
 * 七牛云证书上传脚本 - Node.js版本
 * 使用官方Node.js SDK上传SSL证书到七牛云并配置域名
 * 主要用于调试和与shell版本进行比较
 */

const qiniu = require('qiniu');
const fs = require('fs');
const path = require('path');

// 检查必要的环境变量
if (!process.env.QINIU_ACCESS_KEY || !process.env.QINIU_SECRET_KEY || !process.env.DOMAIN) {
    console.error('错误: 缺少必要的环境变量');
    console.error('需要设置: QINIU_ACCESS_KEY, QINIU_SECRET_KEY, DOMAIN');
    process.exit(1);
}

// 读取证书文件
const certPath = './cert.pem';
const keyPath = './key.pem';

if (!fs.existsSync(certPath) || !fs.existsSync(keyPath)) {
    console.error('错误: 证书文件不存在');
    console.error('请先运行 get-cert.sh 获取证书');
    process.exit(1);
}

console.log('开始使用Node.js SDK上传证书到七牛云...');

// 配置七牛云认证
const accessKey = process.env.QINIU_ACCESS_KEY;
const secretKey = process.env.QINIU_SECRET_KEY;
const domain = process.env.DOMAIN;

const mac = new qiniu.auth.digest.Mac(accessKey, secretKey);
const config = new qiniu.conf.Config();
// 配置区域，这里使用华东区域，可根据实际情况调整
config.zone = qiniu.zone.Zone_z0;

// 读取证书内容
const certContent = fs.readFileSync(certPath, 'utf8');
const keyContent = fs.readFileSync(keyPath, 'utf8');

console.log('[DEBUG] 证书文件读取成功');
console.log('[DEBUG] 证书内容长度:', certContent.length);
console.log('[DEBUG] 私钥内容长度:', keyContent.length);

// 生成证书名称
const certName = `${domain}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
console.log('[DEBUG] 证书名称:', certName);

// 构建请求数据 - 与shell版本保持一致的格式
const requestData = {
    name: certName,
    common_name: domain,
    ca: certContent,
    pri: keyContent
};

console.log('[DEBUG] Node.js版本请求数据:');
console.log(JSON.stringify(requestData, null, 2));

// 生成请求体字符串用于比较
const requestBody = JSON.stringify(requestData);
console.log('[DEBUG] Node.js版本请求体长度:', requestBody.length);
console.log('[DEBUG] Node.js版本请求体内容:');
console.log(requestBody);

// 使用七牛云SDK的内部方法生成签名
const method = 'POST';
const path = '/sslcert';
const host = 'api.qiniu.com';
const contentType = 'application/json';

// 构建签名字符串 - 参考七牛云官方SDK实现
function generateSignString(method, path, host, contentType, body) {
    const upperMethod = method.toUpperCase();
    let signString = `${upperMethod} ${path}\n`;
    signString += `Host: ${host}\n`;
    signString += `Content-Type: ${contentType}\n`;
    signString += '\n';
    
    if (body && contentType !== 'application/octet-stream') {
        signString += body;
    }
    
    return signString;
}

const signString = generateSignString(method, path, host, contentType, requestBody);
console.log('[DEBUG] Node.js版本签名字符串长度:', signString.length);
console.log('[DEBUG] Node.js版本签名字符串内容:');
console.log(signString.replace(/\n/g, '\\n'));

// 生成签名
const crypto = require('crypto');
const hmac = crypto.createHmac('sha1', secretKey);
hmac.update(signString, 'utf8');
const signature = hmac.digest('base64');

// URL安全的Base64编码转换
const safeSignature = signature.replace(/\+/g, '-').replace(/\//g, '_');

// 生成Qiniu格式的token
const token = `Qiniu ${accessKey}:${safeSignature}`;

console.log('[DEBUG] Node.js版本原始签名:', signature);
console.log('[DEBUG] Node.js版本URL安全签名:', safeSignature);
console.log('[DEBUG] Node.js版本生成的Token:', token);

// 使用原生HTTP请求进行上传，以便更好地控制和调试
const https = require('https');
const querystring = require('querystring');

function uploadCertificate() {
    return new Promise((resolve, reject) => {
        const postData = requestBody;
        
        const options = {
            hostname: 'api.qiniu.com',
            port: 443,
            path: '/sslcert',
            method: 'POST',
            headers: {
                'Authorization': token,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
                'Host': 'api.qiniu.com'
            }
        };
        
        console.log('[DEBUG] Node.js版本请求选项:');
        console.log(JSON.stringify(options, null, 2));
        
        const req = https.request(options, (res) => {
            console.log('[DEBUG] Node.js版本响应状态码:', res.statusCode);
            console.log('[DEBUG] Node.js版本响应头:', JSON.stringify(res.headers, null, 2));
            
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                console.log('[DEBUG] Node.js版本响应体:', data);
                
                if (res.statusCode === 200) {
                    try {
                        const result = JSON.parse(data);
                        resolve(result);
                    } catch (e) {
                        reject(new Error(`解析响应失败: ${e.message}`));
                    }
                } else {
                    reject(new Error(`HTTP错误 ${res.statusCode}: ${data}`));
                }
            });
        });
        
        req.on('error', (e) => {
            reject(new Error(`请求错误: ${e.message}`));
        });
        
        req.write(postData);
        req.end();
    });
}

// 配置域名使用新证书
function configureDomainCertificate(certId) {
    return new Promise((resolve, reject) => {
        const domainConfigData = {
            certId: certId,
            forceHttps: true
        };
        
        const configBody = JSON.stringify(domainConfigData);
        console.log('[DEBUG] Node.js版本域名配置数据:', configBody);
        
        // 生成域名配置的签名
        const domainPath = `/domain/${domain}/httpsconf`;
        const domainSignString = generateSignString('PUT', domainPath, host, contentType, configBody);
        
        console.log('[DEBUG] Node.js版本域名配置签名字符串:', domainSignString.replace(/\n/g, '\\n'));
        
        const domainHmac = crypto.createHmac('sha1', secretKey);
        domainHmac.update(domainSignString, 'utf8');
        const domainSignature = domainHmac.digest('base64');
        const domainSafeSignature = domainSignature.replace(/\+/g, '-').replace(/\//g, '_');
        const domainToken = `Qiniu ${accessKey}:${domainSafeSignature}`;
        
        console.log('[DEBUG] Node.js版本域名配置Token:', domainToken);
        
        const options = {
            hostname: 'api.qiniu.com',
            port: 443,
            path: domainPath,
            method: 'PUT',
            headers: {
                'Authorization': domainToken,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(configBody),
                'Host': 'api.qiniu.com'
            }
        };
        
        const req = https.request(options, (res) => {
            console.log('[DEBUG] Node.js版本域名配置响应状态码:', res.statusCode);
            
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                console.log('[DEBUG] Node.js版本域名配置响应体:', data);
                
                if (res.statusCode === 200) {
                    resolve(data);
                } else {
                    reject(new Error(`域名配置失败 ${res.statusCode}: ${data}`));
                }
            });
        });
        
        req.on('error', (e) => {
            reject(new Error(`域名配置请求错误: ${e.message}`));
        });
        
        req.write(configBody);
        req.end();
    });
}

// 主函数
async function main() {
    try {
        console.log('\n=== Node.js版本证书上传开始 ===');
        
        // 上传证书
        const uploadResult = await uploadCertificate();
        
        if (uploadResult.certID) {
            console.log('证书上传成功，证书ID:', uploadResult.certID);
            
            // 配置域名使用新证书
            console.log(`正在为域名 ${domain} 配置证书...`);
            await configureDomainCertificate(uploadResult.certID);
            console.log('域名证书配置成功');
        } else {
            throw new Error('证书上传失败，未获取到证书ID');
        }
        
        console.log('\n=== Node.js版本证书上传和配置完成 ===');
        
    } catch (error) {
        console.error('错误:', error.message);
        process.exit(1);
    }
}

// 运行主函数
if (require.main === module) {
    main();
}

module.exports = {
    uploadCertificate,
    configureDomainCertificate,
    generateSignString
};