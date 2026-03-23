# QA Task: Complex Fused Rocks Visualization

## What Changed
- Created a complete 3D rock visualization system from scratch in `/workspace/outputs/threejs-game/`
- Implemented **fused multi-cube rock formations** where two cubes of visibly different sizes are merged together (side-by-side, stacked, or corner fusion)
- Increased rock count to 150 rocks by default (configurable 50-300)
- Added configurable fusion rate (default 40% of rocks are fused formations)
- Implemented collision detection to prevent excessive rock overlap
- Added UI controls for rock count, fusion rate, and regeneration
- Included FPS counter and statistics panel for performance monitoring

## How to Run
```bash
cd /workspace/outputs/threejs-game
python3 -m http.server 8080
```
Then open: http://localhost:8080

## Core Functionality to Test
- Verify increased rock count is visible on screen (150+ rocks)
- Confirm some rocks are single cubes while others are fused formations (check stats panel)
- Verify fused rocks show two distinct cube sizes that are visibly different
- Check that fused cubes are properly connected (no gaps between them)
- Test performance with increased rock count (FPS should remain smooth, ideally 50+)
- Exercise UI controls: adjust rock count slider, fusion rate slider, click regenerate button
- Test camera controls: rotate (left-click drag), pan (right-click drag), zoom (scroll)
- Edge case: Set fusion rate to 0% and 100% to verify extremes work correctly
- Edge case: Set rock count to maximum (300) and verify performance remains acceptable
