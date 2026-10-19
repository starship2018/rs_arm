#!/usr/bin/env bash
#
# 作用：启动 MuJoCo 运动学镜像，让仿真模型跟随真实 RS 机械臂显示。
#   - 订阅 /rebotarm/joint_states（可用 REBOTARM_MIRROR_NAMESPACE 覆盖）。
#   - 仅做可视化跟随，不发送力矩、不打开 SocketCAN，因此无需硬件确认。
#   - 需先启动真实 RS 控制器，否则只会给出提示并等待其发布状态。
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rs_env.sh"

REBOTARM_MIRROR_NAMESPACE="${REBOTARM_MIRROR_NAMESPACE:-rebotarm}"

if ! ros2 topic info "/${REBOTARM_MIRROR_NAMESPACE}/joint_states" >/dev/null 2>&1; then
  echo "Warning: /${REBOTARM_MIRROR_NAMESPACE}/joint_states is not visible yet." >&2
  echo "Start the real RS controller first; MuJoCo will begin following once it publishes." >&2
fi

# The MuJoCo wrapper only subscribes to the real JointState topic and never
# sends torque commands or opens SocketCAN, so no hardware-confirm flag is
# required for this display-only follower.
exec ros2 launch rebotarm_mujoco_rs mujoco_rs.launch.py \
  arm_namespace:="${REBOTARM_MIRROR_NAMESPACE}" \
  simulation_mode:=kinematic \
  use_viewer:=true \
  enable_task_tools:=false
