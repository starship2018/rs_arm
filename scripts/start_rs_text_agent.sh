#!/usr/bin/env bash
#
# 作用：启动 RS 文本指令代理，并提供 HTTP 控制面板。
#   - 通过 MCP 连接抓取代理（默认 http://127.0.0.1:8081/mcp）。
#   - HTTP 服务默认监听 0.0.0.0:8082（REBOTARM_AGENT_HTTP_HOST/PORT 可覆盖）。
#   - 以 --yes 自动确认，额外命令行参数会原样传给代理程序。
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rs_env.sh"

export REBOTARM_NAMESPACE="${REBOTARM_NAMESPACE:-rebotarm_rs}"
export REBOTARM_MCP_URL="${REBOTARM_MCP_URL:-http://127.0.0.1:8081/mcp}"

REBOTARM_AGENT_HOST="${REBOTARM_AGENT_HTTP_HOST:-0.0.0.0}"
REBOTARM_AGENT_PORT="${REBOTARM_AGENT_HTTP_PORT:-8082}"

echo "RS text agent: ${REBOTARM_MCP_URL}"
echo "HTTP dashboard: http://${REBOTARM_AGENT_HOST}:${REBOTARM_AGENT_PORT}"

exec python3 -m rebotarm_agent.rebotarm_text_agent \
  --http-server \
  --http-host "${REBOTARM_AGENT_HOST}" \
  --http-port "${REBOTARM_AGENT_PORT}" \
  --yes \
  "$@"
