"""Check the fixed D405 assembly without starting ROS or connecting hardware."""
import importlib.util
from pathlib import Path
from xml.etree import ElementTree as ET

import xacro
from urdf_parser_py.urdf import URDF

PACKAGE = Path(__file__).resolve().parents[1]
SHARED = PACKAGE.parents[2] / "reBotArm_simulator-RS/public/models/wrist-cameras"
SPEC = importlib.util.spec_from_file_location(
    "rviz_urdf_compat", PACKAGE / "launch/rviz_urdf_compat.py"
)
COMPAT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPAT)


def test_d405_description():
    xml = xacro.process_file(
        str(PACKAGE / "description/urdf/ReBot_Arm_RS.urdf.xacro"),
    ).toxml()
    root = ET.fromstring(COMPAT.make_rviz_compatible(xml))
    robot = URDF.from_xml_string(ET.tostring(root, encoding="unicode"))
    assert robot.get_root() == "base_link"
    assert len(robot.link_map) == len(robot.links)
    assert len(robot.joint_map) == len(robot.joints)
    for link in robot.links:
        robot.get_chain("base_link", link.name)
    assert all(len(link.findall("visual")) <= 1 for link in root.findall("link"))
    for mesh in root.iter("mesh"):
        uri = mesh.get("filename")
        prefix = "package://rebotarm_bringup/"
        assert uri.startswith(prefix)
        assert (PACKAGE / uri[len(prefix):]).is_file(), uri
    assert robot.parent_map["camera_mount_link"][1] == "gripper_end"
    assert "camera_link" in robot.link_map
    # Preserve source mounting transforms, optical frames and mesh scales.
    source = ET.parse(SHARED / "urdf/d405.urdf").getroot()
    expanded = ET.fromstring(xml)
    for joint in source.findall("joint"):
        actual = expanded.find(f"joint[@name='{joint.get('name')}']")
        assert [(e.tag, e.attrib) for e in actual.iter()] == [(e.tag, e.attrib) for e in joint.iter()]
    source_meshes = [m.attrib for m in source.iter("mesh")]
    actual_meshes = [m.attrib for m in expanded.iter("mesh") if "wrist-cameras" in m.get("filename")]
    expected = [dict(m, filename=m["filename"].replace(
        "../meshes/", "package://rebotarm_bringup/description/wrist-cameras/meshes/"
    )) for m in source_meshes]
    assert actual_meshes == expected
