#!/bin/bash
# claude-ctl.sh - Claude Code CLI subAgent wrapper
#
# 统一接口: run | status | result | cancel | cleanup
#
# ── 命令说明 ──────────────────────────────────────────────
#
# run        执行任务（前台等待或后台异步）
#   --task-id <id>              任务 ID（必须指定）
#   --bg                        后台执行，立即返回 PID
#   --permission-mode <mode>    权限模式: acceptEdits | bypassPermissions | default | plan
#   --allowed-tools <tools>     限制可用工具，如 "Bash,Write,Read"
#   --max-turns <n>             限制 Agent 轮次
#   --model <model>             指定模型（如 claude-sonnet-4-6）
#   -- <prompt>                  任务描述（必须放最后）
#
# status     查询任务状态
#   --task-id <id>              查询单个任务
#   --all                       列出所有任务
#
# result     获取任务结果
#   --task-id <id>              提取指定任务的输出结果
#
# cancel     取消后台任务
#   --task-id <id>              终止指定任务的进程
#
# cleanup    清理已完成/失败/取消的任务文件
#
# ── 示例 ─────────────────────────────────────────────────
#
#   # 同步执行
#   bash claude-ctl.sh run --task-id t1 --permission-mode acceptEdits -- "列出当前目录文件"
#
#   # 后台并行派发
#   bash claude-ctl.sh run --task-id a --bg --permission-mode acceptEdits -- "任务A" &
#   bash claude-ctl.sh run --task-id b --bg --permission-mode acceptEdits -- "任务B" &
#   wait
#
#   # 轮询结果
#   bash claude-ctl.sh status --task-id a
#   bash claude-ctl.sh result --task-id a
#
# ── 环境变量 ──────────────────────────────────────────────
#
#   CLAUDE_CTL_TASK_DIR   自定义任务存储目录（默认 /tmp/claude-ctl-tasks）
#
# ── 输出格式 ──────────────────────────────────────────────
#
#   所有命令输出 JSON，便于程序解析:
#   {"task_id":"t1","status":"completed","exit_code":0,"result":"..."}
#   {"task_id":"t1","status":"running","pid":1234,"output":"..."}

set -euo pipefail

# --- Config ---
CLI_NAME="claude"
TASK_DIR="${CLAUDE_CTL_TASK_DIR:-/tmp/claude-ctl-tasks}"
mkdir -p "$TASK_DIR"

# Convert TASK_DIR to Windows-native path for Python (Git Bash on Windows)
TASK_DIR_WIN="$(cygpath -w "$TASK_DIR" 2>/dev/null || echo "$TASK_DIR")"

# --- Python Helper (embedded) ---
# We pass data via environment variables to avoid shell interpolation issues
PY_HELPER='
import json, sys, os

def write_task():
    path = os.environ["CTL_TASK_PATH"]
    data = {
        "task_id": os.environ.get("CTL_TASK_ID", ""),
        "status": os.environ.get("CTL_STATUS", ""),
        "exit_code": int(os.environ.get("CTL_EXIT_CODE", "0")),
        "pid": os.environ.get("CTL_PID", ""),
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)

def extract_result():
    path = os.environ["CTL_OUTPUT_PATH"]
    result_parts = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    result_parts.append(line)
                    continue
                msg_type = obj.get("type", "")
                if msg_type == "result":
                    text = obj.get("result", "")
                    if text:
                        result_parts.append(text)
                elif msg_type == "assistant":
                    content = obj.get("message", {}).get("content", [])
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            result_parts.append(block.get("text", ""))
                elif "content" in obj:
                    content = obj["content"]
                    if isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                result_parts.append(block.get("text", ""))
                    elif isinstance(content, str):
                        result_parts.append(content)
    except Exception:
        try:
            with open(path, encoding="utf-8") as f:
                result_parts.append(f.read())
        except Exception:
            pass
    print("\n".join(result_parts).strip())

def json_encode():
    text = sys.stdin.read()
    print(json.dumps(text, ensure_ascii=False))

def get_field():
    path = os.environ["CTL_TASK_PATH"]
    field = os.environ.get("CTL_FIELD", "status")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        print(data.get(field, ""))
    except Exception:
        print("")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "write_task":
        write_task()
    elif cmd == "extract_result":
        extract_result()
    elif cmd == "json_encode":
        json_encode()
    elif cmd == "get_field":
        get_field()
