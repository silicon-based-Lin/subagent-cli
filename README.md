# subagent-cli

**[English](README.md) | [中文](README.zh-CN.md)**

> Wrap any Agent CLI as a reusable subAgent for your primary Agent, with parallel task dispatch.

![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![Agents](https://img.shields.io/badge/Agents-Claude%20%7C%20Codex%20%7C%20OpenCode%20%7C%20CodeBuddy%20%7C%20Gemini%20%7C%20Aider-orange)

---

## What is this?

**TL;DR: Let expensive Agents think, let cheap Agents work.**

| Role | Who | Does What |
|------|-----|-----------|
| Boss (Orchestrator) | Codex / Claude Code / any primary Agent | Understand requirements, split tasks, review results |
| Worker (SubAgent) | Claude Code / DeepSeek / Codex / ... | Execute coding, testing, review in parallel |

```
┌─────────────┐
│  Primary     │  ← Thinks, plans, reviews (expensive model)
│  Agent       │
└──────┬──────┘
       │ dispatch
  ┌────┼────┬────┐
  ▼    ▼    ▼    ▼
┌───┐┌───┐┌───┐┌───┐
│ S1││ S2││ S3││ S4│  ← Execute in parallel (cheap models, mix & match)
└───┘└───┘└───┘└───┘
```

**Use cases:**

- **Save Codex quota** — GPT-5.5 plans only, Claude Code + DeepSeek V4 do the heavy lifting
- **Heterogeneous teams** — Architect (Claude) designs, Developer (Codex) codes, Reviewer (CodeBuddy) audits
- **Batch processing** — 10 files to migrate? 10 subAgents in parallel, primary Agent collects results

> **Core value**: Separate "thinking" from "doing". Use premium models for decisions, low-cost models for execution. Total cost can be 1/5 of using premium models for everything.

---

## Quick Start

```bash
# 1. Verify CLI availability
bash scripts/check_cli.sh claude

# 2. Run a simple task
bash scripts/claude-ctl.sh run --task-id test-1 --permission-mode acceptEdits -- "Reply with: OK"

# 3. Parallel dispatch
bash scripts/claude-ctl.sh run --task-id a1 --bg --permission-mode acceptEdits -- "Task A" &
bash scripts/codex-ctl.sh  run --task-id b1 --bg --sandbox workspace-write --skip-git-check -- "Task B" &
wait
bash scripts/claude-ctl.sh result --task-id a1
bash scripts/codex-ctl.sh  result --task-id b1
```

---

## Install

<details>
<summary><b>Option 1: Claude Code Plugin (Recommended)</b></summary>

```bash
# Add marketplace
/plugin marketplace add silicon-based-Lin/subagent-cli

# Install from marketplace
/plugin install subagent-cli@<marketplace-name>
```

Automatically registers the `/subagent-cli` slash command and skill triggers.

</details>

<details>
<summary><b>Option 2: Codex CLI Plugin</b></summary>

```bash
# Via Codex TUI
/plugins install subagent-cli

# Or manually clone to .agents/skills/
mkdir -p .agents/skills
cp -r /path/to/subagent-cli .agents/skills/subagent-cli
```

Codex auto-discovers `SKILL.md`. The entire directory is copied as a unit — relative paths to `scripts/` and `references/` remain intact.

</details>

<details>
<summary><b>Option 3: Claude Code Skill (manual)</b></summary>

```bash
mkdir -p .claude/skills
cp -r /path/to/subagent-cli .claude/skills/subagent-cli
```

</details>

<details>
<summary><b>Option 4: Standalone script</b></summary>

```bash
cp /path/to/subagent-cli/scripts/claude-ctl.sh ./
bash claude-ctl.sh run --task-id test --permission-mode acceptEdits -- "Hello"
```

</details>

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| Bash | Built-in on macOS/Linux; Git Bash on Windows |
| Target CLI | Installed and authenticated (see `references/cli-patterns.md`) |
| Python | Used for UTF-8 result extraction |

---

## Warning

> [!CAUTION]
> All `*-ctl.sh` scripts run Agent CLIs in sandbox or permission-bypass mode.
> SubAgents will have **file read/write and command execution permissions** without human confirmation.
>
> **Do NOT run in production, directories with sensitive data, or with unreviewed prompts.**
>
> Risks:
> - SubAgents may perform unexpected file operations
> - SubAgents may access files outside the working directory
> - Parallel tasks may exhaust system resources or API quotas
>
> **Always run inside a Git repo so you can `git diff` and `git checkout` to rollback.**

---

## Usage

### Trigger in Agent CLI

```
# Claude Code slash command
/subagent-cli

# Natural language (works in Claude Code & Codex)
"Use Codex CLI as a subAgent"
"Wrap OpenCode CLI"
"Run 3 Claude Code subAgents in parallel to write tests"
```

### Terminal commands

```bash
# Foreground (sync)
bash scripts/claude-ctl.sh run --task-id t1 --permission-mode acceptEdits -- "List files"

# Background (async)
bash scripts/codex-ctl.sh run --task-id t2 --bg --sandbox workspace-write --skip-git-check -- "Analyze code"

# Status / Result / Cancel / Cleanup
bash scripts/claude-ctl.sh status --task-id t1
bash scripts/codex-ctl.sh result --task-id t2
bash scripts/claude-ctl.sh cancel --task-id t1
bash scripts/claude-ctl.sh cleanup
```

### Specify model

```bash
bash scripts/claude-ctl.sh    run --task-id t1 --model claude-sonnet-4-6 --permission-mode acceptEdits -- "Task"
bash scripts/codex-ctl.sh     run --task-id t2 --model o3 --sandbox workspace-write --skip-git-check -- "Task"
bash scripts/opencode-ctl.sh  run --task-id t3 --model anthropic/claude-sonnet-4-6 --skip-permissions -- "Task"
```

### Output format

All commands output JSON:

```json
{"task_id":"t1","status":"completed","exit_code":0,"result":"Hello, World!"}
{"task_id":"t1","status":"running","pid":1234,"mode":"background"}
{"error":"connection_or_auth_failure","detail":"...","action":"Please check API Key..."}
```

---

## Multi-Agent Examples

<details>
<summary><b>Homogeneous parallel — same CLI, multiple tasks</b></summary>

```
"Run 3 Claude Code subAgents in parallel:
 - subAgent-1: Write unit tests for user module
 - subAgent-2: Write unit tests for order module
 - subAgent-3: Write unit tests for payment module
 Aggregate coverage report when all complete"
```

</details>

<details>
<summary><b>Heterogeneous — different CLIs, different roles</b></summary>

```
"Build a 4-agent team:
 - Architect (Claude Code): Design DB schema and API interfaces
 - Backend (Codex): Implement API logic
 - Frontend (OpenCode): Write React components
 - QA (CodeBuddy): Code review and test verification
 Run in parallel, QA agent produces final report"
```

</details>

<details>
<summary><b>Pipeline with review gates</b></summary>

```
"Complete dev pipeline with subAgents:
 Phase 1 (parallel): Codex-1 writes feature A, Codex-2 writes feature B
 Phase 2: Claude Code cross-reviews both features
 Phase 3: CodeBuddy runs tests and outputs quality report"
```

</details>

---

## CLI Options Reference

<details>
<summary><b>claude-ctl.sh</b></summary>

| Flag | Description |
|------|-------------|
| `--task-id <id>` | Task ID (required) |
| `--bg` | Run in background |
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `plan` |
| `--allowed-tools <tools>` | Restrict tools, e.g. `"Bash,Write,Read"` |
| `--max-turns <n>` | Limit agent turns |
| `--model <model>` | Specify model |

</details>

<details>
<summary><b>codex-ctl.sh</b></summary>

| Flag | Description |
|------|-------------|
| `--task-id <id>` | Task ID (required) |
| `--bg` | Run in background |
| `--sandbox <mode>` | `read-only` / `workspace-write` / `danger-full-access` |
| `--bypass` | Skip all approvals and sandbox |
| `--model <model>` | Specify model (e.g. `o3`, `o4-mini`, `gpt-4.1`) |
| `--workdir <dir>` | Working directory |
| `--skip-git-check` | Allow running outside Git repos |

</details>

<details>
<summary><b>opencode-ctl.sh</b></summary>

| Flag | Description |
|------|-------------|
| `--task-id <id>` | Task ID (auto-generated if omitted) |
| `--bg` | Run in background |
| `--model <provider/model>` | Specify model (e.g. `anthropic/claude-sonnet-4-6`) |
| `--agent <name>` | Specify agent |
| `--dir <dir>` | Working directory |
| `--skip-permissions` | Auto-approve all permissions (dangerous) |
| `--files <f1,f2>` | Attach files (comma-separated) |

</details>

<details>
<summary><b>codebuddy-ctl.sh</b></summary>

| Flag | Description |
|------|-------------|
| `--task-id <id>` | Task ID (auto-generated if omitted) |
| `--bg` | Run in background |
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `plan` |
| `--allowed-tools <tools>` | Restrict tools |
| `--max-turns <n>` | Limit agent turns |
| `--model <model>` | Specify model |

</details>

---

## Design Decisions

### Why Bash?

- **Zero dependencies** — Bash is built-in everywhere (Git Bash on Windows)
- **Zero code invasion** — Only calls CLI public interfaces, never modifies target CLI
- **Process isolation** — Each task is an independent OS process; crashes don't cascade
- **Transparent** — `cat *.ctl.sh` to audit the full behavior
- **Unified interface** — All CLIs share `run / status / result / cancel / cleanup`
- **JSON-native output** — Structured output, no regex parsing needed

### Why not MCP?

SubAgent's core need is "batch dispatch + parallel execution + result collection". Bash's stateless process model is a perfect fit. MCP is better suited for real-time interactive tool calls with bidirectional streaming.

### Auth Error Detection

All `*-ctl.sh` scripts include built-in `check_auth_errors` that scans output for keywords like `auth`, `unauthorized`, `401`, `403`, `timeout`, `ECONNREFUSED`. On match: immediately kill the task, mark as `failed`, return actionable error JSON.

---

## Project Structure

```
subagent-cli/
├── .claude-plugin/
│   └── plugin.json             # Claude Code plugin manifest
├── codex-plugin/
│   └── plugin.json             # Codex CLI plugin manifest
├── commands/
│   └── subagent-cli.md         # Slash command definition
├── scripts/
│   ├── check_cli.sh            # CLI availability check
│   ├── claude-ctl.sh           # Claude Code wrapper
│   ├── codex-ctl.sh            # Codex CLI wrapper
│   ├── opencode-ctl.sh         # OpenCode wrapper
│   ├── node-ctl.sh             # Node.js wrapper
│   └── codebuddy-ctl.sh        # CodeBuddy wrapper
├── references/
│   └── cli-patterns.md         # CLI install & usage reference
├── SKILL.md                    # Skill definition (shared by all install methods)
└── README.md
```

---

## Adding a New CLI

```bash
# 1. Recon: find non-interactive mode and output format flags
<cli> --help 2>&1

# 2. Copy template
cp scripts/claude-ctl.sh scripts/<cli>-ctl.sh

# 3. Modify: replace CLI command, flag mappings, auth error keywords
```

See `SKILL.md` for the full workflow.

---

## License

MIT
