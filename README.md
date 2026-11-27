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
  A sub-sector is its own room standing in a hole in the one around it:
  rotating or mirroring it takes the hole along, and reshaping either one
  never bends the other's walls.
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
actions plus every value of the selection, grouped into sections you can
fold: *Draw*, then for the selection *Sector* (heights, size, wall
thickness), *Materials* and *Selected Wall*, and, folded until you open them,
*Texture Alignment*, *Rotate, Mirror & Copy*, *Thicken Walls*, *Stairs*,
*New Sectors in Empty Space* and *Controls*.


- `D` — draw a polygon: click points (grid snapped; snaps to existing corners),
  click the first point or press Enter to finish, Backspace removes a point,
  hold Shift for no grid snap. For an exact side, type a length
  and press Enter: the point goes that far toward the mouse (angles snap to
  15°; Shift for any angle).
- Stopping a polygon before it's closed (Esc, another tool, or selecting
  another node) with two or more points keeps it as an **unfinished polygon**:
  a red line saved with the scene. Click either end (in Select or Draw
  Polygon) to continue drawing from there; close it as usual to make the
  sector. Delete over a red line discards it, as does taking a continued one
  back to a single point with Backspace and stopping. Unfinished polygons
  build nothing in the level.
- `B` — draw a rectangle: click a corner, then the opposite corner. For an
  exact size, type the width, Tab, the depth, Enter (or set Width/Depth in the
  dock). A typed side with the other left free follows the mouse.
- Typed numbers are in the current units (e.g. `64` = 2 m in Doom units).
- Click — select a sector; Shift+click adds to the selection. Selected
  sectors are outlined and their floors, ceilings and walls get a light amber
  tint, so you can see exactly what's selected.
