# AnyRouter Transparent Proxy

> 一个基于 FastAPI 的轻量级透明 HTTP 代理服务，专为解决 AnyRouter 的 Anthropic API 在 Claude Code for VS Code 插件报错 500 导致无法使用的问题而设计。

## ✨ 特性

- 🚀 **完全透明**：支持所有 HTTP 方法（GET、POST、PUT、PATCH、DELETE、OPTIONS、HEAD）
- 🌊 **流式响应**：使用 `httpx.AsyncClient` 异步处理，完美支持流式传输
- 🔒 **标准兼容**：严格按照 RFC 7230 规范过滤 hop-by-hop 头部
- 🎯 **灵活配置**：支持自定义目标 URL、请求头注入和 System Prompt 替换
- 📍 **链路追踪**：自动维护 X-Forwarded-For 链，便于追踪客户端 IP
- ⚡ **高性能**：基于异步架构，连接池复用，高效处理并发请求
- 🔧 **智能处理**：自动计算 Content-Length，避免请求体修改导致的长度不匹配错误

## 🎯 核心功能

### System Prompt 替换

支持动态替换 Anthropic API 请求体中的 `system` 数组第一个元素的 `text` 内容，适用于：

- Claude Code CLI 场景自定义
- Claude Agent SDK 行为调整
- 统一注入系统级提示词

### 智能请求头处理

- **自动过滤**：移除 hop-by-hop 头部（Connection、Keep-Alive 等）
- **Host 重写**：自动将 Host 头改写为目标服务器域名
- **Content-Length 自动计算**：移除原始 Content-Length，由 httpx 根据实际内容自动计算
- **自定义注入**：支持覆盖或添加任意自定义请求头
- **IP 追踪**：智能维护 X-Forwarded-For 链

## 🚀 快速开始

### 方式一：使用 Docker（推荐）

#### 环境要求

- Docker
- Docker Compose（可选）

#### 使用 Docker Compose（最简单）

```bash
# 1. 克隆或下载项目
git clone <repository-url>
cd AnyRouter-Transparent-Proxy

# 2. 复制环境变量模板（可选）
cp .env.example .env

# 3. 编辑 .env 文件修改配置（可选）
# 默认使用 https://anyrouter.top

# 4. 启动服务
docker-compose up -d

# 5. 查看日志
docker-compose logs -f

# 6. 停止服务
docker-compose down

# 7.重启服务
docker-compose down && docker-compose up -d
```

#### 使用 Docker 命令

```bash
# 1. 构建镜像
docker build -t anthropic-proxy .

# 2. 运行容器
docker run -d \
  --name anthropic-proxy \
  -p 8088:8088 \
  -e API_BASE_URL=https://anyrouter.top \
  anthropic-proxy

# 3. 查看日志
docker logs -f anthropic-proxy

# 4. 停止容器
docker stop anthropic-proxy
docker rm anthropic-proxy
```

服务将在 `http://localhost:8088` 启动。

然后替换 Claude Code 中的 API 地址就可以啦~

### 方式二：本地 Python 运行

#### 环境要求

- Python 3.7+
- pip

#### 安装依赖

```bash
# 创建虚拟环境（可选但推荐）
python3 -m venv .venv
source .venv/bin/activate  # macOS/Linux
# 或
.venv\Scripts\activate     # Windows

# 安装依赖
pip install fastapi uvicorn httpx python-dotenv
```

### 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env
```

编辑 `.env` 文件修改自己要改的变量即可。

### 启动服务

```bash
# 开发模式（自动重载）
python anthropic_proxy.py

# 或使用 uvicorn 直接启动
uvicorn anthropic_proxy:app --host 0.0.0.0 --port 8088 --reload
```

服务将在 `http://0.0.0.0:8088` 启动。

同样替换 Claude Code 中的 API 地址就可以啦~

## ⚙️ 配置说明

### 环境变量配置

