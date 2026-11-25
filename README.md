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
- A sector can be open to the sky (untick **Has ceiling**): no ceiling is
  built, its walls still rise to its ceiling height, and there are no upper
  walls between two open sectors (like Doom's sky).
- Collision is built automatically, in the editor and in the game.
- Textures are world-aligned (one repeat per meter), so they line up across
  neighbouring floors and walls.
- Only the sector shapes, heights and materials are saved in your scene; the
  mesh is rebuilt when the scene loads.

## Controls (with the Sector Map selected)

While a Sector Map is selected, a **toolbar** above the 3D viewport has the
tools (Select, Draw, Rectangle), the actions on the selection (Join, Simplify,
Thicken with its thickness, Delete / Hide Wall), Floor / Ceiling toggles, and
the grid and units. The **Sectors** panel next to the Inspector has the same
actions plus every value of the selection; its *New sectors* and *Controls*
sections are folded away until you open them.


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
- Click a wall — select just that wall. In the dock, set its own **Wall top**
  / **Wall bottom** (e.g. a 1 m half wall) without changing the rest of the
  room, or press **Delete** (or tick **Hidden**) to remove it as an opening
  with no collision. Hidden walls of the selected sector show as dashed
  outlines; **Show Hidden Walls** brings them back, **Reset Wall** undoes a
  wall's own settings. Settings stay with the wall when you drag its corners.
  (Walls between two sectors take their height from the neighbouring floor or
  ceiling, so they can be hidden but not resized.)
- **Simplify Sector** (dock) — remove points that don't change the selected
  sectors' shapes: extra points along straight walls (within 1 mm) and seams
  inside the sector. Points where a neighbouring sector's corner touches the
  wall still show as handles, since rooms meet there.
- **Has floor** / **Has ceiling** (dock) — remove a sector's floor or ceiling.
- `J` (or **Join Sectors** in the dock) — join the selected sectors into one,
  with the first-selected one's heights and materials. Walls between them
  disappear.
- **Wall thickness** — walls are thin by default. Give a room (in the dock's
  **Wall thickness**, or with **Thicken** on the toolbar) or a single selected
  wall a thickness and its walls become solid blocks built outward, with an
  outer face and a top: the room keeps its size and its floor plan doesn't
  change. Set 0 to make them thin again. Corners join up; a wall that stops
  (at an opening into another room, or a single thick wall) gets a square end.
  Only a room's outer walls count, not the edges around things inside it.
  Where a wall faces another room instead of solid space (e.g. a room inside a
  room), Thicken takes the thickness from that room. With the room selected,
  thick walls show extra handles: drag an **outer corner** (blue) anywhere to
  reshape the block (e.g. a tapered or angled wall), or drag an **outer face**
  in or out to change that wall's thickness (dragging it all the way in makes
  it thin). Hand-placed corners follow the room's corners; setting a new
  thickness squares them up again. **Thicken toward:
  Inward** or **Centered** shrink the room instead (cutting its floor).
- Page Up / Page Down, or Alt+mouse wheel, over a floor or ceiling — raise or
  lower it one grid step (all selected sectors if the hovered one is selected).
- `[` / `]` — smaller / larger grid. Delete — delete selected sectors.
- Right mouse button still flies Godot's editor camera.
- The dock edits heights and materials of the selection, the grid, units
  (meters, or Doom units at 32 per meter), and defaults for new sectors.

Every edit can be undone with Ctrl+Z.

## Planned

Splitting sectors, per-wall textures, texture alignment, a stair
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
  godot --headless --path . --script res://test/toolbar_test.gd
  godot --headless --path . --script res://test/player_test.gd
  ```

## License

MIT — see [LICENSE](LICENSE).

GoDoomBuilder is a fan-made tool and is not affiliated with or endorsed by id
Software or the makers of Doom Builder.
