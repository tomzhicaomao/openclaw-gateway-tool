# OpenClaw 服务切换工具

macOS 上 OpenClaw 服务的开机启动/后台运行管理工具。管理 Main Gateway、Rescue Gateway 和 Node Host 三个服务。

## 功能

一键切换以下服务的状态：

| 服务 | 端口 | launchd 标签 |
|------|------|-------------|
| Main Gateway | 18789 | `ai.openclaw.gateway` |
| Rescue Gateway | 19001 | `ai.openclaw.rescue-gateway` |
| Node Host | — | `ai.openclaw.node` |

- **开启模式** — 设置开机启动（launchd）并立即启动后台进程
- **关闭模式** — 取消开机启动并杀掉后台进程

## 安装

```bash
# 下载脚本
curl -o ~/bin/toggle-openclaw.sh https://raw.githubusercontent.com/tomzhicaomao/openclaw-gateway-tool/main/toggle-openclaw.sh
chmod +x ~/bin/toggle-openclaw.sh

# 下载测试（可选）
curl -o ~/bin/test-toggle-openclaw.bats https://raw.githubusercontent.com/tomzhicaomao/openclaw-gateway-tool/main/test-toggle-openclaw.bats
```

## 使用

### 交互菜单

直接运行进入交互菜单：

```bash
toggle-openclaw.sh
```

```
==========================================
  OpenClaw 服务切换工具
==========================================

  当前状态:
  ────────────────────────────────────────
  [运行中] Main Gateway (端口 18789)

  [运行中] Rescue Gateway (端口 19001)

  [运行中] Node Host
  ────────────────────────────────────────

  请选择操作:

    1) 开启全部
    2) 关闭全部
    3) 仅开启 Main Gateway (18789)
    4) 仅关闭 Main Gateway (18789)
    5) 仅开启 Rescue Gateway (19001)
    6) 仅关闭 Rescue Gateway (19001)
    7) 仅开启 Node Host
    8) 仅关闭 Node Host
    9) 刷新状态
    10) 退出
```

### 命令行参数

```bash
toggle-openclaw.sh on       # 开启全部
toggle-openclaw.sh off      # 关闭全部
toggle-openclaw.sh status   # 查看状态
```

## 工作原理

脚本通过 macOS 的 `launchctl` 管理服务：

| 操作 | 执行的命令 |
|------|-----------|
| 开启 | `launchctl enable` → `launchctl bootstrap` |
| 关闭 | `launchctl bootout` → `launchctl disable` → `kill` 进程 |

管理的 plist 文件：

| 服务 | Plist 文件 |
|------|-----------|
| Main Gateway | `~/Library/LaunchAgents/ai.openclaw.gateway.plist` |
| Rescue Gateway | `~/Library/LaunchAgents/ai.openclaw.rescue-gateway.plist` |
| Node Host | `~/Library/LaunchAgents/ai.openclaw.node.plist` |

开启后 launchd 自动保持进程存活（KeepAlive=true），重启后自动启动（RunAtLoad=true）。

关闭后 launchd 不再管理该服务，下次重启也不会自动拉起。

## 测试

```bash
# 安装 bats
npm install -g bats

# 运行测试
bats ~/bin/test-toggle-openclaw.bats
```

---

## 配套工具：模型配置切换

`configure-openclaw-model.sh` 用于快速切换 OpenClaw 的大模型配置（如切换到 DeepSeek）：

### 安装

```bash
curl -o ~/bin/configure-openclaw-model.sh https://raw.githubusercontent.com/tomzhicaomao/openclaw-gateway-tool/main/configure-openclaw-model.sh
chmod +x ~/bin/configure-openclaw-model.sh
```

### 交互式使用

```bash
configure-openclaw-model.sh
```

按提示输入 API Key 即可完成配置。

### 命令行使用

```bash
# 所有 agent 使用同一模型
configure-openclaw-model.sh \
  --api-key sk-xxx \
  --model deepseek-v4-flash

# 区分主 agent 和普通 agent
configure-openclaw-model.sh \
  --api-key sk-xxx \
  --lead-model deepseek-v4-pro \
  --model deepseek-v4-flash \
  --lead-agent pm01

# 跳过确认，直接执行
configure-openclaw-model.sh --api-key sk-xxx --model deepseek-v4-flash --force
```

### 工作原理

脚本通过 Python3 直接编辑 `~/.openclaw/openclaw.json` 和 `~/.openclaw-rescue/openclaw.json`：

1. 备份原配置文件
2. 添加新的模型 Provider（如 DeepSeek）
3. 更新默认模型和每个 Agent 的模型分配
4. 验证 JSON 合法性
5. 保留原有 Provider 作为 fallback

## 文件

- `toggle-openclaw.sh` — 服务切换主脚本（数组驱动的服务定义，易扩展）
- `configure-openclaw-model.sh` — 大模型配置切换脚本
- `test-toggle-openclaw.bats` — Bats 单元测试（11 个测试用例）
