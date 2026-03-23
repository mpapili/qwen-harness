#!/usr/bin/env node
/**
 * playwright-runner.js
 * Runs inside the official Playwright Docker container.
 * Called by playwright-tool.sh with action + args.
 *
 * Usage:
 *   node playwright-runner.js start-browser              Launch persistent Chromium via CDP
 *   node playwright-runner.js goto      <url>
 *   node playwright-runner.js screenshot
 *   node playwright-runner.js inspect                    List all interactive elements (no screenshot)
 *   node playwright-runner.js click     <selector>
 *   node playwright-runner.js clickxy   <x> <y>          Click at pixel coordinates
 *   node playwright-runner.js fill      <selector> <value>
 *   node playwright-runner.js type      <selector> <value>
 *   node playwright-runner.js hover     <selector>
 *   node playwright-runner.js scroll    <x> <y>
 *   node playwright-runner.js eval      <js-expression>
 *
 * State is persisted between calls via /workspace/.playwright-session.json
 * Screenshots are saved to /workspace/screenshots/
 *
 * Persistent session:
 *   Call start-browser once at the start of a QA session. All subsequent
 *   commands connect to the same Chromium process via CDP, so JS state
 *   (scroll position, open modals, filled forms) is preserved between calls.
 *   Call stop (via playwright-tool.sh stop) to kill the browser when done.
 */

const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const STATE_FILE = '/workspace/.playwright-session.json';
const SCREENSHOTS_DIR = '/workspace/screenshots';

function readState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return { url: null, count: 0 };
  }
}

