const test = require('node:test')
const assert = require('node:assert/strict')
const Shared = require('../engines/shared.js')
const Podman = require('../engines/podman.js')

// Synthetic fixtures matching the schema confirmed live against a real
// podman 6.1.0 install during design research (see
// docs/superpowers/specs/2026-09-02-podman-integration-design.md) — values
// are made up, not the real containers captured during that research.
function containerFixture(overrides) {
  return Object.assign({
    Id: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f601',
    Names: ['myapp-web'],
    Image: 'docker.io/library/nginx:latest',
    State: 'running',
    Status: 'Up 3 minutes',
    Ports: [{ host_ip: '127.0.0.1', host_port: 8080, container_port: 80, protocol: 'tcp' }],
    CreatedAt: '3 minutes ago'
  }, overrides)
}

const RUNNING_JSON = JSON.stringify([containerFixture({})])

const STOPPED_JSON = JSON.stringify([containerFixture({
  Id: 'b1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f602',
  Names: ['myapp-worker'],
  Image: 'docker.io/library/alpine:latest',
  State: 'exited',
  Status: 'Exited (0) 5 minutes ago',
  Ports: [],
  CreatedAt: '10 minutes ago'
})])

const RUNNING_AND_STOPPED_JSON = JSON.stringify([
  containerFixture({}),
  containerFixture({
    Id: 'b1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f602',
    Names: ['myapp-worker'],
    Image: 'docker.io/library/alpine:latest',
    State: 'exited',
    Status: 'Exited (0) 5 minutes ago',
    Ports: [],
    CreatedAt: '10 minutes ago'
  })
])

test('psCommand uses the array-form --format json, not the row template', () => {
  assert.deepEqual(Podman.psCommand('/usr/bin/podman'), ['/usr/bin/podman', 'ps', '-a', '--format', 'json'])
})

test('logsCommand builds the argv for tailing logs', () => {
  assert.deepEqual(Podman.logsCommand('/usr/bin/podman', 'abc123', 200), ['/usr/bin/podman', 'logs', '--tail', '200', '--timestamps', 'abc123'])
})

test('actionCommand maps verbs to the right flags', () => {
  assert.deepEqual(Podman.actionCommand('/usr/bin/podman', 'stop', 'abc123'), ['/usr/bin/podman', 'stop', 'abc123'])
  assert.deepEqual(Podman.actionCommand('/usr/bin/podman', 'start', 'abc123'), ['/usr/bin/podman', 'start', 'abc123'])
  assert.deepEqual(Podman.actionCommand('/usr/bin/podman', 'remove', 'abc123'), ['/usr/bin/podman', 'rm', '-f', 'abc123'])
})

test('parseContainerList parses the whole-array JSON form', () => {
  const list = Podman.parseContainerList(RUNNING_AND_STOPPED_JSON, Shared)
  assert.equal(list.length, 2)
  const running = list.find(c => c.name === 'myapp-web')
  assert.equal(running.isRunning, true)
  assert.equal(running.id.length, 12)
  assert.equal(running.image, 'docker.io/library/nginx:latest')
  assert.equal(running.statusText, 'Up 3 minutes')
  assert.deepEqual(running.ports, [{ hostPort: 8080, containerPort: 80, protocol: 'tcp' }])
})

test('parseContainerList reads Names as an array, taking the first element', () => {
  const list = Podman.parseContainerList(STOPPED_JSON, Shared)
  assert.equal(list[0].name, 'myapp-worker')
  assert.equal(list[0].isRunning, false)
})

test('parseContainerList defaults healthStatus to none (not available from ps)', () => {
  const list = Podman.parseContainerList(RUNNING_JSON, Shared)
  assert.equal(list[0].healthStatus, 'none')
})

test('parseContainerList dedupes ports the same way as Docker', () => {
  const dupPorts = JSON.stringify([containerFixture({
    Ports: [
      { host_ip: '0.0.0.0', host_port: 5050, container_port: 80, protocol: 'tcp' },
      { host_ip: '::', host_port: 5050, container_port: 80, protocol: 'tcp' }
    ]
  })])
  const list = Podman.parseContainerList(dupPorts, Shared)
  assert.equal(list[0].ports.length, 1)
})

test('parseContainerList clamps oversized fields', () => {
  const huge = 'x'.repeat(Shared.MAX_FIELD_LEN + 5000)
  const list = Podman.parseContainerList(JSON.stringify([containerFixture({ Image: huge, Names: [huge], Status: huge })]), Shared)
  assert.equal(list[0].image.length, Shared.MAX_FIELD_LEN)
  assert.equal(list[0].name.length, Shared.MAX_FIELD_LEN)
  assert.equal(list[0].statusText.length, Shared.MAX_FIELD_LEN)
})

test('parseContainerList caps the number of containers', () => {
  const many = Array.from({ length: Shared.MAX_CONTAINERS + 50 }, (_, i) => containerFixture({ Id: 'c' + i, Names: ['c' + i] }))
  assert.equal(Podman.parseContainerList(JSON.stringify(many), Shared).length, Shared.MAX_CONTAINERS)
})

test('parseContainerList handles an empty list', () => {
  assert.deepEqual(Podman.parseContainerList('[]', Shared), [])
})

test('parseContainerList handles unparseable stdout without throwing', () => {
  assert.deepEqual(Podman.parseContainerList('not json', Shared), [])
})

test('parseContainerList handles a non-array top-level value without throwing', () => {
  assert.deepEqual(Podman.parseContainerList('{"oops":true}', Shared), [])
})

test('classifyError reports not-installed when the binary is missing', () => {
  assert.equal(Podman.classifyError(false, '').kind, 'not-installed')
})

test('classifyError falls back to unknown, truncated', () => {
  const result = Podman.classifyError(true, 'some other failure')
  assert.equal(result.kind, 'unknown')
  assert.equal(result.message, 'some other failure')
})