'

py() {
  python -c "$PY_HELPER" "$@"
}

# --- Path Helpers ---
# Bash paths (for shell operations like cat, rm)
task_file()   { echo "$TASK_DIR/$1.json"; }
output_file() { echo "$TASK_DIR/$1.output"; }
pid_file()    { echo "$TASK_DIR/$1.pid"; }

# Windows-native paths (for Python)
task_file_win()   { echo "$TASK_DIR_WIN\\$1.json"; }
output_file_win() { echo "$TASK_DIR_WIN\\$1.output"; }

# --- Task State ---
write_task() {
  local id="$1" status="$2" exit_code="${3:-0}" pid="${4:-}"
  CTL_TASK_ID="$id" CTL_STATUS="$status" CTL_EXIT_CODE="$exit_code" \
    CTL_PID="$pid" CTL_TASK_PATH="$(task_file_win "$id")" \
    py write_task
}

read_task() {
  local tf
  tf=$(task_file "$1")
  if [[ -f "$tf" ]]; then
    cat "$tf"
  else
    echo "{\"task_id\":\"$1\",\"status\":\"unknown\",\"exit_code\":-1}"
  fi
}

get_task_field() {
  CTL_TASK_PATH="$(task_file_win "$1")" CTL_FIELD="${2:-status}" py get_field
}

extract_result() {
  # Convert path to Windows-native for Python
  local win_path
  win_path="$(cygpath -w "$1" 2>/dev/null || echo "$1")"
  CTL_OUTPUT_PATH="$win_path" py extract_result
}

json_encode() {
  py json_encode
}

# 检测连接/认证错误，发现即终止并提示用户
check_auth_errors() {
  local output_file="$1"
  [[ -f "$output_file" ]] || return 0

  local errors
  errors=$(grep -i -E 'auth|unauthorized|401|403|credentials|no.*key|invalid.*key|login|Reconnecting|connection refused|timeout waiting|unreachable|ECONNREFUSED|ENOTFOUND|expired|billing' "$output_file" 2>/dev/null | head -5)

  if [[ -n "$errors" ]]; then
    local error_json
    error_json=$(echo "$errors" | json_encode)
    echo "{\"error\":\"connection_or_auth_failure\",\"detail\":$error_json,\"action\":\"Please check: 1) ANTHROPIC_API_KEY is set correctly, 2) Run 'claude' to complete login, 3) Network connectivity to Anthropic API\",\"exit_code\":2}"
    return 1
  fi
  return 0
}

# --- Commands ---
cmd_run() {
  local task_id="" bg=false allowed_tools="" permission_mode="" max_turns="" model=""
  local prompt=""

  # Parse options before --
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id)         task_id="$2"; shift 2 ;;
      --bg)              bg=true; shift ;;
      --allowed-tools)   allowed_tools="$2"; shift 2 ;;
      --permission-mode) permission_mode="$2"; shift 2 ;;
      --max-turns)       max_turns="$2"; shift 2 ;;
      --model)           model="$2"; shift 2 ;;
      --)                shift; prompt="$*"; shift $# ;;
      *)                 prompt="$*"; shift $# ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    echo '{"error":"--task-id is required","exit_code":1}'
    return 1
  fi

  if [[ -z "$prompt" ]]; then
    echo '{"error":"prompt is required","exit_code":1}'
    return 1
  fi

  local of
  of=$(output_file "$task_id")

  # Build claude command
  local cmd=( "$CLI_NAME" -p --output-format json )

  # Permission mode (default: acceptEdits)
  cmd+=( --permission-mode "${permission_mode:-acceptEdits}" )

  # Optional: allowed tools
  [[ -n "$allowed_tools" ]] && cmd+=( --allowedTools "$allowed_tools" )

  # Optional: max turns
  [[ -n "$max_turns" ]] && cmd+=( --max-turns "$max_turns" )

  # Optional: model
  [[ -n "$model" ]] && cmd+=( --model "$model" )

  # Append prompt
  cmd+=( -- "$prompt" )

  if $bg; then
    # Background execution
    write_task "$task_id" "running" 0
    (
      "${cmd[@]}" > "$of" 2>&1
      local ec=$?
      write_task "$task_id" "$([[ $ec -eq 0 ]] && echo completed || echo failed)" "$ec"
    ) &
    local bg_pid=$!
    echo "$bg_pid" > "$(pid_file "$task_id")"
    write_task "$task_id" "running" 0 "$bg_pid"

    # 等待短暂时间后检查是否有立即的认证错误
    sleep 3
    if ! check_auth_errors "$of"; then
      kill "$bg_pid" 2>/dev/null || true
      write_task "$task_id" "failed" 2
      check_auth_errors "$of"
      return 1
    fi

    echo "{\"task_id\":\"$task_id\",\"status\":\"running\",\"pid\":$bg_pid,\"output\":\"$of\"}"
  else
    # Foreground execution
    write_task "$task_id" "running" 0
    "${cmd[@]}" > "$of" 2>&1
    local ec=$?

    # 检测连接/认证错误
    if ! check_auth_errors "$of"; then
      write_task "$task_id" "failed" 2
      check_auth_errors "$of"
      return 1
    fi

    local final_status
    final_status=$([[ $ec -eq 0 ]] && echo completed || echo failed)
    write_task "$task_id" "$final_status" "$ec"

    local result
    result=$(extract_result "$of")
    local result_json
    result_json=$(echo "$result" | json_encode)
    echo "{\"task_id\":\"$task_id\",\"status\":\"$final_status\",\"exit_code\":$ec,\"result\":$result_json}"
  fi
}

