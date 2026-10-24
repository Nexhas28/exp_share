# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.11] - 2026-10-24

### Added

- Gen 3 support (FireRed / LeafGreen / Ruby / Sapphire / Emerald). The manifest
  now declares `"games": ["gen1", "gen2", "gen3"]`. The exp award reads the
  party from the battle's `playerParty` and the options from
  `battle.session.engineOptions`, the same table the save stores. GEN 1,
  GEN 5+, BALANCED, AVERAGE, CUSTOM and SINGLE EXP SHARE use the same formulas
  as Gen 1 and Gen 2. Ruby, Sapphire and Emerald share the `gen3` token;
  tests ran headless on FireRed data only.
- The Gen 3 shared-exp line goes through the battle text box. It shows before
  the fighters' own gain lines; Gen 2 shows it after them.
- Gen 3 OPTIONS opened from the title screen, before any save is loaded, read
  and write the same options block as the in-game menu.
- Gen 3: the EXP SHARE rows live on OPTIONS > BATTLE OPTIONS; PERCENT rows are
  always listed there and read `--` unless CUSTOM.
- LEVEL UP JINGLE on Gen 3: ITEM replaces every `MUS_LEVEL_UP` fanfare with the
  item pickup song (`MUS_OBTAIN_ITEM`). That includes level-ups and the coin
  case and hidden-item pickup jingles, which reuse the level-up fanfare.

### Fixed

- Eggs no longer receive the bench share on Gen 3.
- The LEVEL UP JINGLE choice is now read from saved options when no game has
  loaded yet. Before this fix it was ignored until `game.ready` on every
  generation.
- The Gen 3 share line and jingle wrap use `require` instead of
  `package.loaded`, which is empty inside the mod's sandbox.
- After a same-process reload of the mod, the Gen 3 jingle wrap uses the
  latest copy of the mod's settings.

## [0.1.10] - 2026-08-21

### Fixed

- CUSTOM percentage rows now appear immediately when switching modes in an
  already-open OPTIONS menu.

## [0.1.9] - 2026-08-21

### Added

- CUSTOM mode while preserving GEN 1, GEN 5+, BALANCED and AVERAGE.
- PERCENT and PERCENT SLOT rows under CUSTOM, with global or per-party-slot
  percentages from 10% through 100%.
- Standalone Lua coverage for CUSTOM mode, conditional rows and per-slot
  percentage splits.

## [0.1.8] - 2026-08-20

### Added

- LEVEL UP JINGLE toggle in the OPTIONS menu: toggle between LEVEL UP (the default level-up fanfare) and ITEM (the regular item pickup chime). When set to ITEM, leveling up in battle or move learning plays the shorter item pickup jingle (`Get_Item1` on Gen 1, `Sfx_Item` on Gen 2) for faster level-up transitions.

## [0.1.7] - 2026-08-11

### Added

- Gold (Gen 2) support. The manifest now declares `"games": ["gen1", "gen2"]`,
  and the exp award reads the save, party and options from Gen 2's Battle
  shape (`battle.save` / `battle.party`, with `battle.player` being the party
  mon directly) instead of Gen 1's `battle.game`. The shared-exp line
  announces through Gen 2's message emit, and the OPTIONS rows persist via
  `persistOptions` where `writeOptions` is absent. Every split (GEN 1 / GEN 5+
  / BALANCED / AVERAGE and SINGLE EXP SHARE) behaves the same on Gold as on
  Red/Blue/Yellow.

## [0.1.6] - 2026-08-11

### Fixed

- EXP SHARE now works alongside overhaul mods that take over the battle
  experience award (e.g. the Crystal 251 mod). Previously such a mod wrapped
  the same experience hook at a higher priority and ran first, silently
  swallowing the award so the EXP SHARE modes never applied. The hook now
  runs at priority 90, before those wraps, so a configured mode (GEN 1 /
  GEN 5+ / BALANCED / AVERAGE) is honoured. With OFF selected the mod defers
  as before, so the other mod's own experience system still applies.

## [0.1.5] - 2026-08-05

### Added

- SINGLE EXP SHARE row in the OPTIONS menu, under EXP SHARE: cycle ALL / 1 / 2 / 3 / 4 / 5 / 6. Set to a slot number, the shared exp goes only to the Pokemon in that party slot instead of the whole bench; the fighters keep their own gain either way. ALL (the default) keeps the party-wide split. The GEN 1, GEN 5+, BALANCED and AVERAGE splits all honour the slot.

## [0.1.4] - 2026-08-05

### Changed

- The EXP SHARE row cycler now advances the mode with a direct index
  lookup instead of scanning the mode list linearly. Same behaviour.

## [0.1.3] - 2026-08-02

### Added

- AVERAGE preset in the EXP SHARE row (OFF / GEN 1 / GEN 5+ / BALANCED / AVERAGE): the GEN 5+ split with the same level gate as BALANCED, but measured against the party's average level (whole party, floored) instead of the active fighter's -- a bench Pokemon only gains exp while it is below that average.

## [0.1.2] - 2026-08-02

### Added

- BALANCED preset in the EXP SHARE row (OFF / GEN 1 / GEN 5+ / BALANCED): the GEN 5+ split with a level gate -- a bench Pokemon only gains exp while it is below the active fighter's level, so the bench trails the party instead of out-leveling the mons that actually fight. At-level or over-leveled bench mons get nothing until the fighter levels past them.

### Changed

- The shared-exp line now reads "EXP is shared amongst the party!" (EXP capitalised).

## [0.1.1] - 2026-08-02

### Fixed

- The "Exp is shared amongst the party" line now appears right after the participating Pokemon's own gains, before the bench Pokemon's level-up and move-learn messages (previously the bench level-ups queued before the share announcement).

## [0.1.0] - 2026-08-02

### Added

- EXP SHARE row in the OPTIONS menu cycling OFF / GEN 1 / GEN 5+.
- GEN 1 mode: the fighters split half the exp, the whole party splits the other half (vanilla Exp. All behavior, division bug included).
- GEN 5+ mode: the fighters keep the full exp; every alive bench mon gets half a fighter's share.
- One "Exp is shared amongst the party" line replaces the per-mon gain messages for shared exp; level-ups and move learning still show per mon.
