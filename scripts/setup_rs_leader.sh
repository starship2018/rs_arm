#!/usr/bin/env bash
#
# 作用：安装并编译 leader 端接口。
#   - 加载 rs_env.sh 中的 ROS 2 / venv 环境。
#   - 安装 requirements-rs-leader.txt 中的 Python 依赖。
#   - 用 colcon 编译 rebotarm_msgs 与 rebotarmcontroller 两个包。
#   - 完成后需重启 RS/Fake 驱动和 rosbridge，并刷新网页控制台。
#
set -euo pipefail
REBOTARM_TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REBOTARM_TASK_ROOT}/scripts/rs_env.sh"
python -m pip install -r "${REBOTARM_TASK_ROOT}/requirements-rs-leader.txt"
cd "${REBOTARM_TASK_ROOT}/rebotarm_ros2_RS"
colcon build --symlink-install --packages-select rebotarm_msgs rebotarmcontroller
echo 'Leader interfaces built. Restart RS/Fake driver and rosbridge; reload the web console.'
