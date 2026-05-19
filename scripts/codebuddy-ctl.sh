#!/bin/bash
# codebuddy-ctl.sh - CodeBuddy CLI subAgent wrapper
#
# 统一接口: run | status | result | cancel | cleanup
#
# ── 命令说明 ──────────────────────────────────────────────
#
# run        执行任务（前台等待或后台异步）
#   --task-id <id>              任务 ID（不指定则自动生成）
#   --bg                        后台执行，立即返回 PID
#   --permission-mode <mode>    权限模式: acceptEdits | bypassPermissions | default | plan
#   --allowed-tools <tools>     限制可用工具，如 "Read,Write,Edit,Bash"
#   --max-turns <n>             限制 Agent 轮次
#   --model <model>             指定模型
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
# cleanup    清理过期任务文件
#   [max_age_seconds]           过期时间，默认 3600 秒
#
# ── 示例 ─────────────────────────────────────────────────
#
#   # 同步执行
#   bash codebuddy-ctl.sh run --task-id t1 --permission-mode bypassPermissions -- "列出当前目录文件"
#
#   # 后台并行派发
#   bash codebuddy-ctl.sh run --task-id a --bg --permission-mode bypassPermissions -- "任务A" &
#   bash codebuddy-ctl.sh run --task-id b --bg --permission-mode bypassPermissions -- "任务B" &
#   wait
#
#   # 轮询结果
#   bash codebuddy-ctl.sh status --task-id a
#   bash codebuddy-ctl.sh result --task-id a
#
#   # 查看所有任务
#   bash codebuddy-ctl.sh status --all
#
# ── 环境变量 ──────────────────────────────────────────────
#
#   CODEBUDDY_TASK_DIR    自定义任务存储目录（默认系统临时目录/codebuddy-tasks）
#
# ── 输出格式 ──────────────────────────────────────────────
#
#   所有命令输出 JSON，便于程序解析:
#   {"task_id":"t1","status":"completed","exit_code":0,"result":"..."}
#   {"task_id":"t1","status":"running","pid":1234,"mode":"background"}

set -euo pipefail

TASK_DIR="${CODEBUDDY_TASK_DIR:-$(python -c 'import tempfile,os; d=os.path.join(tempfile.gettempdir(),"codebuddy-tasks"); os.makedirs(d,exist_ok=True); print(d)' 2>/dev/null || echo '/tmp/codebuddy-tasks')}"
mkdir -p "$TASK_DIR"

json_escape() {
  python -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || \
  sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/ g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/^/"/;s/$/"/'
}

# 检测连接/认证错误，发现即终止并提示用户
check_auth_errors() {
  local output_file="$1"
  [[ -f "$output_file" ]] || return 0

  local errors
  errors=$(grep -i -E 'auth|unauthorized|401|403|credentials|no.*key|invalid.*key|login|Reconnecting|connection refused|timeout waiting|unreachable|ECONNREFUSED|ENOTFOUND' "$output_file" 2>/dev/null | head -5)

  if [[ -n "$errors" ]]; then
    local error_json
    error_json=$(echo "$errors" | json_escape)
    echo "{\"error\":\"connection_or_auth_failure\",\"detail\":$error_json,\"action\":\"Please check: 1) API Key is set correctly, 2) CLI login status, 3) Network connectivity\",\"exit_code\":2}"
    return 1
  fi
  return 0
}

