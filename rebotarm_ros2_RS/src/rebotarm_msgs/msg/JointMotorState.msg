std_msgs/Header header
string joint_name
float64 position
float64 velocity
float64 torque
uint8 status_code
# 驱动板/MOS 温度（°C），来自同一帧反馈，不额外占用总线
float64 temperature
# 转子温度（°C）；RobStride 不上报，恒为 0
float64 temperature_rotor
