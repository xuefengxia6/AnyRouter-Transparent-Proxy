# Backend 模块文档

> [根目录](../CLAUDE.md) > **backend**

---

## 📋 模块概述

**Backend** 是 AnyRouter 透明代理的后端服务模块，基于 FastAPI 框架构建，负责 HTTP 代理、请求处理、统计收集和 Web 管理面板 API。

**技术栈**: FastAPI + httpx + Uvicorn + sse-starlette

**关键特性**:
- 异步 HTTP 代理，支持流式响应 (SSE)
- System Prompt 动态替换/插入
- 请求/响应头部过滤（RFC 7230 兼容）
- 统计数据收集和实时监控
- 日志持久化与查询
- Web 管理面板 RESTful API

---

## 📁 目录结构

```
backend/
├── app.py                    # 主应用入口，FastAPI 应用定义
├── config.py                 # 配置管理，加载环境变量
├── requirements.txt          # Python 依赖清单
├── services/                 # 业务逻辑层
│   ├── __init__.py
│   ├── proxy.py             # 代理处理逻辑
│   ├── stats.py             # 统计收集服务
│   └── log_storage.py       # 日志持久化服务
├── routers/                  # 路由层
│   ├── __init__.py
│   └── admin.py             # 管理面板 API 路由
└── utils/                    # 工具函数
    ├── __init__.py
    └── encoding.py          # 编码处理工具
```

---

## 🧩 核心模块

### 1. 主应用模块 (`app.py`)

**职责**: FastAPI 应用定义、生命周期管理、主代理路由

**关键函数**:

| 函数名 | 行号 | 功能描述 |
|--------|------|----------|
| `lifespan()` | 54-128 | FastAPI 生命周期管理，初始化 HTTP 客户端和后台任务 |
| `health_check()` | ~145 | 健康检查端点，用于容器监控 |
| `admin_static()` | ~160 | 处理 Web 管理面板静态文件请求 |
| `proxy()` | ~190+ | **核心**: 捕获所有路由并转发请求，支持流式响应 |

**代理逻辑流程**:
1. 读取请求体（如果存在）
2. 过滤请求头（移除 hop-by-hop 头部）
3. 对 `/v1/messages` 路由执行 System Prompt 处理
4. 构建并发送上游请求（使用 `httpx.build_request()` + `send(stream=True)`）
5. 过滤响应头
6. 返回流式响应（使用 `BackgroundTask` 管理连接关闭）

**设计亮点**:
- ✅ 使用 `lifespan` 事件管理 HTTP 客户端生命周期
- ✅ 全局共享 `httpx.AsyncClient` 实现连接池复用
- ✅ `BackgroundTask` 确保流式响应后正确关闭连接
- ✅ 异步并发启动统计更新和日志生产者任务

---

### 2. 配置管理模块 (`config.py`)

**职责**: 加载环境变量、管理全局配置、自定义请求头加载

**主要配置项**:

| 配置名称 | 类型 | 说明 |
|---------|------|------|
| `TARGET_BASE_URL` | `str` | 上游 API 目标地址 |
| `SYSTEM_PROMPT_REPLACEMENT` | `str \| None` | System Prompt 替换文本 |
| `SYSTEM_PROMPT_BLOCK_INSERT_IF_NOT_EXIST` | `bool` | 启用插入模式 |
| `HOP_BY_HOP_HEADERS` | `set[str]` | RFC 7230 hop-by-hop 头部列表 |
| `CUSTOM_HEADERS` | `dict` | 自定义请求头（从 `env/.env.headers.json` 加载） |
| `LOG_PERSISTENCE_ENABLED` | `bool` | 启用日志持久化 |
| `LOG_STORAGE_PATH` | `str` | 日志存储路径 |
| `DEBUG_MODE` | `bool` | 调试模式开关 |
| `PORT` | `int` | 服务端口 |

**关键函数**:
- `load_custom_headers()`: 从 JSON 文件加载自定义请求头，支持 `__` 前缀注释字段

---

### 3. 代理处理服务 (`services/proxy.py`)

**职责**: 请求/响应过滤、System Prompt 处理

**关键函数**:

