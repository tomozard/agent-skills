# Lessons from the originating house revision

This example involved a two-story house advertised as 316 square meters, four principal bedrooms, and three parking bays. The user ultimately clarified five main bathrooms plus one small service bathroom. These values are specific to that project.

The first model was broadly similar but did not place rooms precisely enough. Rebuilding from original image pixel coordinates made room boundaries and openings reviewable before exterior refinement.

## Discrepancies that mattered

| Area | Correction | Reusable lesson |
|---|---|---|
| Ground-floor service zone | Restored the stepped footprint and external passage; moved the small bathroom entrance to the west wall | Check actual access routes, not just fixture placement |
| Service bedroom | Kept its cot separate from the four principal bedrooms | Reconcile room categories instead of counting beds |
| Ground-floor main bedroom | Corrected entrance to the dining/hall side and bed orientation | Review every room's entrance and headboard independently |
| Main entrance | Corrected double doors to open outward onto the porch | Read swing geometry from a magnified reference |
| Upper bedrooms | Corrected three entrances and headboard orientations | Do not mirror or reuse room templates without checking |
| Upper left-front suite | Separated its private sitting area from the common family lounge | Similar finishes do not imply a shared room |
| Master suite | Matched dressing, sitting, bathing, and sleeping zones | Review subzones within large rooms |
| Stair | Reduced the central opening to the traced bounds and made a real slab opening | A dark void marker is not sufficient geometry |
| Floor finishes | Removed coplanar overlaps producing black patches | Check render defects separately from layout errors |

The final count was two main bathrooms downstairs, three upstairs, and one small downstairs service bathroom. This was checked against fixtures and room identities, not raw object totals.

## What the result did and did not establish

The revision provided editable Blender floor studies, top plans, dollhouse views, trace data, and source-image overlays. Each floor was traced independently. The supplied images did not establish measured wall lengths, floor-to-floor height, a verified 316-square-meter area, or final registration between stories. Those remained explicit assumptions or unresolved checks.

The build used simple furniture and cut walls so the user could judge the layout. The exterior from the earlier version was retained as superseded, not presented as updated to the new plan.

No project-specific paths, downloaded images, or fixed house geometry are required by this skill. New projects should use their own source files, room inventory, scale evidence, and current user decisions.
