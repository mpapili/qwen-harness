# QA Task: Jump Mechanics Fix

## What Changed
- **Removed jump cooldown**: Player can now jump instantly from any position when grounded (no 150ms delay)
- **Added 'jump over' check disable**: 100ms grace period after jump where collision checks are disabled, allowing player to jump over obstacles without being blocked
- **Increased jump force**: Changed from 8 to 12 for more responsive upward movement
- **Tightened ground detection**: Reduced tolerance from 1.5 to 0.1 units for precise ground detection
- **Jump mechanics**: Player can leave the ground immediately when jump is pressed, gravity applies downward acceleration each frame, and player can instantly jump again upon landing

## How to Run
```bash
cd /workspace/outputs/threejs-game
python3 -m http.server 8000
```
Then open: http://localhost:8000?auto-test=true

Click to start (or auto-starts in test mode).

## Core Functionality to Test
Verify the jump mechanics using Playwright (`/workspace/agent-utils/playwright-tool.sh`):
- Player can jump from any horizontal position by pressing Space
- Jump creates a consistent upward arc with gravity pulling player down
- Player can immediately jump again after landing (no cooldown delay)
- Rapid Space key presses only register when grounded (no mid-air jumps)
- Player can jump over small obstacles without being blocked during initial jump frames
- Edge case: jumping near platform/rock boundaries works correctly

Use `window.gameTestAPI.jump()` to trigger jumps programmatically and `window.gameTestAPI.getState()` to verify player position/velocity.
