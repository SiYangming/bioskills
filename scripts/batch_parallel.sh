#!/usr/bin/env bash
# scripts/batch_parallel.sh — 共享：按命令文件并发执行
# 用法：batch_run_cmdfile <cmd_file> <jobs>
# 优先 ParaFly → GNU parallel → xargs
batch_run_cmdfile() {
  local cmd_file="${1:?cmd_file required}"
  local jobs="${2:?jobs required}"
  if [[ ! -s "$cmd_file" ]]; then
    echo "[ERROR] command file empty or missing: $cmd_file" >&2
    return 1
  fi
  echo "[INFO] commands: $(wc -l < "$cmd_file")  jobs=$jobs"
  if command -v ParaFly >/dev/null 2>&1; then
    echo "[INFO] runner=ParaFly"
    ParaFly -c "$cmd_file" -CPU "$jobs"
  elif command -v parallel >/dev/null 2>&1; then
    echo "[INFO] runner=GNU parallel"
    parallel -j "$jobs" --delay 0.2 --bar < "$cmd_file"
  else
    echo "[INFO] runner=xargs"
    xargs -I CMD -P "$jobs" bash -c 'CMD' < "$cmd_file"
  fi
}

# 保守默认并发：未设置时取 min(4, nproc)
batch_default_jobs() {
  local n
  n=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
  if [[ "$n" -gt 4 ]]; then echo 4; else echo "$n"; fi
}
