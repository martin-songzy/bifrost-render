# 实施计划与决策记录

## 已定决策

| # | 决策 | 理由 |
|---|---|---|
| D1 | 网关选 Bifrost v2.4.0 固定镜像 | 官方 Web UI 图形化管理 + Go 单二进制轻量 + 支持 Postgres config_store |
| D2 | 配置库用 Supabase Free PostgreSQL | 用户已有账号；解决 Render 临时磁盘的持久化问题 |
| D3 | 镜像直接拉 Docker Hub，不在 Render 构建 | 免费 build 分钟额度有限，也避免编译开销 |
| D4 | config.json 只含非密钥骨架，真实配置由 Web UI 写库 | 中转站 Key 由 UI 添加后入 Supabase，不进 Git |
| D5 | logs_store / vector_store / governance 不启用 | 只保留 config_store，最小化数据库用量与内存 |

## config.json 关键字段（依据官方 storage 文档）

```json
{
  "config_store": {
    "enabled": true,
    "type": "postgres",
    "config": {
      "host": "env.PG_HOST",
      "port": "5432",
      "user": "env.PG_USER",
      "password": "env.PG_PASSWORD",
      "db_name": "postgres",
      "ssl_mode": "require",
      "max_idle_conns": 2,
      "max_open_conns": 5
    }
  }
}
```

- `db_name`：Supabase 默认库名为 `postgres`。
- 连接池故意调小（2/5）：512MB 网关 + Supabase Free 免费实例都不适合大开销连接。
- Supabase 提供 Session Pooler 地址（Port 5432），`ssl_mode=require` 满足其 TLS 要求。

## render.yaml 要点

- `type: web`，`runtime: image`，指向 `docker.io/maximhq/bifrost:v2.4.0`。
- 端口 8080（Bifrost 默认）。
- `plan: free`。
- 环境变量 `PG_HOST/PG_USER/PG_PASSWORD` 用 `sync: false`（在控制台填写，不进 Git）。

## 验收清单（对应 README 第 5 节）

1. **持久化**：UI 改配置 → 手动 "Manual Deploy" 重启 → 配置仍在。
2. **Dify 接入**：Base URL `https://<service>.onrender.com/v1`，Key 用 Bifrost 客户端密钥，模型名与 Bifrost 内配置一致。
3. **Agent 工具调用**：Dify Agent + Function Calling 完整往返一次。
4. **failover**：同一名模型配 A/B 两站；禁用 A 或填错 A 的 Key → 请求落到 B → 日志确认切换。
5. **保活**：UptimeRobot 5 分钟打 `/health`，一周内 Render 不休眠。

## 部署踩坑记录

**问题（已解决）**：首次部署直接用 `runtime: image` 拉官方镜像，仓库里的 `config/config.json` 不会进容器，Bifrost 回退到本地 SQLite，启动时报 `database is locked` 并以 fatal 退出。

**修复**：改为 `runtime: docker` + 自制两行 Dockerfile（`FROM maximhq/bifrost:v2.4.0` + `COPY config/config.json /app/data/config.json`）。官方 entrypoint 固定用 `-app-dir /app/data`，所以这个路径正确。

**验证通过的日志**：`configstore: postgres config store ready`、`successfully started bifrost, serving UI on http://0.0.0.0:8080`。

## 用户操作步骤（控制台侧）

1. GitHub 新建仓库（可公开，仓库内无任何密钥），把本目录推上去。
2. Supabase → New Project（Free，区域选离 Render 近的，如 Singapore）→ 记下 Session Pooler 的 Host / User / 密码。
3. Render → New → Blueprint → 选该仓库；在环境变量里填 `PG_*` 和 `BIFROST_ADMIN_PASSWORD` → 部署。
4. 部署成功后访问 `https://<service>.onrender.com`，用管理密码登录 Web UI。
5. Web UI 添加中转站（OpenAI-compatible：Base URL / API Key / 模型映射为统一别名）→ 保存 → 重启验证持久化。
6. Dify 里按验收清单 2~3 接入测试。
