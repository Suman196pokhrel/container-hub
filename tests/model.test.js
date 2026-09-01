const test = require('node:test')
const assert = require('node:assert/strict')
const Model = require('../Model.js')

test('parsePorts dedupes IPv4/IPv6 and includes container-only ports', () => {
  const result = Model.parsePorts('443/tcp, 0.0.0.0:5050->80/tcp, [::]:5050->80/tcp')
  assert.deepEqual(result, [
    { hostPort: null, containerPort: 443, protocol: 'tcp' },
    { hostPort: 5050, containerPort: 80, protocol: 'tcp' }
  ])
})

test('parsePorts returns an empty array for no ports', () => {
  assert.deepEqual(Model.parsePorts(''), [])
})

test('formatPortsDisplay renders host arrows and bare container ports', () => {
  const ports = [
    { hostPort: null, containerPort: 443, protocol: 'tcp' },
    { hostPort: 5050, containerPort: 80, protocol: 'tcp' }
  ]
  assert.equal(Model.formatPortsDisplay(ports), '443, 5050→80')
})

test('formatPortsDisplay returns empty string for no ports', () => {
  assert.equal(Model.formatPortsDisplay([]), '')
})

test('parseContainerLine parses a running container', () => {
  const line = JSON.stringify({
    ID: 'd187d155b275',
    Image: 'dpage/pgadmin4:latest',
    Names: 'sambad-pgadmin-1',
    State: 'running',
    Status: 'Up 24 minutes',
    HealthStatus: 'none',
    Ports: '443/tcp, 0.0.0.0:5050->80/tcp, [::]:5050->80/tcp',
    CreatedAt: '2026-08-30 08:13:28 +0930 ACST'
  })
  const result = Model.parseContainerLine(line)
  assert.equal(result.id, 'd187d155b275')
  assert.equal(result.name, 'sambad-pgadmin-1')
  assert.equal(result.image, 'dpage/pgadmin4:latest')
  assert.equal(result.isRunning, true)
  assert.equal(result.statusText, 'Up 24 minutes')
  assert.equal(result.ports.length, 2)
})

test('parseContainerLine marks non-running states correctly', () => {
  const line = JSON.stringify({
    ID: 'e6dbf75f362d', Image: 'sambad-worker', Names: 'sambad-worker-1',
    State: 'created', Status: 'Created', HealthStatus: 'none', Ports: '', CreatedAt: ''
  })
  const result = Model.parseContainerLine(line)
  assert.equal(result.isRunning, false)
  assert.deepEqual(result.ports, [])
})

test('parseContainerLine returns null for blank or invalid input', () => {
  assert.equal(Model.parseContainerLine(''), null)
  assert.equal(Model.parseContainerLine('not json'), null)
})

test('sortContainers puts running first, then sorts by name', () => {
  const containers = [
    { name: 'zeta', isRunning: false },
    { name: 'alpha', isRunning: true },
    { name: 'beta', isRunning: true }
  ]
  const sorted = Model.sortContainers(containers)
  assert.deepEqual(sorted.map(c => c.name), ['alpha', 'beta', 'zeta'])
})

test('parseContainerList parses multiple lines and sorts them', () => {
  const running = JSON.stringify({ ID: '1', Image: 'x', Names: 'zzz-running', State: 'running', Status: 'Up', HealthStatus: 'none', Ports: '', CreatedAt: '' })
  const stopped = JSON.stringify({ ID: '2', Image: 'x', Names: 'aaa-stopped', State: 'exited', Status: 'Exited', HealthStatus: 'none', Ports: '', CreatedAt: '' })
  const list = Model.parseContainerList(running + '\n' + stopped + '\n')
  assert.equal(list.length, 2)
  assert.equal(list[0].name, 'zzz-running')
  assert.equal(list[1].name, 'aaa-stopped')
})

test('parseContainerList skips blank lines', () => {
  assert.deepEqual(Model.parseContainerList('\n\n'), [])
})

test('statusColorFor classifies running, unhealthy, and stopped containers', () => {
  assert.equal(Model.statusColorFor({ isRunning: true, healthStatus: 'none' }), 'running')
  assert.equal(Model.statusColorFor({ isRunning: true, healthStatus: 'healthy' }), 'running')
  assert.equal(Model.statusColorFor({ isRunning: true, healthStatus: 'unhealthy' }), 'unhealthy')
  assert.equal(Model.statusColorFor({ isRunning: false, healthStatus: 'none' }), 'stopped')
  assert.equal(Model.statusColorFor(null), 'stopped')
})
