# Gate B — M11 part B's review, and its fixes

Gate B reviewed part B's candidate (`47a0af6`, the W33look2 merge; the diff from `0.11.0-m11`) through the plan's
lenses 2, 4, 5, 6 and 7 and GDScript correctness. It confirmed two major and five minor findings; one fix lane
(`pkg/gateBfix`) fixed or recorded each, every fix with a test that fails before it. What is left is in
`docs/plans/FOLLOWUPS.md`, "From the M12 gate review"; the decisions are in `docs/DECISIONS.md` §3.6.

## Findings and fixes

| # | Severity | Finding | Fix | Test |
| --- | --- | --- | --- | --- |
| 1 | major | `GiantLook.apply`'s skip-unchanged cache (P57) skipped a hidden piece's material but moved the root-wide last build and last push on: a garment taken off while a build slider moved, or while the layering changed, was shown again with its old `build` / `push_m` / `pushed` (the jerkin at build 0 on a +1/+1 body, so the body pushed through it; the hauberk pushed 0.32 m off the body over no tunic). Creator preview, thumbnails and the game's rig alike. 7 of the first 12 random sequences of ten looks differed from a fresh model. | `build`, `build_max_m` (skin and cloth) and a garment's or accessory's `push_m` and `pushed` are part of each material's own compared values (`_put`); the root's `META_BUILD` and `META_PUSH` are gone. A whole look stays about 0.33 ms (`test_giant_preview`'s 1 ms check unchanged). | `tests/integration/test_giant_look_cache.gd` (the build, the push and the beads after a build change); `tests/slow/test_giant_look_cache_random.gd` (24 random sequences of ten looks): each sequence on one model against a fresh model given the last look (`tests/support/giant_look_cache_check.gd`). |
| 2 | major | A gameplay change inside part B: W32's leash contact rule (`EnemyActor.LEASH_CONTACT_M` 0.05 m, `LEASH_CONTACT_WAY_S` 1 s; `d09f1d7`) was recorded as a test fix. | No code change: recorded as an accepted gameplay change (`docs/DECISIONS.md` §3.6, `docs/BALANCE_LOG.md`, FOLLOWUPS for the release notes). | `tests/slow/test_leash_waits.gd`, `test_a_return_pressed_into_a_giant_for_a_second_begins_its_wait_phase_0` / `_phase_30`: a soldier sent home rides into a giant outside its leash and begins its way wait on the 60th tick pressed into him with no path failure (with the rule off: 314 ticks, two failures). |
| 3 | minor | The option grid kept its pictures by option id only: the beard's Beads grid first showed the hair's bead pictures, a grid opened after a dye change the old dye's, and a picture still in flight when another grid opened landed on it for good. | `OptionGrid.open()` forgets the pictures; `ThumbnailCache.thumbnail_ready` carries the item's key, and `CreatorScreen` shows only a picture its page asked for. | `tests/slow/test_creator_thumbnails.gd`: `test_the_beard_beads_grid_never_shows_the_hair_beads_grids_pictures`, `test_a_picture_in_flight_for_another_grid_never_lands_on_the_grid_open`, `test_a_grid_opened_after_a_dye_change_never_shows_the_old_dyes_picture`. |
| 4 | minor | Typing a name in an open grid: Q, E, R, V and F kept their creator meaning mid-word ("iron" searched "ion" and randomized the Clothing category). | The first letter typed puts the focus in the find box, so the rest types there. Q, E, R, V and F keep their meaning as the first key (a name that starts with one needs "/"). `docs/systems/P55.md`, `docs/USABILITY_SCRIPT.md` row 14. | `tests/integration/test_creator_grid.gd`, `test_typing_a_name_in_a_grid_types_the_creators_own_keys_into_the_box`. |
| 5 | minor | The shrine's clothing line named the outfit's dye for a garment with its own (the bronze breastplate in an iron outfit read "iron"); the creator's Colours row offered "Outfit's dye" for it. | `Appearance.slot_dye_id` resolves a slot's dye as `to_look` draws it (the slot's, the garment's own, the outfit's); `to_look`, the shrine's line and the Colours row use it ("Its own: Bronze"). | `tests/unit/test_appearance_record.gd`, `test_the_shrine_and_the_colours_row_name_a_garment_s_own_dye`. |
| 6 | minor | The README's controls table said the creator zooms with LT and RT; the preview's comment too. | The right stick's up and down zoom; LT and RT jump five rows and turn a grid's pages. | `tests/unit/test_ship_docs.gd`, `test_the_readme_names_the_creators_zoom_and_triggers_as_they_are`. |
| 7 | minor | The creator's picture cache never let go of a picture and keyed a garment's by all three dyes: each dye change made a full set again (up to 256 KiB each). | At most `ThumbnailCache.MAX_PICTURES` (200, about 50 MiB at the largest size), the least recently shown going first; a garment's key names only the dye it is drawn in. | `tests/unit/test_thumbnail_cache.gd`; `tests/slow/test_creator_thumbnails.gd`, `test_a_garment_s_picture_is_keyed_by_its_own_dye_only`. |

## The review's "plausible, not reproduced"

The first, a death reload of a migrated version-1 save before any checkpoint saying the migration message again, was
tried and does not happen: the reload uses the in-memory checkpoint document (its flags already hold
`appearance.slots_seen`) and shows no load message. The rest were not run. Both are in FOLLOWUPS.

## Unchanged

The seeded 120 s soak (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors); no data
file, asset or shader changed.
