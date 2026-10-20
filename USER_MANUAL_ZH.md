# reBot Arm B601-RS 完整使用手册

本手册面向第一次使用本工程的用户，覆盖安装、MuJoCo 仿真、网页控制、视觉抓放、AI
助手、RS 真机、停止恢复和常见故障排查。

> 真机启动前必须清空工作区、固定机械臂、确认急停可用，并先在仿真中验证动作。首次
> 真机测试建议把速度限制在 `0.2–0.4 rad/s`，一次只移动一个关节。

## 1. 系统组成

本仓库可以从三个视角理解：运行中的服务、控制软件的分层，以及构建产物。三者不是互相
替代的关系，而是同一套系统的不同切面。

### 1.1 运行服务

| 服务 | 默认地址/命名空间 | 作用 |
|---|---|---|
| 网页控制台 | `http://localhost:3002` | 3D、关节、夹爪、视觉和 AI 操作 |
| rosbridge | `ws://localhost:9090` | 网页与 ROS 2 通信 |
| RS 仿真 | `/rebotarm_rs` | Fake Driver 和 MuJoCo |
| RS 真机 | `/rebotarm` | RobStride/SocketCAN 控制 |
| 电机网关（可选） | `ws://127.0.0.1:9002` | MotorBridge 直连，绕过 ROS |
| MCP Agent | `http://127.0.0.1:8081/mcp` | 机械臂工具和抓取任务 |
| text-agent | `http://127.0.0.1:8082` | 网页自然语言助手 |

常规仿真需要两个终端：终端 1 运行仿真，终端 2 运行网页。自然语言控制再使用终端 3
运行 text-agent。

### 1.2 控制软件栈：motorbridge 与 reBotArm_control_py

控制真机时，一条网页或 ROS 指令按下面的层次向下传递：

```text
网页控制台 / AI Agent / MoveIt
        │ ROS 2 topic / service / action
        ▼
reBotArmController 节点（rebotarmcontroller 包）
        │ HardwareManager：命令仲裁、在线轨迹、状态发布
        ▼
reBotArm_control_py（机械臂语义层）
        │ 关节组、FK/IK、动力学、重力补偿、轨迹
        ▼
motorbridge（电机与总线驱动层）
        │ SocketCAN can0 / DM 串口
        ▼
RobStride / 达妙电机
```

**motorbridge 的作用（设备驱动层）**

- 它是独立的 PyPI 包（本仓库锁定 `motorbridge==0.5.1`），不是本仓库源码。Python 侧
  通过 `Controller`、`Motor`、`Mode`、`MotorState` 等接口调用原生库；wheel 内还带有
  Rust 编写的 `ws_gateway` WebSocket 网关。
- 负责“单个电机如何通信”：打开 SocketCAN、CAN-FD 或 DM 串口，按厂商（RobStride、
  达妙、Hexfellow、MyActuator、HighTorque）编码/解析帧，做超时和错误处理。
- 提供使能、失能、清错、置零、模式切换，以及 `send_mit`、`send_pos_vel`、`send_vel`、
  `send_force_pos` 等控制原语；还能读写电机寄存器、轮询反馈、读取状态字和
  `t_mos`/`t_rotor` 温度。
- 它不认识机械臂：不知道 URDF、关节链、末端位姿、逆运动学、重力补偿或轨迹。它只保证
  “这条 CAN 指令被正确发给这个电机，并把反馈取回来”。
- 在本工程中，`reBotArm_control_py` 是它的主要使用者；`scripts/read_rs_motor_temps.py`
  也直接用它读取温度。网页的 MotorBridge 直连模式则通过 `ws_gateway` 使用同一套能力。

**reBotArm_control_py 的作用（机械臂语义层）**

该目录是随主仓库提交的 vendored SDK（`rebotarm_ros2_RS/third_party/reBotArm_control_py`，
非 submodule）。`rebotarmcontroller` 在导入时把它加入 `sys.path`，并使用其
`config/rebotarm_rs.yaml` 描述 RS 电机 ID、型号、分组和增益。