| 函数名 | 功能描述 |
|--------|----------|
| `filter_request_headers(headers)` | 过滤请求头，移除 hop-by-hop 头部和 Content-Length |
| `filter_response_headers(headers)` | 过滤响应头，移除 hop-by-hop 头部、Content-Length 和 Content-Encoding |
| `process_request_body(body)` | 处理请求体，替换/插入 System Prompt |
| `prepare_forward_headers(...)` | 准备转发请求头，注入自定义头部 |

**System Prompt 处理逻辑**:

```python
# 仅在 /v1/messages 路由执行
if path == "/v1/messages" and SYSTEM_PROMPT_REPLACEMENT:
    body = process_request_body(body)

# process_request_body 内部逻辑
if SYSTEM_PROMPT_BLOCK_INSERT_IF_NOT_EXIST:
    if CLAUDE_CODE_KEYWORD not in original_text:
        # 插入模式：在开头插入新元素
        new_element = {...}
        data["system"].insert(0, new_element)
    else:
        # 包含关键字则替换
        data["system"][0]["text"] = SYSTEM_PROMPT_REPLACEMENT
else:
    # 替换模式：直接替换
    data["system"][0]["text"] = SYSTEM_PROMPT_REPLACEMENT
```

---

### 4. 统计收集服务 (`services/stats.py`)

**职责**: 收集请求统计、性能指标、错误日志，提供实时日志流

**全局数据结构**:

| 变量名 | 类型 | 用途 |
|--------|------|------|
| `request_stats` | `dict` | 全局统计数据（总请求数、成功数、失败数、流量等） |
| `recent_requests` | `deque` | 最近 1000 个请求的性能数据 |
| `error_logs` | `deque` | 最近 500 个错误日志 |
| `path_stats` | `defaultdict` | 按路径分组的统计 |
| `time_window_stats` | `dict` | 按时间窗口的统计（用于图表） |
| `log_queue` | `asyncio.Queue` | 日志消息队列（SSE 推送） |
| `log_subscribers` | `set` | SSE 连接订阅者集合 |

**关键函数**:

| 函数名 | 功能描述 |
|--------|----------|
| `record_request_start(path, method, bytes_sent)` | 记录请求开始，返回请求 ID |
| `record_request_success(...)` | 记录请求成功，更新统计和性能指标 |
| `record_request_error(...)` | 记录请求错误，更新错误日志 |
| `broadcast_log_message(log_entry)` | 广播日志消息到所有 SSE 订阅者 |
| `periodic_stats_update()` | 后台任务：定期更新时间窗口统计 |
| `log_producer()` | 后台任务：从队列消费日志并广播 |

**后台任务**:
- `periodic_stats_update()`: 每分钟更新时间窗口统计（请求数、错误数、流量）
- `log_producer()`: 消费日志队列，广播到所有 SSE 订阅者

---

### 5. 日志持久化服务 (`services/log_storage.py`)

**职责**: 日志按日期持久化存储、查询、清理

**类结构**:

```python
class LogStorage:
    def __init__(self, storage_path, daily_limit, retention_days):
        # 初始化存储路径和配置

    def store_log(self, log_entry: dict) -> bool:
        # 存储日志到对应日期文件

    def query_logs(self, start_date, end_date, filters) -> list:
        # 查询指定日期范围的日志

    def get_recent_logs(self, limit) -> list:
        # 获取最近的日志（最多 limit 条）

    def clear_all_logs(self) -> bool:
        # 清空所有日志文件

    def _cleanup_old_logs(self):
        # 清理过期日志（根据 retention_days）
```

**文件存储格式**:
- 路径: `{storage_path}/YYYY-MM-DD.jsonl`
- 格式: JSON Lines（每行一个 JSON 对象）
- 自动清理: 超过 `retention_days` 的日志自动删除

---

### 6. 管理面板路由 (`routers/admin.py`)

**职责**: 提供 Web 管理面板的 RESTful API

**API 端点**:

| 端点 | 方法 | 功能描述 |
|------|------|----------|
| `/api/stats` | GET | 获取系统统计信息 |
| `/api/errors` | GET | 获取错误日志列表 |
| `/api/config` | GET | 获取当前配置 |
| `/api/config` | POST | 更新配置（自定义请求头） |
| `/api/logs/stream` | GET | 实时日志流 (SSE) |
| `/api/logs/history` | GET | 查询历史日志 |
| `/api/logs/recent` | GET | 获取最近日志 |
| `/api/logs/clear` | DELETE | 清空所有日志 |
| `/admin/{path:path}` | GET | 静态文件服务（前端页面） |

