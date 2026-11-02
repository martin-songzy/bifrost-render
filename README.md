# Bifrost 网关 · Render Free 部署项目

> 状态：**搭建中** · 创建：2026-11 · 平台：Render Free + Supabase Free（PostgreSQL）

## 1. 目标

把多个 OpenAI-compatible 中转站聚合到统一地址和统一模型名，提供自动故障切换（failover），供 Dify Cloud Agent 通过 OpenAI 兼容接口调用。要求：

- 图形化管理中转站和模型（Bifrost Web UI）
- 配置持久化：Supabase PostgreSQL（Free Project）
- 部署平台：Render Free（单 Web Service，Docker）
- 无需额外后端服务；UptimeRobot 5 分钟 HTTP 保活

## 2. 架构

```text
Dify Cloud Agent
      │  OpenAI 兼容 /v1 + Bifrost 客户端密钥
      ▼
Bifrost（Render Free Docker，Web UI 同端口 8080）
      ├── 中转站 A（主）
      ├── 中转站 B（备）
      └── 中转站 C（备）
      │  config_store：PostgreSQL（env.PG_*，ssl_mode=require）
      ▼
Supabase Free Project（配置持久化；日志/向量功能不启用）

UptimeRobot ──每 5 分钟──▶ https://<service>.onrender.com/health（不触发模型调用）
```

## 3. 组件与版本

| 组件 | 选型 | 说明 |
|---|---|---|
| 网关 | Docker 镜像 `maximhq/bifrost:v2.4.0`（固定版本，不用 latest） | Go 网关 + 内置 Web UI |
| 配置库 | Supabase PostgreSQL，Session Pooler 连接 | Free：500MB，2 个活跃项目上限，1 周不活动会暂停 |
| 平台 | Render Free Web Service | 0.1 CPU / 512MB / 750h·月/workspace / 15 分钟无流量休眠 |
| 保活 | UptimeRobot Free，5 分钟 HTTP 监控 | 只打 `/health`，不触发模型调用 |

依据：Bifrost 官方 storage 文档（`config_store` 支持 SQLite/PostgreSQL，`env.` 前缀读环境变量）；Render Free 文档。

## 4. 仓库文件

```text
bifrost-render/
├── README.md                 ← 本文档（项目索引与进度）
├── PLAN.md                   ← 实施计划、决策记录、验收清单
├── config/config.json        ← Bifrost 初始配置（不含任何密钥）
├── render.yaml               ← Render Blueprint（服务定义）
└── .gitignore                ← 忽略本地秘密文件
```

密钥一律走 Render 环境变量（`env.` 前缀在 config.json 中引用），**不进 Git**：

| 环境变量 | 内容 | 来源 |
|---|---|---|
| `PG_HOST` / `PG_USER` / `PG_PASSWORD` | Supabase Session Pooler 地址 / 用户 / 密码 | Supabase → Connect |
| `BIFROST_SETUP_TOKEN` | Web UI 首次创建管理员账户用的一次性引导令牌 | 自定随机串（≥32 位） |

中转站 API Key 在 Web UI 里添加后自动写入 Supabase，不落本地文件。

## 5. 实施进度

- [x] 选型与官方证据核查（Bifrost v2.4.0 / Supabase Free / Render Free）
- [x] 仓库文件就绪（Dockerfile、config.json、render.yaml、文档）
- [x] 首次部署成功，健康检查 `/health` 返回 200
- [x] 已确认 `configstore: postgres config store ready`（走 Supabase，不是本地 SQLite）
- [ ] 设置 `BIFROST_SETUP_TOKEN`，首次登录创建管理员
- [ ] 验证配置持久化（后台修改 → 重新部署 → 仍在）
- [ ] 添加中转站，Dify 接入测试（含工具调用）
- [ ] 双站 failover 验证
- [ ] UptimeRobot 保活配置

## 6. 关键风险（记录在案）

1. Render Free 临时磁盘：本地任何文件不持久，一切持久状态依赖 Supabase。
2. Supabase Free 1 周不活动可能暂停项目 → 网关全挂；保活不覆盖数据库活动。
3. 512MB 未实测：启动峰值、并发长流可能触发 OOM。
4. Render 免费服务异常高主动出站流量可能被暂停（阈值未公开）。
5. Render 休眠后首个请求延迟约 1 分钟，Dify 侧需接受该冷启动。
