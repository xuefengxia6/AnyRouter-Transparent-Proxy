# Frontend 模块文档

> [根目录](../CLAUDE.md) > **frontend**

---

## 📋 模块概述

**Frontend** 是 AnyRouter 透明代理的 Web 管理面板前端项目，基于 Vue 3 + TypeScript 构建，提供直观的监控、日志、配置管理界面。

**技术栈**: Vue 3 + TypeScript + Vite + Pinia + TailwindCSS 4 + Chart.js

**关键特性**:
- 实时监控仪表板（请求统计、性能指标、图表）
- 实时日志流（SSE，支持过滤和搜索）
- 历史日志查询（按日期、路径、方法、状态码过滤）
- 配置管理（环境变量、自定义请求头）
- PWA 支持（离线访问、桌面安装、自动更新）
- 响应式设计（支持移动端和桌面端）

---

## 📁 目录结构

```
frontend/
├── public/
│   └── icons/
│       └── pwa.svg              # PWA 图标
├── src/
│   ├── main.ts                  # 应用入口
│   ├── App.vue                  # 根组件
│   ├── router/
│   │   └── index.ts             # 路由配置
│   ├── stores/
│   │   └── index.ts             # Pinia 状态管理
│   ├── services/
│   │   └── api.ts               # API 服务层
│   ├── views/                   # 页面组件
│   │   ├── Dashboard.vue        # 仪表板页面
│   │   ├── Monitoring.vue       # 监控中心页面
│   │   ├── Logs.vue             # 日志查看页面
│   │   └── Config.vue           # 配置管理页面
│   ├── components/              # 公共组件
│   │   ├── BaseLayout.vue       # 布局组件
│   │   ├── Icon.vue             # 图标组件
│   │   └── NotificationContainer.vue  # 通知容器
│   ├── composables/             # 组合式函数
│   │   └── useRealtime.ts       # 实时数据钩子
│   ├── types/
│   │   └── index.ts             # TypeScript 类型定义
│   └── utils/
│       └── statusStyle.ts       # 状态样式工具
├── package.json                 # 前端依赖
├── vite.config.ts               # Vite 构建配置
├── tsconfig.json                # TypeScript 配置
├── tailwind.config.ts           # TailwindCSS 配置
└── index.html                   # HTML 模板
```

---

## 🧩 核心模块

### 1. 应用入口 (`src/main.ts`)

**职责**: 初始化 Vue 应用、注册插件、挂载应用

```typescript
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import router from './router'
import App from './App.vue'

const app = createApp(App)

app.use(createPinia())
app.use(router)

app.mount('#app')
```

**注册的 PWA Service Worker**:
- 自动更新检测
- 离线缓存策略
- 后台同步

---

### 2. 路由配置 (`src/router/index.ts`)

**职责**: 定义页面路由、路由守卫

**路由列表**:

| 路径 | 组件 | 名称 | 功能 |
|------|------|------|------|
| `/` | - | - | 重定向到 `/dashboard` |
| `/dashboard` | `Dashboard.vue` | Dashboard | 仪表板页面 |
| `/config` | `Config.vue` | Config | 配置管理页面 |
| `/monitoring` | `Monitoring.vue` | Monitoring | 监控中心页面 |
| `/logs` | `Logs.vue` | Logs | 日志查看页面 |

**路由守卫**:
- `beforeEach`: 设置页面标题（`${meta.title} - 管理面板`）

---

### 3. API 服务层 (`src/services/api.ts`)

**职责**: 封装后端 API 调用，统一错误处理

**核心功能**:

```typescript
// API 客户端配置
const createApiClient = (): KyInstance => {
  return ky.create({
    prefixUrl: API_BASE_URL,  // '/api'
    timeout: API_TIMEOUT,      // 30000ms
    hooks: {
      beforeRequest: [/* 注入 Authorization 头 */],
      afterResponse: [/* 处理 401 和错误 */]
    }
  })
}
```

**API 方法**:

| 方法名 | HTTP 方法 | 端点 | 功能 |
|--------|-----------|------|------|
| `fetchSystemStats()` | GET | `/api/stats` | 获取系统统计信息 |
| `fetchErrorLogs()` | GET | `/api/errors` | 获取错误日志 |
| `fetchSystemConfig()` | GET | `/api/config` | 获取当前配置 |
| `updateSystemConfig(data)` | POST | `/api/config` | 更新配置 |
| `subscribeToLogs(callback)` | SSE | `/api/logs/stream` | 订阅实时日志流 |
| `fetchLogHistory(params)` | GET | `/api/logs/history` | 查询历史日志 |
| `fetchRecentLogs(limit)` | GET | `/api/logs/recent` | 获取最近日志 |
| `clearAllLogs()` | DELETE | `/api/logs/clear` | 清空所有日志 |

**错误处理**:
- 401: 清除 Token，跳转登录页
- 其他错误: 抛出 `ApiError` 异常

---

### 4. 状态管理 (`src/stores/index.ts`)

**职责**: 全局状态管理（使用 Pinia）

**Store 结构**:

