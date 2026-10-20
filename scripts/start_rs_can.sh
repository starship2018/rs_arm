#!/usr/bin/env bash
#
# 作用：启动 RS 真机使用的 SocketCAN 接口（默认 can0，1 Mbps）。
#   - 检查接口是否存在，未识别到 USB-CAN 适配器时给出明确提示。
#   - 先 down 再设置 bitrate，随后 up，最后打印链路详情确认状态。
#   - 非 root 运行时通过 sudo 执行 ip 命令。
# 用法：./scripts/start_rs_can.sh [接口名]
#   环境变量 RS_CAN_IFACE / RS_CAN_BITRATE 可覆盖默认接口名与波特率。
#
set -euo pipefail

CAN_IFACE="${1:-${RS_CAN_IFACE:-can0}}"
CAN_BITRATE="${RS_CAN_BITRATE:-1000000}"

log() { echo "[start_rs_can] $*"; }
die() { echo "[start_rs_can] 错误：$*" >&2; exit 1; }

if ! [[ "${CAN_BITRATE}" =~ ^[1-9][0-9]*$ ]]; then
  die "波特率必须为正整数，当前值：${CAN_BITRATE}"
fi

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

"${SUDO[@]}" "${IP_BIN}" link show dev "${CAN_IFACE}" >/dev/null 2>&1 \
  || die "未找到 CAN 接口 ${CAN_IFACE}；请确认 USB-CAN 适配器已插好（可用 ip link 或 dmesg | tail 查看接口名）"

log "配置 ${CAN_IFACE}：bitrate=${CAN_BITRATE}"
"${SUDO[@]}" "${IP_BIN}" link set dev "${CAN_IFACE}" down 2>/dev/null || true
"${SUDO[@]}" "${IP_BIN}" link set dev "${CAN_IFACE}" type can bitrate "${CAN_BITRATE}" \
  || die "设置 ${CAN_IFACE} 的 CAN 参数失败，请确认接口类型与波特率"
"${SUDO[@]}" "${IP_BIN}" link set dev "${CAN_IFACE}" up \
  || die "启动 ${CAN_IFACE} 失败"

"${IP_BIN}" -details link show dev "${CAN_IFACE}"

can_is_up "${CAN_IFACE}" || die "${CAN_IFACE} 未进入 UP 状态，请检查硬件与驱动"

log "${CAN_IFACE} 已启动，bitrate=${CAN_BITRATE}"
