# Fortress art in the game

Presentation assets for the labyrinth renderer. Rooms use a fixed 2:1 frame;
backgrounds fit inside it without cropping or stretching. Actors are separate
transparent images, positioned by their visible bounds and foot pivot.

`manifest.json` maps stable content IDs to PNGs or atlas regions. It contains
base rooms, path stages, six hero classes, three Lords and eight terrain layers.
Unknown actors and special phases retain the existing vector renderer.

The committed PNGs and manifest are sufficient to run and export the game.
The following authoring paths refer to separate local working material, not
required runtime dependencies. Source images, generation prompts and provenance
remain under:

- `deliverables/ui/fortress-textures-v1/`
- `deliverables/ui/fortress-quality-v2/`
- `deliverables/ui/fortress-heroes-v1/`
- `deliverables/ui/fortress-room-prototype/art/`

Rebuild the copied assets with
`python deliverables/ui/fortress-integration/build_assets.py` from the repository
root. The game uses the native PNG sources, not compressed preview images.
The manifest must remain in both export presets' include filters.

Display corrections (3 November 2026): square chamber atlases have authored wide
siblings. Their manifest regions are exactly 2:1, including all path stages and
empty chambers, so fitting no longer leaves grey side bands. Characters are
unchanged. The poison/mimic atlas has 6 columns and 4 rows; other atlases use 5×4.

Eight standalone ground materials fill the visible world in every build mode.
World-space mirrored repeat keeps their scale and position stable when panning
or zooming. Materials follow the existing three-row depth layers; material 8
continues at greater depths. Excavation adds outlines and actions over this same
ground, rather than separate texture blocks.

Selected PNGs and their complete built-in ImageGen prompts/provenance are in
`deliverables/ui/fortress-display-fix/selected_sources.json`. Source images are
archived beside that file; rebuilding works from those copies too.

Sprites currently provide one pose; movement, hit feedback and effects are driven
by game events. These assets do not contain authored frame-by-frame combat cycles.

Special forms: `throne-guardian.png`, `living-mouth.png` and `living-heart.png`
are transparent sprites, with bounds and foot pivots in the manifest. Guardian
and appendage are resolved by their actual phase IDs for stages 2/5/15; the living
chamber's base actor is its small vulnerable heart. `living-chambers-states.png`
has three columns (stages 2/5/15) and two rows (alive/cleared), each region 2:1.
Only final owner defeat selects `cleared`; preparation restores the live view.
Prompts and source copies: `deliverables/ui/fortress-special-forms/sources.json`.

`title-encounter.jpg` is the main menu illustration, generated from text with
the built-in ImageGen tool and encoded as a 1536×1024 JPEG. Prompt:

> Landscape 3:2 cinematic dark fantasy painted key art for the Godot game No Hero Returns. Three small medieval adventurers seen clearly from behind in the lower center foreground, knight with shield, hooded ranger and staff mage, preparing to face a towering ominous crowned dungeon lord silhouette looming above them in the darkness at the back of a stone throne hall. Torches warm amber against deep charcoal stone and smoky dark shadows. Grounded painterly game illustration, crisp silhouettes, atmosphere and scale. Keep group and lord within central 65 percent for mobile crops. No lettering, typography, UI, logo or watermark.
