#!/bin/sh
# wb2api 启动脚本（带烧分防护自动重设）
# 用法: sh start.sh [运行目录]   默认 ./run
# 说明: panel 下发的 models.hidden / pool.credit_floor 历史上不持久化，
#       每次启动后自动重设一次，防手滑打到 x1.25+ 高倍率模型烧分。
set -e

RUN_DIR="${1:-./run}"
BIN="${WB2API_BIN:-./wb2api}"
KEY="${WB_API_KEY:-change-me-local-key}"
LISTEN_PORT="${WB_PORT:-7863}"

# 已在跑则跳过
pgrep -f 'wb2api -config' >/dev/null && { echo "already running"; exit 0; }

mkdir -p "$RUN_DIR/auths" "$RUN_DIR/data"
cd "$RUN_DIR"
nohup "$BIN" -config config.json > server.log 2>&1 &

# 等就绪后重设烧分防护（hidden 12 个高倍率模型 + 积分保护线 45）
(
  for i in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -m 2 -o /dev/null "http://127.0.0.1:${LISTEN_PORT}/panel/api/overview" && break
    sleep 1
  done
  curl -s -m 5 -X POST -H "Authorization: Bearer ${KEY}" -H 'content-type: application/json' \
    -d '{"models":{"hidden":["gpt-6-astra","gpt-6-astra-pro","gpt-6-sol-pro","gpt-5.5","gpt-5.6-sol","gpt-5.6-terra","gpt-5.4","kimi-k3","kimi-k2.8-preview","grok-4.7","primary-model","deep-model"]},"pool":{"credit_floor":45}}' \
    "http://127.0.0.1:${LISTEN_PORT}/panel/api/config" >/dev/null 2>&1 \
    && echo "$(date '+%F %T') hidden/credit_floor reapplied" >> data/startup-guard.log
) &

sleep 2
tail -3 server.log
