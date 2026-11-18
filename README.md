# Wildlands

A small, original voxel sandbox made for **Godot 4.7**. Explore a procedurally generated landscape, mine blocks and build freely. This is a playable creative-mode foundation, not a complete Minecraft recreation: there are no mobs, crafting, survival systems, multiplayer or infinite terrain.

## Play

1. Install Godot 4.7 (standard edition), open the project manager, and import `project.godot`.
2. Open the project and press **F5** to run it. The world is built on first launch; allow a moment for the loading screen.
3. For Android or iOS, install the appropriate Godot export templates and configure the platform's export settings in Godot. Touch controls are enabled automatically on mobile, or can be enabled in Settings.

### Controls

- **WASD** move, **mouse** look, **Space** jump, **Shift** sprint.
- **Left click** mine; **right click** place the selected block. Reach is six blocks.
- **1–7**, the mouse wheel, or the hotbar select a block. Blocks are unlimited.
- **Esc** or the Settings button opens the settings menu and releases the mouse.
- On touch screens, drag on the left to move and on the right to look. Use the Mine, Place and Jump buttons. Tap a hotbar slot to select it.

Settings include field of view, view distance, look sensitivity, shadows, fog and touch controls. Lower view distance or disable shadows for slower devices. Edits and settings are stored locally in Godot's `user://` directory; remove `world.cfg` there to reset the world. Player position isn't saved. The world is a finite 96 × 96 block area with a height limit of 32 blocks.

## Project structure

- `scripts/world.gd`: deterministic terrain, trees, procedural block textures, chunk meshes and saved edits.
- `scripts/player.gd`: first-person movement, raycast interactions and touch input.
- `scripts/game.gd`: scene setup, lighting, sky and water.
- `scripts/hud.gd`: hotbar, loading screen, touch buttons and graphics settings.

All art is generated at runtime and has no external asset dependencies. Uses the Compatibility renderer for broad desktop and mobile support.

## Smoke test

A headless smoke test exercises generation, keyboard movement, terrain collision, raycast mining and placement, settings, and persistence across a restart. On Linux, run it with a temporary data directory so it cannot change your normal save:

```sh
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --editor --quit
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script res://tests/smoke_test.gd
```

The test does not check actual rendered graphics, performance, or touch input on a device.
