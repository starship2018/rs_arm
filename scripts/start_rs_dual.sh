#!/usr/bin/env bash
#
# 作用：同时启动真实 RS 机械臂与 RS 假驱动仿真，并启动 rosbridge。
#   - 真实硬件：bringup.launch.py（can0，命名空间 /rebotarm）。
#   - 仿真镜像：fake_rs_bringup.launch.py（命名空间 /rebotarm_rs）。
#   - 复用或启动 9090 端口的 rosbridge。
# 安全：默认拒绝运行，需设置
#   REBOTARM_RS_HARDWARE_CONFIRM=I_UNDERSTAND_RS_WILL_MOVE。
# 互斥：与 start_rs_sim.sh 共用 /tmp/rebotarm_rs_sim.lock，防止重复启动。
#
set -euo pipefail

if [[ "${REBOTARM_RS_HARDWARE_CONFIRM:-}" != "I_UNDERSTAND_RS_WILL_MOVE" ]]; then
  echo "Dual launch includes the real RS arm and is blocked by default." >&2
  echo "Set REBOTARM_RS_HARDWARE_CONFIRM=I_UNDERSTAND_RS_WILL_MOVE to continue." >&2
  exit 2
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rs_env.sh"

REBOTARM_SIM_LOCK=/tmp/rebotarm_rs_sim.lock
exec 9>"${REBOTARM_SIM_LOCK}"
if ! flock -n 9; then
  echo "An RS simulation or dual launch is already running." >&2
  exit 1
fi

if ! ip link show can0 >/dev/null 2>&1; then
  echo "SocketCAN interface can0 does not exist." >&2
  exit 1
fi

REBOTARM_CHILD_PIDS=()

cleanup() {
  if ((${#REBOTARM_CHILD_PIDS[@]})); then
    # Phase 1: graceful SIGTERM to process groups
    for pid in "${REBOTARM_CHILD_PIDS[@]}"; do
      kill -TERM -- "-${pid}" 2>/dev/null || true
    done
    # Allow time for graceful shutdown
    sleep 2
    # Phase 2: force SIGKILL -- process groups first, then session survivors
    for pid in "${REBOTARM_CHILD_PIDS[@]}"; do
      kill -KILL -- "-${pid}" 2>/dev/null || true
    done
    # Catch nodes that created their own process groups within the session
    for pid in "${REBOTARM_CHILD_PIDS[@]}"; do
      local survivors
      survivors=$(ps -eo pid,sid --no-headers | awk -v sid="$pid" '$2==sid{print $1}' | tr '\n' ' ')
      if [[ -n "${survivors// /}" ]]; then
        kill -KILL ${survivors} 2>/dev/null || true
      fi
    done
    wait "${REBOTARM_CHILD_PIDS[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

setsid ros2 launch rebotarm_bringup bringup.launch.py \
  model:=rs channel:=can0 arm_namespace:=rebotarm \
  ee_frame_id:=gripper_end use_rviz:="${REBOTARM_USE_RVIZ:-false}" 9>&- &
REBOTARM_CHILD_PIDS+=("$!")

setsid ros2 launch rebotarm_bringup fake_rs_bringup.launch.py \
  arm_namespace:=rebotarm_rs use_rviz:=false 9>&- &
REBOTARM_CHILD_PIDS+=("$!")

if command -v ss >/dev/null && ss -ltn | grep -qE '[:.]9090[[:space:]]'; then
  echo "Reusing the rosbridge server already listening on port 9090."
else
  setsid ros2 launch rosbridge_server rosbridge_websocket_launch.xml \
    port:=9090 address:=0.0.0.0 9>&- &
  REBOTARM_CHILD_PIDS+=("$!")
fi

echo "RS hardware namespace: /rebotarm"
echo "RS simulation namespace: /rebotarm_rs"
echo "rosbridge: ws://0.0.0.0:9090"
wait
