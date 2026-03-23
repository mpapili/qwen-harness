# QA Task: Jump on Non-Ground Objects Bug Fix

## What Changed
- Added `checkStandingOnObject()` method to detect when player is standing on top of any collision object (rocks, platforms, etc.)
- Added `getObjectSurfaceHeight()` method to get the Y position of the highest object surface under the player
- Modified the `update()` method in physics.js to set `isGrounded = true` when player is standing on any solid object, not just terrain
- Jump now works consistently from rocks, platforms, and other solid objects with the same jump velocity as from ground

## How to Run
```bash
cd /workspace/outputs/threejs-game
python3 -m http.server 8080
```
Then open: http://localhost:8080

Click to start the game, then use WASD to move and Space to jump.

## Core Functionality to Test
- Player can jump when standing on a rock (the main bug fix)
- Player can jump when standing on any platform or solid object
- Jump height/velocity is consistent across different surface types (ground, rocks, platforms)
- Player cannot jump while in mid-air (normal jump restriction should still apply)
- Edge case: Verify jump works when transitioning between different object types (e.g., jumping from ground onto a rock, then jumping again)
- Edge case: Verify jump works on small/narrow objects

Use Playwright via `/workspace/agent-utils/playwright-tool.sh` to automate testing if needed.
