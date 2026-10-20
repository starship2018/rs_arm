#!/usr/bin/env python3
"""读取 RS 各关节电机的驱动板温度（MOS）与转子温度。

温度只存在于驱动层（motorbridge 的 MotorState.t_mos / t_rotor），ROS 的
JointMotorState 和网页都没有该字段，所以本脚本直接用 motorbridge SDK 占用
SocketCAN 读取。据此必须让 reBotArm 控制器处于停止状态，避免两个进程争用
同一路 CAN。

读取方式：打开 RobStride 的主动上报（active report）→ 轮询反馈帧 → 解析温度，
结束后恢复为关闭（控制器本身不依赖主动上报）。

用法：
    ./scripts/read_rs_motor_temps.py
    ./scripts/read_rs_motor_temps.py --json
    ./scripts/read_rs_motor_temps.py --threshold 60 --timeout 3
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import unicodedata
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
SDK_CONFIG_DIR = REPO_ROOT / "rebotarm_ros2_RS" / "third_party" / "reBotArm_control_py" / "config"

CONTROLLER_MARKERS = ("reBotArmController", "bringup.launch.py")


def log(message: str) -> None:
    print(f"[read_rs_motor_temps] {message}", file=sys.stderr)


def die(message: str, code: int = 1) -> "NoReturn":  # noqa: F821
    log(f"错误：{message}")
    raise SystemExit(code)


def running_controller_pids() -> list[int]:
    pids: list[int] = []
    for cmdline in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            raw = cmdline.read_bytes()
        except OSError:
            continue
        text = raw.replace(b"\0", b" ").decode(errors="replace")
        if any(marker in text for marker in CONTROLLER_MARKERS):
            try:
                pids.append(int(cmdline.parent.name))
            except ValueError:
                continue
    return pids


def resolve_config(path: str | None) -> Path:
    if path:
        config = Path(path).expanduser()
        if not config.is_file():
            die(f"配置文件不存在：{config}")
        return config

    global_cfg = SDK_CONFIG_DIR / "rebotarm.yaml"
    if not global_cfg.is_file():
        die(f"未找到 {global_cfg}；请用 --config 指定硬件配置")
    data = yaml.safe_load(global_cfg.read_text()) or {}
    hw_name = data.get("hardware_yaml")
    if not hw_name:
        die(f"{global_cfg} 中没有 hardware_yaml")
    config = Path(hw_name)
    if not config.is_absolute():
        config = SDK_CONFIG_DIR / hw_name
    if not config.is_file():
        die(f"硬件配置不存在：{config}")
    return config


def load_joints(config: Path) -> list[dict]:
    data = yaml.safe_load(config.read_text()) or {}
    joints = data.get("joints") or []
    if not joints:
        die(f"{config} 中没有 joints 定义")
    return joints


def read_temperatures(channel: str, joints: list[dict], timeout: float) -> list[dict]:
    from motorbridge import Controller

    for joint in joints:
        if str(joint.get("vendor", "damiao")).lower() != "robstride":
            die(f"仅支持 RobStride 电机，{joint.get('name')} 的 vendor 为 {joint.get('vendor')}")

    try:
        ctrl = Controller(channel)
    except Exception as exc:  # noqa: BLE001
        die(f"打开 {channel} 失败（{exc}）；先运行 ./scripts/start_rs_can.sh")

    motors = {}
    report_enabled: list = []
    try:
        for joint in joints:
            motors[joint["name"]] = ctrl.add_robstride_motor(
                int(joint["motor_id"]),
                int(joint.get("feedback_id", 0xFD)),
                str(joint.get("model", "rs-00")),
            )

        for motor in motors.values():
            motor.robstride_set_active_report(True)
            report_enabled.append(motor)

        states: dict[str, object] = {}
        deadline = time.monotonic() + max(timeout, 0.2)
        while time.monotonic() < deadline and len(states) < len(motors):
            ctrl.poll_feedback_once()
            for name, motor in motors.items():
                if name in states:
                    continue
                state = motor.get_state()
                if state is not None:
                    states[name] = state
            if len(states) < len(motors):
                time.sleep(0.01)

        rows = []
        for joint in joints:
            name = joint["name"]
            state = states.get(name)
            rows.append(
                {
                    "joint": name,
                    "motor_id": int(joint["motor_id"]),
                    "model": str(joint.get("model", "")),
                    "mos_c": None if state is None else round(float(state.t_mos), 1),
                    "rotor_c": None if state is None else round(float(state.t_rotor), 1),
                    "status_code": None if state is None else int(state.status_code),
                }
            )
        return rows
    finally:
        for motor in report_enabled:
            try:
                motor.robstride_set_active_report(False)
            except Exception:  # noqa: BLE001
                pass
        for motor in motors.values():
            try:
                motor.close()
            except Exception:  # noqa: BLE001
                pass
        try:
            ctrl.close_bus()
        except Exception:  # noqa: BLE001
            pass
        ctrl.close()


def _width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def _pad(text: str, width: int) -> str:
    return text + " " * max(width - _width(text), 0)


def print_table(rows: list[dict], threshold: float) -> None:
    widths = (10, 8, 8, 12, 12, 8)

    def line(cells: list[str]) -> str:
        return "  ".join(_pad(cell, width) for cell, width in zip(cells, widths)).rstrip()

    print(line(["关节", "电机ID", "型号", "MOS温度", "转子温度", "状态字"]))
    hottest = None
    missing = []
    for row in rows:
        mos = "—" if row["mos_c"] is None else f"{row['mos_c']:.1f} °C"
        rotor = "—" if row["rotor_c"] is None else f"{row['rotor_c']:.1f} °C"
        status = "—" if row["status_code"] is None else str(row["status_code"])
        flag = ""
        if row["mos_c"] is None:
            missing.append(row["joint"])
        elif row["mos_c"] >= threshold:
            flag = "  <-- 超阈值"
        if row["mos_c"] is not None and (hottest is None or row["mos_c"] > hottest["mos_c"]):
            hottest = row
        print(
            line([row["joint"], f"0x{row['motor_id']:02X}", row["model"], mos, rotor, status]) + flag
        )

    if hottest is not None:
        print(f"最高 MOS 温度：{hottest['mos_c']:.1f} °C（{hottest['joint']}），阈值 {threshold:.0f} °C")
    if missing:
        print(f"未收到反馈：{', '.join(missing)}（检查供电、CAN 连接或电机 ID）")
    print("注：RobStride 不上报转子温度，转子温度列恒为 0.0。")


def main() -> int:
    parser = argparse.ArgumentParser(description="读取 RS 关节电机温度（需先停止 reBotArm 控制器）")
    parser.add_argument("--channel", default="can0", help="SocketCAN 接口名，默认 can0")
    parser.add_argument("--config", default=None, help="硬件 YAML（默认按 rebotarm.yaml 的 hardware_yaml 解析）")
    parser.add_argument("--timeout", type=float, default=2.0, help="等待反馈的秒数，默认 2")
    parser.add_argument("--threshold", type=float, default=70.0, help="温度告警阈值（°C），默认 70")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出")
    parser.add_argument(
        "--allow-running-controller",
        action="store_true",
        help="允许在控制器运行时读取（会与控制器争用 CAN，默认拒绝）",
    )
    args = parser.parse_args()

    pids = running_controller_pids()
    if pids and not args.allow_running_controller:
        die(
            "检测到 reBotArm 控制器正在运行（pid: "
            + ", ".join(str(pid) for pid in pids)
            + "）；请先停止真机控制（Ctrl+C），否则两个进程会争用同一路 CAN",
            3,
        )

    config = resolve_config(args.config)
    joints = load_joints(config)
    rows = read_temperatures(args.channel, joints, args.timeout)

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    else:
        print_table(rows, args.threshold)

    return 0 if all(row["mos_c"] is not None for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
