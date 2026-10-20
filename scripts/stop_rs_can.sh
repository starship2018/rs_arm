#!/usr/bin/env bash
#
# 作用：关闭 RS 真机使用的 SocketCAN 接口（默认 can0）。
#   - 接口不存在时视为已关闭，直接返回成功。
#   - 关闭后打印链路状态，便于确认不再有报文收发。
#   - 非 root 运行时通过 sudo 执行 ip 命令。
# 用法：./scripts/stop_rs_can.sh [接口名]
#   环境变量 RS_CAN_IFACE 可覆盖默认接口名。
#
set -euo pipefail

CAN_IFACE="${1:-${RS_CAN_IFACE:-can0}}"

log() { echo "[stop_rs_can] $*"; }
die() { echo "[stop_rs_can] 错误：$*" >&2; exit 1; }

if command -v ip >/dev/null 2>&1; then
  IP_BIN="$(command -v ip)"
elif [[ -x /usr/sbin/ip ]]; then
  IP_BIN=/usr/sbin/ip
else
  die "未找到 ip 命令，请先安装 iproute2"
fi

can_is_up() {
  local header
  header="$("${IP_BIN}" -details link show dev "$1" 2>/dev/null | head -n 1 || true)"
  grep -Eq '<([^>]*,)?UP(,[^>]*)?>' <<<"${header}"
}

SUDO=()
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "需要 root 权限，但系统未安装 sudo"
  SUDO=(sudo)
fi

if ! "${SUDO[@]}" "${IP_BIN}" link show dev "${CAN_IFACE}" >/dev/null 2>&1; then
  log "CAN 接口 ${CAN_IFACE} 不存在，无需关闭"
  exit 0
fi

log "关闭 ${CAN_IFACE}"
"${SUDO[@]}" "${IP_BIN}" link set dev "${CAN_IFACE}" down 2>/dev/null || true

can_is_up "${CAN_IFACE}" && die "${CAN_IFACE} 仍处于 UP 状态，关闭失败"

"${IP_BIN}" -details link show dev "${CAN_IFACE}"
log "${CAN_IFACE} 已关闭"