```typescript
export const useMainStore = defineStore('main', {
  state: () => ({
    systemStats: null as SystemStats | null,
    errorLogs: [] as ErrorLog[],
    systemConfig: null as SystemConfig | null,
    logs: [] as LogEntry[],
    isLoading: false,
    notifications: [] as Notification[]
  }),

  actions: {
    async loadSystemStats() { /* ... */ },
    async loadErrorLogs() { /* ... */ },
    async loadSystemConfig() { /* ... */ },
    async updateConfig(data) { /* ... */ },
    addNotification(notification) { /* ... */ },
    removeNotification(id) { /* ... */ }
  }
})
```

**使用示例**:

```typescript
const store = useMainStore()

// 加载系统统计
await store.loadSystemStats()

// 访问状态
console.log(store.systemStats)
```

---

### 5. 页面组件

#### 5.1 仪表板页面 (`src/views/Dashboard.vue`)

**职责**: 显示系统概览、统计卡片、快速操作

**核心数据**:
- 总请求数、成功率、平均响应时间
- 请求趋势图表（最近 1 小时）
- 快速链接（监控中心、日志查看、配置管理）

**技术实现**:
- 使用 Chart.js 绘制趋势图
- 定时刷新数据（每 5 秒）

---

#### 5.2 监控中心页面 (`src/views/Monitoring.vue`)

**职责**: 实时监控、性能指标、路径统计

**核心功能**:
- 实时请求统计（请求数、错误数、流量）
- 路径分组统计（按路径显示请求数、错误数、平均响应时间）
- 性能指标图表（响应时间分布、请求吞吐量）
- 最近错误日志列表

**技术实现**:
- 使用 `useRealtime()` 组合式函数订阅实时数据
- Chart.js 绘制性能图表
- 自动刷新（每 10 秒）

---

#### 5.3 日志查看页面 (`src/views/Logs.vue`)

**职责**: 实时日志流、历史日志查询、日志过滤

**核心功能**:
- **实时日志流**: SSE 订阅，自动滚动到底部
- **历史日志查询**: 按日期范围、路径、方法、状态码过滤
- **日志操作**: 清空日志、导出日志（CSV）
- **日志详情**: 点击展开查看完整日志内容

**过滤器**:
- 日期范围选择（开始日期、结束日期）
- 路径过滤（模糊匹配）
- HTTP 方法过滤（GET、POST、PUT、DELETE 等）
- 状态码过滤（200、404、500 等）

**技术实现**:
- SSE: `fetchEventSource()` 订阅 `/api/logs/stream`
- 虚拟滚动: 优化大量日志渲染性能
- 状态码颜色: 根据状态码显示不同颜色（绿色 2xx、黄色 3xx、红色 4xx/5xx）

---

#### 5.4 配置管理页面 (`src/views/Config.vue`)

**职责**: 显示和编辑系统配置

**核心功能**:
- **环境变量显示**: 只读显示当前环境变量（API URL、System Prompt、日志配置等）
- **自定义请求头编辑**: 可编辑 `env/.env.headers.json` 配置
- **保存配置**: 提交更新到后端

**配置项**:
- API Base URL
- System Prompt Replacement
- System Prompt Insert Mode
- Debug Mode
- Port
- Log Persistence Enabled
- Log Storage Path
- Log Retention Days
- Custom Headers (可编辑)

**技术实现**:
- 表单验证（JSON 格式校验）
- 保存前确认提示
- 成功/失败通知

---

### 6. 组合式函数

#### 6.1 实时数据钩子 (`src/composables/useRealtime.ts`)

**职责**: 封装 SSE 订阅逻辑，提供实时数据流

```typescript
export function useRealtime() {
  const logs = ref<LogEntry[]>([])
  const isConnected = ref(false)

  const connect = () => {
    subscribeToLogs((log) => {
      logs.value.push(log)
      // 限制内存占用
      if (logs.value.length > 1000) {
        logs.value.shift()
      }
    })
    isConnected.value = true
  }

  const disconnect = () => {
    // 关闭 SSE 连接
    isConnected.value = false
  }

  onUnmounted(() => {
    disconnect()
  })

  return { logs, isConnected, connect, disconnect }
}
```

---

### 7. TypeScript 类型定义 (`src/types/index.ts`)

**核心类型**:

```typescript
// 系统统计
export interface SystemStats {
  total_requests: number
  successful_requests: number
  failed_requests: number
  total_bytes_sent: number
  total_bytes_received: number
  uptime: number
  avg_response_time: number
}

// 日志条目
export interface LogEntry {
  id: string
  timestamp: string
  method: string
  path: string
  status_code: number
  response_time: number
  bytes_sent: number
  bytes_received: number
  error?: string
}

// 错误日志
export interface ErrorLog {
  timestamp: string
  path: string
  method: string
  status_code: number
  error: string
}

// 系统配置
export interface SystemConfig {
  api_base_url: string
  system_prompt_replacement: string | null
  system_prompt_block_insert_if_not_exist: boolean
  debug_mode: boolean
  port: number
  custom_headers: Record<string, string>
  log_persistence_enabled: boolean
  log_storage_path: string
  log_retention_days: number
}
```

