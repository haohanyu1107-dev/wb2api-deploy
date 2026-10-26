# workbuddy2api 部署指南（含烧分防护）

[workbuddy2api-panel](https://github.com/linguo2625469/workbuddy2api-panel)（下称 **wb2api**）
把 WorkBuddy（www.workbuddy.ai）的账号积分翻译成 OpenAI 兼容 API + Web 管理面板。
本仓库补充**部署流程**与一套**防烧分配置**（WorkBuddy 积分是真金白银，29/34 个模型
思考关不掉、隐性吃分，手滑一次 x1.25+ 模型就是几十积分）。

```
OpenAI 客户端 ──> wb2api :7863 ──> WorkBuddy 上游
                  │  /v1/chat/completions（含 SSE）
                  │  /panel/ 控制台
                  └─  auths/ 账号凭据 · data/state.json · 烧分防护
```

## 前置条件

- Go 1.22+（源码编译）或 Docker，或直接用上游 Release 二进制
- 一个 WorkBuddy 账号（注册送积分；积分随时间自然回涨）

## 部署步骤

### 1. 获取并编译

```bash
git clone https://github.com/linguo2625469/workbuddy2api-panel.git wb2api-src
cd wb2api-src
go build -o ../wb2api ./cmd/server
```

Docker 用户可直接用仓库自带 `docker-compose.yml`。

### 2. 准备运行目录

```bash
mkdir -p wb2api/run && cd wb2api/run
cp ../config.example.json config.json   # 本仓库的 example 已含防烧分默认值
```

`config.json` 必看字段：

| 字段 | 说明 |
|---|---|
| `listen` | 监听地址，默认 `:7863` |
| `api_key` | **改成你自己的 key**，客户端凭它调用 |
| `auth_dir` | OAuth 凭据目录（`auths/`），**绝不外泄、绝不进 git** |
| `state_file` | 运行状态，`data/state.json` |
| `cooldown` | 上游限流的自动冷却策略 |
| `models.hidden` | 烧分防护：对外隐藏的高倍率模型名单（本仓库预置 12 个） |
| `pool.credit_floor` | 积分保护线（本仓库预置 45，低于此线拒绝高倍率调用） |

### 3. 启动（带防烧分护栏）

```bash
WB_API_KEY=你的key sh start.sh ./run
```

`start.sh` 会：等就绪 → **自动重设 hidden/credit_floor**（这两项历史上重启会丢，
护栏兜底，重设记录写 `run/data/startup-guard.log`）。

### 4. 登录账号（拿凭据）

```bash
# 发起登录，返回 state
curl -s -X POST http://127.0.0.1:7863/panel/api/login/start \
  -H 'Content-Type: application/json' -d '{"realm":"global"}'
# → 用浏览器打开返回的授权链接，登录 WorkBuddy 完成授权
# → 轮询直到成功，凭据自动落盘 auths/*.json
curl -s "http://127.0.0.1:7863/panel/api/login/poll?state=<state>"
```

也可开 `http://127.0.0.1:7863/panel/` 在网页上完成。

### 5. 验证

```bash
sh scripts/verify.sh 7863 你的key
```

四连检查：探活 → 账号健康 + 防护生效 → 高倍率模型泄漏扫描 → 真实推理
（免费档 `global:hy3`，x0 倍率不烧分）。

或手动：

```bash
curl -s -H "Authorization: Bearer <key>" http://127.0.0.1:7863/panel/api/overview
curl -s -H "Authorization: Bearer <key>" http://127.0.0.1:7863/v1/models
curl -s -X POST http://127.0.0.1:7863/v1/chat/completions \
  -H "Authorization: Bearer <key>" -H 'Content-Type: application/json' \
  -d '{"model":"global:hy3","messages":[{"role":"user","content":"hi"}]}'
```

## 注意事项

1. **探活端点是 `/panel/api/overview`，不是 `/health`**（后者 404）。
2. **模型 id 带 `global:` 前缀**：调 `global:hy3`，不是 `hy3`；404/503 瞬回
   先查是不是裸 id。
3. **`deepseek-v4.1-flash` 上游有小时级频控**（HTTP 6004）：wb2api 会自动
   cooldown 并报 `model_blocked`——不是故障，换模型即可。
4. **免费档（x0）**：`hy3`、`deepseek-v4.1-flash`。上游模型阵容会变
   （本仓库 hidden 名单按当时阵容维护），新出现的高倍率模型记得补进
   `models.hidden`。
5. **升级/重启后跑一遍 `verify.sh`**：确认防护重设成功、账号仍健康。
6. `auths/` 里的凭据等价于账号本身：目录权限收紧，别放进任何仓库。

## License

MIT（本仓库的部署脚本与文档；wb2api 本体版权归上游作者，见其仓库 LICENSE）
