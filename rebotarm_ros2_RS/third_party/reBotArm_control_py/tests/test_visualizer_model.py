"""Load the MeshCat geometry without opening a viewer or touching hardware."""
import importlib.util
import sys
from pathlib import Path

import numpy as np
import pinocchio as pin

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reBotArm_control_py.kinematics import load_robot_model

spec = importlib.util.spec_from_file_location(
    "visualizer", Path(__file__).resolve().parents[1] / "example/sim/visualizer.py"
)
visualizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visualizer)


def test_default_visualizer_has_d405_and_preserves_joint_mapping():
    control = load_robot_model()
    model, visuals = visualizer._load_visual_model()
    assert list(model.names) == list(control.names)
    assert model.existFrame("camera_link")
    assert model.existFrame("camera_color_optical_frame")
    assert any(obj.name.startswith("camera_link_") for obj in visuals.geometryObjects)
    data = model.createData()
    q = pin.neutral(model)
    pin.framesForwardKinematics(model, data, q)
    control_data = control.createData()
    pin.framesForwardKinematics(control, control_data, q)
    np.testing.assert_allclose(
        data.oMf[model.getFrameId("gripper_end")].homogeneous,
        control_data.oMf[control.getFrameId("gripper_end")].homogeneous,
    )
    camera = model.getFrameId("camera_link")
    before = data.oMf[camera].translation.copy()
    q[0] += 0.5
    pin.framesForwardKinematics(model, data, q)
    assert np.linalg.norm(data.oMf[camera].translation - before) > 0.01
