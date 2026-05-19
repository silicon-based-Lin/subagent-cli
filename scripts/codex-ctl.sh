#!/bin/bash
# codex-ctl.sh - Codex CLI subAgent wrapper
#
# 统一接口: run | status | result | cancel | cleanup
#
# ── 命令说明 ──────────────────────────────────────────────
#
# run        执行任务（前台等待或后台异步）
#   --task-id <id>              任务 ID（不指定则自动生成）
#   --bg                        后台执行，立即返回 PID
#   --sandbox <mode>            沙箱模式: read-only | workspace-write | danger-full-access
#   --bypass                    跳过所有审批和沙箱（危险，仅限外部沙箱环境）
#   --model <model>             指定模型（如 o3, o4-mini, gpt-4.1）
#   --workdir <dir>             指定工作目录
#   --skip-git-check            允许在非 Git 仓库中运行
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
#   # 同步执行（只读沙箱）
#   bash codex-ctl.sh run --task-id t1 --sandbox workspace-write -- "列出当前目录文件"
#
#   # 后台并行派发
#   bash codex-ctl.sh run --task-id a --bg --sandbox workspace-write -- "任务A" &
#   bash codex-ctl.sh run --task-id b --bg --sandbox workspace-write -- "任务B" &
#   wait
#
#   # 指定模型
#   bash codex-ctl.sh run --task-id t2 --model o3 --sandbox workspace-write -- "分析代码"
#
#   # 轮询结果
#   bash codex-ctl.sh status --task-id a
#   bash codex-ctl.sh result --task-id a
#
# ── 环境变量 ──────────────────────────────────────────────
#
#   CODEX_CTL_TASK_DIR    自定义任务存储目录（默认系统临时目录/codex-ctl-tasks）
#   OPENAI_API_KEY        OpenAI API Key（Codex 需要）
#
# ── 输出格式 ──────────────────────────────────────────────
#
#   所有命令输出 JSON，便于程序解析:
#   {"task_id":"t1","status":"completed","exit_code":0,"result":"..."}
#   {"task_id":"t1","status":"running","pid":1234,"mode":"background"}

set -euo pipefail

TASK_DIR="${CODEX_CTL_TASK_DIR:-$(python -c 'import tempfile,os; d=os.path.join(tempfile.gettempdir(),"codex-ctl-tasks"); os.makedirs(d,exist_ok=True); print(d)' 2>/dev/null || echo '/tmp/codex-ctl-tasks')}"
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
    echo "{\"error\":\"connection_or_auth_failure\",\"detail\":$error_json,\"action\":\"Please check: 1) OPENAI_API_KEY is set correctly, 2) Run 'codex login' to authenticate, 3) Network connectivity to OpenAI API\",\"exit_code\":2}"
    return 1
  fi
  return 0
}

cmd_run() {
  local task_id="" bg=false sandbox="workspace-write" bypass=false model="" workdir="" skip_git=false prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id)        task_id="$2"; shift 2 ;;
      --bg)             bg=true; shift ;;
      --sandbox)        sandbox="$2"; shift 2 ;;
      --bypass)         bypass=true; shift ;;
      --model)          model="$2"; shift 2 ;;
      --workdir)        workdir="$2"; shift 2 ;;
      --skip-git-check) skip_git=true; shift ;;
      --)               prompt="$2"; shift 2 ;;
      *)                prompt="$1"; shift ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    task_id="codex-$(date +%s)-$RANDOM"
  fi

  if [[ -z "$prompt" ]]; then
    echo '{"error":"no prompt provided","exit_code":1}'
    exit 1
  fi

  local task_file="$TASK_DIR/$task_id"
  local meta_file="$task_file.meta.json"
  local output_file="$task_file.output.txt"
  local result_file="$task_file.result.txt"
  local pid_file="$task_file.pid"

  # 构建命令: codex exec --json -o <result_file>
  local cmd="codex exec --json -o \"$result_file\""
  cmd="$cmd --sandbox $sandbox"

  if $bypass; then
    cmd="$cmd --dangerously-bypass-approvals-and-sandbox"
  fi
  if [[ -n "$model" ]]; then
    cmd="$cmd --model $model"
  fi
  if [[ -n "$workdir" ]]; then
    cmd="$cmd --cd \"$workdir\""
  fi
  if $skip_git; then
    cmd="$cmd --skip-git-repo-check"
  fi

  # 写入元数据
  cat > "$meta_file" <<METAEOF
{"task_id":"$task_id","status":"running","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","prompt":$(echo "$prompt" | json_escape)}
METAEOF

  if $bg; then
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

  # 优先使用 -o 导出的结果文件
  if [[ -f "$result_file" && -s "$result_file" ]]; then
    CBC_OUTPUT_FILE="$result_file" python -c "
