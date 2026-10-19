#!/usr/bin/env bash
#
# 作用：RS ROS 2 工作空间的首次初始化与完整构建。
#   - 识别 ROS 2 发行版并加载 /opt/ros 环境。
#   - 创建/复用 rebotarm_ros2_RS/.venv，安装硬件与 MuJoCo 的 pip 依赖。
#     venv 不完整时自动重建；缺少 python3-venv 时退回“无 pip 建 venv + 用系统 pip 引导”。
#   - 校验随仓库分发的 reBotArm SDK 和集成 MuJoCo 模型是否齐全。
#   - 拒绝 third_party 下存在嵌套 .git，保证第三方源码由主仓库直接管理。
#   - 可用时执行 rosdep install，最后 colcon build 全部包。
#
set -euo pipefail

REBOTARM_RS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${ROS_DISTRO:-}" ]]; then
  REBOTARM_ROS_DISTRO="${ROS_DISTRO}"
elif [[ -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04) REBOTARM_ROS_DISTRO=humble ;;
    *) REBOTARM_ROS_DISTRO=jazzy ;;
  esac
else
  REBOTARM_ROS_DISTRO=jazzy
fi
REBOTARM_ROS_SETUP="/opt/ros/${REBOTARM_ROS_DISTRO}/setup.bash"
REBOTARM_WS="${REBOTARM_RS_ROOT}/rebotarm_ros2_RS"
REBOTARM_VENV="${REBOTARM_WS}/.venv"
REBOTARM_SDK_DIR="${REBOTARM_WS}/third_party/reBotArm_control_py"
REBOTARM_MUJOCO_MODEL_DIR="${REBOTARM_WS}/src/rebotarm_mujoco_rs/models"

if [[ ! -f "${REBOTARM_ROS_SETUP}" ]]; then
  echo "ROS 2 environment not found: ${REBOTARM_ROS_SETUP}" >&2
  exit 1
fi

REBOTARM_RESTORE_NOUNSET=false
if [[ $- == *u* ]]; then
  REBOTARM_RESTORE_NOUNSET=true
  set +u
fi
source "${REBOTARM_ROS_SETUP}"

REBOTARM_VENV_PYTHON="${REBOTARM_VENV}/bin/python"

# A failed `python3 -m venv` (for example when python3-venv is not installed)
# still leaves bin/python behind, so checking that path alone would skip
# recreation and fail later at "source .venv/bin/activate".
rebotarm_venv_is_ready() {
  [[ -x "${REBOTARM_VENV_PYTHON}" ]] &&
    [[ -f "${REBOTARM_VENV}/bin/activate" ]] &&
    "${REBOTARM_VENV_PYTHON}" -m pip --version >/dev/null 2>&1
}

rebotarm_create_venv() {
  rm -rf "${REBOTARM_VENV}"
  if "/usr/bin/python3" -m venv --system-site-packages "${REBOTARM_VENV}"; then
    return 0
  fi
  echo "Python venv support is incomplete (ensurepip is unavailable)." >&2
  echo "Falling back to a venv without pip and seeding pip from the system one." >&2
  rm -rf "${REBOTARM_VENV}"
  "/usr/bin/python3" -m venv --without-pip --system-site-packages "${REBOTARM_VENV}"
  if ! "${REBOTARM_VENV_PYTHON}" -m pip install --upgrade --ignore-installed pip; then
    echo "Unable to bootstrap pip into ${REBOTARM_VENV}." >&2
    echo "Install the venv support and retry: sudo apt install python3-venv" >&2
    exit 1
  fi
}

if ! rebotarm_venv_is_ready; then
  rebotarm_create_venv
fi
source "${REBOTARM_VENV}/bin/activate"

if [[ "${REBOTARM_RESTORE_NOUNSET}" == true ]]; then
  set -u
fi
unset REBOTARM_RESTORE_NOUNSET

if [[ ! -f "${REBOTARM_SDK_DIR}/reBotArm_control_py/__init__.py" ]]; then
  echo "Vendored reBotArm control SDK is missing: ${REBOTARM_SDK_DIR}" >&2
  exit 1
fi

if [[ ! -f "${REBOTARM_MUJOCO_MODEL_DIR}/rs_arm.xml" ]] ||
   [[ ! -f "${REBOTARM_MUJOCO_MODEL_DIR}/meshes/base_link.STL" ]]; then
  echo "Integrated RS MuJoCo model is missing: ${REBOTARM_MUJOCO_MODEL_DIR}" >&2
  exit 1
fi

if find "${REBOTARM_WS}/third_party" -mindepth 2 -maxdepth 2 -name .git -print -quit | grep -q .; then
  echo "Nested Git metadata found under rebotarm_ros2_RS/third_party." >&2
  echo "Vendor sources must be ordinary files owned by the main repository." >&2
  exit 1
fi

"${REBOTARM_VENV}/bin/python" -m pip install --upgrade pip
"${REBOTARM_VENV}/bin/python" -m pip install \
  -r "${REBOTARM_RS_ROOT}/requirements-rs-hardware.txt" \
  -r "${REBOTARM_RS_ROOT}/requirements-rs-mujoco.txt"

if rosdep db >/dev/null 2>&1; then
  rosdep install --from-paths "${REBOTARM_WS}/src" --ignore-src -r -y
else
  echo "rosdep is not initialized; skipping system dependency installation." >&2
  echo "Recommended: sudo rosdep init && rosdep update" >&2
  echo "Then: rosdep install --from-paths ${REBOTARM_WS}/src --ignore-src -r -y" >&2
fi
cd "${REBOTARM_WS}"
colcon build --symlink-install

# rosdep is the only step that installs ROS packages such as control_msgs and
# tf_transformations.  When it is skipped the build still succeeds while the
# controller fails later at import time, so report the gaps here.
REBOTARM_MISSING_TESTED=()
for dependency in \
  "control_msgs:ros-humble-control-msgs" \
  "tf_transformations:ros-humble-tf-transformations" \
  "xacro:ros-humble-xacro" \
  "moveit_configs_utils:ros-humble-moveit" \
  "rosbridge_server:ros-humble-rosbridge-server"; do
  module="${dependency%%:*}"
  package="${dependency##*:}"
  if ! "${REBOTARM_VENV}/bin/python" -c "import ${module}" >/dev/null 2>&1; then
    REBOTARM_MISSING_TESTED+=("${package}")
  fi
done
if ((${#REBOTARM_MISSING_TESTED[@]})); then
  echo "Missing ROS 2 runtime packages: ${REBOTARM_MISSING_TESTED[*]}" >&2
  echo "ros2 launch will fail until they are installed:" >&2
  echo "  sudo apt install ${REBOTARM_MISSING_TESTED[*]}" >&2
fi

echo "RS ROS 2 workspace ready."
echo "Run: source ${REBOTARM_WS}/install/setup.bash"