function writeState(state) {
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

function nextScreenshotPath(count) {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
  return path.join(SCREENSHOTS_DIR, `screenshot_${String(count).padStart(3, '0')}.png`);
}

async function handleStartBrowser(state) {
  const execPath = chromium.executablePath();
  const proc = spawn(execPath, [
    '--headless=new',
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--remote-debugging-port=9222',
    '--window-size=1920,1080',
    '--user-data-dir=/tmp/pw-profile',
    '--disable-cache',
    '--use-gl=angle',
    '--use-angle=swiftshader',
    '--enable-webgl',
    '--enable-webgl2',
    '--ignore-gpu-blocklist',
    '--disable-gpu-sandbox',
    'about:blank',
  ], { detached: true, stdio: 'ignore' });
  proc.unref();
  // Give Chrome time to start and open the debugging port
  await new Promise(r => setTimeout(r, 1500));
  writeState({ url: null, count: state.count || 0, cdpPort: 9222, cdpPid: proc.pid });
  console.log(`Browser started on CDP port 9222 (pid ${proc.pid})`);
}

async function run() {
  const [,, action, ...args] = process.argv;

  if (!action) {
    console.error('Usage: node playwright-runner.js <action> [args...]');
    process.exit(1);
  }

  const state = readState();

  // start-browser is handled before any browser connection
  if (action === 'start-browser') {
    await handleStartBrowser(state);
    return;
  }

  // --- browser setup: CDP (persistent) or fresh launch (fallback) ---
  let browser, context, page, usingCDP = false;

  if (state.cdpPort) {
    try {
      browser = await Promise.race([
        chromium.connectOverCDP(`http://localhost:${state.cdpPort}`),
        new Promise((_, reject) => setTimeout(() => reject(new Error('CDP connect timeout')), 5000)),
      ]);
      usingCDP = true;
      const contexts = browser.contexts();
      if (contexts.length > 0) {
        context = contexts[0];
      } else {
        context = await browser.newContext({
          viewport: { width: 1920, height: 1080 },
          ignoreHTTPSErrors: true,
        });
      }
      const pages = context.pages();
      page = pages.length > 0 ? pages[0] : await context.newPage();
    } catch (cdpErr) {
      console.error(`CDP connect failed (${cdpErr.message}), falling back to fresh browser`);
      usingCDP = false;
    }
  }

  if (!usingCDP) {
    browser = await chromium.launch({
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--use-gl=angle',
        '--use-angle=swiftshader',
        '--enable-webgl',
        '--enable-webgl2',
        '--ignore-gpu-blocklist',
        '--disable-gpu-sandbox',
      ],
    });
    context = await browser.newContext({
      viewport: { width: 1920, height: 1080 },
      ignoreHTTPSErrors: true,
    });
    page = await context.newPage();
  }

  const count = (state.count || 0) + 1;
  const screenshotPath = nextScreenshotPath(count);
  let newUrl = state.url;

  try {
    switch (action) {
      case 'goto': {
        const url = args[0];
        if (!url) { console.error('goto requires a URL'); process.exit(1); }
        await page.goto(url, { waitUntil: 'load', timeout: 15000 });
        await page.waitForTimeout(1000); // JS init settle
        newUrl = page.url();
        break;
      }

      case 'screenshot': {
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        // CDP: page already has state — no reload needed
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        newUrl = page.url();
        break;
      }

      case 'inspect': {
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        const elements = await page.evaluate(() => {
          const results = [];
          const seen = new Set();

          function bestSelector(el) {
            if (el.id) return `#${el.id}`;
            const testId = el.getAttribute('data-testid');
            if (testId) return `[data-testid="${testId}"]`;
            const tag = el.tagName.toLowerCase();
            const classes = Array.from(el.classList).filter(c => c.trim()).join('.');
            if (classes) return `${tag}.${classes}`;
            const text = el.textContent.trim().slice(0, 40).replace(/"/g, '\\"');
            if (text) return `${tag}:has-text("${text}")`;
            return tag;
          }

          const queries = ['button', 'a[href]', 'input', 'select', 'textarea', 'label', '[role="button"]', '[onclick]'];
          for (const sel of queries) {
            document.querySelectorAll(sel).forEach(el => {
              if (seen.has(el)) return;
              seen.add(el);
              const entry = {
                tag: el.tagName.toLowerCase(),
                text: el.textContent.trim().slice(0, 60),
                selector: bestSelector(el),
              };
              if (el.id) entry.id = el.id;
              if (el.className && typeof el.className === 'string' && el.className.trim()) entry.class = el.className.trim();
              if (el.getAttribute('href')) entry.href = el.getAttribute('href');
              if (el.type) entry.type = el.type;
              results.push(entry);
            });
          }
          return results;
        });
        console.log('ELEMENTS:');
        console.log(JSON.stringify(elements, null, 2));
        // inspect does NOT take a screenshot — it's a data-only operation
        console.log('NO_SCREENSHOT');
        if (!usingCDP) await browser.close();
        return; // exit early — count is NOT incremented
      }

      case 'click': {
        const selector = args[0];
        if (!selector) { console.error('click requires a selector'); process.exit(1); }
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        await page.click(selector, { timeout: 10000 });
        await page.waitForTimeout(500);
        newUrl = page.url();
        break;
      }

      case 'clickxy': {
        const x = parseFloat(args[0]);
        const y = parseFloat(args[1]);
        if (isNaN(x) || isNaN(y)) { console.error('clickxy requires x and y coordinates'); process.exit(1); }
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        await page.mouse.click(x, y);
        await page.waitForTimeout(500);
        newUrl = page.url();
        break;
      }

      case 'fill': {
        const [selector, ...valueParts] = args;
        const value = valueParts.join(' ');
        if (!selector) { console.error('fill requires a selector and value'); process.exit(1); }
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        await page.fill(selector, value, { timeout: 10000 });
        await page.waitForTimeout(500);
        newUrl = page.url();
        break;
      }

      case 'type': {
        const [selector, ...valueParts] = args;
        const value = valueParts.join(' ');
        if (!selector) { console.error('type requires a selector and value'); process.exit(1); }
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        await page.type(selector, value, { delay: 50, timeout: 10000 });
        await page.waitForTimeout(500);
        newUrl = page.url();
        break;
      }

      case 'hover': {
        const selector = args[0];
        if (!selector) { console.error('hover requires a selector'); process.exit(1); }
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        await page.hover(selector, { timeout: 10000 });
        await page.waitForTimeout(500);
        newUrl = page.url();
        break;
      }

      case 'scroll': {
        const x = parseInt(args[0] || '0', 10);
        const y = parseInt(args[1] || '500', 10);
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        await page.evaluate(([sx, sy]) => window.scrollBy(sx, sy), [x, y]);
        await page.waitForTimeout(500);
        newUrl = page.url();
        break;
      }

      case 'eval': {
        const jsExpr = args.join(' ');
        if (!jsExpr) { console.error('eval requires a JS expression'); process.exit(1); }
        if (!state.url) { console.error('No active session. Run "goto <url>" first.'); process.exit(1); }
        if (!usingCDP) await page.goto(state.url, { waitUntil: 'load', timeout: 15000 });
        const result = await page.evaluate(jsExpr);
        console.log('eval result:', JSON.stringify(result));
        newUrl = page.url();
        break;
      }

      default:
        console.error(`Unknown action: ${action}`);
        console.error('Available actions: start-browser, goto, screenshot, inspect, click, clickxy, fill, type, hover, scroll, eval');
        process.exit(1);
    }

    // Take screenshot and save state for all actions except inspect (which returns early above)
    await page.screenshot({ path: screenshotPath, fullPage: false });
    writeState({ ...state, url: newUrl, count });

    // Output relative path so the agent can reference it with @
    const relativePath = screenshotPath.replace('/workspace/', '');
    console.log(`SCREENSHOT_SAVED: ${relativePath}`);
    console.log(`CURRENT_URL: ${newUrl}`);

  } catch (err) {
    console.error(`Playwright error during "${action}": ${err.message}`);
    if (!usingCDP) await browser.close();
    process.exit(1);
  }

  // CDP browser stays alive between calls — only disconnect the WebSocket, never close Chrome.
  // Without disconnect(), Playwright keeps the Node event loop alive via the open WebSocket
  // and the process hangs indefinitely after printing SCREENSHOT_SAVED.
  if (usingCDP) await browser.disconnect();
  else await browser.close();
}

run();
