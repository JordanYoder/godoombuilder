# GoDoomBuilder

Doom-style sector mapping for **Godot 4.7**, in the 3D editor. If you've used
Ultimate Doom Builder, this should feel familiar: draw floor outlines, give each
area a floor and ceiling height, and the walls, steps, ledges and collision are
built for you. Unlike a 2D map editor, you draw and edit directly in Godot's 3D
viewport, so you see the result as you work.

A standalone plugin with no other add-ons required.

## Install

1. Copy `addons/godoombuilder` into your project's `addons/` folder.
2. Enable **GoDoomBuilder** in Project Settings → Plugins.
3. Open a 3D scene and find the **Sectors** tab next to the Inspector. Click
   **New Sector Map** (or add a `DMMap` node with Add Node).

## How it works

Each area you draw is a **sector**: a floor area with a floor height, ceiling
height, and floor/ceiling/wall materials.

- Walls are generated automatically: full walls around the outside, and step
  (lower) and upper walls where neighbouring sectors' heights differ.
- Drawing inside a sector makes a sub-sector (platform, pit, pillar) that
  starts with the same heights. Drawing across sectors cuts them.
- Deleting a sector leaves solid space (e.g. a pillar).
- Collision is built automatically, in the editor and in the game.
- Textures are world-aligned (one repeat per meter), so they line up across
  neighbouring floors and walls.
- Only the sector shapes, heights and materials are saved in your scene; the
  mesh is rebuilt when the scene loads.

## Controls (with the Sector Map selected)

- `D` — draw a sector: click points (grid snapped; snaps to existing corners),
  click the first point or press Enter to finish, Backspace removes a point,
  hold Shift for no grid snap, Esc cancels. For an exact side, type a length
  and press Enter: the point goes that far toward the mouse (angles snap to
  15°; Shift for any angle).
- `B` — draw a rectangle: click a corner, then the opposite corner. For an
  exact size, type the width, Tab, the depth, Enter (or set Width/Depth in the
  dock). A typed side with the other left free follows the mouse.
- Typed numbers are in the current units (e.g. `64` = 2 m in Doom units).
- Click — select a sector; Shift+click adds to the selection.
- Drag a selected sector's corner (square handles) or wall line to reshape it.
  Corners shared with neighbouring sectors, and walls meeting it, move along,
  so rooms stay connected. Moves that would cross or overlap are refused; Esc
  cancels a drag.
- Width / Depth in the dock resize the selected sectors exactly, keeping the
  center or a chosen corner fixed.
- Page Up / Page Down, or Alt+mouse wheel, over a floor or ceiling — raise or
  lower it one grid step (all selected sectors if the hovered one is selected).
- `[` / `]` — smaller / larger grid. Delete — delete selected sectors.
- Right mouse button still flies Godot's editor camera.
- The dock edits heights and materials of the selection, the grid, units
  (meters, or Doom units at 32 per meter), and defaults for new sectors.

Every edit can be undone with Ctrl+Z.

## Planned

Splitting/joining sectors, per-wall textures, texture alignment, a stair
builder, doors and lifts, lighting, a things palette, slopes, and rooms over
rooms.

## This repository

The repo is also a Godot project for developing the plugin:

- `test/demo_level.tscn` is the main scene (F5 plays it): a hall with stairs
  up to a platform, a pit, a pillar, a low corridor, and a second room with a
  sunken pool under a tall skylight. Regenerate it with
  `--headless --path . --script res://test/make_demo_level.gd`.
- `test/player/fps_player.tscn` is a simple first-person player you can drop
  into any scene with a map: WASD, mouse look, Space jump, Shift run, V fly,
  Esc frees the mouse, H hides the help. It walks up steps up to 0.6 m like a
  Doom player, with the view easing over each step.
- Tests (each prints `RESULT: OK` when everything passes):

  ```
  godot --headless --path . --script res://test/map_test.gd
  godot --headless --path . --script res://test/tool_test.gd
  godot --headless --path . --script res://test/player_test.gd
  ```

## License

MIT — see [LICENSE](LICENSE).

GoDoomBuilder is a fan-made tool and is not affiliated with or endorsed by id
Software or the makers of Doom Builder.