cmd_run() {
  local task_id="" bg=false allowed_tools="" permission_mode="acceptEdits" max_turns="" model="" prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id)       task_id="$2"; shift 2 ;;
      --bg)            bg=true; shift ;;
      --allowed-tools) allowed_tools="$2"; shift 2 ;;
      --permission-mode) permission_mode="$2"; shift 2 ;;
      --max-turns)     max_turns="$2"; shift 2 ;;
      --model)         model="$2"; shift 2 ;;
      --)              prompt="$2"; shift 2 ;;
      *)               prompt="$1"; shift ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    task_id="cbc-$(date +%s)-$RANDOM"
  fi

  if [[ -z "$prompt" ]]; then
    echo '{"error":"no prompt provided","exit_code":1}'
    exit 1
  fi

  local task_file="$TASK_DIR/$task_id"
  local meta_file="$task_file.meta.json"
  local output_file="$task_file.output.txt"
  local pid_file="$task_file.pid"

  # 构建命令
  local cmd="codebuddy -p --output-format json"
  cmd="$cmd --permission-mode $permission_mode"

  if [[ -n "$allowed_tools" ]]; then
    cmd="$cmd --tools \"$allowed_tools\""
  fi
  if [[ -n "$max_turns" ]]; then
    cmd="$cmd --max-turns $max_turns"
  fi
  if [[ -n "$model" ]]; then
    cmd="$cmd --model $model"
  fi

  # 写入元数据
  cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"running","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","prompt":$(echo "$prompt" | json_escape)}
METAEOF

  if $bg; then
    # 后台执行
    bash -c "$cmd -- $(echo "$prompt" | json_escape)" > "$output_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"

    # 等待短暂时间后检查是否有立即的认证错误
    sleep 3
    if ! check_auth_errors "$output_file"; then
      kill "$pid" 2>/dev/null || true
      rm -f "$pid_file"
      cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"failed","exit_code":2,"error":"connection_or_auth_failure","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF
      return 1
    fi

    echo "{\"task_id\":\"$task_id\",\"status\":\"running\",\"pid\":$pid,\"mode\":\"background\"}"
  else
    # 前台执行
    bash -c "$cmd -- $(echo "$prompt" | json_escape)" > "$output_file" 2>&1
    local exit_code=$?

    # 检测连接/认证错误
    if ! check_auth_errors "$output_file"; then
      cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"failed","exit_code":2,"error":"connection_or_auth_failure","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF
      check_auth_errors "$output_file"
      return 1
    fi

    local status="completed"
    [[ $exit_code -ne 0 ]] && status="failed"

    # 更新元数据
    cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"$status","exit_code":$exit_code,"finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF

    # 提取结果
    local result
    result=$(extract_result "$output_file")
    echo "{\"task_id\":\"$task_id\",\"status\":\"$status\",\"exit_code\":$exit_code,\"result\":$result}"
  fi
}

extract_result() {
  local output_file="$1"
  if [[ ! -f "$output_file" ]]; then
    echo '""'
    return
  fi

  # Use env var to pass path safely to Python (avoids backslash escaping issues)
  CBC_OUTPUT_FILE="$output_file" python -c "
import sys, json, os

sys.stdin.reconfigure(encoding='utf-8')
sys.stdout.reconfigure(encoding='utf-8')

with open(os.environ['CBC_OUTPUT_FILE'], 'r', encoding='utf-8') as f:
    content = f.read()

try:
    data = json.loads(content)
    if isinstance(data, list):
        # Find type=result block first (CodeBuddy format)
        for item in data:
            if isinstance(item, dict) and item.get('type') == 'result':
                print(json.dumps(item.get('result', '')))
                sys.exit(0)
        # Fallback: find last assistant message
        for msg in reversed(data):
            if isinstance(msg, dict) and msg.get('role') == 'assistant':
                c = msg.get('content', '')
                if isinstance(c, list):
                    texts = [b.get('text','') for b in c if isinstance(b,dict) and b.get('type')=='text']
                    print(json.dumps('\n'.join(texts)))
                else:
                    print(json.dumps(str(c)))
                sys.exit(0)
        print(json.dumps(''))
        sys.exit(0)
except json.JSONDecodeError:
    pass

# JSONL format
for line in content.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if isinstance(obj, dict) and obj.get('type') == 'result':
            print(json.dumps(obj.get('result', obj.get('text', ''))))
            sys.exit(0)
    except json.JSONDecodeError:
        continue

print(json.dumps(content[-2000:]))
" 2>/dev/null || echo '""'
}

