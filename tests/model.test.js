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
