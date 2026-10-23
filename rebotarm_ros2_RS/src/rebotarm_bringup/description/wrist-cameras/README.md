# ROS / RViz 腕部相机

从仓库 `reBotArm_simulator-RS/public/models/wrist-cameras/` 复用 D405 相机及支架。
本目录的 URDF 用作 Xacro include：删除原装配中占位的 `gripper_end` link，
网格路径改为 `package://rebotarm_bringup/description/wrist-cameras/meshes/`。
安装位置、光学坐标系、网格比例、碰撞和惯性描述保持来源文件的值。

机器人入口为 `../urdf/ReBot_Arm_RS.urdf.xacro`，固定包含 D405 相机及支架，
无需设置相机型号参数。
原始 `ReBot_Arm_RS.urdf` 继续只包含机械臂和夹爪。

在仓库根目录构建并加载环境：

```bash
cd rebotarm_ros2_RS
colcon build --symlink-install --packages-up-to rebotarm_bringup rebotarm_moveit_config
source install/setup.bash
```

无需连接硬件即可查看：

```bash
ros2 launch rebotarm_bringup fake_rs_bringup.launch.py use_rviz:=true
```

硬件 `bringup.launch.py` 和 MoveIt 的 `demo.launch.py`、`hardware.launch.py`
同样固定加载 D405 相机及支架。

Three.js 网页服务在启动时展开同一 Xacro，`/api/urdf` 返回完整模型，
相机网格通过 bringup 的资源路径提供，不再额外挂载相机。
启动网页服务需要当前 Python 环境能够 `import xacro`。
底层库 MeshCat 可视化默认加载同一入口；显式传入其他 URDF 仍按调用方指定加载。
底层库的运动学、重力补偿及标定工具保留原 SDK 模型，以免改变实机标定。
MuJoCo 保留 MJCF 格式，D405 转换脚本从本目录装配读取模型，
Python MuJoCo 和 `web_mujoco` 共用该转换结果。

本改动提供相机外观和 TF，不启动相机驱动或发布真实图像。
安装坐标沿用仿真装配，不替代实机手眼标定。

来源版本和原始资源哈希见 `source.json`，该文件保留上游来源记录，
并非本目录改写后的 URDF 哈希清单。源 Xacro、STEP、生成脚本及装配截图
仍位于上述共享资源目录。上游相机描述和网格采用 Apache-2.0，
支架 CAD 及派生几何采用 CERN-OHL-W-2.0；许可文本见 `licenses/`。