| SDK 模块 | 作用 |
|---|---|
| `actuator` | `RebotArm` / `JointGroup`：按 `arm` 六关节和 `gripper` 分组，负责连接、使能、模式切换、控制循环和分组同步发包 |
| `kinematics` | 基于 Pinocchio 和 URDF 的正运动学、逆运动学、关节限位与末端坐标系 |
| `dynamics` | 质量矩阵、科氏力、重力向量、逆动力学等刚体动力学计算 |
| `controllers` | `RebotArmEndPose` 末端位姿控制、`GravityCompensation` 重力补偿 |
| `trajectory` | SE(3) 测地线轨迹采样、CLIK 跟踪、关节空间轨迹规划 |

它把“六轴机械臂 + 夹爪”的业务概念翻译成每个电机的 MIT/POS_VEL 指令，再把电机反馈
组装成关节状态。所有真正的 CAN 收发仍交给 motorbridge，因此它不重复实现设备协议。
`rebotarmcontroller` 的 `HardwareManager` 正是通过 `RebotArm`、`RebotArmEndPose`、
`compute_generalized_gravity`、`compute_fk` 等接口把 ROS 层与 SDK 连接起来。

两者的职责边界可以概括为：

| 能力 | motorbridge | reBotArm_control_py |
|---|---|---|
| 电机 ID、CAN 帧、超时、模式切换 | 实现 | 调用 |
| 单电机使能/失能/置零/参数/温度 | 实现 | 调用 |
| 关节分组、同步发送、控制循环 | 不涉及 | 实现 |
| URDF FK/IK、关节限位 | 不涉及 | 实现 |
| 重力补偿、末端控制、轨迹规划 | 不涉及 | 实现 |
| ROS 话题/服务/动作、命令仲裁 | 不涉及 | 不涉及（由 `rebotarmcontroller` 实现） |

一句话：**motorbridge 让“一个电机”动起来并报回状态，reBotArm_control_py 让“一条
机械臂”按关节、位姿、轨迹和重力补偿的语义动起来。**

### 1.3 真机的两条控制通路

| 通路 | 链路 | 适用场景 |
|---|---|---|
| ROS 2（推荐） | 网页 → rosbridge → `reBotArmController` → `reBotArm_control_py` → motorbridge → `can0` | 正常控制、轨迹、重力补偿、MuJoCo 跟随、AI/视觉抓取 |
| MotorBridge 直连 | 网页 MotorBridge 面板 → `ws://127.0.0.1:9002` 网关 → `can0` | 单电机调试、扫描、参数和温度读取 |

直连通路绕过 ROS、命令仲裁和安全回零，只适合调试，不能替代物理急停，也不能与
`reBotArmController` 同时占用同一条 `can0`。`./rebotarm` 不会自动启动 `ws_gateway`，
需要按 motorbridge 的说明单独运行。MuJoCo 仿真使用 Fake Driver 和 MuJoCo 物理，
不经过 motorbridge，因此仿真可用不代表真机 CAN 链路已就绪。

### 1.4 仓库构建组成与作用

**构建输入**

| 路径 | 类型 | 作用 |
|---|---|---|
| `rebotarm_ros2_RS/src` | colcon 工作空间 | 7 个 ROS 2 包，见下表 |
| `rebotarm_ros2_RS/third_party/reBotArm_control_py` | vendored Python 源码 | 机械臂语义层 SDK，被控制器直接导入 |
| `reBotArm_simulator-RS` | Node.js 静态站点 | 端口 3002 的网页控制台，含 ROS、MotorBridge、视觉和 AI 界面 |
| `web_mujoco` | Vite + MuJoCo WASM | 端口 5173 的独立浏览器仿真，不连接 ROS 和真机 |
| `scripts`、`setup.sh`、`rebotarm` | 运维脚本 | 环境检查、依赖安装、工作区构建、CAN 启停和服务启动 |
| `requirements-rs-*.txt` | 依赖锁定 | 硬件、MuJoCo 与可选 leader 臂的 Python 依赖 |