import sys, json, os
sys.stdout.reconfigure(encoding='utf-8')
with open(os.environ['CBC_OUTPUT_FILE'], 'r', encoding='utf-8') as f:
    content = f.read().strip()
# 尝试 JSON 解析
try:
    data = json.loads(content)
    if isinstance(data, str):
        print(json.dumps(data))
    else:
        print(json.dumps(data))
    sys.exit(0)
except json.JSONDecodeError:
    pass
print(json.dumps(content))
" 2>/dev/null || echo '""'
    return
  fi

  # 回退: 从 JSONL 输出中提取
  if [[ -f "$output_file" && -s "$output_file" ]]; then
    CBC_OUTPUT_FILE="$output_file" python -c "
import sys, json, os
sys.stdout.reconfigure(encoding='utf-8')
with open(os.environ['CBC_OUTPUT_FILE'], 'r', encoding='utf-8') as f:
    content = f.read()

results = []
for line in content.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        t = obj.get('type', '')
        if t == 'message':
            msg = obj.get('message', {})
            if isinstance(msg, dict):
                for block in msg.get('content', []):
                    if isinstance(block, dict) and block.get('type') == 'text':
                        results.append(block.get('text', ''))
        elif t == 'response_output_text':
            results.append(obj.get('text', ''))
        elif t == 'response_completed':
            # 提取最终响应
            resp = obj.get('response', {})
            if isinstance(resp, dict):
                for block in resp.get('output', []):
                    if isinstance(block, dict) and block.get('type') == 'output_text':
                        for seg in block.get('content', []):
                            if isinstance(seg, dict) and seg.get('type') == 'output_text':
                                results.append(seg.get('text', ''))
    except json.JSONDecodeError:
        continue

if results:
    print(json.dumps('\n'.join(results)))
else:
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

  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "{\"task_id\":\"$task_id\",\"status\":\"running\",\"pid\":$pid}"
      return
    else
      local output_file="$TASK_DIR/$task_id.output.txt"
      local result_file="$TASK_DIR/$task_id.result.txt"
      local exit_code=0
      local status="completed"
      local result
      result=$(extract_result "$output_file" "$result_file")

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
  local result_file="$TASK_DIR/$task_id.result.txt"
  local meta_file="$TASK_DIR/$task_id.meta.json"

  if [[ ! -f "$meta_file" ]]; then
    echo "{\"error\":\"task $task_id not found\",\"exit_code\":1}"
    exit 1
  fi

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
  result=$(extract_result "$output_file" "$result_file")
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
  local cleaned=0
  for meta in "$TASK_DIR"/*.meta.json; do
    [[ -f "$meta" ]] || continue
    local tid
    tid=$(basename "$meta" .meta.json)
    local status
    status=$(python -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null || echo "")
    if [[ "$status" == "completed" || "$status" == "failed" || "$status" == "cancelled" ]]; then
      rm -f "$TASK_DIR/$tid.meta.json" "$TASK_DIR/$tid.output.txt" "$TASK_DIR/$tid.result.txt" "$TASK_DIR/$tid.pid"
      ((cleaned++)) || true
    fi
  done
  echo "{\"cleaned\":$cleaned}"
}

# Main
case "${1:-help}" in
  run)     shift; cmd_run "$@" ;;
  status)  shift; cmd_status "$@" ;;
  result)  shift; cmd_result "$@" ;;
  cancel)  shift; cmd_cancel "$@" ;;
  cleanup) shift; cmd_cleanup "$@" ;;
  *)
    echo "Usage: codex-ctl.sh <command> [options]"
    echo "Commands: run, status, result, cancel, cleanup"
    echo ""
    echo "run:    --task-id <id> [--bg] [--sandbox <mode>] [--bypass] [--model <model>] [--workdir <dir>] [--skip-git-check] -- <prompt>"
    echo "status: --task-id <id> | --all"
    echo "result: --task-id <id>"
    echo "cancel: --task-id <id>"
    echo "cleanup"
    exit 0
    ;;
esac
