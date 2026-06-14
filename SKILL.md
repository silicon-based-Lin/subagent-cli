---
name: subagent-cli
description: |
  将任意 Agent CLI（ClaudeCode、Codex CLI、OpenCode CLI、CodeBuddy CLI 等）封装为当前主 Agent 的可复用 subAgent Tool。
  当用户提到"把 XX CLI 作为 subAgent"、"封装 XX CLI"、"用 XX CLI 执行任务"、"并行调用 XX CLI"时触发此技能。
  也适用于用户想让多个 Agent CLI 协作完成任务的场景。
---

# SubAgent CLI 技能

将任意 Agent CLI 封装为当前主 Agent 的可复用 Tool，支持并行派发任务。

## 核心流程

整个封装过程分为 7 步，其中前 3 步是必须通过的门禁。

---

### 门禁 0：目标 CLI 确认

用户触发技能时，先判断是否明确指定了目标 CLI。

**判断规则**：用户消息中提到了具体的 CLI 名称（如"用 Claude Code 作为 subAgent"、"封装 Codex CLI"）则视为明确指定，跳过此门禁。

**未明确指定时**，弹出选择框：

> 请选择要封装为 subAgent 的 Agent CLI：
>
> 1. **Claude Code** — Anthropic 官方，Node.js，浏览器登录或 API Key
> 2. **Codex CLI** — OpenAI 官方，Node.js，ChatGPT 登录或 API Key
> 3. **Gemini CLI** — Google 官方，Node.js，Google 账号登录（免费额度）
> 4. **Aider** — Python，支持 100+ 语言，多模型
> 5. **Crush** (原 OpenCode) — Go，Charmbracelet，多 LLM
> 6. **CodeBuddy** — 自研/内部工具
> 7. **其他** — 输入自定义 CLI 名称

用户选择后，记录目标 CLI 名称，进入下一个门禁。

---

### 门禁 0.5：Windows Git Bash 检测

当检测到当前系统为 Windows 时，需确认用户已安装 Git Bash。

**检测方式**：检查 `MSYSTEM` 或 `GIT_BASH` 环境变量，或检查 `uname` 输出是否包含 `MINGW` / `MSYS`。

```bash
uname -s 2>/dev/null | grep -qiE 'MINGW|MSYS' && echo "Git Bash" || echo "Not Git Bash"
```

- **非 Windows** → 跳过此门禁
- **Windows 且 Git Bash 可用** → 继续下一步
- **Windows 但无 Git Bash** → 暂停，询问用户：

> 检测到当前系统为 Windows。subagent-cli 的脚本依赖 Bash 环境，请先安装 Git for Windows：
> https://git-scm.com/download/win
>
> 安装完成后，请在 Git Bash 中重新运行此技能。

用户确认已安装后重新检测。未确认则终止。

---

### 门禁 1：环境检测

在做任何事之前，先确认目标 CLI 是否可用。

```bash
<cli_name> --version
```

- **通过**：记录版本信息，继续下一步
- **未通过**：暂停，询问用户：

> 目标 CLI `<cli_name>` 未安装或不在 PATH 中。
> 是否需要安装？安装后请确保已完成登录认证。

用户确认已安装并登录后，重新检测。未确认则终止。

#### 常见 CLI 安装速查

| CLI | 安装命令 | 登录方式 |
|-----|---------|---------|
| Claude Code | `npm install -g @anthropic-ai/claude-code` | 首次运行引导登录，或设 `ANTHROPIC_API_KEY` |
| Codex CLI | `npm install -g @openai/codex` | ChatGPT 账号登录，或设 `OPENAI_API_KEY` |
| Gemini CLI | `npm install -g @google/gemini-cli` | Google 账号浏览器登录（免费 60 请求/分钟） |
| Crush (原 OpenCode) | `npm install -g @charmland/crush` | 设对应 LLM 提供商的 API Key |
| Aider | `pip install aider-chat` | 设对应模型的 API Key |
| CodeBuddy | 按项目文档安装 | 按项目文档配置 |

详细安装方法和参数说明见 `references/cli-patterns.md`。

---

### 门禁 2：权限确认

subAgent 需要读写文件权限才能正常执行任务。在开始封装前，询问用户：

> 为了让 subAgent 能执行读写操作，需要放开以下权限：
> - 读取文件（Read）
> - 写入文件（Write/Edit）
> - 执行命令（Bash，按需）
>
> 是否同意？

用户确认后，在封装脚本中通过 `--permission-mode` 或 `--allowedTools` 配置权限。

---

### 第 3 步：CLI 侦察（可跳过）

先检查 `scripts/<cli_name>-ctl.sh` 是否已存在：
- **已存在** → 跳过第 3 步和第 4 步，直接进入第 5 步验证
- **不存在** → 执行 `--help` 侦察并编写脚本

读取 `--help` 输出，识别：