**ROS 2 包**

| 包 | 构建类型 | 产物与作用 |
|---|---|---|
| `rebotarm_msgs` | `ament_cmake` | 6 个 msg、5 个 srv、1 个 action；生成 Python/C++ 接口，是构建目录中文件最多的包 |
| `rebotarmcontroller` | `ament_python` | `reBotArmController`、`FakeRsDriver` 及示例可执行文件；封装硬件、ROS 服务/动作和状态发布 |
| `rebotarm_bringup` | `ament_python` | launch、硬件配置、URDF/网格、RViz 资源 |
| `rebotarm_moveit_config` | `ament_cmake` | MoveIt 2 的 SRDF、ros2_control 和 RViz 配置（仅安装配置） |
| `rebotarm_moveit_demos` | `ament_python` | `pick_place`、`draw_square` 等 MoveIt 示例 |
| `rebotarm_agent` | `ament_python` | MCP 工具服务（8081）和网页文本助手（8082） |
| `rebotarm_mujoco_rs` | `ament_python` | MuJoCo 同步、场景相机/检测、任务服务和关节滑块 GUI，并安装模型与网格 |

**构建产物**

- `rebotarm_ros2_RS/build` 是 colcon 的中间目录，保存 CMake 缓存、生成的 ROS 接口和
  各包的临时文件；`rebotarm_ros2_RS/install` 是运行目录，入口脚本、Python 模块、消息
  库和 share 资源都在这里；`rebotarm_ros2_RS/log` 保存每次构建日志。
- 当前脚本使用的就是这套嵌套构建：`scripts/rs_env.sh` 只 source
  `rebotarm_ros2_RS/install/setup.bash`，构建由
  `scripts/setup_rs_workspace_init.sh` 执行 `colcon build --symlink-install` 完成。
  `--symlink-install` 让 Python 源码修改通常无需重新构建即可生效；修改
  `rebotarm_msgs` 的 msg/srv/action 后仍必须重新执行 colcon build。
- `rebotarm_ros2_RS/.venv` 使用 `--system-site-packages` 创建，安装硬件和 MuJoCo 的
  pip 依赖；ROS 包本身由 colcon 安装到 `install`，不进入 venv。
- 仓库根目录的 `build/`、`install/`、`log/` 是早期在根目录执行 colcon 留下的旧产物，
  已被 `.gitignore` 忽略，当前脚本不会读取它们。它们不影响运行，确认没有进程使用后
  可以删除；日常只使用 `rebotarm_ros2_RS/` 下的构建。
- 网页控制台不需要构建，`node server.js` 直接提供静态文件；`web_mujoco` 通过
  `npm run build` 生成 `dist/`，该目录不提交。运行期还会生成 `.env`、`.certs` 等本地
  文件，应按需保留且不要提交。

## 2. 支持环境

- 推荐 Ubuntu 24.04、ROS 2 Jazzy、Python 3.12、Node.js 18+；
- Ubuntu 22.04、ROS 2 Humble、Python 3.10 可用，真机需自行回归；
- 真机总线为 SocketCAN `can0`，波特率 `1 Mbps`；
- 推荐最新版 Chrome、Chromium、Edge 或 Firefox。

## 3. 下载与首次安装

本仓库已经直接包含控制 SDK 和 MuJoCo 上游源码，没有 Git submodule，也没有嵌套 Git
仓库。普通 clone 即可取得完整构建输入：

```bash
git clone https://github.com/Yang-Ci/ReBot_Arm_DigitalTwin_RS.git
cd ReBot_Arm_DigitalTwin_RS
```

在当前机器上的默认目录为：

```bash
cd /home/robot/ReBot_Arm_DigitalTwin_RS
```

先只读检查环境：

```bash
./setup.sh --check
```

安装缺失依赖、创建 Python 环境并构建 ROS 工作区：

```bash
./setup.sh --yes
./rebotarm doctor
```

