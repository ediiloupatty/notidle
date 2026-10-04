#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const pkg = require('../package.json');

const INSTALL_DIR = path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'stayon');
const AGENT = path.join(INSTALL_DIR, 'agent.ps1');
const CONFIG = path.join(INSTALL_DIR, 'config.json');
const STARTUP_LNK = path.join(
  process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
  'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'stayon.lnk'
);
const POWERSHELL = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');

const DEFAULT_CONFIG = {
  hotkeyMods: 3, // Ctrl+Alt
  hotkeyVk: 0x4f, // O
  hotkeyLabel: 'Ctrl+Alt+O',
  intervalSeconds: 60,
  startActive: false,
};

const MODS = { ctrl: 2, control: 2, alt: 1, shift: 4, win: 8 };

const NOT_INSTALLED = 'Not installed. Run: npx stayon';

function parseHotkey(combo) {
  const parts = String(combo).toLowerCase().split('+').map((p) => p.trim()).filter(Boolean);
  let mods = 0;
  let vk = 0;
  let keyLabel = '';
  for (const p of parts) {
    if (MODS[p]) {
      mods |= MODS[p];
    } else if (/^[a-z0-9]$/.test(p)) {
      if (vk) return null;
      vk = p.toUpperCase().charCodeAt(0);
      keyLabel = p.toUpperCase();
    } else if (/^f([1-9]|1[0-9]|2[0-4])$/.test(p)) {
      if (vk) return null;
      vk = 0x70 + Number(p.slice(1)) - 1;
      keyLabel = p.toUpperCase();
    } else {
      return null;
    }
  }
  if (!vk || !mods) return null;
  const label = [
    mods & 2 && 'Ctrl',
    mods & 1 && 'Alt',
    mods & 4 && 'Shift',
    mods & 8 && 'Win',
    keyLabel,
  ].filter(Boolean).join('+');
  return { hotkeyMods: mods, hotkeyVk: vk, hotkeyLabel: label };
}

function ps(script, env) {
  const r = spawnSync(POWERSHELL, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script], {
    encoding: 'utf8',
    windowsHide: true,
    env: { ...process.env, ...env },
  });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