1. **子命令列表**：哪些命令对 subAgent 角色有用
2. **输出格式参数**：是否有 `--output-format json`、`--print` 等
3. **权限控制参数**：`--permission-mode`、`--allowedTools`、`--disallowedTools`、`-y` 等
4. **任务管理参数**：`--task-id`、`--session-id`、`--max-turns` 等
5. **CLI 类型判断**：
   - 纯工具型：直接执行，输出结果（如 git、docker）
   - Agent 型：有 LLM 决策，可能自主选择工具（如 claude、codebuddy）

Agent 型 CLI 需要特别注意行为控制（禁用不需要的工具，防止自主行为偏离预期）。

```bash
<cli_name> --help 2>&1
```

---

### 第 4 步：编写封装脚本（仅当预置脚本不存在时）

如果 `scripts/<cli_name>-ctl.sh` 已存在，跳过此步。否则根据第 3 步侦察结果生成脚本：

创建一个 `<cli_name>-ctl.sh` wrapper 脚本，统一接口：

```
<cli_name>-ctl.sh run      --task-id <id> [--bg] [--allowed-tools <tools>] [--permission-mode <mode>] [-- <prompt>]
<cli_name>-ctl.sh status   --task-id <id> | --all
<cli_name>-ctl.sh result   --task-id <id>
<cli_name>-ctl.sh cancel   --task-id <id>
```

#### 关键实现要点

1. **task_id 机制**：每个任务有唯一标识，支持状态追踪和结果提取
2. **同步/异步**：`--bg` 支持后台执行，前台执行自动等待
3. **权限透传**：将 `--allowed-tools` 和 `--permission-mode` 透传给底层 CLI
4. **JSON 输出**：所有命令输出 JSON，便于主 Agent 解析
5. **结果提取**：`result` 命令从原始输出中提取最终结果（支持 JSON 数组和 JSONL 格式）
6. **编码兼容**：Windows 上用 `python -c` 处理 UTF-8，避免 GBK 编码问题

---

### 第 5 步：注册为 Tool

将封装脚本注册为主 Agent 的可调用 Tool。

#### 纯 Tool 模式（推荐）

subAgent 不经过 LLM，直接调用 wrapper 脚本：

```python
import subprocess, json

def <cli_name>_run(prompt, task_id, allowed_tools=None, permission_mode=None):
    args = ["bash", "<cli_name>-ctl.sh", "run", "--task-id", task_id]
    if allowed_tools:
        args.extend(["--allowed-tools", allowed_tools])
    if permission_mode:
        args.extend(["--permission-mode", permission_mode])
    args.extend(["--", prompt])
    result = subprocess.run(args, capture_output=True, timeout=300)
    return json.loads(result.stdout.decode("utf-8"))
```

#### Agent 模式（需要自主判断时）

subAgent 有自己的 LLM，能自主决策：

```python
def <cli_name>_agent(task):
    # 调用 Anthropic API，定义 tools，跑 tool_use 循环
    # 参考 anthropic SDK 文档
    pass
```

---

### 第 6 步：验证与迭代

1. 跑一个简单任务验证端到端流程
2. 检查边界情况：
   - 权限拒绝 → 确认 `--allowed-tools` 配置
   - 超时 → 调整 timeout
   - 空结果 → 检查结果提取逻辑
   - 编码错误 → 确认 UTF-8 处理
3. 验证并行能力：同时派发 2-3 个任务

---

### 端到端验证门禁

当用户要求验证 subAgent 编排能力时，优先使用临时目录和只读/最小权限任务，避免修改真实仓库文件。

#### 环境门禁

先确认所有目标 CLI 都能完成非交互最小对话，而不只是 `--version` 可用：

```bash
codex exec --sandbox read-only --skip-git-repo-check "Reply exactly: CODEX_OK"
claude -p --output-format json --permission-mode acceptEdits -- "Reply exactly: CLAUDE_OK"
```

- 如果 Claude Code 返回 `Not logged in · Please run /login`，说明 Claude 侧未完成登录，不能继续验证 Claude 调 Codex。
- 如果用户通过 npm/nvm 安装 Claude Code，但非交互 shell 中 `claude` 不在 `PATH`，用 `zsh -lic 'command -v claude'` 定位真实路径，或显式把 nvm 的 Node bin 目录加到测试命令的 `PATH`。
- 如果本机没有 `node`/`npm`，但 Codex App 提供 bundled Node，可临时把 bundled Node 加入 `PATH`，不要污染系统全局安装。
- 如果脚本依赖 `python`，但系统只有 `python3`，先显式记录环境缺口；测试时可临时把 Python 3.10+ 软链到临时 `PATH` 中。
- 自动化调用 `codex exec` 时给进程关闭 stdin（例如命令末尾加 `< /dev/null`），避免 Codex 进入 `Reading additional input from stdin...` 后等待输入而不执行后续命令。

#### 双向调用门禁

验证 Codex CLI 与 Claude Code 双向调用时，使用固定字符串和临时目录：

