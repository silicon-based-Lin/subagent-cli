#!/bin/bash
# opencode-ctl.sh - OpenCode CLI subAgent wrapper
#
# 统一接口: run | status | result | cancel | cleanup
#
# ── 命令说明 ──────────────────────────────────────────────
#
# run        执行任务（前台等待或后台异步）
#   --task-id <id>              任务 ID（不指定则自动生成）
#   --bg                        后台执行，立即返回 PID
#   --model <provider/model>    指定模型（如 openai/gpt-4.1, anthropic/claude-sonnet-4-6）
#   --agent <name>              指定 Agent
#   --dir <dir>                 指定工作目录
#   --skip-permissions          自动审批所有权限（危险）
#   --files <files>             附加文件（逗号分隔）
#   --variant <level>           模型变体/推理强度（如 high, max, minimal）
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
#   bash opencode-ctl.sh run --task-id t1 --skip-permissions -- "列出当前目录文件"
#
#   # 后台并行派发
#   bash opencode-ctl.sh run --task-id a --bg --skip-permissions -- "任务A" &
#   bash opencode-ctl.sh run --task-id b --bg --skip-permissions -- "任务B" &
#   wait
#
#   # 指定模型
#   bash opencode-ctl.sh run --task-id t2 --model anthropic/claude-sonnet-4-6 --skip-permissions -- "分析代码"
#
#   # 附加文件
#   bash opencode-ctl.sh run --task-id t3 --skip-permissions --files src/app.js,src/util.js -- "重构代码"
#
#   # 轮询结果
#   bash opencode-ctl.sh status --task-id a
#   bash opencode-ctl.sh result --task-id a
#
# ── 环境变量 ──────────────────────────────────────────────
#
#   OPENCODE_CTL_TASK_DIR  自定义任务存储目录（默认系统临时目录/opencode-ctl-tasks）
#   OPENAI_API_KEY         OpenAI API Key
#   ANTHROPIC_API_KEY      Anthropic API Key
#   GEMINI_API_KEY         Google Gemini API Key
#
# ── 输出格式 ──────────────────────────────────────────────
#
#   所有命令输出 JSON，便于程序解析:
#   {"task_id":"t1","status":"completed","exit_code":0,"result":"..."}
#   {"task_id":"t1","status":"running","pid":1234,"mode":"background"}

set -euo pipefail

TASK_DIR="${OPENCODE_CTL_TASK_DIR:-$(python -c 'import tempfile,os; d=os.path.join(tempfile.gettempdir(),"opencode-ctl-tasks"); os.makedirs(d,exist_ok=True); print(d)' 2>/dev/null || echo '/tmp/opencode-ctl-tasks')}"
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
  errors=$(grep -i -E 'auth|unauthorized|401|403|credentials|no.*key|invalid.*key|login|Reconnecting|connection refused|timeout waiting|unreachable|ECONNREFUSED|ENOTFOUND|expired|billing|quota|rate.limit' "$output_file" 2>/dev/null | head -5)

  if [[ -n "$errors" ]]; then
    local error_json
    error_json=$(echo "$errors" | json_escape)
    echo "{\"error\":\"connection_or_auth_failure\",\"detail\":$error_json,\"action\":\"Please check: 1) API Key is set correctly (OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY), 2) Run 'opencode providers' to configure, 3) Network connectivity\",\"exit_code\":2}"
    return 1
  fi
  return 0
}

