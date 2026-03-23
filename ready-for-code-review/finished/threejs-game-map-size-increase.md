# QA Task: ThreeJS Game Map Size Increase

## What Changed
- Increased map size from 200x200 to 500x500 units (2.5x linear = 6.25x area)
- Increased rock count from 50 to 150 to maintain obstacle density across larger area
- Increased safe zone radius from 15 to 25 units for larger spawn-safe area
- Increased starfield radius from 100-200 to 200-400 to match larger map scale
- Updated SITE-INDEX.MD documentation

## How to Run
```bash
cd /workspace/outputs/threejs-game
python3 -m http.server 8000
```
Then open: http://localhost:8000

## Core Functionality to Test
- Walk in multiple directions (WASD) and verify it takes significantly longer to reach map edges compared to before
- Verify rocks are properly distributed across the expanded terrain
- Verify terrain generation works correctly at the new scale with no visual artifacts
- Test in auto-test mode (`?auto-test=true`) to ensure automated tests still pass using Playwright at `/workspace/agent-utils/playwright-tool.sh`