cmd_status() {
  if [[ "${1:-}" == "--all" ]]; then
    local first=true
    echo -n "["
    for tf in "$TASK_DIR"/*.json; do
      [[ -f "$tf" ]] || continue
      $first || echo -n ","
      first=false
      cat "$tf"
    done
    echo "]"
  else
    local task_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --task-id) task_id="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ -z "$task_id" ]]; then
      echo '{"error":"--task-id is required","exit_code":1}'
      return 1
    fi
    read_task "$task_id"
  fi
}

cmd_result() {
  local task_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$task_id" ]]; then
    echo '{"error":"--task-id is required","exit_code":1}'
    return 1
  fi

  local status
  status=$(get_task_field "$task_id" "status")

  local of
  of=$(output_file "$task_id")
  local result
  result=$(extract_result "$of")
  local result_json
  result_json=$(echo "$result" | json_encode)

  echo "{\"task_id\":\"$task_id\",\"status\":\"$status\",\"result\":$result_json}"
}

cmd_cancel() {
  local task_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$task_id" ]]; then
    echo '{"error":"--task-id is required","exit_code":1}'
    return 1
  fi

  local pf
  pf=$(pid_file "$task_id")
  if [[ -f "$pf" ]]; then
    local pid
    pid=$(cat "$pf")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pf"
  fi

  write_task "$task_id" "cancelled" 1
  echo "{\"task_id\":\"$task_id\",\"status\":\"cancelled\"}"
}

cmd_cleanup() {
  local count=0
  for tf in "$TASK_DIR"/*.json; do
    [[ -f "$tf" ]] || continue
    local tid
    tid=$(basename "$tf" .json)
    local status
    status=$(get_task_field "$tid" "status")

    if [[ "$status" == "completed" || "$status" == "failed" || "$status" == "cancelled" ]]; then
      rm -f "$tf" "$(output_file "$tid")" "$(pid_file "$tid")"
      ((count++)) || true
    fi
  done

  echo "{\"cleaned\":$count}"
}

# --- Main ---
case "${1:-}" in
  run)     shift; cmd_run "$@" ;;
  status)  shift; cmd_status "$@" ;;
  result)  shift; cmd_result "$@" ;;
  cancel)  shift; cmd_cancel "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *)
    echo "Usage: $0 {run|status|result|cancel|cleanup} [options]"
    echo ""
    echo "Commands:"
    echo "  run      --task-id <id> [--bg] [--allowed-tools <tools>] [--permission-mode <mode>] [--max-turns <n>] [--model <model>] [-- <prompt>]"
    echo "  status   --task-id <id> | --all"
    echo "  result   --task-id <id>"
    echo "  cancel   --task-id <id>"
    echo "  cleanup"
    exit 1
    ;;
esac
