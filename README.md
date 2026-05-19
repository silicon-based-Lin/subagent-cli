# subagent-cli

> 将任意 Agent CLI 封装为主 Agent 的可复用 subAgent ，支持并行派发。
> 
> 案例：节省Codex的额度，GPT 5.5 只做规格制定和任务规划，由ClaudeCode+Deepseek V4完成任务实施

![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Agents](https://img.shields.io/badge/Agents-Claude%20%7C%20Codex%20%7C%20OpenCode%20%7C%20CodeBuddy%20%7C%20Gemini%20%7C%20Aider-orange)

---

## WARNING: RISK NOTICE

> **所有 `*-ctl.sh` 脚本会在沙箱或绕过审批的模式下运行 Agent CLI。**
> 
> 这意味着 subAgent 将拥有**文件读写和命令执行权限**，且无需人工确认。
> 
> **请勿在生产环境、含敏感数据的目录、或未经审查的 prompt 下运行。**
> 
> 使用本技能即表示你理解并接受以下风险：
> 
> - subAgent 可能执行非预期的文件操作
> - subAgent 可能访问工作目录外的文件（取决于沙箱配置）
> - 并行任务可能耗尽系统资源或 API 配额
> 
> **建议：始终在 Git 仓库中运行，以便通过 `git diff` 和 `git checkout` 回滚。**

---

## Why Bash Wrapper?

本技能采用 **纯 Bash 脚本** 作为 Agent CLI 的封装层，而非 Python/Node.js SDK 或插件系统。这种写法的核心优势：

### Zero Code Invasion — 零代码入侵

不修改目标 CLI 的任何源码、配置文件或插件。Wrapper 仅通过 CLI 的公开接口（`--help`、`--print`、`--output-format`）交互，目标 CLI 可随时升级、替换、卸载，不影响封装层。

### Universal Compatibility — 通用兼容

Bash 是所有 \*nix 系统和 Git Bash on Windows 的原生运行时。无需安装 Python、Node.js 或任何额外依赖。一个 `.sh` 文件复制到任意项目即可使用。

### Process-level Isolation — 进程级隔离

每个 subAgent 任务是一个独立的 OS 进程（`bash -c "..."`），天然具备：

- 崩溃隔离：单个任务失败不影响其他任务
- 资源可控：通过 `kill` 终止、通过 `timeout` 限制
- 并行安全：多个任务可同时运行，无锁竞争

### Transparent & Auditable — 透明可审计

所有逻辑都在纯文本 Shell 脚本中，没有编译产物、没有二进制依赖、没有黑盒 SDK。任何人都能 `cat *.ctl.sh` 审查完整行为。

### Unified Interface — 统一接口

所有 Agent CLI（Claude、Codex、CodeBuddy、Gemini、Aider...）共享同一套命令模式：

```
run / status / result / cancel / cleanup
```

主 Agent 只需学习一套 API，即可驱动任意底层 CLI。

### JSON-native Output — JSON 原生输出

所有命令输出结构化 JSON，主 Agent 可直接 `json.loads()` 解析，无需正则提取或文本猜测。

### Built-in Safety Net — 内置安全网

所有 `*-ctl.sh` 内置 `check_auth_errors` 函数，自动检测连接/认证错误并立即终止，不会静默重试。

---

## Bash vs MCP — 为什么不用 MCP？

[MCP (Model Context Protocol)](https://modelcontextprotocol.io/) 是 Anthropic 推出的工具协议，允许 Agent 通过标准化接口调用外部工具。理论上可以用 MCP Server 封装 Agent CLI，但 Bash wrapper 在 subAgent 场景下有决定性优势：

### 对比总览

| 维度       | Bash Wrapper (`*-ctl.sh`)   | MCP Server                   |
| -------- | --------------------------- | ---------------------------- |
| **依赖**   | 零依赖（系统自带 Bash）              | 需运行 Node.js/Python 进程        |
| **入侵性**  | 零代码入侵，只调 CLI 公开接口           | 需实现 MCP 协议层，绑定 CLI 内部 API    |
| **并行**   | 原生 `&` + `wait`，进程级隔离       | 需管理多连接、多 session 状态          |
| **调试**   | `cat script.sh` + `bash -x` | 需查 MCP 日志、协议消息、transport 状态  |
| **可移植**  | 复制一个 `.sh` 文件即可             | 需安装依赖、配置 transport、注册 server |
| **升级安全** | CLI 升级不影响 wrapper           | CLI API 变更可能破坏 MCP Server    |
| **适用场景** | 批量派发、CI/CD、并行任务             | 单次工具调用、实时交互                  |

### 详细对比

#### 1. 进程模型：进程 vs 长驻服务

MCP Server 是一个**长驻进程**，通过 stdio 或 SSE 与 Agent 通信。每个 Agent CLI 需要一个独立的 MCP Server 进程，且需要管理连接生命周期。

Bash wrapper 是**一次性进程**——每次调用启动、执行完毕退出。天然适配并行派发：

```bash
# Bash: 10 个并行任务，10 个独立进程，互不干扰
for i in $(seq 1 10); do
  bash claude-ctl.sh run --task-id "t$i" --bg -- "任务 $i" &
done
wait

# MCP: 需要管理 10 个 MCP Server 实例的连接、状态、超时
# 还需处理 Server 崩溃后的连接恢复
```

#### 2. 依赖链：零 vs 重

```
Bash wrapper:    bash → CLI（如 claudeCode、codex）
MCP Server:      Node.js/Python → MCP SDK → transport → CLI
```

MCP 方案引入了额外的 runtime、SDK、transport 层。在 CI/CD 环境、Docker 容器、远程服务器上，Bash wrapper 只需 `bash` 和目标 CLI，无需安装任何额外依赖。

#### 3. 状态管理：无状态 vs 有状态

Bash wrapper 天然**无状态**——每个任务是独立进程，任务间无共享状态。任务元数据存储在文件系统（`/tmp/<cli>-ctl-tasks/`），任何时候都可以 `cat` 查看或 `rm` 清理。

MCP Server 是**有状态的**——维护 session、connection、tool registration。Server 崩溃意味着丢失所有活跃状态。

#### 4. 错误处理：进程隔离 vs 协议级错误

```bash
# Bash: 进程崩溃 = 任务失败，其他任务不受影响
bash codex-ctl.sh run --task-id t1 -- "任务" &
PID=$!
# 如果 codex 崩溃，只影响 t1，t2-t10 继续运行
```

MCP Server 崩溃可能导致：

- 与 Agent 的连接中断
- 所有通过该 Server 派发的任务丢失
- 需要重新注册 Server、重建连接

#### 5. 可审计性：纯文本 vs 协议消息

```bash
# 任何人可以审查 wrapper 的完整行为
cat claude-ctl.sh

# 调试：直接看原始输出
cat /tmp/claude-ctl-tasks/t1.output.txt
```

MCP 调试需要：

- 理解 MCP 协议（JSON-RPC 2.0）
- 查看 Server 日志
- 分析 transport 层消息（stdio/SSE）
- 区分 Server 错误和 CLI 错误

#### 6. 适用场景

**选 Bash wrapper 当：**

- 需要并行派发多个 Agent 任务
- 在 CI/CD 或无头环境中运行
- 需要最大可移植性（复制即用）
- 需要进程级隔离和崩溃恢复
- 任务是「发射后不管」模式

**选 MCP 当：**

- 需要实时交互式工具调用
- 需要双向流式通信
- 工具需要向 Agent 回调/通知
- 需要动态注册/注销工具

> **结论**：subAgent 场景的核心需求是「批量派发 + 并行执行 + 结果收集」，Bash wrapper 的无状态进程模型完美匹配。MCP 更适合「单次工具调用 + 实时交互」的场景。

---

## Pre-built Scripts

```
scripts/
├── check_cli.sh        # 检测任意 CLI 是否可用
├── claude-ctl.sh       # Claude Code wrapper
├── codex-ctl.sh        # Codex CLI wrapper
├── opencode-ctl.sh     # OpenCode CLI wrapper
└── codebuddy-ctl.sh    # CodeBuddy CLI wrapper
```

---

## Install

### 方式一：作为 Claude Code 技能安装（推荐）

将整个技能目录放入项目的 `.claude/skills/` 下，Claude Code 会自动识别：

```bash
# 克隆或复制到项目
mkdir -p .claude/skills
cp -r /path/to/subagent-cli .claude/skills/

# 目录结构
.claude/skills/subagent-cli/
├── SKILL.md                    # 技能定义（Claude Code 自动读取）
├── README.md                   # 本文档
├── scripts/
│   ├── check_cli.sh
│   ├── claude-ctl.sh
│   ├── codex-ctl.sh
│   ├── opencode-ctl.sh
│   └── codebuddy-ctl.sh
└── references/
    └── cli-patterns.md
```

安装后，在 Claude Code 对话中输入 `/subagent-cli` 或提到「封装 XX CLI」「用 XX 作为 subAgent」即可触发。

### 方式二：单独复制 wrapper 脚本

只需一个 `.sh` 文件，复制到任意项目即可使用：

```bash
# 复制需要的 wrapper
cp .claude/skills/subagent-cli/scripts/claude-ctl.sh ./

# 直接调用
bash claude-ctl.sh run --task-id test --permission-mode acceptEdits -- "Say hello"
```

### 前置条件

| 条件     | 说明                                                   |
| ------ | ---------------------------------------------------- |
| Bash   | 系统自带（Windows 需 Git Bash）                             |
| 目标 CLI | 对应的 Agent CLI 已安装并登录（见 `references/cli-patterns.md`） |
| Python | 结果提取使用 Python（仅 UTF-8 编码处理）                          |

### 验证安装

```bash
# 检测目标 CLI 是否可用
bash scripts/check_cli.sh claude
bash scripts/check_cli.sh codex
bash scripts/check_cli.sh opencode
bash scripts/check_cli.sh codebuddy

# 跑一个简单任务
bash scripts/claude-ctl.sh run --task-id verify-1 --permission-mode acceptEdits -- "Reply with: OK"
```

---

## Usage

### 在 Claude Code 中触发

```
# 方式 1：斜杠命令
/subagent-cli

# 方式 2：自然语言
"把 Codex CLI 作为 subAgent"
"封装 OpenCode CLI"
```

技能会自动执行门禁检查 → 侦察 → 编写/复用脚本 → 验证的完整流程。

### 技能驱动的多 Agent 协作模式

以下是在 Claude Code 中通过自然语言驱动 subAgent 的典型场景：

#### 单 Agent 任务

```
"用 Codex 帮我审查 src/app.ts 的代码质量"
"让 Claude Code 重构 utils/ 目录，去掉重复代码"
"用 OpenCode 写一个 REST API 的 CRUD 接口"
```

#### 同构并行 — 同一 CLI 多任务分发

```
"并行驱动 3 个 Claude Code subAgent，分别负责：
 - subAgent-1: 编写用户模块的单元测试
 - subAgent-2: 编写订单模块的单元测试
 - subAgent-3: 编写支付模块的单元测试
 全部完成后汇总覆盖率报告"
```

```
"用 5 个 Codex subAgent 并行处理：
 - 分别对 src/auth、src/api、src/db、src/ui、src/utils 五个目录
   进行代码审查并输出各自的改进建议"
```

#### 异构协作 — 不同 CLI 各司其职

```
"驱动多个不同 CLI 作为 subAgent 团队协作完成以下任务：
 - Claude Code: 负责架构设计，输出技术方案文档
 - Codex: 根据技术方案编写核心代码实现
 - CodeBuddy: 对生成的代码进行安全审查
 按任务复杂度分工，最终需要有一个审查验证 subAgent 确认质量"
```

```
"组建一个 4 人 subAgent 团队：
 - 架构师 (Claude Code): 设计数据库 schema 和 API 接口
 - 后端开发 (Codex): 实现 API 逻辑
 - 前端开发 (OpenCode): 编写 React 组件
 - QA 审查 (CodeBuddy): 对所有产出进行代码审查和测试验证
 并行执行，最后由 QA subAgent 汇总审查报告"
```

#### 含审查验证的流水线

```
"用 subAgent 完成一个完整的开发流水线：
 第一阶段（并行）：
   - Codex-1: 编写 feature A 的代码
   - Codex-2: 编写 feature B 的代码
 第二阶段（等第一阶段完成）：
   - Claude Code: 对两个 feature 的代码进行交叉审查
 第三阶段（等第二阶段完成）：
   - CodeBuddy: 运行测试并输出最终质量报告"
```

```
"实现一个「开发 + 验证」的双 subAgent 模式：
 - 开发 Agent (Codex): 实现需求
 - 验证 Agent (Claude Code): 读取开发 Agent 的产出，
   检查功能正确性、边界情况、代码规范，输出 PASS/FAIL
 如果 FAIL，将审查意见反馈给开发 Agent 重新修改"
```

#### 批量处理

```
"用 subAgent 批量处理以下 10 个文件的 TypeScript 迁移：
 每个文件分配一个 Codex subAgent，并行转换，
 最后由一个 Claude Code subAgent 汇总所有变更并检查类型一致性"
```

```
"为以下 6 个微服务分别生成 Dockerfile 和 docker-compose 配置：
 每个服务一个 subAgent 并行处理，最后由审查 subAgent
 检查所有配置的一致性和安全性"

### 在终端中直接调用 wrapper

```bash
# 同步执行（前台等待）
bash claude-ctl.sh run --task-id t1 --permission-mode acceptEdits -- "列出当前目录文件"

# 后台执行（立即返回）
bash codex-ctl.sh run --task-id t2 --bg --sandbox workspace-write --skip-git-check -- "分析代码"

# 查询状态
bash claude-ctl.sh status --task-id t1
bash claude-ctl.sh status --all

# 获取结果
bash codex-ctl.sh result --task-id t2

# 取消任务
bash claude-ctl.sh cancel --task-id t1

# 清理已完成的任务
bash claude-ctl.sh cleanup
```

### 并行派发

```bash
# 同时派发 4 个不同 CLI 的任务
bash claude-ctl.sh    run --task-id a1 --bg --permission-mode acceptEdits -- "任务 A" &
bash codex-ctl.sh     run --task-id b1 --bg --sandbox workspace-write --skip-git-check -- "任务 B" &
bash opencode-ctl.sh  run --task-id c1 --bg --skip-permissions -- "任务 C" &
bash codebuddy-ctl.sh run --task-id d1 --bg --permission-mode bypassPermissions -- "任务 D" &
wait

# 收集结果
bash claude-ctl.sh     result --task-id a1
bash codex-ctl.sh      result --task-id b1
bash opencode-ctl.sh   result --task-id c1
bash codebuddy-ctl.sh  result --task-id d1
```

### 指定模型

```bash
bash claude-ctl.sh    run --task-id t1 --model claude-sonnet-4-6 --permission-mode acceptEdits -- "任务"
bash codex-ctl.sh     run --task-id t2 --model o3 --sandbox workspace-write --skip-git-check -- "任务"
bash opencode-ctl.sh  run --task-id t3 --model anthropic/claude-sonnet-4-6 --skip-permissions -- "任务"
bash codebuddy-ctl.sh run --task-id t4 --model deepseek-v4-pro --permission-mode bypassPermissions -- "任务"
```

### 输出格式

所有命令输出 JSON，便于程序解析：

```json
{"task_id":"t1","status":"completed","exit_code":0,"result":"Hello, World!"}
{"task_id":"t1","status":"running","pid":1234,"mode":"background"}
{"error":"connection_or_auth_failure","detail":"...","action":"Please check API Key..."}
```

---

## CLI Options Reference

### claude-ctl.sh

| 参数                         | 说明                                                       |
| -------------------------- | -------------------------------------------------------- |
| `--task-id <id>`           | 任务 ID（必须）                                                |
| `--bg`                     | 后台执行                                                     |
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `plan` |
| `--allowed-tools <tools>`  | 限制可用工具，如 `"Bash,Write,Read"`                             |
| `--max-turns <n>`          | 限制 Agent 轮次                                              |
| `--model <model>`          | 指定模型                                                     |

### codex-ctl.sh

| 参数                 | 说明                                                     |
| ------------------ | ------------------------------------------------------ |
| `--task-id <id>`   | 任务 ID（必须）                                              |
| `--bg`             | 后台执行                                                   |
| `--sandbox <mode>` | `read-only` / `workspace-write` / `danger-full-access` |
| `--bypass`         | 跳过所有审批和沙箱                                              |
| `--model <model>`  | 指定模型（如 `o3`, `o4-mini`, `gpt-4.1`）                     |
| `--workdir <dir>`  | 指定工作目录                                                 |
| `--skip-git-check` | 允许在非 Git 仓库中运行                                         |

### opencode-ctl.sh

| 参数                         | 说明                                                        |
| -------------------------- | --------------------------------------------------------- |
| `--task-id <id>`           | 任务 ID（不指定则自动生成）                                           |
| `--bg`                     | 后台执行                                                      |
| `--model <provider/model>` | 指定模型，格式 `provider/model`（如 `anthropic/claude-sonnet-4-6`） |
| `--agent <name>`           | 指定 Agent                                                  |
| `--dir <dir>`              | 指定工作目录                                                    |
| `--skip-permissions`       | 自动审批所有权限（危险）                                              |
| `--files <f1,f2>`          | 附加文件（逗号分隔）                                                |
| `--variant <level>`        | 模型变体/推理强度（如 `high`, `max`, `minimal`）                     |

### codebuddy-ctl.sh

| 参数                         | 说明                                                       |
| -------------------------- | -------------------------------------------------------- |
| `--task-id <id>`           | 任务 ID（不指定则自动生成）                                          |
| `--bg`                     | 后台执行                                                     |
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `plan` |
| `--allowed-tools <tools>`  | 限制可用工具                                                   |
| `--max-turns <n>`          | 限制 Agent 轮次                                              |
| `--model <model>`          | 指定模型                                                     |

---

## Auth Error Detection

所有 `*-ctl.sh` 内置 `check_auth_errors`，执行后自动扫描输出中的以下关键词：

```
auth  unauthorized  401  403  credentials  login
Reconnecting  connection refused  timeout waiting
unreachable  ECONNREFUSED  ENOTFOUND  expired  billing
```

匹配到任一关键词时：

1. 立即终止任务（后台任务 kill 进程）
2. 标记任务状态为 `failed`
3. 返回包含修复建议的错误 JSON

```json
{
  "error": "connection_or_auth_failure",
  "detail": "Reconnecting... timeout waiting for child process to exit",
  "action": "Please check: 1) API Key is set correctly, 2) CLI login status, 3) Network connectivity"
}
```

--- 

## Project Structure

```
.claude/skills/subagent-cli/
├── SKILL.md                    # 技能定义（主 Agent 读取）
├── README.md                   # 本文档
├── scripts/
│   ├── check_cli.sh            # CLI 可用性检测
│   ├── claude-ctl.sh           # Claude Code wrapper
│   ├── codex-ctl.sh            # Codex CLI wrapper
│   └── codebuddy-ctl.sh        # CodeBuddy wrapper
└── references/
    └── cli-patterns.md         # 已知 CLI 安装与参数参考
```

---

## Adding a New CLI

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
