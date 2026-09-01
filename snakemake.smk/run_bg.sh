#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LOG_DIR="$SCRIPT_DIR/logs"
PID_FILE="$SCRIPT_DIR/.daemon.pid"
LOG_FILE="$LOG_DIR/daemon.log"

# Define the command to run in the background here
# Example: COMMAND="sleep 3600"
COMMAND="sleep 6"

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

start() {
  if is_running; then
    echo "running: $(cat "$PID_FILE")"
    exit 0
  fi
  if [[ -z "$COMMAND" ]]; then
    echo "COMMAND is not set"
    exit 1
  fi
  mkdir -p "$LOG_DIR"
  nohup bash -c "$COMMAND" >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "started: $(cat "$PID_FILE")"
}

status() {
  if is_running; then
    echo "running: $(cat "$PID_FILE")"
    if [[ -f "$LOG_FILE" ]]; then
      tail -n 20 "$LOG_FILE" || true
    fi
  else
    echo "not running"
  fi
}

stop() {
  if ! is_running; then
    echo "not running"
    return 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "stopped"
}

restart() {
  stop || true
  start
}

logs() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  tail -n 200 -f "$LOG_FILE"
}

cmd="${1:-start}"
case "$cmd" in
  start|status|stop|restart|logs)
    "$cmd"
    ;;
  *)
    echo "usage: $0 {start|status|stop|restart|logs}"
    exit 1
    ;;
esac