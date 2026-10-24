# Exp Share

Party-wide experience from the OPTIONS menu, in Gen 1 Exp. All style, Gen 5+ Exp. Share style, BALANCED / AVERAGE presets, or CUSTOM percentage mode — with one "EXP is shared amongst the party" line instead of a gain message per Pokemon. A SINGLE EXP SHARE row can scope the shared exp to one party slot instead of the whole bench. Works on Red/Blue/Yellow, Gold, and FireRed/LeafGreen/Ruby/Sapphire/Emerald.

## How to try it

1. Install the mod and enable it in the mod manager (MODS row in OPTIONS).
2. Open OPTIONS and cycle the EXP SHARE row with LEFT/RIGHT: OFF / GEN 1 / GEN 5+ / BALANCED / AVERAGE / CUSTOM.
3. Fight. In GEN 1, the fighters split half the exp and the whole party splits the other half (the vanilla Exp. All split, including its division bug). In GEN 5+, the fighters keep the full exp and every alive bench mon gets half a fighter's share.
4. BALANCED is the GEN 5+ split with a level gate: a bench mon only gains exp while it is below the active fighter's level, so the bench trails the party instead of out-leveling the mons that actually fight. AVERAGE is the same gate measured against the party's average level (whole party, floored) instead of the active fighter. At- or over-threshold bench mons wait for the party to level past them.
5. CUSTOM keeps each fighter at the full participant share. The PERCENT SLOT and PERCENT rows appear immediately when CUSTOM is selected. PERCENT SLOT cycles ALL / 1 / 2 / 3 / 4 / 5 / 6. ALL edits the global percentage; selecting a party slot edits that slot's override. PERCENT cycles 10% through 100%, so 100% gives every living bench mon the same amount as one fighter.
6. The SINGLE EXP SHARE row (below the CUSTOM rows) still cycles ALL / 1 / 2 / 3 / 4 / 5 / 6. ALL (the default) shares with the whole bench; a slot number shares only with the Pokemon in that party slot — pick a slot past the party's size and nothing is shared at all. The fighters keep their own gain lines in every mode.
7. The LEVEL UP JINGLE row toggles between LEVEL UP (default fanfare) and ITEM (regular item pickup chime) to replace the longer level-up fanfare with a quick item pickup sound. On Gen 3, ITEM also covers the coin-case and hidden-item pickup jingles, which reuse the level-up fanfare.
8. Shared recipients get one "EXP is shared amongst the party" line; the fighters still get their own "X gained N EXP. Points!" lines, and everyone's level-ups, stat boxes and move learning still show.

## Notes

- Gen 3 (FireRed / LeafGreen / Ruby / Sapphire / Emerald) was tested headless on FireRed data only.
- The setting is per save (stored in the save's options) and persists like every other options row.
- CUSTOM percentage settings are also stored in the save's options. Unconfigured party slots inherit the global percentage.
- Bench mons receive stat experience using the same configured divisor as EXP;
  in GEN 5+, BALANCED and AVERAGE that is half a fighter's share.
- OFF restores vanilla behavior exactly, including the vanilla EXP. All item's per-mon messages.

## Layout

- `manifest.json` — identity, version range, load order
- `main.lua` — the entry chunk; the OPTIONS rows and the exp split hook
- `tests/custom_test.lua` — standalone coverage of CUSTOM controls and splits

## Loop

1. `POKEPORT_DEV=1 love .` once, leave it running
2. edit, press F5 to hot-reload, backtick for the dev console
3. `python3 tools/modkit.py validate exp_share` before sharing
4. `python3 tools/modkit.py pack mods/exp_share` to ship
