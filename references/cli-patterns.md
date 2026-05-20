# 已知 Agent CLI 的安装与使用参考

> 以下信息仅供快速参考，安装命令和参数可能随版本更新变化，请以各 CLI 官方文档为准。

---

## 1. Claude Code (`claude`)

**来源**: Anthropic 官方
**仓库**: https://github.com/anthropics/claude-code

### 安装

```bash
# 前置要求: Node.js >= 18
npm install -g @anthropic-ai/claude-code
```

### 登录认证

首次运行 `claude` 会引导登录，支持：
- Anthropic API Key（设置环境变量 `ANTHROPIC_API_KEY`）
- Claude Max/Team 订阅登录
- OAuth 浏览器登录

### 核心参数

```
-p, --print                    # 非交互模式，输出到 stdout
--output-format <format>       # text | json | stream-json
--permission-mode <mode>       # acceptEdits | bypassPermissions | default | plan
--allowedTools <tools>         # 显式允许工具，如 "Bash,Write,Read"
--disallowedTools <tools>      # 显式禁用工具
--max-turns <number>           # 限制 Agent 轮次
--model <model>                # 指定模型
--session-id <uuid>            # 指定会话 ID
-c, --continue                 # 继续最近会话
-y, --dangerously-skip-permissions  # 跳过所有权限检查（仅沙箱）
```

### 封装建议

- 默认禁用 Write/Edit/Bash，只允许纯生成
- 需要写文件时用 `--allowedTools "Write,Read"`
- 结果在 JSON 输出的 `type=result` 块中

---

## 2. OpenAI Codex CLI (`codex`)

**来源**: OpenAI 官方
**仓库**: https://github.com/openai/codex

### 安装

```bash
# 方式一: npm
npm install -g @openai/codex

# 方式二: Homebrew (macOS)
brew install --cask codex

# 方式三: 从 GitHub Releases 下载二进制
# https://github.com/openai/codex/releases/latest
# macOS Apple Silicon: codex-aarch64-apple-darwin.tar.gz
# macOS x86_64: codex-x86_64-apple-darwin.tar.gz
# Linux x86_64: codex-x86_64-unknown-linux-musl.tar.gz
# Linux arm64: codex-aarch64-unknown-linux-musl.tar.gz
```

### 登录认证

- 推荐：运行 `codex` 后选择 **Sign in with ChatGPT**（支持 Plus/Pro/Business/Edu/Enterprise）
- 也可使用 API Key：设置 `OPENAI_API_KEY` 环境变量

### 核心参数

```
--model <model>                # 指定模型
--approval-mode <mode>         # auto-edit | full-auto
-q, --quiet                    # 静默模式
```

### 封装建议

- Codex 是 Agent 型，会自主执行命令
- 使用 `--approval-mode` 控制自主程度
- 需要设置 `OPENAI_API_KEY`

---

## 3. Gemini CLI (`gemini`)

**来源**: Google 官方
**仓库**: https://github.com/google-gemini/gemini-cli

### 安装

```bash
# 方式一: npx（无需安装）
npx @google/gemini-cli

# 方式二: npm 全局安装
npm install -g @google/gemini-cli

# 方式三: Homebrew (macOS/Linux)
brew install gemini-cli

# 方式四: MacPorts (macOS)
sudo port install gemini-cli

# 方式五: Anaconda（受限环境）
conda create -y -n gemini_env -c conda-forge nodejs
conda activate gemini_env
npm install -g @google/gemini-cli
```

### 登录认证

- 使用 Google 账号登录（免费额度：60 请求/分钟，1000 请求/天）
- 首次运行 `gemini` 会引导浏览器登录

### 核心参数

```
--model <model>                # 指定 Gemini 模型
-s, --sandbox                  # 沙箱模式
--sandbox-image <image>        # 自定义沙箱镜像
```

### 封装建议

- 内置工具：Google Search、文件操作、Shell 命令、网页抓取
- 支持 MCP 扩展
- 免费额度较高，适合批量任务

---