---

## 🔧 依赖管理

### package.json

```json
{
  "dependencies": {
    "vue": "^3.5.25",
    "vue-router": "^4.6.3",
    "pinia": "^3.0.4",
    "ky": "^1.14.1",
    "chart.js": "^4.5.1",
    "vue-chartjs": "^5.3.3",
    "workbox-window": "^7.4.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^6.0.2",
    "vite": "^7.2.4",
    "typescript": "~5.9.3",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/vite": "^4.1.17",
    "vite-plugin-pwa": "^0.21.1"
  }
}
```

**依赖说明**:
- **Vue**: 渐进式 JavaScript 框架
- **Vue Router**: 官方路由库
- **Pinia**: 官方状态管理库
- **ky**: 基于 Fetch API 的 HTTP 客户端
- **Chart.js**: 图表库
- **TailwindCSS**: 实用优先的 CSS 框架
- **vite-plugin-pwa**: PWA 支持插件

---

## 🚀 构建和部署

### 开发模式

```bash
cd frontend
npm install
npm run dev
```

访问: `http://localhost:5173`

### 生产构建

```bash
npm run build
```

**构建输出**: `../static/`（由后端静态服务）

**构建优化**:
- Tree-shaking: 自动移除未使用代码
- Code splitting: 按路由分割代码
- Minification: 压缩 JS/CSS
- PWA 清单: 生成 Service Worker 和 manifest.json

---

## 🎨 样式系统

### TailwindCSS 4 配置

```typescript
// tailwind.config.ts
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#0ea5e9',   // 天蓝色
        success: '#10b981',   // 绿色
        warning: '#f59e0b',   // 橙色
        error: '#ef4444',     // 红色
        dark: '#0f172a'       // 深蓝色
      }
    }
  }
}
```

**颜色语义**:
- `primary`: 主要按钮、链接
- `success`: 成功状态（2xx 状态码）
- `warning`: 警告状态（3xx 状态码）
- `error`: 错误状态（4xx/5xx 状态码）
- `dark`: 背景色

---

## 📱 PWA 配置

### Service Worker 策略

```typescript
// vite.config.ts
VitePWA({
  registerType: 'autoUpdate',
  workbox: {
    globPatterns: ['**/*.{js,css,html,ico,png,svg}'],
    runtimeCaching: [
      {
        urlPattern: /^https:\/\/api\./,
        handler: 'NetworkFirst',
        options: {
          cacheName: 'api-cache',
          expiration: {
            maxEntries: 50,
            maxAgeSeconds: 300  // 5 分钟
          }
        }
      }
    ]
  }
})
```

**缓存策略**:
- **静态资源**: CacheFirst（优先从缓存读取）
- **API 请求**: NetworkFirst（优先从网络获取，失败时使用缓存）

---

## 🧪 测试建议

### 推荐测试框架
- **Vitest**: Vue 生态的测试框架
- **Vue Test Utils**: Vue 组件测试工具
- **Playwright**: E2E 测试

### 测试覆盖点
- [ ] 组件单元测试（Dashboard、Monitoring、Logs、Config）
- [ ] API 服务层测试（模拟 HTTP 请求）
- [ ] 状态管理测试（Pinia store）
- [ ] 路由守卫测试
- [ ] 工具函数测试（statusStyle）
- [ ] E2E 测试（完整用户流程）

---

## ♿ 可访问性 (Accessibility)

### 已实施
- ✅ 语义化 HTML 标签
- ✅ ARIA 标签（表格、按钮）
- ✅ 键盘导航支持
- ✅ 高对比度颜色（符合 WCAG 2.1 AA 标准）

### 推荐增强
- [ ] 添加 `<label>` 标签关联表单输入
- [ ] 添加 `alt` 属性到图片
- [ ] 添加 `aria-live` 区域通知屏幕阅读器
- [ ] 测试键盘导航完整性

---

## 🔒 安全最佳实践

### 已实施
- ✅ CSP (Content Security Policy): 通过 Vite 配置
- ✅ XSS 防护: Vue 自动转义
- ✅ HTTPS: 通过反向代理（生产环境推荐）

### 推荐增强
- [ ] 启用 API Key 认证（localStorage）
- [ ] 添加 CSRF Token（如果启用 Cookie 认证）
- [ ] 定期更新依赖（安全漏洞扫描）

---

## 📈 性能优化

### 已实施
- ✅ 代码分割（按路由懒加载）
- ✅ 图片优化（SVG 图标）
- ✅ Gzip 压缩（生产构建）
- ✅ 虚拟滚动（日志列表）

### 推荐增强
- [ ] 图片懒加载
- [ ] 使用 CDN 托管静态资源
- [ ] 添加 Lighthouse CI 性能测试
- [ ] 优化 Chart.js 渲染性能（使用 Web Worker）

---

## 📝 维护日志

| 日期 | 版本 | 变更说明 |
|------|------|----------|
| 2025-12-12 | v1.0.0 | 初始化前端模块文档 |

---

**返回**: [根目录文档](../CLAUDE.md)
