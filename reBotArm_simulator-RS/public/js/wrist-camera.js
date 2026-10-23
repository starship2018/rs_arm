(function () {
  class WristCamera {
    constructor(status) {
      this.status = status;
      window.rebotI18n?.onLangChange(() => this.renderStatus());
    }

    attach(robot, ghostRobot) {
      this.robot = robot;
      this.ghostRobot = ghostRobot;
      this.ready = !!robot.getObjectByName('camera_link') &&
        !!ghostRobot.getObjectByName('camera_link');
      this.renderStatus();
    }

    renderStatus() {
      this.status.textContent = window.rebotI18n.t(
        this.ready ? 'wrist.ready' : 'wrist.failed', { model: 'D405' }
      );
    }

    getDiagnostics() {
      const pose = (root, name) => {
        const link = root?.getObjectByName(name);
        if (!link) return null;
        link.updateWorldMatrix(true, false);
        return {
          position: link.getWorldPosition(new THREE.Vector3()).toArray(),
          quaternion: link.getWorldQuaternion(new THREE.Quaternion()).toArray()
        };
      };
      return {
        active: this.ready ? 'd405' : 'none', requested: 'd405', loading: false,
        mount: pose(this.robot, 'camera_mount_link'),
        camera: pose(this.robot, 'camera_link'),
        ghostCamera: pose(this.ghostRobot, 'camera_link')
      };
    }
  }

  window.RebotWristCamera = WristCamera;
})();
