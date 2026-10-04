#!/usr/bin/env node
'use strict';

// Builds site/install.ps1 from scripts/install.template.ps1 with agent/agent.ps1 embedded,
// so the PowerShell installer always ships the same agent as the npm package.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const agent = fs.readFileSync(path.join(root, 'agent', 'agent.ps1'), 'utf8').replace(/\r\n/g, '\n').replace(/\n+$/, '');

if (/[^\x00-\x7f]/.test(agent)) throw new Error('agent/agent.ps1 must be ASCII (it is written with ASCII encoding).');
if (/^'@/m.test(agent)) throw new Error("agent/agent.ps1 must not have a line starting with '@ (it ends the embedding here-string).");

const template = fs.readFileSync(path.join(__dirname, 'install.template.ps1'), 'utf8').replace(/\r\n/g, '\n');
if (!template.includes('\n__AGENT__\n')) throw new Error('install.template.ps1 is missing the __AGENT__ line.');

const out = template.replace('\n__AGENT__\n', () => '\n' + agent + '\n');
fs.writeFileSync(path.join(root, 'site', 'install.ps1'), out);
console.log('site/install.ps1 built (' + out.length + ' bytes)');
