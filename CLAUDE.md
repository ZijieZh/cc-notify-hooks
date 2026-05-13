# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

**cc-notify-hooks** 是 Claude Code 与 Codex CLI 的分级推送通知系统，支持 13 个通知渠道。通过 hook 事件触发多渠道通知，用户响应后自动取消排队中的推送。

Fork 自 `MarioZZJ/cc-notify-hooks`，当前版本已添加 **Windows 原生通知支持**（PowerShell NotifyIcon 气泡提示）。

## 技术栈

- **语言**: Bash
- **依赖**: `jq`（JSON 解析，必需）、`curl`（HTTP 请求）、PowerShell（Windows 通知）
- **集成**: Claude Code hooks（`~/.claude/settings.json`）/ Codex CLI hooks（`~/.codex/hooks.json`）

## 常用命令

```bash
# 安装
bash install.sh                  # 交互式选择目标
bash install.sh claude           # 直接安装到 Claude Code（~/.claude/hooks/）
bash install.sh codex            # 直接安装到 Codex CLI（~/.codex/cc-notify-hooks/）

# 测试
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh <channel>    # 测试单个渠道（如 bark / windows / macos）
bash test_notify.sh list         # 列出已启用渠道及延迟
bash test_notify.sh hook         # 模拟 Claude Code 完整 hook 流程
bash test_notify.sh codex        # 模拟 Codex CLI PermissionRequest 事件

# 插件模式本地运行
claude --plugin-dir .
```

## 架构

### 核心机制（pending-file 取消模型）

```
Hook 事件触发
    │
    ▼
notify.sh ── 清除旧 pending → 创建新 pending_${ID} 标记文件
    │
    │  ┌── 后台子 shell 按 delay 排序执行 ─────────┐
    ├─ │ sleep delay → pending 存在？ → 调用 channel → 发送
    │  │   pending 被清除？ → 立即退出，后续跳过
    │  └────────────────────────────────────────────┘
    │
用户交互 ──→ clear_pending.sh → rm pending_* → 所有排队推送取消
```

- **分级延迟**: 短通知（秒级：macOS/Windows/Telegram/Bark/Pushover/ntfy/Gotify）→ 长通知（分钟级：微信/飞书/钉钉/Slack/Discord）
- **速率限制**: 同类事件默认 10 秒内只推一次（`rate_limit`）
- **过滤规则**: 子 agent 跳过、`stop_hook_active=true` 跳过、`/exit` 后 Stop 静默

### 目录结构

```
scripts/notify.sh              # 主调度器：事件过滤、构建发送队列、后台执行 pipeline
scripts/clear_pending.sh       # 用户交互时清除 ${STATE_DIR}/pending_*
scripts/channels/*.sh          # 13 个渠道实现，每个 ~15-40 行，统一接口 send_<name>(title, body, config_json)
hooks/hooks.json               # Claude Code hook 定义（用 ${CLAUDE_PLUGIN_ROOT} 占位）
hooks/codex-hooks.json         # Codex CLI hook 定义（用相对路径 ./scripts/...）
config/notify.example.json     # 配置模板
install.sh                     # 安装路由（分发到 install/claude.sh 或 install/codex.sh）
install/claude.sh              # 合并 hooks 到 ~/.claude/settings.json
install/codex.sh               # 合并 hooks 到 ~/.codex/hooks.json
test_notify.sh                 # 连通性测试（支持单渠道 / 全量 / hook 模拟）
skills/config/SKILL.md         # 交互式配置 skill（/cc-notify-hooks:config，Claude Code 专属）
.claude-plugin/                # Claude Code 插件清单 + marketplace
.codex-plugin/                 # Codex CLI 插件清单
.agents/plugins/               # Codex CLI marketplace
```

### 渠道脚本接口规范

每个 `scripts/channels/<name>.sh` 定义一个函数：

```bash
send_<name>() {
    local title="$1" body="$2" config="$3"
    # 从 $config（JSON 字符串）用 jq 提取凭证
    # 发送失败用 || true 包裹，不阻断其他渠道
}
```

- `$config` 通过 `jq -c ".channels.\"${name}\""` 传入
- 特殊字段：`macos` 有 `sound`；`windows` 有 `sound`（SystemSounds）和 `events`
- Windows 渠道使用 `powershell.exe -NoProfile -NonInteractive -Command` 调用 NotifyIcon

### 配置查找顺序（`scripts/notify.sh`）

1. `${CC_NOTIFY_CONFIG}`（环境变量覆盖）
2. `${CLAUDE_PLUGIN_DATA}/notify.json`（Claude 插件模式）
3. `~/.codex/cc-notify-hooks/notify.json`（Codex 独立模式）
4. `~/.claude/hooks/notify.json`（Claude 独立模式）

无配置文件时：macOS/Windows 自动降级为系统原生通知（仅 `notification` 事件），其他平台直接退出。

## Claude vs Codex 差异

| | Claude Code | Codex CLI |
|--|-------------|-----------|
| 配置路径 | `~/.claude/settings.json` | `~/.codex/hooks.json` + `~/.codex/config.toml` |
| 字段差异 | `message` | `prompt`（notify.sh 已 fallback） |
| 通知事件 | `Notification` | 无此事件，用 `PermissionRequest` 替代 |
| Hook 定义 | `hooks/hooks.json` | `hooks/codex-hooks.json` |
| 启用 hooks | 默认开启 | 需 `codex_hooks = true` |
| 刷新方式 | `/reload-plugins` | 重启进程 |

## 开发注意事项

- 新增渠道：在 `scripts/channels/` 添加 `<name>.sh` + 在 `config/notify.example.json` 添加模板 + 在 `install/claude.sh` 和 `install/codex.sh` 的 `CHANNEL_DEFS` 添加交互配置项
- 修改安装脚本后：独立安装模式用 `bash install.sh claude` 验证；插件模式用 `claude --plugin-dir .` 验证
- 版本号变更：四份清单同步更新 — `.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、`.codex-plugin/plugin.json`、`.agents/plugins/marketplace.json`
- Windows 安装注意：`jq` 可能不在 PATH 中，需引导用户下载 `jq.exe` 到可用位置
- 调试：`/tmp/claude-hooks-debug.log`（`scripts/notify.sh` 写入）

## 参考

- [Claude Code 插件开发](https://code.claude.com/docs/en/plugins.md)
- [Claude Code 插件参考](https://code.claude.com/docs/en/plugins-reference.md)
- [Codex Hooks 文档](https://developers.openai.com/codex/hooks)
