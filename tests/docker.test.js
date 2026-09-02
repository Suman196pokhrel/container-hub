const test = require('node:test')
const assert = require('node:assert/strict')
const Shared = require('../engines/shared.js')
const Docker = require('../engines/docker.js')

test('binaryCandidates lists only trusted absolute paths', () => {
  for (const p of Docker.binaryCandidates) assert.equal(p.charAt(0), '/')
})

test('psCommand pipes through head -c with --no-trunc, full ids', () => {
  const cmd = Docker.psCommand('/usr/bin/docker', 600000)
  assert.deepEqual(cmd.slice(0, 2), ['/bin/sh', '-c'])
  assert.match(cmd[2], /^\/usr\/bin\/docker ps -a --no-trunc --format '\{\{json \.\}\}' \| \/usr\/bin\/head -c 600000$/)
})

test('logsCommand pipes through head -c', () => {
  const cmd = Docker.logsCommand('/usr/bin/docker', 'abc123', 200, 700000)
  assert.deepEqual(cmd.slice(0, 2), ['/bin/sh', '-c'])
  assert.equal(cmd[2], '/usr/bin/docker logs --tail 200 --timestamps abc123 | /usr/bin/head -c 700000')
})

test('actionCommand maps verbs to the right flags (plain argv, no shell)', () => {
  assert.deepEqual(Docker.actionCommand('/usr/bin/docker', 'stop', 'abc123'), ['/usr/bin/docker', 'stop', 'abc123'])
  assert.deepEqual(Docker.actionCommand('/usr/bin/docker', 'start', 'abc123'), ['/usr/bin/docker', 'start', 'abc123'])
  assert.deepEqual(Docker.actionCommand('/usr/bin/docker', 'remove', 'abc123'), ['/usr/bin/docker', 'rm', '-f', 'abc123'])
})

test('inspectCommand builds the argv for a fresh pre-remove identity check', () => {
  assert.deepEqual(Docker.inspectCommand('/usr/bin/docker', 'abc123'), ['/usr/bin/docker', 'inspect', '--format', '{{.Id}} {{.State.Status}}', 'abc123'])
})

test('parsePorts dedupes IPv4/IPv6 and includes container-only ports', () => {
  const result = Docker.parsePorts('443/tcp, 0.0.0.0:5050->80/tcp, [::]:5050->80/tcp')
  assert.deepEqual(result, [
    { hostPort: null, containerPort: 443, protocol: 'tcp' },
    { hostPort: 5050, containerPort: 80, protocol: 'tcp' }
  ])
})

test('parsePorts returns an empty array for no ports', () => {
  assert.deepEqual(Docker.parsePorts(''), [])
})

test('parseContainerList parses ps JSON lines and clamps fields', () => {
  const running = JSON.stringify({ ID: '1', Image: 'x', Names: 'zzz-running', State: 'running', Status: 'Up', HealthStatus: 'none', Ports: '0.0.0.0:5050->80/tcp', CreatedAt: '' })
  const stopped = JSON.stringify({ ID: '2', Image: 'x', Names: 'aaa-stopped', State: 'exited', Status: 'Exited', HealthStatus: 'none', Ports: '', CreatedAt: '' })
  const list = Docker.parseContainerList(running + '\n' + stopped + '\n', Shared)
  assert.equal(list.length, 2)
  assert.equal(list[0].name, 'zzz-running')
  assert.equal(list[0].ports.length, 1)
  assert.equal(list[1].name, 'aaa-stopped')
})

test('parseContainerList skips blank lines', () => {
  assert.deepEqual(Docker.parseContainerList('\n\n', Shared), [])
})

test('parseContainerList clamps oversized fields', () => {
  const huge = 'x'.repeat(Shared.MAX_FIELD_LEN + 5000)
  const line = JSON.stringify({ ID: '1', Image: huge, Names: huge, State: 'running', Status: huge, HealthStatus: 'none', Ports: '', CreatedAt: '' })
  const result = Docker.parseContainerList(line, Shared)[0]
  assert.equal(result.image.length, Shared.MAX_FIELD_LEN)
  assert.equal(result.name.length, Shared.MAX_FIELD_LEN)
  assert.equal(result.statusText.length, Shared.MAX_FIELD_LEN)
})

test('parseContainerList rejects a line longer than MAX_LINE_LEN', () => {
  const line = JSON.stringify({ ID: '1', Names: 'x'.repeat(Shared.MAX_LINE_LEN) })
  assert.deepEqual(Docker.parseContainerList(line, Shared), [])
})

test('parseContainerList caps the number of containers', () => {
  const lines = Array.from({ length: Shared.MAX_CONTAINERS + 50 }, (_, i) =>
    JSON.stringify({ ID: String(i), Image: 'x', Names: 'c' + i, State: 'running', Status: 'Up', HealthStatus: 'none', Ports: '', CreatedAt: '' })
  ).join('\n')
  assert.equal(Docker.parseContainerList(lines, Shared).length, Shared.MAX_CONTAINERS)
})

test('classifyError reports not-installed when the binary is missing', () => {
  assert.equal(Docker.classifyError(false, '').kind, 'not-installed')
})

test('classifyError reports permission-denied', () => {
  assert.equal(Docker.classifyError(true, 'permission denied while trying to connect to the Docker daemon socket').kind, 'permission-denied')
})

test('classifyError reports daemon-down', () => {
  assert.equal(Docker.classifyError(true, 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?').kind, 'daemon-down')
})

test('classifyError falls back to unknown, truncated', () => {
  const result = Docker.classifyError(true, 'some other failure')
  assert.equal(result.kind, 'unknown')
  assert.equal(result.message, 'some other failure')
})
