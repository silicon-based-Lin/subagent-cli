#!/bin/bash
# node-ctl.sh - node CLI subAgent wrapper (auto-generated)
#
# 统一接口: run | status | result | cancel | cleanup
#
# ── 命令说明 ──────────────────────────────────────────────
#
# run        执行任务（前台等待或后台异步）
#   --task-id <id>              任务 ID（不指定则自动生成）
#   --bg                        后台执行，立即返回 PID
#   -- <prompt>                  任务描述（必须放最后）
#
# status     查询任务状态
#   --task-id <id>              查询单个任务
#   --all                       列出所有任务
#
# result     获取任务结果
#   --task-id <id>
#
# cancel     取消后台任务
#   --task-id <id>
#
# cleanup    清理已完成的任务文件

set -euo pipefail

TASK_DIR="${NODE_CTL_TASK_DIR:-$(python -c 'import tempfile,os; d=os.path.join(tempfile.gettempdir(),"node-ctl-tasks"); os.makedirs(d,exist_ok=True); print(d)' 2>/dev/null || echo '/tmp/node-ctl-tasks')}"
mkdir -p "$TASK_DIR"

json_escape() {
  python -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null ||   sed 's/\\\\\\\\/g; s/"/\\"/g; s/\t/\\t/ g' | sed ':a;N;\$!ba;s/\n/\\n/g' | sed 's/^/"/;s/\$//"/'
}

check_auth_errors() {
  local output_file="$1"
  [[ -f "$output_file" ]] || return 0
  local errors
  errors=$(grep -i -E 'auth|unauthorized|401|403|credentials|no.*key|invalid.*key|login|Reconnecting|connection refused|timeout waiting|unreachable|ECONNREFUSED|ENOTFOUND|expired|billing' "$output_file" 2>/dev/null | head -5)
  if [[ -n "$errors" ]]; then
    local error_json
    error_json=$(echo "$errors" | json_escape)
    echo "{\"error\":\"connection_or_auth_failure\",\"detail\":$error_json,\"action\":\"Please check: 1) API Key is set correctly, 2) CLI login status, 3) Network connectivity\",\"exit_code\":2}"
    return 1
  fi
  return 0
}

cmd_run() {
  local task_id="" bg=false prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --bg)      bg=true; shift ;;
      --)        prompt="$2"; shift 2 ;;
      *)         prompt="$1"; shift ;;
    esac
  done

  [[ -z "$task_id" ]] && task_id="node-$(date +%s)-$RANDOM"
  if [[ -z "$prompt" ]]; then
    echo '{"error":"no prompt provided","exit_code":1}'
    exit 1
  fi

  local task_file="$TASK_DIR/$task_id"
  local meta_file="$task_file.meta.json"
  local output_file="$task_file.output.txt"
  local result_file="$task_file.result.txt"
  local pid_file="$task_file.pid"

  # 构建命令
  local cmd="node -p"

  cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"running","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF

  if $bg; then
    bash -c "$cmd -- $(echo "$prompt" | json_escape)" > "$output_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"
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
    bash -c "$cmd -- $(echo "$prompt" | json_escape)" > "$output_file" 2>&1
    local exit_code=$?
    if ! check_auth_errors "$output_file"; then
      cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"failed","exit_code":2,"error":"connection_or_auth_failure","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF
      check_auth_errors "$output_file"
      return 1
    fi
    local status="completed"
    [[ $exit_code -ne 0 ]] && status="failed"
    cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"$status","exit_code":$exit_code,"finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
METAEOF
    local result
    result=$(extract_result "$output_file" "$result_file")
    echo "{\"task_id\":\"$task_id\",\"status\":\"$status\",\"exit_code\":$exit_code,\"result\":$result}"
  fi
}