通过 `.env` 文件或环境变量进行配置：

```bash
# .env 文件内容
API_BASE_URL=https://anyrouter.top  # 或 https://q.quuvv.cn
```

> 注：配置完成后需要重新启动服务

## 📖 使用示例

### 作为 API 中转

```bash
# 原始请求
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -d '{"model": "claude-3-5-sonnet-20241022", ...}'

# 通过代理
curl http://localhost:8088/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -d '{"model": "claude-3-5-sonnet-20241022", ...}'
```

## 🏗️ 架构设计

### 请求处理流程

```
客户端请求
    ↓
proxy() 捕获路由
    ↓
filter_request_headers() 过滤请求头
    ↓
process_request_body() 处理请求体（可选替换 system prompt）
    ↓
重写 Host 头 + 注入自定义头 + 添加 X-Forwarded-For
    ↓
httpx.AsyncClient 发起上游请求
    ↓
filter_response_headers() 过滤响应头
    ↓
StreamingResponse 流式返回给客户端
```

### 关键组件

- **路由处理**：`@app.api_route("/{path:path}")` 捕获所有路径
- **生命周期管理**：使用 FastAPI lifespan 事件管理 HTTP 客户端生命周期
- **共享客户端池**：全局共享 `httpx.AsyncClient` 实现连接复用，提升性能
- **异步请求**：60秒超时，支持长时间流式响应
- **流式传输**：`StreamingResponse` + `aiter_bytes()` 高效处理大载荷
- **头部过滤**：符合 RFC 7230 规范，双向过滤 hop-by-hop 头部和 Content-Length

## 🔧 技术细节

### 请求头过滤规则

根据 RFC 7230 规范，自动移除以下头部：

**Hop-by-hop 头部：**
- Connection
- Keep-Alive
- Proxy-Authenticate
- Proxy-Authorization
- TE
- Trailers
- Transfer-Encoding
- Upgrade

**额外过滤：**
- Content-Length（因为请求体可能被修改，由 httpx 自动重新计算）

### System Prompt 替换逻辑

1. 检查 `SYSTEM_PROMPT_REPLACEMENT` 是否配置
2. 尝试解析请求体为 JSON
3. 验证 `system` 字段存在且为非空数组
4. 检查第一个元素包含 `text` 字段
5. 替换 `system[0].text` 的内容
6. 重新序列化为 JSON 并返回

失败时自动回退到原始请求体，确保服务稳定性。

### HTTP 客户端生命周期管理

使用 FastAPI 的 `lifespan` 上下文管理器：

1. **启动时**：创建共享的 `httpx.AsyncClient` 实例
2. **运行时**：所有请求复用同一个客户端，享受连接池优势
3. **关闭时**：优雅关闭客户端，释放所有连接资源

这种设计避免了每次请求都创建新客户端，解决了流式响应中客户端过早关闭的问题。

## 📝 日志输出

代理服务会输出详细的调试信息：

```
[Proxy] Original body (123 bytes): {...}
[System Replacement] Successfully parsed JSON body
[System Replacement] Original system[0].text: You are Claude Code...
[System Replacement] Replaced with: 你是一个有用的AI助手
[System Replacement] Successfully modified body (original size: 123 bytes, new size: 145 bytes)
```

## 🛡️ 安全性与稳定性

- ❌ **不跟随重定向**：`follow_redirects=False` 防止重定向攻击
- ⏱️ **请求超时**：60秒超时防止资源耗尽
- 🔍 **错误处理**：上游请求失败时返回 502 状态码
- 🔧 **自动容错**：Content-Length 自动计算，避免修改请求体导致的协议错误
- 🔄 **连接管理**：共享客户端池确保连接正确关闭，避免资源泄漏
- 📋 **日志记录**：请求体内容被记录（生产环境建议移除敏感信息日志）

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**注意**：本项目仅供学习和开发测试使用，请确保遵守相关服务的使用条款。