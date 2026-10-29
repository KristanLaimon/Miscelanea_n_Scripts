// Dependency-free smoke check using a local Chromium/Edge DevTools connection.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const root = path.resolve('dist/web');
const target = path.resolve('target');
await mkdir(target, { recursive: true });
const profile = await mkdtemp(path.join(target, 'browser-smoke-'));
const executable = process.argv[2] ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const file = path.resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (!file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
    const data = await readFile(file);
    const type = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' }[path.extname(file)] ?? 'application/octet-stream';
    response.writeHead(200, { 'Content-Type': type }).end(data);
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const browser = spawn(executable, ['--headless=new', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], { windowsHide: true, stdio: 'ignore' });
let socket;
try {
  let debugPort;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { debugPort = Number((await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]); break; }
    catch { await delay(100); }
  }
  assert(debugPort, 'Browser DevTools did not start');
  const pages = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
  const page = pages.find(page => page.type === 'page');
  assert(page, 'No browser page');
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let sequence = 0;
  const pending = new Map();
  const errors = [];
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
    if (message.id) {
      const callback = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) callback.reject(new Error(JSON.stringify(message.error))); else callback.resolve(message.result);
    }
  };
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++sequence; pending.set(id, { resolve, reject }); socket.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => (await call('Runtime.evaluate', { expression, returnByValue: true })).result.value;
  await call('Runtime.enable');
  await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', { width: 1440, height: 960, deviceScaleFactor: 1, mobile: false });
  await call('Page.navigate', { url: `http://127.0.0.1:${port}/` });
  let ready = false;
  for (let attempt = 0; attempt < 150; attempt++) {
    ready = await evaluate('!document.getElementById("loading")');
    if (ready || errors.length) break;
    await delay(200);
  }
  assert.deepEqual(errors, [], 'Browser startup threw an exception');
  assert(ready, `Editor did not start: ${await evaluate('document.body.innerText')}`);
  assert(await evaluate('document.querySelector("canvas").width > 0'), 'Canvas is empty');
  await delay(400);
  await writeFile(path.join(target, 'browser-wide.png'), Buffer.from((await call('Page.captureScreenshot')).data, 'base64'));
  const click = async (x, y) => {
    await call('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    await delay(150);
  };
  await call('Page.setInterceptFileChooserDialog', { enabled: true });
  await click(330, 35); // Open project.
  assert(await evaluate('!!document.querySelector("input[type=file]")'), 'Project chooser did not open');
  // A cancelled chooser must release the editor so another operation can start.
  await evaluate('document.querySelector("input[type=file]").dispatchEvent(new Event("cancel"))');
  await delay(200);
  assert(!await evaluate('!!document.querySelector("input[type=file]")'), 'Cancelled chooser remained open');
  await click(330, 35);
  const document = await call('DOM.getDocument');
  const input = await call('DOM.querySelector', { nodeId: document.root.nodeId, selector: 'input[type=file]' });
  assert(input.nodeId, 'Editor remained busy after cancelling the first chooser');
  await call('DOM.setFileInputFiles', { nodeId: input.nodeId, files: [path.resolve('examples/demo.kdj')] });
  await delay(300);
  assert(!await evaluate('!!document.querySelector("input[type=file]")'), 'Project import did not finish');
  const downloads = path.join(profile, 'downloads');
  await mkdir(downloads);
  await call('Page.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });
  await click(410, 35); // Save project to a real browser download.
  let downloaded;
  for (let attempt = 0; attempt < 50; attempt++) {
    try { downloaded = await readFile(path.join(downloads, 'demo.kdj')); break; }
    catch { await delay(100); }
  }
  assert(downloaded, 'Project download did not finish');
  assert.deepEqual(downloaded, await readFile('examples/demo.kdj'), 'Downloaded project changed during the round trip');
  // Real keyboard input exercises the app's playback shortcut.
  await call('Input.dispatchKeyEvent', { type: 'keyDown', key: ' ', code: 'Space', windowsVirtualKeyCode: 32 });
  await call('Input.dispatchKeyEvent', { type: 'keyUp', key: ' ', code: 'Space', windowsVirtualKeyCode: 32 });
  await delay(500);
  await call('Input.dispatchKeyEvent', { type: 'keyDown', key: ' ', code: 'Space', windowsVirtualKeyCode: 32 });
  await call('Input.dispatchKeyEvent', { type: 'keyUp', key: ' ', code: 'Space', windowsVirtualKeyCode: 32 });
  await call('Emulation.setDeviceMetricsOverride', { width: 800, height: 650, deviceScaleFactor: 1.25, mobile: false });
  await delay(400);
  await writeFile(path.join(target, 'browser-compact.png'), Buffer.from((await call('Page.captureScreenshot')).data, 'base64'));
  assert.deepEqual(errors, [], 'Browser interaction threw an exception');
  console.log('PASS: browser startup, chooser cancellation, project upload/download round trip, keyboard input, resize, high DPI; screenshots in target/browser-*.png');
} finally {
  socket?.close();
  browser.kill();
  server.close();
}
