# agent-utils/

Shared tools available to all agents running inside the qwen container.

---

## playwright-tool.sh — Visual Browser Testing

Headless Chromium running **directly inside this container** — no Docker socket required.
Playwright and its Chromium binary are baked into the `qwen-code-cli` image, so any
server started inside the qwen container (e.g. `python3 -m http.server 8080`) is reachable
at `http://localhost:<port>` from Playwright with no extra configuration.

Screenshots are saved to `/workspace/screenshots/` and can be viewed by passing the path
to qwen with the `@` prefix.

### Quick reference

```bash
# Start a persistent browser session (preserves scroll, modals, form state between calls)
/workspace/agent-utils/playwright-tool.sh start-browser
# → prints: Browser started on CDP port 9222 (pid XXXXX)

# Navigate to a URL and take a screenshot
/workspace/agent-utils/playwright-tool.sh goto http://localhost:8080
# → prints: SCREENSHOT_SAVED: screenshots/screenshot_001.png

# View the screenshot with qwen
qwen --yolo --prompt "@screenshots/screenshot_001.png What do you see?"

# Get real selectors from the live DOM (run this BEFORE clicking anything)
# NOTE: inspect does NOT produce a screenshot — it is data-only
/workspace/agent-utils/playwright-tool.sh inspect
# → prints: ELEMENTS: [ {"tag":"button","text":"Buy Now","selector":"#buy-btn"}, ... ]
# → then:   NO_SCREENSHOT

# Click an element using a real selector from inspect
/workspace/agent-utils/playwright-tool.sh click "#buy-btn"

# Click at pixel coordinates (fallback when selector-based click fails)
/workspace/agent-utils/playwright-tool.sh clickxy 640 450

# Fill a form field
/workspace/agent-utils/playwright-tool.sh fill "#email" "test@example.com"

# Scroll down 800px
/workspace/agent-utils/playwright-tool.sh scroll 0 800

# Evaluate JavaScript in the page context
/workspace/agent-utils/playwright-tool.sh eval "document.title"

# Show current session state (URL + screenshot counter)
/workspace/agent-utils/playwright-tool.sh session

# Clear session state when done
/workspace/agent-utils/playwright-tool.sh stop
```

### Full QA workflow for a web app

```bash
# 1. Start the app (from the "How to Run" section in the ready-for-qa task)
cd /workspace/outputs/my-site
python3 -m http.server 8080 &
SERVER_PID=$!
sleep 1

# 2. Start persistent browser (keeps ALL state between calls)
/workspace/agent-utils/playwright-tool.sh start-browser

# 3. Initial screenshot
/workspace/agent-utils/playwright-tool.sh goto http://localhost:8080
# → SCREENSHOT_SAVED: screenshots/screenshot_001.png

# 3. Visual inspection
qwen --yolo --prompt "@screenshots/screenshot_001.png Does this page look correct? List any issues."

# 4. Get real selectors from the DOM before clicking anything
/workspace/agent-utils/playwright-tool.sh inspect
# → ELEMENTS: [{"tag":"button","text":"Buy Now","id":"buy-btn","selector":"#buy-btn"}, ...]

# 5. Click using the real selector from inspect
/workspace/agent-utils/playwright-tool.sh click "#buy-btn"
# → SCREENSHOT_SAVED: screenshots/screenshot_002.png
qwen --yolo --prompt "@screenshots/screenshot_002.png Did clicking Buy trigger the expected behavior?"

# 5b. If selector click fails, fall back to coordinates (estimate from 1920x1080 screenshot)
/workspace/agent-utils/playwright-tool.sh clickxy 640 450

# 6. Clean up
/workspace/agent-utils/playwright-tool.sh stop
kill $SERVER_PID 2>/dev/null || true
```

### Implementation notes

- **playwright-tool.sh** — thin bash wrapper; sets `NODE_PATH` and `PLAYWRIGHT_BROWSERS_PATH` then calls `node` directly.
- **playwright-runner.js** — Node.js script executed in this container.
  Persists session state (current URL + screenshot counter) in `/workspace/.playwright-session.json`.
- Playwright (`@1.49.0`) and its Chromium binary are installed in `/opt/playwright-agent/` and
  `/opt/playwright-browsers/` at image build time — no network access needed at runtime.
- **`start-browser`** launches Chromium as a background process with `--remote-debugging-port=9222`.
  All subsequent commands connect to it via CDP and share the same page state — scroll position,
  open modals, filled forms, and JS state are all preserved between calls. Always call `start-browser`
  at the beginning of a QA session and `stop` at the end.
- **`inspect`** queries the live DOM for all interactive elements and returns a JSON list with the best
  available selector for each (priority: `#id` > `[data-testid]` > `tag.class` > `tag:has-text("...")`).
  **Does not take a screenshot** — prints `NO_SCREENSHOT` instead. Data-only operation.
- **`clickxy`** clicks at pixel coordinates using `page.mouse.click(x, y)`. Use as a fallback when a
  CSS selector click fails — coordinates can be estimated from the 1920×1080 screenshot.
- All interaction actions (`click`, `clickxy`, `fill`, `type`, `hover`) wait 500 ms after the action
  before taking the screenshot, so JS animations and state changes finish before the image is captured.