安装脚本不会覆盖已有 `.env`，也不会重新下载或重置 `rebotarm_ros2_RS/third_party`。如果只需
重建 ROS 工作区：

```bash
./scripts/setup_rs_workspace_init.sh
```

## 4. 启动完整 MuJoCo 仿真

终端 1：

```bash
cd /home/robot/ReBot_Arm_DigitalTwin_RS
./rebotarm start rs_sim
```

该命令会启动 RS Fake Driver、MuJoCo、桌面物体、俯视相机、颜色检测、MCP Agent 和
rosbridge。看到以下信息表示主要服务已启动：

```text
RS simulation: /rebotarm_rs
MuJoCo mode: physics
MCP grasp agent: http://127.0.0.1:8081/mcp
rosbridge: ws://0.0.0.0:9090
```

保持终端运行，使用 `Ctrl+C` 正常停止，不要使用 `Ctrl+Z`。

常用选项：

```bash
# 不打开 MuJoCo 原生窗口
REBOTARM_MUJOCO_VIEWER=false ./rebotarm start rs_sim

# 仅运动学跟随；没有物体接触，不能验证物理抓取
REBOTARM_MUJOCO_MODE=kinematic ./rebotarm start rs_sim

# 确认没有有效任务后，清理残留仿真并重启
./rebotarm start rs_sim --force
```

视觉抓取必须使用默认 `physics` 模式。

夹爪上的 TCP 红点只是末端位置辅助标记，不参与碰撞或物理仿真，也不影响抓放 IK。
默认隐藏；可在相机选择窗口勾选“显示 TCP 红点”，或在 MuJoCo 窗口按 `T` 切换显示/隐藏。
ROS 相机画面保持隐藏该标记。也可以通过
`ros2 param set /rebotarm_rs_mujoco show_tcp_marker true` 显示，改为 `false` 隐藏。

## 5. 启动和连接网页

终端 2：

```bash
cd /home/robot/ReBot_Arm_DigitalTwin_RS
./rebotarm start web
```

浏览器打开 `http://localhost:3002`，然后：

1. 控制目标选择“RS 仿真（`/rebotarm_rs`）”；
2. ROS WebSocket 填写 `ws://localhost:9090`；
3. 点击连接，等待状态显示在线；
4. 仿真 Fake Driver 会自动允许网页控制。

从局域网其他电脑访问时，将两个 `localhost` 都换为运行服务的虚拟机 IP，例如：

```text
http://192.168.1.20:3002
ws://192.168.1.20:9090
```

## 6. 网页控制功能

### 6.1 关节和夹爪

- J1–J6 控制六个机械臂关节；
- J7/夹爪以开口宽度显示，命令范围约 `0–71.5 mm`；
- 仿真网页模型由 MuJoCo 实际反馈驱动；
- 真机模式中实线模型表示测量反馈，半透明模型表示命令目标；目标到位或等待超时后，半透明鬼影会自动隐藏；
- 网页速度范围为 `0.05–1.50 rad/s`，真机首次使用建议 `0.2–0.4 rad/s`。
- 姿态预设之间使用统一的 30 Hz smoothstep 轨迹，并根据最大关节变化自动延长时间；夹爪按同一时间线渐变。

### 6.2 Pose 和 IK

Pose 输入单位是米：X 向前、Y 向左、Z 向上。输入目标和时长后点击“IK 运动”。目标不可
达时，先提高 Z 或减小水平距离，不要连续快速点击。

### 6.3 使能、回零和失能

- 仿真一般无需手动使能；
- 真机控制器每次重启后需要重新使能；
- “安全回零”会平滑返回零位，并保持当前夹爪开口，不再隐式闭合；
- “从零点执行当前姿态”会先用一段轨迹回到零点，再用第二段轨迹执行到网页当前姿态；默认每段 `2 s`；
- 非零位失能会先回零并验证，失败时保持使能；
- 网页按钮不是物理急停，真机必须配备可用急停。

### 6.4 重力补偿