extract_result() {
  local output_file="$1"
  local result_file="$2"
  if [[ -f "$result_file" && -s "$result_file" ]]; then
    CBC_OUTPUT_FILE="$result_file" python -c "
import sys, json, os
sys.stdout.reconfigure(encoding='utf-8')
with open(os.environ['CBC_OUTPUT_FILE'], 'r', encoding='utf-8') as f:
    content = f.read().strip()
try:
    data = json.loads(content)
    print(json.dumps(data))
    sys.exit(0)
except json.JSONDecodeError:
    pass
print(json.dumps(content))
" 2>/dev/null || echo '""'
    return
  fi
  if [[ -f "$output_file" && -s "$output_file" ]]; then
    CBC_OUTPUT_FILE="$output_file" python -c "
import sys, json, os
sys.stdout.reconfigure(encoding='utf-8')
with open(os.environ['CBC_OUTPUT_FILE'], 'r', encoding='utf-8') as f:
    content = f.read()
data = json.loads(content) if content.strip().startswith(('[','{')) else None
if isinstance(data, list):
    for item in data:
        if isinstance(item, dict) and item.get('type') == 'result':
            print(json.dumps(item.get('result', '')))
            sys.exit(0)
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
for line in content.strip().split('\n'):
    try:
        obj = json.loads(line.strip())
        if isinstance(obj, dict) and obj.get('type') == 'result':
            print(json.dumps(obj.get('result', obj.get('text', ''))))
            sys.exit(0)
    except: continue
print(json.dumps(content[-2000:]))
" 2>/dev/null || echo '""'
    return
  fi
  echo '""'
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
  [[ -z "$task_id" ]] && echo '{"error":"no task_id provided","exit_code":1}' && exit 1
  local meta_file="$TASK_DIR/$task_id.meta.json"
  local pid_file="$TASK_DIR/$task_id.pid"
  [[ ! -f "$meta_file" ]] && echo "{\"error\":\"task $task_id not found\",\"exit_code\":1}" && exit 1
  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "{\"task_id\":\"$task_id\",\"status\":\"running\",\"pid\":$pid}"
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
  [[ -z "$task_id" ]] && echo '{"error":"no task_id provided","exit_code":1}' && exit 1
  local meta_file="$TASK_DIR/$task_id.meta.json"
  [[ ! -f "$meta_file" ]] && echo "{\"error\":\"task $task_id not found\",\"exit_code\":1}" && exit 1
  local pid_file="$TASK_DIR/$task_id.pid"
  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "{\"task_id\":\"$task_id\",\"status\":\"waiting\",\"message\":\"task still running\"}"
      return
    fi
  fi
  local result=$(extract_result "$TASK_DIR/$task_id.output.txt" "$TASK_DIR/$task_id.result.txt")
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
  [[ -z "$task_id" ]] && echo '{"error":"no task_id provided","exit_code":1}' && exit 1
  local pid_file="$TASK_DIR/$task_id.pid"
  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file")
    kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
  echo "{\"task_id\":\"$task_id\",\"status\":\"cancelled\"}"
}

cmd_cleanup() {
  local cleaned=0
  for meta in "$TASK_DIR"/*.meta.json; do
    [[ -f "$meta" ]] || continue
    local tid=$(basename "$meta" .meta.json)
    local st=$(python -c "import json; print(json.load(open(r'$meta')).get('status',''))" 2>/dev/null || echo "")
    if [[ "$st" == "completed" || "$st" == "failed" || "$st" == "cancelled" ]]; then
      rm -f "$TASK_DIR/$tid.meta.json" "$TASK_DIR/$tid.output.txt" "$TASK_DIR/$tid.result.txt" "$TASK_DIR/$tid.pid"
      ((cleaned++)) || true
    fi
  done
  echo "{\"cleaned\":$cleaned}"
}

case "${1:-help}" in
  run)     shift; cmd_run "$@" ;;
  status)  shift; cmd_status "$@" ;;
  result)  shift; cmd_result "$@" ;;
  cancel)  shift; cmd_cancel "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *)       echo "Usage: node-ctl.sh {run|status|result|cancel|cleanup} [options]"; exit 0 ;;
esac
