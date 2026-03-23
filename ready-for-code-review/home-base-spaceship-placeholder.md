# QA Task: Home Base Spaceship Placeholder

## What Changed
- Added a white spaceship placeholder as the player's "home base" near the world origin
- The spaceship is composed of 2 geometric shapes: a cylinder (body) and a cone (nose)
- Positioned at coordinates (-25, 0, 0) to be visible but not obstruct player spawning at origin
- Applied white material with subtle emissive glow for visibility in dark scenes
- Marked as static/non-collidable object (userData flags: isStatic, isHomeBase, isCollidable: false)
- Added "Home Base: Active" indicator to the info panel UI

## How to Run
```bash
cd /workspace/outputs/threejs-game
python3 -m http.server 8080
```
Then open: http://localhost:8080

## Core Functionality to Test
- Verify the white spaceship is visible from the player spawn point (origin)
- Confirm the spaceship is positioned to the left of the scene (negative X axis) and does not obstruct the center area
- Check that the spaceship remains stationary (does not move or rotate during animation)
- Validate the white color is clearly visible in the scene lighting
- Test orbit controls (click & drag) to view the spaceship from multiple angles
- Confirm the "Home Base: Active" indicator appears in the info panel

Use Playwright via `/workspace/agent-utils/playwright-tool.sh` to verify visual rendering and UI elements.