- **Claude Code 调 Codex CLI**：可让 Claude 以 `--permission-mode bypassPermissions` 在临时目录执行 `codex exec --sandbox read-only --skip-git-repo-check "Reply exactly: CODEX_FROM_CLAUDE_OK"`，再检查结果文件。
- **Codex CLI 调 Claude Code**：先确认 Codex 能在非交互任务中实际进入命令执行阶段，再启动 Claude；给 Claude 子进程加 30 秒左右的超时保护，避免 keychain、登录态或 sandbox 环境导致长时间挂起。
- 双向测试只要求基本对话返回，不要让任一子 agent 写真实仓库文件。

#### 并行门禁

验证并行能力时至少同时启动 3 个只读子任务，并检查每个任务都返回唯一标记：

```bash
codex exec --json -o /tmp/a.result.txt --sandbox read-only --skip-git-repo-check "Reply exactly: A_OK" &
codex exec --json -o /tmp/b.result.txt --sandbox read-only --skip-git-repo-check "Reply exactly: B_OK" &
codex exec --json -o /tmp/c.result.txt --sandbox read-only --skip-git-repo-check "Reply exactly: C_OK" &
wait
```

通过标准：

- 3 个进程都退出为 0
- 3 个结果文件都存在
- 每个结果只包含对应的唯一标记

#### Wrapper 误判排查

如果直接调用 CLI 成功，但 `*-ctl.sh` wrapper 失败，先检查 wrapper 自身：

- `check_auth_errors` 不应让普通 warning 触发认证失败；优先匹配明确的错误字段或清晰的认证失败短语。
- 后台任务不能只根据 PID 消失就写成 `completed`，必须记录真实退出码。
- 前台任务在 `set -e` 下要显式捕获非 0 退出码，否则会停留在 `running` 状态。
- `status` 和 `result` 必须读取同一份任务状态文件；在 Unix/macOS 上不要把 `TASK_DIR` 拼成 `"$TASK_DIR_WIN\\$id.json"`，Windows 路径转换只应在 Git Bash/Windows 环境下启用。

---

### SkillOpt-Sleep 优化流程

完成真实验证后，可以用 SkillOpt-Sleep 提炼会话经验，但不要盲目 `adopt`：

```bash
export SKILLOPT_SLEEP_REPO=/path/to/SkillOpt
export PATH="/path/to/python-3.10-plus/bin:$PATH"

bash "$SKILLOPT_SLEEP_REPO/plugins/run-sleep.sh" dry-run --project "$(pwd)"
bash "$SKILLOPT_SLEEP_REPO/plugins/run-sleep.sh" run --project "$(pwd)" --backend codex
bash "$SKILLOPT_SLEEP_REPO/plugins/run-sleep.sh" status --project "$(pwd)"
```

采纳规则：

- 只有 staged report 中 `accepted=true` 且 `edits` 非空时，才考虑 `adopt`。
- `accepted=false` 或 `edits=[]` 时，不要强行应用；改为人工审查测试结果，把可复用门禁补充到本技能。
- SkillOpt 生成的 staging 目录属于中间产物，除非用户要求保留，否则不要提交。

---

## 模式选择指南

| 场景 | 推荐模式 | 原因 |
|------|---------|------|
| 生成文本/代码 | 纯 Tool | 不需要 LLM 决策，直接执行 |
| 需要多步推理 | Agent 模式 | subAgent 需要自主判断中间步骤 |
| 严格控制行为 | 纯 Tool + 禁用工具 | 防止 Agent 自主行为偏离 |
| 并行批量任务 | 纯 Tool | 无额外 API 开销，速度更快 |

## 注意事项

1. **不要给 Agent 型 CLI 开放不需要的权限**：默认禁用 Write/Edit/Bash，按需开放
2. **超时控制**：单个任务设合理 timeout，防止阻塞
3. **并行数限制**：用 `max_workers` 控制，避免资源耗尽
4. **结果提取层**：原始输出可能很长，只提取关键信息给主 Agent
5. **幂等性**：相同 task_id 重复执行应产生合理行为（覆盖或跳过）
6. **连接/认证错误立即终止**：检测到 `auth`、`unauthorized`、`401`、`403`、`timeout`、`connection refused`、`Reconnecting`、`credentials` 等关键词时，立即停止任务，抛出错误并询问用户检查 API Key 或登录状态，不要重试或静默忽略

---

## 预置脚本

`scripts/` 目录下包含可直接使用的封装脚本，各脚本头部有完整用法说明：
- `scripts/check_cli.sh` — 检测任意 Agent CLI 是否可用
- `scripts/claude-ctl.sh` — Claude Code CLI wrapper（run/status/result/cancel/cleanup）
- `scripts/codex-ctl.sh` — Codex CLI wrapper（run/status/result/cancel/cleanup）
- `scripts/opencode-ctl.sh` — OpenCode CLI wrapper（run/status/result/cancel/cleanup）
- `scripts/codebuddy-ctl.sh` — CodeBuddy CLI wrapper（run/status/result/cancel/cleanup）

所有 `*-ctl.sh` 脚本内置 `check_auth_errors`：执行后自动检测 `auth`/`unauthorized`/`401`/`403`/`Reconnecting`/`timeout waiting` 等关键词，发现即终止并返回错误 JSON，提示用户检查 API Key 或登录状态。