真机重力补偿启动时先保持当前测量姿态，再平滑过渡到低刚度增益，避免模式切换突动。
进入重补后可以手动拖动机械臂，夹爪默认进入低阻随动助力：只有检测到手动运动时才施加小力矩，
静止、接近开合限位或超过保护速度时助力为零，无需手动切换夹爪模式。
启动重补前先取下被夹物体，并让手指远离夹点。退出重补后系统自动保持机械臂与夹爪的当前位置；抓取或轨迹动作前应先退出重补。

### 6.5 真机推动示教与平滑回放

真机连接、使能并打开控制锁后，在“TCP 示教”区选择“完整路径”或“仅最终位置”，然后点击“推动 RS 真机示教”。
网页会启动重力补偿，同步记录 J1–J6 和夹爪开口。结束示教后先停止录制和重力补偿，再执行安全回零；
“结束示教回零后的夹爪”可选保持当前开口（默认）或回零后闭合。

完整路径回放会先从当前姿态平滑引导到起点，再将原始反馈时间线重采样到约 30 Hz，使用中心平滑降低编码器噪声，夹爪按同一时间线同步回放。
仅最终位置模式用 3 秒平滑轨迹到达最终姿态。导出仍保留原始采样；旧版不含夹爪数据的 JSON 也可导入，回放时保持当前夹爪开口。

## 7. 视觉识别和抓放

视觉面板显示相机图像、检测数量、目标颜色、抓取宽度和方向。

### 7.1 选择目标

- 红色、黄色、蓝色：锁定指定颜色；
- 自动目标：从当前检测中选择，并尽量避免连续选择同一颜色；
- 无检测结果时，先确认仿真、相机和颜色检测节点仍在运行。

### 7.2 视觉抓取流程

点击“视觉抓取”后系统串行执行：

1. 锁定本次颜色；
2. 夹爪打开，同时机械臂走安全高位路线；
3. 移到目标上方并垂直对正；
4. 预下探和最终下探；
5. 闭合夹爪并等待接触稳定；
6. 先执行离桌抬升；
7. 通过视觉确认物体确实升高；
8. 进入安全中转高度。

动作中再次点击不会启动并发 ROS 请求。页面会显示“已排队下一步”，当前动作结束后只
执行最后一次排队请求，避免 rosbridge 服务调用超时。

### 7.3 连续抓取不同物体

夹住黄色后选择蓝色并点击抓取时，流程是：在当前安全高度松开黄色，清除旧夹持状态，
直接走高位路线到蓝色，再执行蓝色抓取。不会返回黄色位置下探。

### 7.4 放置物体

“放置物体”只对已成功抓取并通过抬升验证的物体有效。系统会移动到原位置上方、下探、
打开夹爪，再抬回安全高度。没有已夹持物体时会明确提示，不会进入虚假的“放置中”。

### 7.5 夹爪与物体之间的空隙

MuJoCo 手指内侧包含不可见的薄碰撞垫，用于提高接触稳定性。网页只显示可视网格，因此
夹住黄色圆柱时可能看到几毫米空隙。这是仿真碰撞几何，不是网页显示出来的实体垫片。

## 8. AI 助手

网页按钮只能连接 text-agent，不能自动启动虚拟机中的 Python 服务。

终端 3：

```bash
cd /home/robot/ReBot_Arm_DigitalTwin_RS
export DASHSCOPE_API_KEY='替换成你的 Key'
export REBOTARM_LLM_MODEL='qwen-plus'
./scripts/start_rs_text_agent.sh
```

不要把真实 Key 写入仓库。看到下面的日志表示 8082 已启动：

```text
[text-agent-http] listening on http://0.0.0.0:8082/
```

健康检查：

```bash
curl http://127.0.0.1:8082/health
```

应返回：

```json
{"ok": true, "service": "rebotarm-text-agent"}
```

然后在网页点击“连接 AI 助手”。示例指令：

```text
查询机械臂状态
检测桌面的色块
打开夹爪
移动到 X=0.30 Y=0 Z=0.30
抓取红色物块
安全回零
```