## 4. OpenCode CLI (`opencode`)

**来源**: sst/opencode
**仓库**: https://github.com/sst/opencode

### 安装

```bash
# npm 全局安装
npm install -g opencode-ai

# 或使用 npx（无需安装）
npx opencode-ai
```

### 登录认证

支持多种 LLM 提供商，通过环境变量设置对应 API Key：
```bash
# OpenAI
export OPENAI_API_KEY=sk-...

# Anthropic
export ANTHROPIC_API_KEY=sk-ant-...

# Google Gemini
export GEMINI_API_KEY=...
```

### 核心参数

```
--model <model>                # 指定模型
--provider <provider>          # 指定 LLM 提供商
```

### 封装建议

- Go 编写，跨平台兼容性好
- 支持 MCP 扩展
- 终端原生 UI，适合嵌入式场景
- 需要对应模型的 API Key

---

## 5. Aider (`aider`)

**来源**: Aider-AI
**仓库**: https://github.com/Aider-AI/aider

### 安装

```bash
# 方式一: pip（推荐）
pip install aider-chat

# 方式二: pipx（隔离环境）
pipx install aider-chat

# 方式三: Homebrew
brew install aider
```

### 登录认证

通过环境变量设置 API Key（按使用的模型）：
```bash
# OpenAI
export OPENAI_API_KEY=sk-...

# Anthropic
export ANTHROPIC_API_KEY=sk-ant-...

# 其他模型按文档配置
```

### 核心参数

```
--model <model>                # 指定模型，如 gpt-4o, claude-3.5-sonnet
--edit-format <format>         # 编辑格式: diff | whole | udiff
--no-git                       # 禁用 git 自动提交
--yes-always                   # 自动确认所有操作
--no-auto-commits              # 禁用自动提交
```

### 封装建议

- Aider 是 Agent 型，擅长代码编辑
- 自动 git 提交，可用 `--no-auto-commits` 关闭
- 支持 100+ 编程语言
- 需要对应模型的 API Key

---

## 6. Crush / OpenCode (`crush`)

**来源**: Charmbracelet（OpenCode 已更名为 Crush）
**仓库**: https://github.com/charmbracelet/crush

### 安装

```bash
# macOS/Linux: Homebrew
brew install charmbracelet/tap/crush

# npm
npm install -g @charmland/crush

# Arch Linux
yay -S crush-bin

# Nix
nix run github:numtide/nix-ai-tools#crush

# FreeBSD
pkg install crush

# Windows: Winget
winget install charmbracelet.crush

# Windows: Scoop
scoop bucket add charm https://github.com/charmbracelet/scoop-bucket.git
scoop install crush
```

### 登录认证

- 支持多种 LLM：OpenAI、Anthropic、Google Gemini、AWS Bedrock、Groq、Azure、OpenRouter
- 通过配置文件或环境变量设置对应 API Key

### 核心参数

```
--model <model>                # 指定模型
--provider <provider>          # 指定 LLM 提供商
```

### 封装建议

- Go 编写，跨平台兼容性好
- 支持 MCP 扩展
- 可中途切换 LLM 模型
- 支持 LSP 集成

---

## 7. CodeBuddy CLI (`codeBuddy`)

**来源**: 自研/内部工具

### 安装

按项目文档安装。

### 登录认证

按项目文档配置。

### 核心参数

```
-p, --print                    # 非交互模式
--output-format <format>       # text | json | stream-json
--permission-mode <mode>       # acceptEdits | bypassPermissions | default | plan
--allowedTools <tools>         # 显式允许工具
--disallowedTools <tools>      # 显式禁用工具
--max-turns <number>           # 限制轮次
--model <model>                # 指定模型
--subagent-permission-mode <mode>  # 子 Agent 权限模式
```

### 封装建议

- Agent 型 CLI，有 LLM 决策能力
- 默认禁用 Write/Edit/Bash，强制输出到 stdout
- 结果在 JSON 输出的 `type=result` 块中
- 支持 `--subagent-permission-mode` 控制子 Agent 权限
