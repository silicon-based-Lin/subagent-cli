#!/bin/bash
# check_cli.sh - 检查 Agent CLI 是否可用
#
# 用法:
#   bash check_cli.sh <cli_name>
#
# 返回:
#   0 - CLI 可用（输出 JSON: status=installed, version, help_available）
#   1 - CLI 未安装或不在 PATH 中
#
# 示例:
#   bash check_cli.sh codebuddy
#   bash check_cli.sh claude
#   bash check_cli.sh codex
#
# 输出格式:
#   {"status":"installed","cli":"codebuddy","version":"2.97.3","help_available":true}
#   {"status":"not_installed","cli":"codex","message":"codex 未安装或不在 PATH 中"}

set -euo pipefail

CLI_NAME="${1:?用法: check_cli.sh <cli_name>}"

# 检查是否在 PATH 中
if ! command -v "$CLI_NAME" &>/dev/null; then
    echo "{\"status\":\"not_installed\",\"cli\":\"$CLI_NAME\",\"message\":\"$CLI_NAME 未安装或不在 PATH 中\"}"
    exit 1
fi

# 获取版本
VERSION=$("$CLI_NAME" --version 2>&1 | head -1) || VERSION="unknown"

# 检查是否有帮助信息（基本可用性）
HELP_OK=$("$CLI_NAME" --help &>/dev/null && echo true || echo false)

echo "{\"status\":\"installed\",\"cli\":\"$CLI_NAME\",\"version\":\"$VERSION\",\"help_available\":$HELP_OK}"
exit 0