cmd_status() {
  local task_id="" show_all=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --all)     show_all=true; shift ;;
      *)         task_id="$1"; shift ;;
    esac
  done

  if $show_all; then
    echo "["
    local first=true
    for meta in "$TASK_DIR"/*.meta.json; do
      [[ -f "$meta" ]] || continue
      $first || echo ","
      cat "$meta"
      first=false
    done
    echo "]"
    return
  fi

  if [[ -z "$task_id" ]]; then
    echo '{"error":"no task_id provided","exit_code":1}'
    exit 1
  fi

  local meta_file="$TASK_DIR/$task_id.meta.json"
  local pid_file="$TASK_DIR/$task_id.pid"

  if [[ ! -f "$meta_file" ]]; then
    echo "{\"error\":\"task $task_id not found\",\"exit_code\":1}"
    exit 1
  fi

  # 检查后台进程是否仍在运行
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "{\"task_id\":\"$task_id\",\"status\":\"running\",\"pid\":$pid}"
      return
    else
      # 进程已结束，更新状态
      local output_file="$TASK_DIR/$task_id.output.txt"
      local exit_code=0
      local status="completed"
      local result
      result=$(extract_result "$output_file")

      cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"$status","exit_code":$exit_code,"finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF
      rm -f "$pid_file"
      echo "{\"task_id\":\"$task_id\",\"status\":\"$status\",\"exit_code\":$exit_code,\"result\":$result}"
      return
    fi
  fi

  cat "$meta_file"
}

cmd_result() {
  local task_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      *)         task_id="$1"; shift ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    echo '{"error":"no task_id provided","exit_code":1}'
    exit 1
  fi

  local output_file="$TASK_DIR/$task_id.output.txt"
  local meta_file="$TASK_DIR/$task_id.meta.json"

  if [[ ! -f "$meta_file" ]]; then
    echo "{\"error\":\"task $task_id not found\",\"exit_code\":1}"
    exit 1
  fi

  # 如果还在运行，先等待
  local pid_file="$TASK_DIR/$task_id.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "{\"task_id\":\"$task_id\",\"status\":\"waiting\",\"message\":\"task still running, use status to check\"}"
      return
    fi
  fi

  local result
  result=$(extract_result "$output_file")
  echo "{\"task_id\":\"$task_id\",\"result\":$result}"
}

cmd_cancel() {
  local task_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      *)         task_id="$1"; shift ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    echo '{"error":"no task_id provided","exit_code":1}'
    exit 1
  fi

  local pid_file="$TASK_DIR/$task_id.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "{\"task_id\":\"$task_id\",\"status\":\"cancelled\"}"
    else
      echo "{\"task_id\":\"$task_id\",\"status\":\"already_finished\"}"
    fi
    rm -f "$pid_file"
  else
    echo "{\"task_id\":\"$task_id\",\"status\":\"not_found_or_finished\"}"
  fi
}

cmd_cleanup() {
  local max_age="${1:-3600}"
  local count=0
  find "$TASK_DIR" -name "*.meta.json" -mmin +$((max_age/60)) -exec rm -f {} \; 2>/dev/null
  find "$TASK_DIR" -name "*.output.txt" -mmin +$((max_age/60)) -exec rm -f {} \; 2>/dev/null
  find "$TASK_DIR" -name "*.pid" -mmin +$((max_age/60)) -exec rm -f {} \; 2>/dev/null
  echo "{\"status\":\"cleaned\",\"max_age_seconds\":$max_age}"
}

# Main
case "${1:-help}" in
  run)     shift; cmd_run "$@" ;;
  status)  shift; cmd_status "$@" ;;
  result)  shift; cmd_result "$@" ;;
  cancel)  shift; cmd_cancel "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *)
    echo "Usage: codebuddy-ctl.sh <command> [options]"
    echo "Commands: run, status, result, cancel, cleanup"
    echo ""
    echo "run:    --task-id <id> [--bg] [--allowed-tools <tools>] [--permission-mode <mode>] [--max-turns <n>] [--model <model>] -- <prompt>"
    echo "status: --task-id <id> | --all"
    echo "result: --task-id <id>"
    echo "cancel: --task-id <id>"
    echo "cleanup [max_age_seconds]"
    exit 0
    ;;
esac
