const assert = require('node:assert/strict');
const { test } = require('node:test');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const net = require('node:net');
const path = require('node:path');

test('web model includes one D405 assembly and serves its meshes', { timeout: 15000 }, async (t) => {
  const probe = net.createServer().listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = probe.address().port;
  await new Promise((resolve) => probe.close(resolve));
  const server = spawn(process.execPath, ['server.js'], {
    cwd: path.resolve(__dirname, '..'),
    env: { ...process.env, PORT: String(port), HTTPS: '0' },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  t.after(() => server.kill('SIGTERM'));
  await new Promise((resolve, reject) => {
    server.on('error', reject);
    server.on('exit', (code) => reject(new Error(`server exited: ${code}`)));
    server.stdout.on('data', (data) => {
      if (data.toString().includes('Simulator Started')) resolve();
    });
  });
  const base = `http://127.0.0.1:${port}`;
  const response = await fetch(`${base}/api/urdf`);
  assert.equal(response.status, 200);
  const xml = await response.text();
  for (const name of ['gripper_end', 'camera_mount_link', 'camera_link', 'camera_color_optical_frame']) {
    assert.equal([...xml.matchAll(new RegExp(`<link\\b[^>]*name="${name}"`, 'g'))].length, 1, name);
  }
  assert.ok(!xml.includes('xacro:include'));
  for (const mesh of xml.matchAll(/filename="package:\/\/rebotarm_bringup\/([^\"]+)"/g)) {
    const resource = await fetch(`${base}/api/${mesh[1]}`);
    assert.equal(resource.status, 200, mesh[1]);
    assert.ok(Number(resource.headers.get('content-length')) > 0, mesh[1]);
    await resource.arrayBuffer();
  }
  const html = await (await fetch(base)).text();
  assert.ok(!html.includes('id="wrist-camera-model"'));
  assert.equal((await fetch(`${base}/api/description/wrist-cameras/meshes/%ZZ`)).status, 400);
  assert.equal((await fetch(`${base}/api/description/wrist-cameras/meshes/..%2F..%2Fpackage.xml`)).status, 403);
});
