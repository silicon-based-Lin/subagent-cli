---
name: subagent-cli
description: |
  将任意 Agent CLI 封装为主 Agent 的可复用 subAgent Tool，支持并行派发任务。
  输入 /subagent-cli 触发完整封装流程（环境检测 → 侦察 → 编写脚本 → 验证）。
---

# SubAgent CLI

将任意 Agent CLI（Claude Code、Codex、OpenCode、CodeBuddy、Gemini、Aider 等）封装为当前主 Agent 的可复用 subAgent Tool。

## 关键词别名

这个命令也适用于以下搜索词或自然语言表达：

- Claude Code subAgent / Claude Code 插件 / Claude Code slash command
- Codex CLI wrapper / Codex CLI 子代理 / Codex subAgent
- OpenCode CLI wrapper / CodeBuddy CLI wrapper / Gemini CLI automation / Aider automation
- 多 Agent 协作 / 多智能体编排 / parallel AI agents / agent orchestration
- 命令行 Agent 封装 / LLM CLI wrapper / JSON task runner

## 触发条件

当用户提到以下内容时触发：
- "把 XX CLI 作为 subAgent"
- "封装 XX CLI"
- "用 XX CLI 执行任务"
- "并行调用 XX CLI"
- 想让多个 Agent CLI 协作完成任务

## 使用方式

输入 `/subagent-cli` 启动完整封装流程，或在对话中自然描述需求。

技能会自动执行：门禁检查 → CLI 侦察 → 编写/复用脚本 → 验证。

详细流程和参数说明见 `SKILL.md`。