cmd_run() {
  local task_id="" bg=false model="" agent="" workdir="" skip_perms=false files="" variant="" prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id)           task_id="$2"; shift 2 ;;
      --bg)                bg=true; shift ;;
      --model)             model="$2"; shift 2 ;;
      --agent)             agent="$2"; shift 2 ;;
      --dir)               workdir="$2"; shift 2 ;;
      --skip-permissions)  skip_perms=true; shift ;;
      --files)             files="$2"; shift 2 ;;
      --variant)           variant="$2"; shift 2 ;;
      --)                  prompt="$2"; shift 2 ;;
      *)                   prompt="$1"; shift ;;
    esac
  done

  if [[ -z "$task_id" ]]; then
    task_id="oc-$(date +%s)-$RANDOM"
  fi

  if [[ -z "$prompt" ]]; then
    echo '{"error":"no prompt provided","exit_code":1}'
    exit 1
  fi

  local task_file="$TASK_DIR/$task_id"
  local meta_file="$task_file.meta.json"
  local output_file="$task_file.output.txt"
  local pid_file="$task_file.pid"

  # 构建命令: opencode run --format json
  local cmd="opencode run --format json"

  if [[ -n "$model" ]]; then
    cmd="$cmd --model $model"
  fi
  if [[ -n "$agent" ]]; then
    cmd="$cmd --agent $agent"
  fi
  if [[ -n "$workdir" ]]; then
    cmd="$cmd --dir \"$workdir\""
  fi
  if $skip_perms; then
    cmd="$cmd --dangerously-skip-permissions"
  fi
  if [[ -n "$files" ]]; then
    IFS=',' read -ra file_list <<< "$files"
    for f in "${file_list[@]}"; do
      cmd="$cmd --file \"$f\""
    done
  fi
  if [[ -n "$variant" ]]; then
    cmd="$cmd --variant $variant"
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

  CBC_OUTPUT_FILE="$output_file" python -c "
import sys, json, os

sys.stdout.reconfigure(encoding='utf-8')

with open(os.environ['CBC_OUTPUT_FILE'], 'r', encoding='utf-8') as f:
    content = f.read()

results = []

# 尝试 JSONL 解析（opencode run --format json 输出事件流）
for line in content.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        t = obj.get('type', '')

        # opencode JSON 事件格式
        if t == 'assistant' or t == 'message':
            msg = obj.get('message', obj)
            if isinstance(msg, dict):
                c = msg.get('content', '')
                if isinstance(c, list):
                    for block in c:
                        if isinstance(block, dict) and block.get('type') == 'text':
                            results.append(block.get('text', ''))
                elif isinstance(c, str) and c:
                    results.append(c)
        elif t == 'text':
            results.append(obj.get('text', ''))
        elif t == 'content_block_delta':
            delta = obj.get('delta', {})
            if isinstance(delta, dict) and delta.get('type') == 'text_delta':
                results.append(delta.get('text', ''))
        elif t == 'result' or t == 'response':
            r = obj.get('result', obj.get('text', ''))
            if r:
                results.append(str(r))
        elif 'output' in obj:
            results.append(str(obj['output']))
    except json.JSONDecodeError:
        # 非 JSON 行，可能是纯文本输出
        if line and not line.startswith('{'):
            results.append(line)
        continue

if results:
    print(json.dumps('\n'.join(results)))
else:
    # 回退: 返回原始输出的最后 2000 字符
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

  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "{\"task_id\":\"$task_id\",\"status\":\"running\",\"pid\":$pid}"
      return
    else
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
  local cleaned=0
  for meta in "$TASK_DIR"/*.meta.json; do
    [[ -f "$meta" ]] || continue
    local tid
    tid=$(basename "$meta" .meta.json)
    local status
    status=$(python -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null || echo "")
    if [[ "$status" == "completed" || "$status" == "failed" || "$status" == "cancelled" ]]; then
      rm -f "$TASK_DIR/$tid.meta.json" "$TASK_DIR/$tid.output.txt" "$TASK_DIR/$tid.pid"
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
    echo "Usage: opencode-ctl.sh <command> [options]"
    echo "Commands: run, status, result, cancel, cleanup"
    echo ""
    echo "run:    --task-id <id> [--bg] [--model <provider/model>] [--agent <name>] [--dir <dir>] [--skip-permissions] [--files <f1,f2>] [--variant <level>] -- <prompt>"
    echo "status: --task-id <id> | --all"
    echo "result: --task-id <id>"
    echo "cancel: --task-id <id>"
    echo "cleanup"
    exit 0
    ;;
esac