出现 `ECONNREFUSED 127.0.0.1:8082` 说明网页服务器所在系统没有 text-agent 监听：

```bash
ss -ltnp | grep 8082
curl http://127.0.0.1:8082/health
ss -ltnp | grep 8081
```

若 text-agent 在另一台机器，在 `reBotArm_simulator-RS/.env` 设置：

```text
REBOTARM_TEXT_AGENT_URL=http://虚拟机IP:8082
```

修改后重启网页服务。

## 9. RS 真机

### 9.1 启动前检查

1. 清空工作区并固定机械臂；
2. 确认急停立即可用；
3. 检查电机 ID、零位、方向、负载和终端电阻；
4. 先在仿真中完成同一动作；
5. 第一次只做低速单关节测试。

### 9.2 配置 CAN

```bash
./scripts/start_rs_can.sh   # 启动 can0（默认 1 Mbps），并打印链路状态
./scripts/stop_rs_can.sh    # 关闭 can0
```

接口名或波特率不同时：`./scripts/start_rs_can.sh can1`，或设置
`RS_CAN_IFACE` / `RS_CAN_BITRATE` 环境变量。对应的手动命令：

```bash
sudo ip link set can0 down 2>/dev/null || true
sudo ip link set can0 type can bitrate 1000000
sudo ip link set can0 up
ip -details link show can0
```

### 9.3 启动真机和网页

终端 1：

```bash
cd /home/robot/ReBot_Arm_DigitalTwin_RS
REBOTARM_RS_HARDWARE_CONFIRM=I_UNDERSTAND_RS_WILL_MOVE \
  ./rebotarm start rs
```

终端 2：

```bash
./rebotarm start web
```

网页选择 **RosBridge** “RS 真机（`/rebotarm`）”，输入并连接 `ws://localhost:9090`，勾选 `镜像目标关节到网页 ` 以及 `允许网页向真机RS发送控制`。

将速度限制设为 `0.2–0.4 rad/s`，先小幅移动一个关节，确认方向和反馈一致后再测试其他动作。

真机控制器只用 `Ctrl+C` 停止，不要使用 `Ctrl+Z`。启动脚本会处理异常残留控制器，避免
两个进程同时访问 CAN。

### 9.4 查看关节电机温度

真机控制器运行时会随各关节状态话题发布温度（来自同一帧反馈，不增加总线负载），
**不需要停控制器**：

```bash
ros2 topic echo /rebotarm/joints/joint1/state --field temperature
ros2 topic echo /rebotarm/joints/joint1/state      # 含 temperature / temperature_rotor
```

网页 ROSBridge 面板的“电机温度”显示所有关节（含夹爪）中的最高驱动板温度，鼠标悬停
可看到逐关节数值，达到 70 °C 时变红。

若控制器未运行、需要离线排查，可用只读脚本（会占用 `can0`，因此必须先 `Ctrl+C`
停止控制器）：

```bash
./scripts/read_rs_motor_temps.py                # 表格输出，默认阈值 70 °C
./scripts/read_rs_motor_temps.py --json         # 机器可读
./scripts/read_rs_motor_temps.py --threshold 60 --timeout 3
```

脚本会拒绝在 `reBotArmController` 运行时执行，避免两个进程争用 `can0`。
RobStride 不上报转子温度，`temperature_rotor`（转子温度）恒为 `0.0 °C`，请以
`temperature`（驱动板/MOS 温度）为准；`status_code` 是电机原始状态字，过温等故障会
体现在这里。

### 9.5 真机姿态 MuJoCo 跟随

真机控制器运行后，可在新终端执行：

```bash
./scripts/start_rs_mujoco_follow.sh
```

该脚本只订阅 `/rebotarm/joint_states` 做运动学显示，不打开 SocketCAN，也不向真机发送
力矩命令。

## 10. 停止和恢复

```bash
# 查看管理进程、端口和 CAN
./rebotarm status

# 停止由 rebotarm 管理的网页/rosbridge 子进程
./rebotarm stop
```