- Drag from a floor (or ceiling) across rooms — box select: every sector
  whose middle is inside the box. Shift+drag adds to the selection, Esc
  cancels. (A drag that starts on empty space is still Godot's own.)
- **Select Similar** (dock, with the sector to compare selected first; or the
  **Edit** menu) — select every sector with the same floor height, ceiling
  height, both, or the same floor / ceiling / wall material or all three.
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
  outlines; **Show Hidden Walls** brings them back, **Reset** undoes a
  wall's own settings. Settings stay with the wall when you drag its corners.
  (Walls between two sectors take their height from the neighbouring floor or
  ceiling, so they can be hidden but not resized.)
- **Wall lengths** — every wall of the selected sectors is labelled with its
  length (and hovering a wall shows it too). To set one exactly, click the
  wall, then type the length and press Enter (or use **Length** in the dock;
  Esc clears what you typed). **Keep fixed** picks what stays put: end **A**,
  end **B** (labelled in the viewport) or the **Center**. Corners shared with
  neighbouring sectors move along, so they stretch; a length that would cross
  or overlap is refused.
- **Simplify** (dock) — remove points that don't change the selected
  sectors' shapes: extra points along straight walls (within 1 mm) and seams
  inside the sector. Points where a neighbouring sector's corner touches the
  wall still show as handles, since rooms meet there.
- **Has floor** / **Has ceiling** (dock) — remove a sector's floor or ceiling.
- `J` (or **Join** in the dock) — join the selected sectors into one,
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
  thickness squares them up again. **Toward:
  Inward** or **Centered** (Thicken Walls section) shrink the room instead (cutting its floor).
- **Add / remove corners** — double-click a selected sector's wall to add a
  corner there (on the grid if a grid point lies on the wall; Shift: exactly
  under the mouse), or press **Split** (Selected Wall) with a wall selected to split it in
  the middle. Rooms sharing the wall get the corner too, so dragging it bends
  both. Delete over a corner handle removes the corner (its two walls become
  one); a triangle keeps its three. Pressing Delete again in the same spot
  does nothing until the mouse moves away, so it never goes on to delete the
  sector. Dragging a corner onto the next one merges them.
- **Curve Wall** (select a wall; dock or toolbar **Edit** menu) — bend the
  wall into an arc of **Segments** straight pieces whose middle moves
  **Bulge**: positive outward (the room grows), negative into the room, up to
  a half circle. A room sharing the wall bends with it, and corners on the
  wall move onto the arc.
- `Ctrl+C` / `Ctrl+V` — copy the selected sectors, then place copies: the
  copy follows the mouse (grid / corner snapped), `R` / `Shift+R` turn it 90°,
  `E` / `Shift+E` turn it by the dock's rotate angle, `M` mirrors it, click
  (or Enter) places it, Esc cancels. Like drawing, it
  cuts what's under it. Heights, materials, wall settings and texture
  alignment come along.
- **Rotate 90°** / **Mirror X** / **Mirror Z** (dock or **Edit** menu) — turn
  or flip the selected sectors about the grid point nearest their center.
  **Rotate** next to the angle field turns them by any angle (positive is
  clockwise seen from above). Neighbours stay put, so a move that would
  overlap one is refused; a sector standing inside another takes its hole
  along.
- **Prefabs** — **Save Prefab…** (dock) or **Save as Prefab…** (**Edit** menu) saves the
  selected sectors, with their heights, materials, wall settings and texture
  alignment, as a `.tres` resource. **Prefab…** (under Draw) loads one into this or
  any other map and places it like a paste (R / E / M work). A prefab is a
  plain `DMMapData` resource, so any saved map data works too.
- **Stairs** (dock, folded; or **Edit** menu) — **Make Stairs**: Shift+click
  the steps in order, and each floor becomes one **Step height** above the one
  before (starting from the first one's floor; negative goes down). **Split
  into Steps**: cut one selected sector into **Steps** equal strips across the
  **Climbing** direction (±X, ±Z) and make them stairs. **Ceilings move too**
  moves each ceiling with its floor (a sloping corridor); otherwise ceilings
  stay, rising only where a floor would pass them.
- **Texture alignment** (dock, folded) — textures are world-aligned (one
  repeat per meter) so neighbouring surfaces line up. For the selection's
  floors, ceilings or walls, set an **Offset**, a **Size** (meters per repeat,
  per axis; negative mirrors) and a **Rotation**. With a single wall selected,
  **Walls** aligns just that wall (**Reset Wall** clears it too). A sector
  drawn inside another copies its alignment, so they still line up.
  Normal-mapped materials stay correct (tangents follow the alignment).
  - **Fit** — one texture repeat exactly covering each selected floor or
	ceiling (its bounding box), or each wall (its length and height; with a
	single wall selected, just that one).
  - **Alt+arrow keys** over a surface in the viewport move its texture one
	grid step (Shift: an eighth of a step). Over a selected sector's floor or
	ceiling, every selected one moves; over a wall, just that wall.
  - **Ctrl+Shift+C** over a surface copies its alignment, **Ctrl+Shift+V**
	over another pastes it (also **Copy / Paste Alignment** in the dock, for
	the chosen surface of the selection).
- Page Up / Page Down, or Alt+mouse wheel, over a floor or ceiling — raise or
  lower it one grid step (all selected sectors if the hovered one is selected).
- `[` / `]` — smaller / larger grid. Delete — delete selected sectors.
- Right mouse button still flies Godot's editor camera.
- The dock edits heights and materials of the selection, the grid, units
  (meters, or Doom units at 32 per meter), and defaults for new sectors.

Every edit can be undone with Ctrl+Z.

## Planned

Per-wall materials, doors and lifts, lighting, a things palette, slopes, and
rooms over rooms.

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
  godot --headless --path . --script res://test/features_test.gd
  godot --headless --path . --script res://test/editor_test.gd
  godot --headless --path . --script res://test/tool_test.gd
  godot --headless --path . --script res://test/toolbar_test.gd
  godot --headless --path . --script res://test/player_test.gd
  godot --headless --path . --script res://test/fuzz_test.gd
  ```

  `fuzz_test.gd` draws and drags random shapes and checks that maps stay
  valid. For a longer search: `... fuzz_test.gd -- --rounds=500 --start=5000`;
  to rerun one failing seed with details: `-- --seed=N --verbose`.
- `test/strict_check.sh` checks every addon script with Godot's strict typing
  warnings as errors (untyped declarations, unsafe property and method
  access, unsafe casts and call arguments):
  `GODOT=/path/to/godot bash test/strict_check.sh` (it changes
  `project.godot` for the run and puts it back).
- GitHub Actions runs the strict check and all the tests on every push
  (`.github/workflows/tests.yml`).

### Code layout

- `core/` — the map data and geometry, no editor needed: `DMMapData` (sectors
  and every edit on them, returning a `DMResult`), `DMSector`, `DMGeo`, and
  `DMBuilder`, which builds a `DMBuildInfo` (faces, triangles, outlines) and
  the mesh.
- `nodes/map.gd` — `DMMap`, the node in your scene (mesh, collision, picking).
- `editor/` — `DMEditor` (every edit on the selected map as one undo step,
  usable headless), `DMTool` (viewport input and overlay), the dock, toolbar
  and grid. `plugin.gd` connects `DMEditor` to Godot's editor.

## License

MIT — see [LICENSE](LICENSE).

GoDoomBuilder is a fan-made tool and is not affiliated with or endorsed by id
Software or the makers of Doom Builder.
