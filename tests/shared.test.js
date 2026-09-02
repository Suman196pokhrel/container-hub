const test = require('node:test')
const assert = require('node:assert/strict')
const Shared = require('../engines/shared.js')

test('clamp truncates to maxLen', () => {
  assert.equal(Shared.clamp('x'.repeat(300), Shared.MAX_FIELD_LEN).length, Shared.MAX_FIELD_LEN)
})

test('clamp treats null/undefined as empty string', () => {
  assert.equal(Shared.clamp(null, 10), '')
  assert.equal(Shared.clamp(undefined, 10), '')
})

test('sortContainers puts running first, then sorts by name', () => {
  const containers = [
    { name: 'zeta', isRunning: false },
    { name: 'alpha', isRunning: true },
    { name: 'beta', isRunning: true }
  ]
  assert.deepEqual(Shared.sortContainers(containers).map(c => c.name), ['alpha', 'beta', 'zeta'])
})

test('formatPortsDisplay renders host arrows and bare container ports', () => {
  const ports = [
    { hostPort: null, containerPort: 443, protocol: 'tcp' },
    { hostPort: 5050, containerPort: 80, protocol: 'tcp' }
  ]
  assert.equal(Shared.formatPortsDisplay(ports), '443, 5050→80')
})

test('formatPortsDisplay returns empty string for no ports', () => {
  assert.equal(Shared.formatPortsDisplay([]), '')
})

test('statusColorFor classifies running, unhealthy, and stopped containers', () => {
  assert.equal(Shared.statusColorFor({ isRunning: true, healthStatus: 'none' }), 'running')
  assert.equal(Shared.statusColorFor({ isRunning: true, healthStatus: 'healthy' }), 'running')
  assert.equal(Shared.statusColorFor({ isRunning: true, healthStatus: 'unhealthy' }), 'unhealthy')
  assert.equal(Shared.statusColorFor({ isRunning: false, healthStatus: 'none' }), 'stopped')
  assert.equal(Shared.statusColorFor(null), 'stopped')
})

test('isValidContainerId accepts full-length and short hex ids', () => {
  assert.equal(Shared.isValidContainerId('d187d155b275'), true)
  assert.equal(Shared.isValidContainerId('a'.repeat(64)), true)
})

test('isValidContainerId rejects anything that is not plain lowercase hex', () => {
  assert.equal(Shared.isValidContainerId(''), false)
  assert.equal(Shared.isValidContainerId('a'.repeat(65)), false) // too long
  assert.equal(Shared.isValidContainerId('ABCDEF'), false) // uppercase
  assert.equal(Shared.isValidContainerId('abc; rm -rf /'), false)
  assert.equal(Shared.isValidContainerId('abc | head'), false)
  assert.equal(Shared.isValidContainerId('$(whoami)'), false)
  assert.equal(Shared.isValidContainerId(null), false)
})
