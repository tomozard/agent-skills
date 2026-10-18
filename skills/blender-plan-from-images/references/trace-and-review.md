# Trace data, geometry, and comparison views

## Source coordinates

Record image width/height, file reference, floor ID, scale basis, and transform. For an unrotated image with its origin at top left:

```python
def image_to_world(u, v, origin_u, origin_v, pixels_per_unit):
    return ((u - origin_u) / pixels_per_unit,
            (origin_v - v) / pixels_per_unit)
```

The Y inversion is intentional. Use an orthographic camera above the XY plane with world +Y at the top of the output. Match output aspect ratio to the source. Confirm all four image corners align; camera scale conventions can vary with render aspect. Do not stretch X and Y independently just to improve a match.

A useful trace record contains:

```text
floor
  source: path, width_px, height_px
  transform: origin_px, pixels_per_unit, rotation, scale_basis
  rooms: id, function, category, polygon_px, evidence, confidence
  walls: id, polygon_px or rect_px, room_ids
  doors: id, room_pair, hinge_px, closed_end_px, open_end_px, type
  windows: id, segment_px, wall_id
  furniture: id, room_id, footprint_px, orientation
  stairs: footprint_px, void_polygon_px, direction, height_status
  assumptions / review_corrections
```

Use actual room IDs to link fixtures and labels. Store source coordinates and IDs as custom object properties where useful. Keep units and provisional assumptions alongside the transform, not only in chat.

## Building editable geometry

- Separate floor finishes, walls, openings, furniture, stairs, labels, and presentation setup into collections. Use independent floor scenes or deliberate view layers to avoid accidental cross-floor visibility.
- Rectangular wall segments work well for orthogonal plans. Use polygons for angled or irregular walls. Split walls at openings; a door leaf drawn over an unbroken wall is not an entrance.
- For a swing door, the hinge-to-closed endpoint segment defines the opening. The hinge-to-open endpoint segment defines the displayed leaf. Their lengths should agree, except for explicitly modeled folding/sliding doors.
- Generate the swing arc from the hinge and endpoints. Confirm the intended sweep instead of assuming the shortest arc always represents the reference.
- Use low cut walls and simple furniture for plan review. Detailed furniture is optional and should preserve the footprint and orientation.
- Triangulate concave floor polygons correctly. For a slab hole, use a real mesh opening, nonoverlapping slab regions, or a suitable modifier. A dark rectangle above a slab does not create a void.
- Separate base slabs and finishes in Z or avoid overlapping surfaces. Coplanar finishes can cause black patches or flickering that resemble modeling defects.
- Avoid hidden duplicate revision objects. Visibility in the viewport, render visibility, and view-layer exclusion are separate states.

Before reading dimensions or evaluated geometry after changes, update the dependency graph. Use evaluated geometry for the comparison if modifiers change the footprint. Avoid rerunning an entire creation script blindly: it may duplicate scenes and invalidate counts. Update objects by stable IDs or build a new isolated revision.

## Registration between floors

Use corresponding landmarks, such as stair corners and consistent perimeter/structural intersections. A uniform scale, rotation, and translation usually suffice for unwarped plans; choose at least three well-separated correspondences and inspect remaining landmarks. Do not use arbitrary furniture as structural anchors.

If correspondences disagree, investigate crop/scale differences or inconsistent marketing drawings. Keep each floor's image-space match intact until evidence supports a shared building coordinate system. Report unresolved registration rather than distorting rooms to hide it.

## Overlay and visual review

Place the source image on an unlit/emission plane, then draw thin contrasting wall footprints and door segments above it. Example legend: cyan = walls, orange = door opening and leaf. Keep line widths thin enough to reveal the source beneath. Use matching resolution, framing, and color handling so apparent offsets are meaningful.

The overlay must represent the current model. If a single trace dataset generates both mesh and overlay, check that later edits have not bypassed it. Verify key object coordinates against the dataset or derive outlines from model geometry. An overlay of obsolete trace data is not validation.

Use a compact review table:

| Room ID | Boundary/adjacency | Door/window | Fixtures/furniture | Open issue |
|---|---|---|---|---|
| Example bedroom | Match / corrected | Swing corrected | Headboard corrected | Width unmeasured |

Inspect exterior-facing rooms and internal rooms equally. Pay particular attention to:

- A bathroom entrance hidden beneath a door leaf or furniture in the source.
- A service room accessed from an external passage rather than the adjacent kitchen.
- A private lounge that looks visually continuous with the common hall.
- A stair opening confused with a landing, wall, or white drawing background.
- An outward-opening entrance mistaken for an inward-opening one.

Inspect the final plan at whole-floor scale and ambiguous areas at high magnification. Inspect the dollhouse for geometric defects that a top view hides. Save a new render after changes; do not use an earlier preview to claim the final scene was checked.

## Verification limits

Useful checks include semantic room counts, linked fixture-to-room IDs, matching door leaf/opening lengths, continuity of circulation, wall gaps at doors, and mesh-to-trace agreement. Render inspection is still necessary.

Do not claim pixel-perfect accuracy from a visually plausible overlay. Report a numeric error only if it was actually measured with a stated method. Matching a raster plan does not establish statutory clearance, structural adequacy, exact area, or surveyed dimensions.
