# QA Task: Jump Debug Logging and Bug Fix

## What Changed

**Bug Fixed:** The player character could not jump because the `jump()` method was being called BEFORE the grounded state was updated in the physics update loop. This meant `isGrounded` was always checking the previous frame's state, which could be false even when the player was on the ground.

**Fix Applied:** Reordered the physics update sequence in `physics.js`:
1. First calculate horizontal position and determine grounded state
2. THEN call `jump()` so it checks the current frame's grounded state
3. Apply gravity and recalculate position

**Console Logging Added:**
- `input.js`: Logs when Space key is pressed/released and when `isJumpPressed()` returns true
- `physics.js jump()`: Logs all conditions checked (canJump, isGrounded, cooldown timer) and which condition failed if jump is blocked
- `physics.js update()`: Logs terrain height, grounded state determination, and final isGrounded value

All logs use `[JUMP DEBUG]` prefix for easy filtering in browser DevTools.

## How to Run

```bash
cd /workspace/outputs/threejs-game
python3 -m http.server 8000
```

Then open: http://localhost:8000

Click on the screen to start and lock the mouse pointer.

## Core Functionality to Test

1. **Jump on ground**: Press Space while standing on terrain - player should jump and console should show `[JUMP DEBUG] [PHYSICS.jump()] ALL CONDITIONS PASSED - executing jump`

2. **Jump blocked when airborne**: Press Space while in the air - console should show `[JUMP DEBUG] [PHYSICS.jump()] JUMP BLOCKED` with `isGrounded is false` as the reason

3. **Jump cooldown**: Rapidly press Space - jumps should have 150ms delay between them (check console for cooldown timer messages)

4. **Console logs appear**: Open browser DevTools Console and verify `[JUMP DEBUG]` messages appear when pressing Space

5. **Horizontal movement preserved**: While jumping, WASD movement should still work (the fix recalculates vertical position separately from horizontal)

Use Playwright at `/workspace/agent-utils/playwright-tool.sh` if automated testing is needed.
