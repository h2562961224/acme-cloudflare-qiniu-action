# 自动化SSL证书管理系统

这是一个基于GitHub Actions的自动化SSL证书管理系统，用于自动从Let's Encrypt获取SSL证书并上传到七牛云。

## 背景

- 使用Cloudflare进行域名解析和CDN加速
- 使用七牛云作为对象存储服务
- 七牛云需要HTTPS证书但不提供免费证书
- Let's Encrypt提供的免费证书有效期为90天，需要定期更新

## 功能特性

- ✅ 自动从Let's Encrypt获取SSL证书
- ✅ 使用Cloudflare DNS API进行域名验证
- ✅ 自动上传证书到七牛云
- ✅ 自动配置域名使用新证书
- ✅ 每月自动执行，确保证书及时更新
- ✅ 支持手动触发执行

## 项目结构

```
acme-cloudflare-qiniu-action/
├── .github/
│   └── workflows/
│       └── renew-cert.yml     # GitHub Actions工作流配置
├── scripts/
│   ├── get-cert.sh            # 获取SSL证书脚本
│   └── upload-to-qiniu.sh     # 上传证书到七牛云脚本
├── .env.example               # 环境变量示例
└── README.md                  # 项目说明文档
```

## 配置步骤

### 1. Fork本项目

将本项目Fork到你的GitHub账户下。

### 2. 获取API密钥

#### Cloudflare API密钥
1. 登录Cloudflare控制台
2. 进入 "My Profile" > "API Tokens"
3. 获取 "Global API Key"
4. 记录你的Cloudflare邮箱地址

#### 七牛云API密钥
1. 登录七牛云控制台
2. 进入 "个人中心" > "密钥管理"
3. 获取 "AccessKey" 和 "SecretKey"

### 3. 配置GitHub Secrets

在你的GitHub项目中，进入 "Settings" > "Secrets and variables" > "Actions"，添加以下Secrets：

| Secret名称 | 说明 | 示例 |
|-----------|------|------|
| `CLOUDFLARE_EMAIL` | Cloudflare账户邮箱 | `user@example.com` |
| `CLOUDFLARE_API_KEY` | Cloudflare Global API Key | `abc123...` |
| `QINIU_ACCESS_KEY` | 七牛云AccessKey | `xyz789...` |
| `QINIU_SECRET_KEY` | 七牛云SecretKey | `def456...` |
| `DOMAIN` | 需要证书的域名 | `cdn.example.com` |

### 4. 域名配置要求

确保你的域名满足以下条件：

1. **DNS解析**: 域名必须通过Cloudflare进行DNS解析
2. **七牛云配置**: 域名必须已在七牛云中添加并配置
3. **CNAME记录**: 域名应该CNAME到七牛云提供的域名

## 使用方法

### 自动执行

系统会在每月1号凌晨2点自动执行证书更新流程。

### 手动执行

1. 进入GitHub项目的 "Actions" 页面
2. 选择 "SSL Certificate Renewal" 工作流
3. 点击 "Run workflow" 按钮
4. 选择分支并点击 "Run workflow"

## 工作流程

1. **环境准备**: 安装acme.sh和必要的工具
2. **证书获取**: 使用acme.sh通过Cloudflare DNS验证获取Let's Encrypt证书
3. **证书上传**: 将证书上传到七牛云
4. **域名配置**: 配置域名使用新上传的证书
5. **清理工作**: 删除临时文件

## 故障排除

### 常见问题

1. **DNS验证失败**
   - 检查Cloudflare API密钥是否正确
   - 确认域名确实通过Cloudflare进行DNS解析
   - 检查API密钥权限是否足够

2. **证书上传失败**
   - 检查七牛云API密钥是否正确
   - 确认七牛云账户有足够的权限
   - 检查域名是否已在七牛云中配置

3. **域名配置失败**
   - 确认域名已在七牛云中正确配置
   - 检查域名状态是否正常

### 查看日志

在GitHub Actions的执行页面可以查看详细的执行日志，包括：
- 证书获取过程
- 证书上传结果
- 域名配置状态
- 错误信息（如果有）

## 安全注意事项

1. **API密钥安全**: 所有API密钥都存储在GitHub Secrets中，不会在日志中显示
2. **证书安全**: 证书文件在使用后会自动删除
3. **权限最小化**: 建议为API密钥设置最小必要权限

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request来改进这个项目。

## 开发笔记

### 七牛云API签名问题

在实现证书上传功能时，花了一天时间调试七牛云的API签名认证。

### 遇到的问题

1. **文档不够清晰**: 七牛云文档中QBox和Qiniu两种签名方式的使用场景说明不明确
2. **示例不足**: 管理API的签名示例比较少，主要是上传API的示例
3. **版本差异**: generateAccessToken和generateAccessTokenV2的区别需要看源码才能理解
4. **实现细节**: 不同语言SDK中签名字符串构造的细节有差异

### 解决方案

最终通过对比Node.js官方SDK源码，找到了正确的签名格式：

```
METHOD path
Host: host
Content-Type: content-type

body
```

### 建议

如果要使用七牛云管理API：
1. 参考官方Node.js SDK的`generateAccessTokenV2`实现
2. 遇到问题时直接看SDK源码比较靠谱
3. 签名格式要严格按照上面的格式，换行符和空行都不能少

---

## 支持

如果你在使用过程中遇到问题，可以：

1. 查看GitHub Actions的执行日志
2. 检查配置是否正确
3. 提交Issue描述问题
4. 如果是七牛云API相关问题，建议直接看源码而不是七牛云文档