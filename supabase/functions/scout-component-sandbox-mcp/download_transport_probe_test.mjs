import assert from 'node:assert/strict'
import fs from 'node:fs'

const schema = fs.readFileSync('../_shared/scout_sandbox_contract_schema.ts', 'utf8')
const index = fs.readFileSync('./index.ts', 'utf8')
const view = fs.readFileSync('./view.ts', 'utf8')
const template = fs.readFileSync('./view.template.html', 'utf8')
const design = fs.readFileSync('./DESIGN_CONTRACT.md', 'utf8')

assert.match(schema, /download_probe:\{type:'boolean'/, 'input schema must expose only the temporary boolean diagnostic flag')
assert.match(index, /download_probe=true only when the owner explicitly requests/, 'tool description must constrain the canary to explicit owner requests')
assert.match(index, /'scout\/downloadProbe': true/, 'tool result must activate the View through private result metadata')
assert.equal((view.match(/new App\(/g) || []).length, 1, 'download probe must reuse the one root App lifecycle')
assert.match(view, /app\.getHostCapabilities\?\.\(\)\?\.downloadFile/, 'probe must gate on the host-advertised download capability')
assert.match(view, /await app\.downloadFile\(/, 'probe must use the MCP Apps downloadFile method on the existing root App')
assert.match(view, /file:\/\/\/scout-download-probe\.txt/, 'probe filename must remain fixed and synthetic')
assert.match(view, /Scout MCP Apps download transport probe\.\\r\\n/, 'probe payload must remain fixed synthetic text')
assert.doesNotMatch(view, /window\.openai/, 'probe must not restore ChatGPT-specific window APIs')
assert.doesNotMatch(view, /navigator\.share/, 'probe must not use device-share fallback')
assert.doesNotMatch(view, /URL\.createObjectURL/, 'probe must not use browser object-URL downloads')
assert.doesNotMatch(view, /new Blob\(/, 'probe must not create browser Blob download payloads')
assert.doesNotMatch(view, /import\(['"]https?:\/\//, 'probe must not dynamically import a second MCP Apps SDK')
assert.match(template, /title="Investigate behavior is not wired in this sandbox" disabled>Investigate<\/button>/, 'normal card action must remain inert in the template')
assert.match(design, /Temporary owner approval — 2026-09-17 download transport canary/, 'temporary owner approval must be durable and explicit')

console.log('Scout download transport probe regression passed')