前台仿真、网页、AI 或真机进程在各自终端按 `Ctrl+C`。真机异常时优先按物理急停。

## 11. 常见故障

### ROS 未连接

```bash
ss -ltnp | grep 9090
ros2 node list
./rebotarm status
```

远程浏览器不能使用它自己的 `localhost` 连接虚拟机，应填写虚拟机 IP。

### 视觉按钮没有动作

```bash
ros2 topic echo /rebotarm_rs/vision/color_blocks/detections --once
ros2 topic echo /rebotarm_rs/mujoco/object_states --once
ros2 service list | grep rebotarm_rs
```

确认 MuJoCo 是 `physics` 模式。按钮显示已排队时等待当前串行动作结束。

### rosbridge 调用超时

```bash
ros2 node list | sort
ps -ef | grep -E 'mujoco_sync|fake_rs|rosbridge' | grep -v grep
```

检查是否重复启动节点。网页已串行化抓取和放置请求，不应同时启动多次 IK 服务。

### 夹爪闭合但物体没抬起

- 确认是 `physics` 模式；
- 检查日志是否显示接触稳定和物理抓取验证通过；
- “夹爪为空”会停止抬升，避免假抓取；
- 黄色圆柱的可见空隙可能来自不可见碰撞垫。

### 网页模型抖动

- 确认只有一个控制器和一个反馈源；
- 检查 `/joint_states` 是否有多个发布者；
- 不要同时运行低层回放和手动连续拖动。

### CAN 无反馈

```bash
ip -details -statistics link show can0
candump can0
```

检查供电、波特率、终端电阻和电机 ID。错误计数持续增加时立即停止测试。

## 12. 本地 SDK 与 MuJoCo 模型边界

父仓库直接跟踪：

```text
rebotarm_ros2_RS/third_party/reBotArm_control_py
rebotarm_ros2_RS/src/rebotarm_mujoco_rs/models
```

SDK 是普通源码目录；MuJoCo 目录只保留主工程实际使用的模型 XML 和 STL 网格。它们不是
submodule，也没有各自的 `.git`。来源基线分别记录在 `rebotarm_ros2_RS/third_party/README.md`
和 `rebotarm_ros2_RS/src/rebotarm_mujoco_rs/README.md`。

SDK 没有修改设备协议、CAN 通信、MIT 发包或电机参数读写。当前 SDK 本地修改只有 RS
笛卡尔轨迹安全保护：根据关节空间总行程自动延长过短轨迹，使真机速度不超过约
`0.60 rad/s`。该逻辑已经直接包含在主仓库跟踪的 SDK 源码中。

主工程没有导入原 MuJoCo 工程的 `rebot_b601_rs_sim` 算法、QP 求解器、独立示例或测试。
更新 SDK 或模型时应在父仓库中审查差异并作为普通文件提交，确保一次 clone 就得到完整
可构建工程。

## 13. 验证命令

```bash
source scripts/rs_env.sh
python3 -m pytest rebotarm_ros2_RS/src/rebotarmcontroller/test -q

bash -n setup.sh rebotarm scripts/*.sh
node --check reBotArm_simulator-RS/server.js
node --check reBotArm_simulator-RS/public/js/rebot-sim.js
node --check reBotArm_simulator-RS/public/js/ros/rebot-ros-client.js
node --check reBotArm_simulator-RS/public/js/ros/rebot-ros-ui.js
node --check reBotArm_simulator-RS/public/js/rebot-llm.js
```

排障时保留启动日志、网页 ROS 日志、发生时间、目标颜色、仿真模式及相关 ROS 输出。不要
公开 API Key、Token 或硬件凭据。

## 14. 快速命令表

```bash
./setup.sh --check
./setup.sh --yes
./rebotarm doctor
./rebotarm start rs_sim
./rebotarm start web
./scripts/start_rs_text_agent.sh
REBOTARM_RS_HARDWARE_CONFIRM=I_UNDERSTAND_RS_WILL_MOVE ./rebotarm start rs
./rebotarm status
./rebotarm stop
```