function readConfig() {
  try {
    return { ...DEFAULT_CONFIG, ...JSON.parse(fs.readFileSync(CONFIG, 'utf8')) };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function writeConfig(cfg) {
  fs.writeFileSync(CONFIG, JSON.stringify(cfg, null, 2) + '\n');
}

function isRunning() {
  return ps("try { [void][Threading.Mutex]::OpenExisting('Local\\stayon.agent'); 'yes' } catch { 'no' }").out === 'yes';
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function stopAgent() {
  if (!isRunning()) return false;
  ps("try { [void][Threading.EventWaitHandle]::OpenExisting('Local\\stayon.quit').Set() } catch {}");
  for (let i = 0; i < 25 && isRunning(); i++) sleep(200);
  return true;
}

function startAgent() {
  if (!fs.existsSync(AGENT)) fail(NOT_INSTALLED);
  if (isRunning()) return false;
  // Not spawn({ detached }): powershell.exe exits at once under DETACHED_PROCESS.
  // Start-Process gives the agent its own hidden console, so closing this terminal won't kill it.
  const r = ps(
    "Start-Process -FilePath $env:DC_PS -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('\"' + $env:DC_AGENT + '\"')",
    { DC_PS: POWERSHELL, DC_AGENT: AGENT }
  );
  if (!r.ok) fail('Could not start the agent:\n' + r.err);
  for (let i = 0; i < 50 && !isRunning(); i++) sleep(200);
  return true;
}

function createStartupShortcut() {
  const r = ps(
    [
      '$s = New-Object -ComObject WScript.Shell',
      '$l = $s.CreateShortcut($env:DC_LNK)',
      '$l.TargetPath = $env:DC_PS',
      '$l.Arguments = \'-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "\' + $env:DC_AGENT + \'"\'',
      '$l.WorkingDirectory = $env:DC_DIR',
      '$l.WindowStyle = 7',
      '$l.Description = "stayon - keep Discord Online"',
      '$l.Save()',
    ].join('; '),
    { DC_LNK: STARTUP_LNK, DC_PS: POWERSHELL, DC_AGENT: AGENT, DC_DIR: INSTALL_DIR }
  );
  if (!r.ok) fail('Could not create the startup shortcut:\n' + r.err);
}

function fail(msg) {
  console.error('stayon: ' + msg);
  process.exit(1);
}

function install() {
  const existed = fs.existsSync(AGENT);
  stopAgent();
  fs.mkdirSync(INSTALL_DIR, { recursive: true });
  fs.copyFileSync(path.join(__dirname, '..', 'agent', 'agent.ps1'), AGENT);
  const cfg = readConfig();
  writeConfig(cfg);
  createStartupShortcut();
  startAgent();
  console.log(`stayon ${pkg.version} ${existed ? 'updated' : 'installed'}.

  Press ${cfg.hotkeyLabel} to turn it ON / OFF.
  Tray icon: green = ON, gray = OFF. Left-click it to toggle too.
  Starts automatically when you log in to Windows.

  Change shortcut:  npx stayon hotkey ctrl+shift+f9
  Remove:           npx stayon uninstall`);
}

function uninstall() {
  stopAgent();
  fs.rmSync(STARTUP_LNK, { force: true });
  fs.rmSync(INSTALL_DIR, { recursive: true, force: true });
  console.log('stayon removed.');
}

function setHotkey(combo) {
  const parsed = parseHotkey(combo || '');
  if (!parsed) {
    fail('Invalid shortcut. Use modifiers + one key, e.g. ctrl+alt+o, ctrl+shift+f9, win+alt+d');
  }
  if (!fs.existsSync(INSTALL_DIR)) fail(NOT_INSTALLED);
  writeConfig({ ...readConfig(), ...parsed });
  if (stopAgent()) startAgent();
  console.log(`Shortcut set to ${parsed.hotkeyLabel}.`);
}

function setNudgeInterval(seconds) {
  const n = Number(seconds);
  if (!Number.isInteger(n) || n < 10 || n > 3600) fail('Interval must be a whole number of seconds, 10-3600.');
  if (!fs.existsSync(INSTALL_DIR)) fail(NOT_INSTALLED);
  writeConfig({ ...readConfig(), intervalSeconds: n });
  if (stopAgent()) startAgent();
  console.log(`Interval set to ${n} s.`);
}

function status() {
  if (!fs.existsSync(AGENT)) {
    console.log(NOT_INSTALLED);
    return;
  }
  const cfg = readConfig();
  console.log(`Installed:  ${INSTALL_DIR}
Agent:      ${isRunning() ? 'running (tray icon shows ON/OFF)' : 'not running - start with: npx stayon start'}
Shortcut:   ${cfg.hotkeyLabel}
Interval:   ${cfg.intervalSeconds} s
Autostart:  ${fs.existsSync(STARTUP_LNK) ? 'yes' : 'no'}`);
}

function help() {
  console.log(`stayon ${pkg.version} - keep your Discord status Online while you're away.

Usage:
  npx stayon                 install (or update) and start
  npx stayon hotkey <combo>  change shortcut, e.g. ctrl+alt+o (default)
  npx stayon interval <sec>  idle seconds before each nudge (default 60)
  npx stayon start | stop    start or quit the background agent
  npx stayon status          show what's installed and running
  npx stayon uninstall       remove everything`);
}

function main() {
  if (process.platform !== 'win32') fail('Windows only.');
  const [cmd, arg] = process.argv.slice(2);
  switch (cmd) {
    case undefined:
    case 'install':
      return install();
    case 'uninstall':
    case 'remove':
      return uninstall();
    case 'start':
      return console.log(startAgent() ? 'Started.' : 'Already running.');
    case 'stop':
      return console.log(stopAgent() ? 'Stopped.' : 'Not running.');
    case 'status':
      return status();
    case 'hotkey':
      return setHotkey(arg);
    case 'interval':
      return setNudgeInterval(arg);
    case '-v':
    case '--version':
      return console.log(pkg.version);
    case '-h':
    case '--help':
    case 'help':
      return help();
    default:
      help();
      process.exit(1);
  }
}

main();
