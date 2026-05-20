# subagent-cli

**[English](README.md) | [中文](README.zh-CN.md)**

> 将任意 Agent CLI 封装为主 Agent 的可复用 subAgent，支持并行派发。

![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Agents](https://img.shields.io/badge/Agents-Claude%20%7C%20Codex%20%7C%20OpenCode%20%7C%20CodeBuddy%20%7C%20Gemini%20%7C%20Aider-orange)

---

## 这是什么？

**一句话：让贵的 Agent 当老板，便宜的 Agent 干活。**

| 角色 | 谁干 | 干什么 |
|------|------|--------|
| 老板 (Orchestrator) | Codex / Claude Code / 任意主 Agent | 理解需求、拆任务、验收结果 |
| 打工人 (SubAgent) | Claude Code / DeepSeek / Codex / ... | 并行执行具体编码、测试、审查 |

```
┌─────────────┐
│  主 Agent    │  ← 负责思考、规划、验收（消耗高级模型额度）
│  (老板)      │
└──────┬──────┘
       │ 派发任务
  ┌────┼────┬────┐
  ▼    ▼    ▼    ▼
┌───┐┌───┐┌───┐┌───┐
│ S1││ S2││ S3││ S4│  ← 并行执行（可用便宜模型，可混搭不同 CLI）
└───┘└───┘└───┘└───┘
```

**典型用法：**

- **省 Codex 额度** — GPT-5.5 只做规划和验收，脏活累活全扔给 Claude Code + DeepSeek V4
- **异构团队协作** — 架构师 (Claude) 出方案，开发 (Codex) 写代码，审查 (CodeBuddy) 抓 bug
- **批量处理** — 10 个文件迁移 TypeScript？10 个 subAgent 并行，主 Agent 坐等收货

> **核心价值**：把「思考」和「执行」分离，用高级模型做决策，用低成本模型跑腿。
> 总成本可能只有全用高级模型的 1/5。

---

## 快速开始

```bash
# 1. 检测 CLI 是否可用
bash scripts/check_cli.sh claude

# 2. 跑一个简单任务
bash scripts/claude-ctl.sh run --task-id test-1 --permission-mode acceptEdits -- "Reply with: OK"

# 3. 并行派发
bash scripts/claude-ctl.sh run --task-id a1 --bg --permission-mode acceptEdits -- "任务 A" &
bash scripts/codex-ctl.sh  run --task-id b1 --bg --sandbox workspace-write --skip-git-check -- "任务 B" &
wait
bash scripts/claude-ctl.sh result --task-id a1
bash scripts/codex-ctl.sh  result --task-id b1
```

---

## 安装

<details>
<summary><b>方式一：Claude Code 插件安装（推荐）</b></summary>

```bash
# 添加 marketplace
/plugin marketplace add silicon-based-Lin/subagent-cli

# 从 marketplace 安装
/plugin install subagent-cli@<marketplace-name>
```

安装后自动注册 `/subagent-cli` 斜杠命令和技能触发器。

</details>

<details>
<summary><b>方式二：Codex CLI 插件安装</b></summary>

```bash
# 在 Codex TUI 中
/plugins install subagent-cli

# 或手动克隆到 .agents/skills/
mkdir -p .agents/skills
cp -r /path/to/subagent-cli .agents/skills/subagent-cli
```

Codex 自动发现 `SKILL.md`。整个目录作为一个整体被复制，`scripts/` 和 `references/` 的相对路径保持不变。

</details>

<details>
<summary><b>方式三：Claude Code 技能安装（手动）</b></summary>

```bash
mkdir -p .claude/skills
cp -r /path/to/subagent-cli .claude/skills/subagent-cli
```

</details>

<details>
<summary><b>方式四：单独复制脚本</b></summary>

```bash
cp /path/to/subagent-cli/scripts/claude-ctl.sh ./
bash claude-ctl.sh run --task-id test --permission-mode acceptEdits -- "Hello"
```

</details>

### 前置条件

| 条件 | 说明 |
|------|------|
| Bash | 系统自带（Windows 需 Git Bash） |
| 目标 CLI | 已安装并完成登录认证（见 `references/cli-patterns.md`） |
| Python | 结果提取使用 Python（仅 UTF-8 编码处理） |

---

## 注意事项

> [!CAUTION]
> 所有 `*-ctl.sh` 脚本会在沙箱或绕过审批的模式下运行 Agent CLI。
> subAgent 将拥有**文件读写和命令执行权限**，且无需人工确认。
>
> **请勿在生产环境、含敏感数据的目录、或未经审查的 prompt 下运行。**
>
> 风险：
> - subAgent 可能执行非预期的文件操作
> - subAgent 可能访问工作目录外的文件（取决于沙箱配置）
> - 并行任务可能耗尽系统资源或 API 配额
>
> **建议：始终在 Git 仓库中运行，以便通过 `git diff` 和 `git checkout` 回滚。**

---

## 使用方式

### 在 Agent CLI 中触发

```
# Claude Code 斜杠命令
/subagent-cli

# 自然语言（Claude Code / Codex 均可）
"把 Codex CLI 作为 subAgent"
"封装 OpenCode CLI"
"用 3 个 Claude Code subAgent 并行写测试"
```

### 终端直接调用

```bash
# 同步执行（前台等待）
bash scripts/claude-ctl.sh run --task-id t1 --permission-mode acceptEdits -- "列出当前目录文件"

# 后台执行（立即返回）
bash scripts/codex-ctl.sh run --task-id t2 --bg --sandbox workspace-write --skip-git-check -- "分析代码"

# 查询状态 / 获取结果 / 取消 / 清理
bash scripts/claude-ctl.sh status --task-id t1
bash scripts/codex-ctl.sh result --task-id t2
bash scripts/claude-ctl.sh cancel --task-id t1
bash scripts/claude-ctl.sh cleanup
```

### 指定模型

```bash
bash scripts/claude-ctl.sh    run --task-id t1 --model claude-sonnet-4-6 --permission-mode acceptEdits -- "任务"
bash scripts/codex-ctl.sh     run --task-id t2 --model o3 --sandbox workspace-write --skip-git-check -- "任务"
bash scripts/opencode-ctl.sh  run --task-id t3 --model anthropic/claude-sonnet-4-6 --skip-permissions -- "任务"
```

### 输出格式

所有命令输出 JSON，便于程序解析：

```json
{"task_id":"t1","status":"completed","exit_code":0,"result":"Hello, World!"}
{"task_id":"t1","status":"running","pid":1234,"mode":"background"}
{"error":"connection_or_auth_failure","detail":"...","action":"Please check API Key..."}
```

---

## 多 Agent 协作示例

<details>
<summary><b>同构并行 — 同一 CLI 多任务分发</b></summary>

```
"并行驱动 3 个 Claude Code subAgent，分别负责：
 - subAgent-1: 编写用户模块的单元测试
 - subAgent-2: 编写订单模块的单元测试
 - subAgent-3: 编写支付模块的单元测试
 全部完成后汇总覆盖率报告"
```

</details>

<details>
<summary><b>异构协作 — 不同 CLI 各司其职</b></summary>

```
"组建一个 4 人 subAgent 团队：
 - 架构师 (Claude Code): 设计数据库 schema 和 API 接口
 - 后端开发 (Codex): 实现 API 逻辑
 - 前端开发 (OpenCode): 编写 React 组件
 - QA 审查 (CodeBuddy): 对所有产出进行代码审查和测试验证
 并行执行，最后由 QA subAgent 汇总审查报告"
```

</details>

<details>
<summary><b>含审查验证的流水线</b></summary>

```
"用 subAgent 完成一个完整的开发流水线：
 第一阶段（并行）：Codex-1 编写 feature A，Codex-2 编写 feature B
 第二阶段：Claude Code 对两个 feature 交叉审查
 第三阶段：CodeBuddy 运行测试并输出最终质量报告"
```

</details>

---

## CLI 参数参考

<details>
<summary><b>claude-ctl.sh</b></summary>

| 参数 | 说明 |
|------|------|
| `--task-id <id>` | 任务 ID（必须） |
| `--bg` | 后台执行 |
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `plan` |
| `--allowed-tools <tools>` | 限制可用工具，如 `"Bash,Write,Read"` |
| `--max-turns <n>` | 限制 Agent 轮次 |
| `--model <model>` | 指定模型 |

</details>

<details>
<summary><b>codex-ctl.sh</b></summary>

| 参数 | 说明 |
|------|------|
| `--task-id <id>` | 任务 ID（必须） |
| `--bg` | 后台执行 |
| `--sandbox <mode>` | `read-only` / `workspace-write` / `danger-full-access` |
| `--bypass` | 跳过所有审批和沙箱 |
| `--model <model>` | 指定模型（如 `o3`, `o4-mini`, `gpt-4.1`） |
| `--workdir <dir>` | 指定工作目录 |
| `--skip-git-check` | 允许在非 Git 仓库中运行 |

</details>

<details>
<summary><b>opencode-ctl.sh</b></summary>

| 参数 | 说明 |
|------|------|
| `--task-id <id>` | 任务 ID（不指定则自动生成） |
| `--bg` | 后台执行 |
| `--model <provider/model>` | 指定模型（如 `anthropic/claude-sonnet-4-6`） |
| `--agent <name>` | 指定 Agent |
| `--dir <dir>` | 指定工作目录 |
| `--skip-permissions` | 自动审批所有权限（危险） |
| `--files <f1,f2>` | 附加文件（逗号分隔） |

</details>

<details>
<summary><b>codebuddy-ctl.sh</b></summary>

| 参数 | 说明 |
|------|------|
| `--task-id <id>` | 任务 ID（不指定则自动生成） |
| `--bg` | 后台执行 |
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `plan` |
| `--allowed-tools <tools>` | 限制可用工具 |
| `--max-turns <n>` | 限制 Agent 轮次 |
| `--model <model>` | 指定模型 |

</details>

---

## 设计决策

### 为什么用 Bash？

- **零依赖** — 系统自带 Bash，无需 Python/Node.js
- **零代码入侵** — 不修改目标 CLI 源码，仅通过公开接口交互
- **进程级隔离** — 每个任务独立进程，崩溃互不影响
- **透明可审计** — `cat *.ctl.sh` 即可审查完整行为
- **统一接口** — 所有 CLI 共享 `run / status / result / cancel / cleanup`
- **JSON 原生输出** — 主 Agent 直接解析，无需正则

### 为什么不用 MCP？

subAgent 场景的核心需求是「批量派发 + 并行执行 + 结果收集」，Bash 的无状态进程模型完美匹配。MCP 更适合「单次工具调用 + 实时交互」的场景。

### 认证错误检测

所有 `*-ctl.sh` 内置 `check_auth_errors`，自动扫描输出中的 `auth`、`unauthorized`、`401`、`403`、`timeout`、`ECONNREFUSED` 等关键词。匹配即终止任务，标记为 `failed`，返回包含修复建议的错误 JSON。

---

## 项目结构

```
subagent-cli/
├── .claude-plugin/
│   └── plugin.json             # Claude Code 插件 manifest
├── codex-plugin/
│   └── plugin.json             # Codex CLI 插件 manifest
├── commands/
│   └── subagent-cli.md         # 斜杠命令定义
├── scripts/
│   ├── check_cli.sh            # CLI 可用性检测
│   ├── claude-ctl.sh           # Claude Code wrapper
│   ├── codex-ctl.sh            # Codex CLI wrapper
│   ├── opencode-ctl.sh         # OpenCode wrapper
│   ├── node-ctl.sh             # Node.js wrapper
│   └── codebuddy-ctl.sh        # CodeBuddy wrapper
├── references/
│   └── cli-patterns.md         # 已知 CLI 安装与参数参考
├── SKILL.md                    # 技能定义（所有安装方式共用）
└── README.md
```

---

## 添加新 CLI

封装一个新的 Agent CLI 只需 3 步：

```bash
# 1. 侦察：读取帮助，找到非交互模式和输出格式参数
<cli> --help 2>&1

# 2. 复制模板：以任一现有 *-ctl.sh 为起点
cp scripts/claude-ctl.sh scripts/<cli>-ctl.sh

# 3. 修改：替换 CLI 命令、参数映射、认证检测关键词
```

详细流程见 `SKILL.md` 中的「核心流程」。

---

## License

MIT