**认证机制**:
- ⚠️ 当前版本已移除认证检查，允许直接访问
- 生产环境建议启用 `DASHBOARD_API_KEY` 认证

**关键函数**:
- `_normalize_status_code(entry)`: 确保 `status_code` 为数字，避免前端显示 `"--"` 时颜色不一致

---

### 7. 编码工具 (`utils/encoding.py`)

**职责**: 确保字符串正确处理，避免编码错误

**关键函数**:
- `ensure_unicode(text)`: 确保文本为 Unicode 字符串，自动处理 bytes 转换

---

## 🔧 依赖管理

### requirements.txt

```txt
fastapi==0.115.5
uvicorn==0.32.1
httpx==0.28.1
python-dotenv==1.0.1
sse-starlette==2.2.1
```

**依赖说明**:
- **FastAPI**: 高性能异步 Web 框架
- **Uvicorn**: ASGI 服务器（支持 HTTP/1.1 和 WebSocket）
- **httpx**: 现代异步 HTTP 客户端（支持 HTTP/2 和连接池）
- **python-dotenv**: 环境变量管理
- **sse-starlette**: Server-Sent Events (SSE) 支持

---

## 🚀 启动方式

### 开发模式

```bash
# 从项目根目录运行
python backend/app.py
```

**启动流程**:
1. 加载 `.env` 环境变量
2. 初始化配置（`config.py`）
3. 加载自定义请求头（`env/.env.headers.json`）
4. 创建 FastAPI 应用和 HTTP 客户端
5. 启动后台任务（统计更新、日志生产者）
6. 启动 Uvicorn 服务器（默认端口 8088）

### 生产模式

```bash
# 使用 Uvicorn 启动（推荐使用 Docker）
uvicorn backend.app:app --host 0.0.0.0 --port 8088 --workers 1
```

**注意**: 由于使用全局状态管理统计数据，建议使用单 worker 模式。多 worker 需要引入 Redis 等共享存储。

---

## 📊 性能考虑

### 异步架构优势
- **非阻塞 I/O**: 基于 `asyncio` 和 ASGI，高效处理并发请求
- **连接池复用**: 共享 `httpx.AsyncClient` 实例，减少连接开销
- **流式传输**: 零拷贝流式转发，降低内存占用

### 内存管理
- `recent_requests`: 限制 1000 条（约 100KB）
- `error_logs`: 限制 500 条（约 50KB）
- `log_queue`: 限制 1000 条（防止内存溢出）
- 日志持久化: 按日期分文件，自动清理过期日志

### 优化建议
- 生产环境关闭 `DEBUG_MODE` 减少日志输出
- 配置合理的 `LOG_RETENTION_DAYS` 和 `LOG_DAILY_LIMIT`
- 考虑引入 Redis 实现多 worker 共享状态

---

## 🧪 测试建议

### 推荐测试框架
- **pytest**: Python 测试框架
- **pytest-asyncio**: 异步测试支持
- **httpx**: 测试异步 FastAPI 应用

### 测试覆盖点
- [ ] 代理功能测试（各种 HTTP 方法）
- [ ] System Prompt 替换/插入逻辑
- [ ] 请求/响应头部过滤
- [ ] 统计数据准确性
- [ ] 日志持久化和查询
- [ ] API 端点功能测试
- [ ] 错误处理和边界条件

---

## 🔒 安全最佳实践

### 已实施
- ✅ 防重定向攻击: `follow_redirects=False`
- ✅ 请求超时: 60 秒防止资源耗尽
- ✅ 错误处理: 上游请求失败返回 502
- ✅ 连接管理: `BackgroundTask` 确保连接正确关闭

### 推荐增强
- [ ] 启用 `DASHBOARD_API_KEY` 认证保护管理面板
- [ ] 实现请求限流（基于 IP 或 API Key）
- [ ] 生产环境移除敏感信息日志
- [ ] 使用 HTTPS 部署（通过反向代理）
- [ ] 添加 CORS 策略限制

---

## 📝 维护日志

| 日期 | 版本 | 变更说明 |
|------|------|----------|
| 2025-12-12 | v1.0.0 | 初始化后端模块文档 |

---

**返回**: [根目录文档](../CLAUDE.md)
