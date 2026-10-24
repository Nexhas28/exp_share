-- Standalone: luajit mods/exp_share/tests/exp_share_test.lua
-- Loads the mod through the real headless loader and asserts the OPTIONS
-- row ladder, the GEN 1 / GEN 5+ exp splits, and the hook wiring.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data
local ok = pcall(function()
  Data = require("src.core.Data")
  Data:load()
end)
if not ok or not Data or not Data.constants then
  Data = require("tests.modkit.fixtures").fresh()
end

-- ------------------------------------------------ Gen 2 load gate

do
  -- the manifest claims gen2, so a Gold boot loads it; a gate skip would be
  -- a state of "wrong_generation" with zero errors, which is why the state
  -- is asserted alongside the error count.  A fresh fixture dataset (not the
  -- shared Data above) so the registries the gen1 load fills below do not
  -- collide on the second.
  local fresh = require("tests.modkit.fixtures").fresh()
  local run2 = T.sdk.loadMod("mods/exp_share", { data = fresh, generation = 2 })
  T.eq(run2.mod and run2.mod.state, "loaded",
    "loads on gen 2: " .. tostring(run2.mod and run2.mod.skipReason))
  T.eq(#run2.errors, 0, "gen 2 load has no boot errors")
  T.neq(run2.loader.exports.exp_share, nil, "gen 2 exports reachable")
  run2.release()
end

-- ---- Gen 3 load gate

do
  -- same gate as Gen 2: state "loaded" plus zero errors, so a skipped load
  -- cannot pass silently.  A Gen 3 dataset (Sdk.gen3Data) is required.
  local run3 = T.sdk.loadMod("mods/exp_share", { data = T.sdk.gen3Data(), generation = 3 })
  T.eq(run3.mod and run3.mod.state, "loaded",
    "loads on gen 3: " .. tostring(run3.mod and run3.mod.skipReason))
  T.eq(#run3.errors, 0, "gen 3 load has no boot errors")
  T.eq(type(run3.loader.exports.exp_share), "table", "gen 3 exports reachable")
  T.eq(type(run3.loader.exports.exp_share.modeOf), "function", "gen 3 exports modeOf")
  T.eq(type(run3.loader.exports.exp_share.cycle), "function", "gen 3 exports cycle")
  run3.release()
end

local run = T.sdk.loadMod("mods/exp_share", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local ex = run.loader.exports.exp_share
T.neq(ex, nil, "exports reachable")

-- ------------------------------------------------ the OPTIONS row

local function findRow(game)
  local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
    game, { { id = "text_speed" } })
  for _, row in ipairs(rows) do
    if row.id == "exp_share" then return row end
  end
  return nil
end

local written = 0
local game = {
  save = { options = {} },
  -- method-shaped like the real Game:writeOptions, so a dot-call regression
  -- (self == nil) fails the test instead of being silently swallowed
  writeOptions = function(self)
    assert(type(self) == "table" and self.save ~= nil,
           "writeOptions must be called with a colon")
    written = written + 1
  end,
}

local row = findRow(game)
T.neq(row, nil, "the EXP SHARE row joins the options menu")
T.eq(row.label, "EXP SHARE", "row label")
T.eq(row.value(game), "OFF", "defaults to OFF")
T.eq(row.step(game, 1), true, "stepping right works")
T.eq(game.save.options.expShare, "gen1", "OFF cycles to GEN 1")
T.eq(row.value(game), "GEN 1", "value follows the save")
T.eq(row.step(game, 1), true, "step again")
T.eq(game.save.options.expShare, "gen5", "GEN 1 cycles to GEN 5+")
T.eq(row.value(game), "GEN 5+", "GEN 5+ label")
T.eq(row.step(game, 1), true, "step again")
T.eq(game.save.options.expShare, "balanced", "GEN 5+ cycles to BALANCED")
T.eq(row.value(game), "BALANCED", "BALANCED label")
T.eq(row.step(game, 1), true, "step again")
T.eq(game.save.options.expShare, "average", "BALANCED cycles to AVERAGE")
T.eq(row.value(game), "AVERAGE", "AVERAGE label")
T.eq(row.step(game, -1), true, "stepping left works")
T.eq(game.save.options.expShare, "balanced", "AVERAGE left-cycles to BALANCED")
T.eq(row.step(game, 1), true, "step again")
T.eq(game.save.options.expShare, "average", "BALANCED right-cycles to AVERAGE")
T.eq(row.step(game, 1), true, "step again")
T.eq(game.save.options.expShare, "custom", "AVERAGE cycles to CUSTOM")
T.eq(row.value(game), "CUSTOM", "CUSTOM label")
T.eq(row.step(game, 1), true, "step again")
T.eq(game.save.options.expShare, "off", "CUSTOM cycles back to OFF")
T.eq(written, 8, "each step persists via writeOptions")

game.save.options.expShare = "bogus"
T.eq(ex.modeOf(game), "off", "a garbage value normalizes to OFF")
game.save.options.expShare = "average"
T.eq(ex.modeOf(game), "average", "AVERAGE is a recognized mode")
T.eq(ex.cycle({}), nil, "no save -> nil (launcher is untouched)")
T.eq(ex.cycle({ save = {} }), nil, "no options table -> nil")

-- ------------------------------------------------ GEN 1 split (Exp. All)

do
  -- one ordered event log, so the share line's position among the
  -- applyShare calls is asserted too
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen1" },
                      party = { monA, monB } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen1(ctx)
  -- fighter pass: half the total, split among the fighters, announced
  T.eq(log[1].kind, "share", "gen1: the fighter gets the first share")
  T.eq(log[1].mon, monA, "gen1: the fighter gets the first share")
  T.eq(log[1].split, 2, "gen1: fighter split = participants(1) x 2")
  T.eq(log[1].announce, true, "gen1: the fighter's own gain is announced")
  -- the share line lands before the silent whole-party pass
  T.eq(log[2].kind, "say", "gen1: the share line is queued second")
  T.eq(log[2].text, "EXP is shared\namongst the party!",
    "gen1: the single shared-exp line")
  -- whole-party pass: the halved-and-fighter-divided base re-divided by
  -- the party count, silent (the share line covers it)
  T.eq(log[3].mon, monA, "gen1: the fighter is in the party pass too")
  T.eq(log[3].split, 4, "gen1: party split = participants(1) x party(2) x 2")
  T.eq(log[3].announce, nil, "gen1: party-pass gains are not announced per mon")
  T.eq(log[4].mon, monB, "gen1: the bench mon gets the same party pass")
  T.eq(log[4].split, 4, "gen1: the bench shares the same divisor")
  T.eq(#log, 4, "gen1: fighter share + share line + one share per party mon")
end

do
  -- two fighters, three-party mons: the divisors follow participants
  local log = {}
  local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen1" },
                      party = { monA, monB, monC } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 2,
    alive = { monA, monB },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen1(ctx)
  T.eq(log[1].split, 4, "gen1: fighter share halves with two participants")
  T.eq(log[2].split, 4, "gen1: second fighter same share")
  T.eq(log[3].kind, "say", "gen1: the share line follows the fighters")
  T.eq(log[4].split, 12, "gen1: party pass = participants(2) x party(3) x 2")
  T.eq(#log, 6, "gen1: two fighter shares + share line + three party shares")
end

do
  -- single-mon party: no share line, the mon gets the vanilla amount
  local log = {}
  local monA = { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen1" }, party = { monA } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen1(ctx)
  T.eq(#log, 2, "gen1: solo mon gets both halves")
  T.eq(log[1].split, 2, "gen1: solo fighter half")
  T.eq(log[2].split, 2, "gen1: solo party pass = 1 x 1 x 2")
end

-- ------------------------------------------------ GEN 5+ split

do
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen5" },
                      party = { monA, monB } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].mon, monA, "gen5: the fighter keeps the full amount")
  T.eq(log[1].split, 1, "gen5: fighter split = participants(1)")
  T.eq(log[1].announce, true, "gen5: the fighter's own gain is announced")
  -- the share line lands before the bench level-ups
  T.eq(log[2].kind, "say", "gen5: the share line follows the fighter")
  T.eq(log[2].text, "EXP is shared\namongst the party!",
    "gen5: the single shared-exp line")
  T.eq(log[3].mon, monB, "gen5: the bench mon is paid after the share line")
  T.eq(log[3].split, 2, "gen5: bench gets half a fighter's share")
  T.eq(log[3].announce, nil, "gen5: bench gains are not announced per mon")
  T.eq(#log, 3, "gen5: fighter share + share line + one bench share")
end

do
  -- two fighters, one bench: participants split the full amount
  local log = {}
  local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen5" },
                      party = { monA, monB, monC } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 2,
    alive = { monA, monB },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].split, 2, "gen5: fighter share splits by participants")
  T.eq(log[2].split, 2, "gen5: second fighter same share")
  T.eq(log[3].kind, "say", "gen5: the share line follows both fighters")
  T.eq(log[4].split, 4, "gen5: bench = participants(2) x 2")
  T.eq(#log, 4, "gen5: two fighter shares + share line + one bench share")
end

do
  -- fainted bench mons are skipped; a full-participant party shows no
  -- share line at all
  local log = {}
  local monA, monB, dead = { hp = 10 }, { hp = 10 }, { hp = 0 }
  local battle = {
    game = { save = { options = { expShare = "gen5" },
                      party = { monA, monB, dead } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 2,
    alive = { monA, monB },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(#log, 2, "gen5: fainted bench mon is skipped")
end

do
  -- solo party: vanilla amounts, no message
  local log = {}
  local monA = { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen5" }, party = { monA } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].split, 1, "gen5: solo mon keeps the full amount")
  T.eq(#log, 1, "gen5: no share line for a solo party")
end

-- ------------------------------------------------ BALANCED split

do
  -- bench below the active fighter's level: half share + share line
  local log = {}
  local monA, monB = { hp = 10, level = 12 }, { hp = 10, level = 10 }
  local battle = {
    game = { save = { options = { expShare = "balanced" },
                      party = { monA, monB } } },
    player = { mon = { level = 12 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardBalanced(ctx)
  T.eq(log[1].mon, monA, "balanced: the fighter keeps the full amount")
  T.eq(log[1].split, 1, "balanced: fighter split = participants(1)")
  T.eq(log[2].kind, "say", "balanced: the share line follows the fighter")
  T.eq(log[3].mon, monB, "balanced: the under-leveled bench mon is paid")
  T.eq(log[3].split, 2, "balanced: bench gets half a fighter's share")
  T.eq(log[3].announce, nil, "balanced: bench gains are not announced per mon")
  T.eq(#log, 3, "balanced: fighter share + share line + one bench share")
end

do
  -- bench AT the active fighter's level: no exp, no share line
  local log = {}
  local monA, monB = { hp = 10, level = 12 }, { hp = 10, level = 12 }
  local battle = {
    game = { save = { options = { expShare = "balanced" },
                      party = { monA, monB } } },
    player = { mon = { level = 12 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardBalanced(ctx)
  T.eq(#log, 1, "balanced: a bench mon at the fighter's level gets nothing")
end

do
  -- bench ABOVE the active fighter's level: no exp, no share line
  local log = {}
  local monA, monB = { hp = 10, level = 10 }, { hp = 10, level = 14 }
  local battle = {
    game = { save = { options = { expShare = "balanced" },
                      party = { monA, monB } } },
    player = { mon = { level = 10 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardBalanced(ctx)
  T.eq(#log, 1, "balanced: an over-leveled bench mon gets nothing")
end

do
  -- mixed bench: only the under-leveled mon is paid, share line still
  -- shows once
  local log = {}
  local monA = { hp = 10, level = 12 }
  local under, equal = { hp = 10, level = 9 }, { hp = 10, level = 12 }
  local battle = {
    game = { save = { options = { expShare = "balanced" },
                      party = { monA, under, equal } } },
    player = { mon = { level = 12 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardBalanced(ctx)
  T.eq(log[1].mon, monA, "balanced: the fighter is paid first")
  T.eq(log[2].kind, "say", "balanced: one share line")
  T.eq(log[3].mon, under, "balanced: only the under-leveled bench mon is paid")
  T.eq(#log, 3, "balanced: the at-level bench mon is skipped")
end

do
  -- solo party: vanilla amounts, no gate involvement
  local log = {}
  local monA = { hp = 10, level = 7 }
  local battle = {
    game = { save = { options = { expShare = "balanced" },
                      party = { monA } } },
    player = { mon = { level = 7 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardBalanced(ctx)
  T.eq(log[1].split, 1, "balanced: solo mon keeps the full amount")
  T.eq(#log, 1, "balanced: no share line for a solo party")
end

-- ------------------------------------------------ AVERAGE split

do
  -- party {12, 10, 8} averages 10; the bench at 9 is below it and is
  -- paid, the bench at 10 is at the average and is skipped
  local log = {}
  local monA, monB, monC = { hp = 10, level = 12 }, { hp = 10, level = 9 },
                            { hp = 10, level = 10 }
  local battle = {
    game = { save = { options = { expShare = "average" },
                      party = { monA, monB, monC } } },
    player = { mon = { level = 12 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardAverage(ctx)
  T.eq(log[1].mon, monA, "average: the fighter keeps the full amount")
  T.eq(log[1].split, 1, "average: fighter split = participants(1)")
  T.eq(log[2].kind, "say", "average: the share line follows the fighter")
  T.eq(log[3].mon, monB, "average: the below-average bench mon is paid")
  T.eq(log[3].split, 2, "average: bench gets half a fighter's share")
  T.eq(log[3].announce, nil, "average: bench gains are not announced per mon")
  T.eq(#log, 3, "average: the at-average bench mon is skipped")
end

do
  -- flat party {10, 10, 10} averages 10: the bench at 10 gets nothing
  local log = {}
  local monA, monB = { hp = 10, level = 10 }, { hp = 10, level = 10 }
  local battle = {
    game = { save = { options = { expShare = "average" },
                      party = { monA, monB } } },
    player = { mon = { level = 10 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardAverage(ctx)
  T.eq(#log, 1, "average: a bench mon at the party average gets nothing")
end

do
  -- party {14, 12, 8} averages 11 (floored): the bench at 12 is above
  -- the average and gets nothing (even though it is below the fighter);
  -- only the level-8 bench mon is paid
  local log = {}
  local monA, monHigh, monLow = { hp = 10, level = 14 }, { hp = 10, level = 12 },
                                { hp = 10, level = 8 }
  local battle = {
    game = { save = { options = { expShare = "average" },
                      party = { monA, monHigh, monLow } } },
    player = { mon = { level = 14 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardAverage(ctx)
  T.eq(log[1].mon, monA, "average: the fighter is paid first")
  T.eq(log[2].kind, "say", "average: one share line")
  T.eq(log[3].mon, monLow, "average: only the below-average bench mon is paid")
  T.eq(#log, 3, "average: the above-average bench mon is skipped")
end

do
  -- solo party: no gate involvement
  local log = {}
  local monA = { hp = 10, level = 7 }
  local battle = {
    game = { save = { options = { expShare = "average" },
                      party = { monA } } },
    player = { mon = { level = 7 } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardAverage(ctx)
  T.eq(log[1].split, 1, "average: solo mon keeps the full amount")
  T.eq(#log, 1, "average: no share line for a solo party")
end

-- ------------------------------------------------ SINGLE EXP SHARE row

local function findSlotRow(game)
  local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
    game, { { id = "text_speed" } })
  for _, row in ipairs(rows) do
    if row.id == "exp_share_single" then return row end
  end
  return nil
end

local slotWritten = 0
local slotGame = {
  save = { options = {} },
  writeOptions = function(self)
    assert(type(self) == "table" and self.save ~= nil,
           "writeOptions must be called with a colon")
    slotWritten = slotWritten + 1
  end,
}

local slotRow = findSlotRow(slotGame)
T.neq(slotRow, nil, "the SINGLE EXP SHARE row joins the options menu")
T.eq(slotRow.label, "SINGLE EXP SHARE", "slot row label")
T.eq(slotRow.value(slotGame), "ALL", "slot defaults to ALL")
for _, want in ipairs({ "1", "2", "3", "4", "5", "6" }) do
  T.eq(slotRow.step(slotGame, 1), true, "slot step right (" .. want .. ")")
  T.eq(slotGame.save.options.expShareSingle, want, "slot value follows the save")
  T.eq(slotRow.value(slotGame), want, "slot label shows the slot")
end
T.eq(slotRow.step(slotGame, 1), true, "slot step right wraps")
T.eq(slotGame.save.options.expShareSingle, "all", "slot 6 wraps back to ALL")
T.eq(slotRow.value(slotGame), "ALL", "slot ALL label after the wrap")
T.eq(slotRow.step(slotGame, -1), true, "slot step left works")
T.eq(slotGame.save.options.expShareSingle, "6", "slot ALL left-cycles to 6")
T.eq(slotWritten, 8, "each slot step persists via writeOptions")

slotGame.save.options.expShareSingle = "all"
T.eq(ex.slotOf(slotGame), nil, "ALL means the whole party")
slotGame.save.options.expShareSingle = "3"
T.eq(ex.slotOf(slotGame), 3, "slot 3 is recognized")
slotGame.save.options.expShareSingle = "0"
T.eq(ex.slotOf(slotGame), nil, "slot 0 is out of range")
slotGame.save.options.expShareSingle = "7"
T.eq(ex.slotOf(slotGame), nil, "slot 7 is out of range")
slotGame.save.options.expShareSingle = "bogus"
T.eq(ex.slotOf(slotGame), nil, "a garbage slot value means ALL")
T.eq(ex.cycleSlot({}), nil, "no save -> nil (launcher is untouched)")
T.eq(ex.cycleSlot({ save = {} }), nil, "no options table -> nil")

-- ------------------------------------------------ LEVEL UP JINGLE row & sound redirect

local function findJingleRow(game)
  local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
    game, { { id = "text_speed" } })
  for _, row in ipairs(rows) do
    if row.id == "exp_share_jingle" then return row end
  end
  return nil
end

local jingleWritten = 0
local jingleGame = {
  save = { options = {} },
  writeOptions = function(self)
    assert(type(self) == "table" and self.save ~= nil,
           "writeOptions must be called with a colon")
    jingleWritten = jingleWritten + 1
  end,
}

local jingleRow = findJingleRow(jingleGame)
T.neq(jingleRow, nil, "the LEVEL UP JINGLE row joins the options menu")
T.eq(jingleRow.label, "LEVEL UP JINGLE", "jingle row label")
T.eq(jingleRow.value(jingleGame), "LEVEL UP", "jingle defaults to LEVEL UP")
T.eq(jingleRow.step(jingleGame, 1), true, "jingle step right")
T.eq(jingleGame.save.options.expShareJingle, "item", "jingle value becomes item")
T.eq(jingleRow.value(jingleGame), "ITEM", "jingle label shows ITEM")
T.eq(jingleRow.step(jingleGame, 1), true, "jingle step right again")
T.eq(jingleGame.save.options.expShareJingle, "level_up", "jingle wraps to level_up")
T.eq(jingleRow.value(jingleGame), "LEVEL UP", "jingle label shows LEVEL UP")
T.eq(jingleRow.step(jingleGame, -1), true, "jingle step left")
T.eq(jingleGame.save.options.expShareJingle, "item", "jingle left-steps to item")
T.eq(jingleWritten, 3, "each jingle step persists via writeOptions")

jingleGame.save.options.expShareJingle = "item"
T.eq(ex.jingleOf(jingleGame), "item", "item mode recognized")
T.eq(ex.shouldRedirectJingle(jingleGame), true, "shouldRedirectJingle true for item")
jingleGame.save.options.expShareJingle = "level_up"
T.eq(ex.jingleOf(jingleGame), "level_up", "level_up mode recognized")
T.eq(ex.shouldRedirectJingle(jingleGame), false, "shouldRedirectJingle false for level_up")
jingleGame.save.options.expShareJingle = "bogus"
T.eq(ex.jingleOf(jingleGame), "level_up", "bogus normalizes to level_up")
T.eq(ex.cycleJingle({}), nil, "no save -> nil (launcher is untouched)")
T.eq(ex.cycleJingle({ save = {} }), nil, "no options table -> nil")

do
  local Sound = require("src.core.Sound")
  local played = {}
  local fakeSrc = {
    play = function(self) self.playing = true end,
    stop = function(self) self.playing = false end,
    isPlaying = function(self) return self.playing == true end,
  }
  local gen1Data = {
    audio = {
      sfx = {
        Level_Up = { file = "levelup.wav" },
        Get_Item1 = { file = "item1.wav" },
      }
    }
  }
  local gen2Data = {
    audio = {
      sfx = {
        Sfx_DexFanfare5079 = { file = "dexfanfare.wav" },
        Sfx_Item = { file = "item.wav" },
      }
    }
  }

  -- When toggle is set to ITEM: Level_Up -> Get_Item1 (Gen 1) / Sfx_Item (Gen 2)
  local itemGame = { save = { options = { expShareJingle = "item" } } }
  ex.cycleJingle(itemGame, 0) -- sets activeOptions / updates lastOptions
  T.eq(Sound.resolve(gen1Data, "Level_Up"), "Get_Item1", "gen1 Level_Up redirects to Get_Item1")
  T.eq(Sound.resolve(gen2Data, "Sfx_DexFanfare5079"), "Sfx_Item", "gen2 Sfx_DexFanfare5079 redirects to Sfx_Item")
  T.eq(Sound.resolve(gen2Data, "Level_Up"), "Sfx_Item", "gen2 Level_Up redirects to Sfx_Item")
  T.eq(Sound.ducksMusic(gen1Data, "Level_Up"), Sound.ducksMusic(gen1Data, "Get_Item1"), "ducksMusic follows redirected sfx")

  -- When toggle is set to LEVEL UP: default sounds retained
  local defaultGame = { save = { options = { expShareJingle = "level_up" } } }
  ex.cycleJingle(defaultGame, 0)
  T.eq(Sound.resolve(gen1Data, "Level_Up"), "Level_Up", "gen1 Level_Up stays Level_Up when default")
  T.eq(Sound.resolve(gen2Data, "Sfx_DexFanfare5079"), "Sfx_DexFanfare5079", "gen2 fanfare stays when default")
end

-- ------------------------------------------------ SINGLE-slot splits

do
  -- GEN 5+ with slot 3: only the designated bench mon is paid
  local log = {}
  local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen5", expShareSingle = "3" },
                      party = { monA, monB, monC } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].mon, monA, "single: the fighter keeps the full amount")
  T.eq(log[1].split, 1, "single: fighter split = participants(1)")
  T.eq(log[1].announce, true, "single: the fighter's own gain is announced")
  T.eq(log[2].kind, "say", "single: the share line follows the fighter")
  T.eq(log[3].mon, monC, "single: only the designated slot mon is paid")
  T.eq(log[3].split, 2, "single: the designated mon gets half a fighter's share")
  T.eq(log[3].announce, nil, "single: the designated gain is not announced")
  T.eq(#log, 3, "single: the other bench mon is skipped")
end

do
  -- GEN 5+ slot pointing at the fighter: nothing is shared, no line
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen5", expShareSingle = "1" },
                      party = { monA, monB } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].mon, monA, "single-to-fighter: the fighter keeps the full amount")
  T.eq(#log, 1, "single-to-fighter: no bench, no share line")
end

do
  -- GEN 5+ slot beyond the party size: the empty slot shares to nobody
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen5", expShareSingle = "6" },
                      party = { monA, monB } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].mon, monA, "empty-slot: the fighter keeps the full amount")
  T.eq(#log, 1, "empty-slot: an empty designated slot shares to nobody")
end

do
  -- GEN 1 with slot 2: the party pass reaches only the designated mon
  local log = {}
  local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen1", expShareSingle = "2" },
                      party = { monA, monB, monC } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen1(ctx)
  T.eq(log[1].mon, monA, "gen1 single: the fighter gets its announced half")
  T.eq(log[1].split, 2, "gen1 single: fighter split = participants(1) x 2")
  T.eq(log[1].announce, true, "gen1 single: the fighter's gain is announced")
  T.eq(log[2].kind, "say", "gen1 single: the share line follows the fighter")
  T.eq(log[2].text, "EXP is shared\namongst the party!",
    "gen1 single: the single shared-exp line")
  T.eq(log[3].mon, monB, "gen1 single: only the designated slot mon is in the party pass")
  T.eq(log[3].split, 6, "gen1 single: party pass = 1 x party(3) x 2")
  T.eq(log[3].announce, nil, "gen1 single: the party-pass gain is not announced")
  T.eq(#log, 3, "gen1 single: the other party mons are skipped")
end

do
  -- GEN 1 slot pointing at the fighter: the party pass stays with the
  -- fighter (no share line -- nothing is shared to anyone else)
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local battle = {
    game = { save = { options = { expShare = "gen1", expShareSingle = "1" },
                      party = { monA, monB } } },
    sayNext = function(_, text) log[#log + 1] = { kind = "say", text = text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split, announce)
      log[#log + 1] = { kind = "share", mon = mon, split = split,
                        announce = announce }
    end,
  }
  ex.awardGen1(ctx)
  T.eq(log[1].mon, monA, "gen1 single-to-fighter: the announced half")
  T.eq(log[2].mon, monA, "gen1 single-to-fighter: the party pass stays with the fighter")
  T.eq(log[2].split, 4, "gen1 single-to-fighter: party pass = 1 x party(2) x 2")
  T.eq(#log, 2, "gen1 single-to-fighter: no share line for a fighter-only pass")
end

-- ------------------------------------------------ hook wiring

do
  -- OFF defers to the vanilla split (nextFn runs untouched)
  local sawVanilla = false
  local offBattle = {
    game = { save = { options = { expShare = "off" }, party = {} } },
  }
  Runtime.call("battle.exp_award", function() sawVanilla = true end,
    { battle = offBattle })
  T.eq(sawVanilla, true, "OFF calls through to the vanilla split")
end

do
  -- GEN 5+ replaces the vanilla split without calling it
  local sawVanilla = false
  local calls = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local gen5Battle = {
    game = { save = { options = { expShare = "gen5" },
                      party = { monA, monB } } },
    sayNext = function() end,
  }
  local ctx = {
    battle = gen5Battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) calls[#calls + 1] = split end,
  }
  Runtime.call("battle.exp_award", function() sawVanilla = true end, ctx)
  T.eq(sawVanilla, false, "GEN 5+ replaces the vanilla split")
  T.eq(#calls, 2, "the mod's split ran instead")
end

do
  -- BALANCED replaces the vanilla split without calling it
  local sawVanilla = false
  local calls = {}
  local monA, monB = { hp = 10, level = 12 }, { hp = 10, level = 10 }
  local balancedBattle = {
    game = { save = { options = { expShare = "balanced" },
                      party = { monA, monB } } },
    player = { mon = { level = 12 } },
    sayNext = function() end,
  }
  local ctx = {
    battle = balancedBattle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) calls[#calls + 1] = split end,
  }
  Runtime.call("battle.exp_award", function() sawVanilla = true end, ctx)
  T.eq(sawVanilla, false, "BALANCED replaces the vanilla split")
  T.eq(#calls, 2, "the mod's split ran instead")
end

do
  -- AVERAGE replaces the vanilla split without calling it
  local sawVanilla = false
  local calls = {}
  local monA, monB = { hp = 10, level = 12 }, { hp = 10, level = 9 }
  local averageBattle = {
    game = { save = { options = { expShare = "average" },
                      party = { monA, monB } } },
    player = { mon = { level = 12 } },
    sayNext = function() end,
  }
  local ctx = {
    battle = averageBattle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) calls[#calls + 1] = split end,
  }
  Runtime.call("battle.exp_award", function() sawVanilla = true end, ctx)
  T.eq(sawVanilla, false, "AVERAGE replaces the vanilla split")
  T.eq(#calls, 2, "the mod's split ran instead")
end

do
  -- SINGLE EXP SHARE filters the bench through the real hook
  local sawVanilla = false
  local calls = {}
  local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
  local slotBattle = {
    game = { save = { options = { expShare = "gen5", expShareSingle = "3" },
                      party = { monA, monB, monC } } },
    sayNext = function() end,
  }
  local ctx = {
    battle = slotBattle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) calls[#calls + 1] = mon end,
  }
  Runtime.call("battle.exp_award", function() sawVanilla = true end, ctx)
  T.eq(sawVanilla, false, "single-slot replaces the vanilla split")
  T.eq(#calls, 2, "single through the hook: fighter + one designated mon")
  T.eq(calls[1], monA, "single through the hook: the fighter is paid first")
  T.eq(calls[2], monC, "single through the hook: only the slot-3 mon is paid")
end

-- ------------------------------------------------ real battle integration

do
  local SaveData = require("src.core.SaveData")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local save = SaveData.newGame()
  local monA = Pokemon.new(Data, "FIXMON_A", 10)
  local monB = Pokemon.new(Data, "FIXMON_A", 10)
  save.party = { monA, monB }
  save.options = { expShare = "gen5" }
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  local game = { data = Data, save = save, stack = stack,
                 input = { wasPressed = function() return true end } }
  local battle = BattleState.newWild(game, "FIXMON_B", 5)
  battle.participants = { [battle.player.mon] = true }
  local expBefore = monA.exp + monB.exp
  battle:awardExp()
  T.check(monA.exp > 0, "integration: the fighter gained exp")
  T.check(monB.exp > 0, "integration: the bench mon gained exp")
  T.check(monA.exp + monB.exp > expBefore, "integration: total exp went up")
  T.check(monA.exp > monB.exp,
    "integration: the fighter out-earns the half-share bench mon")
end

-- ------------------------------------------------ Gen 2 (Gold) support

do
  -- Gen 2's Battle carries the save itself (battle.save / battle.party, no
  -- battle.game), announces through battle:emit, and battle.player IS the
  -- party mon.  The GEN 5+ split must pay the fighter and the bench the same
  -- way it does on Gen 1.
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local battle = {
    save = { options = { expShare = "gen5" }, party = { monA, monB } },
    party = { monA, monB },
    player = monA,
    emit = function(_, ev) log[#log + 1] = { kind = "say", text = ev.text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split)
      log[#log + 1] = { kind = "share", mon = mon, split = split }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].mon, monA, "gen2: the fighter keeps the full amount")
  T.eq(log[1].split, 1, "gen2: fighter split = participants(1)")
  T.eq(log[2].kind, "say", "gen2: the share line is emitted")
  T.eq(log[2].text, "EXP is shared\namongst the party!",
    "gen2: the single shared-exp line")
  T.eq(log[3].mon, monB, "gen2: the bench mon is paid after the share line")
  T.eq(log[3].split, 2, "gen2: bench gets half a fighter's share")
  T.eq(#log, 3, "gen2: fighter share + emit line + one bench share")
end

do
  -- Gen 2 BALANCED: battle.player IS the mon, so the cap level comes from
  -- battle.player.level rather than battle.player.mon.level
  local log = {}
  local monA, monB = { hp = 10, level = 12 }, { hp = 10, level = 10 }
  local battle = {
    save = { options = { expShare = "balanced" }, party = { monA, monB } },
    party = { monA, monB },
    player = monA,
    emit = function(_, ev) log[#log + 1] = { kind = "say", text = ev.text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split)
      log[#log + 1] = { kind = "share", mon = mon, split = split }
    end,
  }
  ex.awardBalanced(ctx)
  T.eq(log[1].mon, monA, "gen2 balanced: the fighter keeps the full amount")
  T.eq(log[3].mon, monB, "gen2 balanced: the under-leveled bench mon is paid")
  T.eq(log[3].split, 2, "gen2 balanced: bench gets half a fighter's share")
  T.eq(#log, 3, "gen2 balanced: fighter share + emit line + one bench share")
end

do
  -- Gen 2 AVERAGE: the party average is read from battle.party
  local log = {}
  local monA, monB = { hp = 10, level = 12 }, { hp = 10, level = 9 }
  local battle = {
    save = { options = { expShare = "average" }, party = { monA, monB } },
    party = { monA, monB },
    player = monA,
    emit = function(_, ev) log[#log + 1] = { kind = "say", text = ev.text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split)
      log[#log + 1] = { kind = "share", mon = mon, split = split }
    end,
  }
  ex.awardAverage(ctx)
  T.eq(log[1].mon, monA, "gen2 average: the fighter keeps the full amount")
  T.eq(log[3].mon, monB, "gen2 average: the below-average bench mon is paid")
  T.eq(log[3].split, 2, "gen2 average: bench gets half a fighter's share")
  T.eq(#log, 3, "gen2 average: fighter share + emit line + one bench share")
end

do
  -- Gen 2 SINGLE EXP SHARE: the slot is read from battle.save.options
  local log = {}
  local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
  local battle = {
    save = { options = { expShare = "gen5", expShareSingle = "3" },
             party = { monA, monB, monC } },
    party = { monA, monB, monC },
    player = monA,
    emit = function(_, ev) log[#log + 1] = { kind = "say", text = ev.text } end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split)
      log[#log + 1] = { kind = "share", mon = mon, split = split }
    end,
  }
  ex.awardGen5(ctx)
  T.eq(log[1].mon, monA, "gen2 single: the fighter keeps the full amount")
  T.eq(log[3].mon, monC, "gen2 single: only the slot-3 mon is paid")
  T.eq(#log, 3, "gen2 single: the other bench mon is skipped")
end

do
  -- the exp_award hook reads the mode from battle.save.options on Gen 2
  local sawVanilla = false
  local calls = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local gen5Battle = {
    save = { options = { expShare = "gen5" }, party = { monA, monB } },
    party = { monA, monB },
    emit = function() end,
  }
  local ctx = {
    battle = gen5Battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) calls[#calls + 1] = split end,
  }
  Runtime.call("battle.exp_award", function() sawVanilla = true end, ctx)
  T.eq(sawVanilla, false, "gen2: GEN 5+ replaces the vanilla split")
  T.eq(#calls, 2, "gen2: the mod's split ran instead")
end

do
  -- Gen 2 GEN 1: an isEgg mon in the party takes no share, the party pass
  -- goes to the living non-egg mons only
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local egg = { hp = 10, isEgg = true }
  local battle = {
    save = { options = { expShare = "gen1" }, party = { monA, monB, egg } },
    party = { monA, monB, egg },
    player = monA,
    emit = function() end,
  }
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) log[#log + 1] = { mon = mon, split = split } end,
  }
  ex.awardGen1(ctx)
  T.eq(#log, 3, "gen2 egg gen1: fighter + two party passes, no egg pass")
  for _, entry in ipairs(log) do
    T.neq(entry.mon, egg, "gen2 egg gen1: the isEgg mon gets no share")
  end
  T.eq(log[1].split, 2, "gen2 egg gen1: fighter split is unchanged")
  -- the divisor counts only the two non-egg mons: 1 x 2 x 2
  T.eq(log[2].split, 4, "gen2 egg gen1: divisor leaves the egg out")
  T.eq(log[3].split, 4, "gen2 egg gen1: the second non-egg mon shares the divisor")
end

-- ---- Gen 3 jingle

do
  -- the mod wraps Audio.playFanfare once the Gen 3 audio module is loaded:
  -- with the ITEM jingle a level-up fanfare plays the item chime instead,
  -- and the default LEVEL UP leaves every id untouched.  The audio module is
  -- stubbed before the load and put back after it.
  local played = {}
  local audioStub = {
    playFanfare = function(id) played[#played + 1] = id return true end,
    role = function(name) if name == "levelUp" then return 257 end end,
  }
  local key = "src.core.game3.audio"
  local prev = package.loaded[key]
  package.loaded[key] = audioStub
  local run4 = T.sdk.loadMod("mods/exp_share", { data = T.sdk.gen3Data(), generation = 3 })
  package.loaded[key] = prev
  local ex4 = run4.loader.exports.exp_share
  local game = { save = { options = {} } }

  -- default LEVEL UP: the fanfare id passes through unchanged
  audioStub.playFanfare("MUS_LEVEL_UP")
  T.eq(played[1], "MUS_LEVEL_UP", "gen3 jingle: LEVEL UP leaves the fanfare alone")

  -- ITEM: a level-up fanfare (by name or by the role id) becomes the item chime
  ex4.cycleJingle(game)
  T.eq(game.save.options.expShareJingle, "item", "gen3 jingle: cycles to ITEM")
  audioStub.playFanfare("MUS_LEVEL_UP")
  T.eq(played[2], "MUS_OBTAIN_ITEM", "gen3 jingle: ITEM swaps MUS_LEVEL_UP")
  audioStub.playFanfare(257)
  T.eq(played[3], "MUS_OBTAIN_ITEM", "gen3 jingle: ITEM swaps the levelUp role id")
  audioStub.playFanfare("MUS_WILD_VICTORY")
  T.eq(played[4], "MUS_WILD_VICTORY", "gen3 jingle: other fanfares pass through")

  -- back to LEVEL UP: the swap stops
  ex4.cycleJingle(game)
  T.eq(game.save.options.expShareJingle, "level_up", "gen3 jingle: cycles back to LEVEL UP")
  audioStub.playFanfare("MUS_LEVEL_UP")
  T.eq(played[5], "MUS_LEVEL_UP", "gen3 jingle: LEVEL UP again leaves the fanfare alone")
  run4.release()
end

do
  -- a second load on the same audio module must redirect through the newest
  -- api: the wrapper is installed once, but it reads Audio._expShareApi, which
  -- every load refreshes
  local played = {}
  local audioStub = {
    playFanfare = function(id) played[#played + 1] = id return true end,
    role = function(name) if name == "levelUp" then return 257 end end,
  }
  local key = "src.core.game3.audio"
  local prev = package.loaded[key]
  package.loaded[key] = audioStub
  local run5 = T.sdk.loadMod("mods/exp_share", { data = T.sdk.gen3Data(), generation = 3 })
  run5.release()
  local run6 = T.sdk.loadMod("mods/exp_share", { data = T.sdk.gen3Data(), generation = 3 })
  package.loaded[key] = prev
  local ex6 = run6.loader.exports.exp_share
  local game = { save = { options = {} } }
  ex6.cycleJingle(game)
  T.eq(game.save.options.expShareJingle, "item", "gen3 reload: the second load sets ITEM")
  audioStub.playFanfare("MUS_LEVEL_UP")
  T.eq(played[1], "MUS_OBTAIN_ITEM", "gen3 reload: the wrapper uses the newest api")
  run6.release()
end

-- the Gen 3 blocks run on a generation=3 load: the mod's require of the Gen 3
-- battle UI is a cross-generation denial on a Gen 1 load
local run3 = T.sdk.loadMod("mods/exp_share", { data = T.sdk.gen3Data(), generation = 3 })
local ex3 = run3.loader.exports.exp_share
T.eq(type(ex3.awardGen1), "function", "gen 3 exports awardGen1 for the Gen 3 blocks")
T.eq(type(ex3.awardGen5), "function", "gen 3 exports awardGen5 for the Gen 3 blocks")

-- Gen 3's battle is the raw state table: playerParty plus session, with the
-- options on session.engineOptions.  The share line goes to the battle text
-- box (Ui.push), so the Ui module is stubbed for the duration of a case.
local function withGen3Ui(fn)
  local key = "src.core.game3.battle.ui"
  local prev = package.loaded[key]
  local pushed = {}
  package.loaded[key] = { push = function(text) pushed[#pushed + 1] = text end }
  local ok, err = pcall(fn, pushed)
  package.loaded[key] = prev
  if not ok then error(err, 0) end
end

local function gen3Battle(mode, party)
  return {
    playerParty = party,
    session = { engineOptions = { expShare = mode } },
  }
end

do
  -- GEN 1 on Gen 3: one fighter of three, the two bench mons take the
  -- party pass, and the share line lands in the text box
  withGen3Ui(function(pushed)
    local log = {}
    local monA, monB, monC = { hp = 10 }, { hp = 10 }, { hp = 10 }
    local battle = gen3Battle("gen1", { monA, monB, monC })
    local ctx = {
      battle = battle,
      participants = 1,
      alive = { monA },
      applyShare = function(mon, split, announce)
        log[#log + 1] = { kind = "share", mon = mon, split = split,
                          announce = announce }
      end,
    }
    ex3.awardGen1(ctx)
    T.eq(log[1].mon, monA, "gen3 gen1: the fighter gets the first share")
    T.eq(log[1].split, 2, "gen3 gen1: fighter split = participants(1) x 2")
    T.eq(log[1].announce, true, "gen3 gen1: the fighter's own gain is announced")
    T.eq(#pushed, 1, "gen3 gen1: one share line in the text box")
    T.eq(pushed[1], "EXP is shared\namongst the party!",
      "gen3 gen1: the single shared-exp line")
    T.eq(log[2].mon, monA, "gen3 gen1: the fighter is in the party pass too")
    T.eq(log[2].split, 6, "gen3 gen1: party split = participants(1) x party(3) x 2")
    T.eq(log[3].mon, monB, "gen3 gen1: bench mon B gets the party pass")
    T.eq(log[3].split, 6, "gen3 gen1: bench B shares the same divisor")
    T.eq(log[4].mon, monC, "gen3 gen1: bench mon C gets the party pass")
    T.eq(log[4].split, 6, "gen3 gen1: bench C shares the same divisor")
    T.eq(#log, 4, "gen3 gen1: fighter share + party pass for all three mons")
  end)
end

do
  -- GEN 5+ on Gen 3: the fighter keeps the full amount, the bench gets half
  -- a fighter's share, and fainted bench mons are skipped
  withGen3Ui(function(pushed)
    local log = {}
    local monA, monB, dead = { hp = 10 }, { hp = 10 }, { hp = 0 }
    local battle = gen3Battle("gen5", { monA, monB, dead })
    local ctx = {
      battle = battle,
      participants = 1,
      alive = { monA },
      applyShare = function(mon, split, announce)
        log[#log + 1] = { kind = "share", mon = mon, split = split,
                          announce = announce }
      end,
    }
    ex3.awardGen5(ctx)
    T.eq(log[1].mon, monA, "gen3 gen5: the fighter keeps the full amount")
    T.eq(log[1].split, 1, "gen3 gen5: fighter split = participants(1)")
    T.eq(log[1].announce, true, "gen3 gen5: the fighter's own gain is announced")
    T.eq(#pushed, 1, "gen3 gen5: one share line in the text box")
    T.eq(log[2].mon, monB, "gen3 gen5: the living bench mon is paid")
    T.eq(log[2].split, 2, "gen3 gen5: bench gets half a fighter's share")
    T.eq(log[2].announce, nil, "gen3 gen5: bench gains are not announced per mon")
    T.eq(#log, 2, "gen3 gen5: the fainted mon is skipped")
  end)
end

do
  -- a SPECIES_EGG on the bench is not a battler: it takes no share in GEN 5+
  -- or GEN 1, and the party count used for the GEN 1 divisor is unchanged
  local log = {}
  local monA, monB = { hp = 10 }, { hp = 10 }
  local egg = { hp = 10, species = 412 }
  local battle = gen3Battle("gen5", { monA, monB, egg })
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) log[#log + 1] = { mon = mon, split = split } end,
  }
  ex3.awardGen5(ctx)
  T.eq(#log, 2, "gen3 egg gen5: only the fighter and the bench mon are paid")
  for _, entry in ipairs(log) do
    T.neq(entry.mon, egg, "gen3 egg gen5: the egg gets no share")
  end

  log = {}
  battle = gen3Battle("gen1", { monA, monB, egg })
  ctx.battle = battle
  ex3.awardGen1(ctx)
  T.eq(#log, 3, "gen3 egg gen1: fighter + two party passes, no egg pass")
  for _, entry in ipairs(log) do
    T.neq(entry.mon, egg, "gen3 egg gen1: the egg gets no share")
  end
  T.eq(log[1].split, 2, "gen3 egg gen1: fighter split is unchanged")
  -- the divisor counts only the two non-egg mons: 1 x 2 x 2
  T.eq(log[2].split, 4, "gen3 egg gen1: divisor leaves the egg out")
  T.eq(log[3].split, 4, "gen3 egg gen1: the second non-egg mon shares the divisor")
end

do
  -- AVERAGE on Gen 3 measures the level cap over the non-egg party: the egg
  -- (level 3) would drag the average to 8 and lock monB out, but without it
  -- the cap is floor((12 + 9) / 2) = 10 and monB at 9 still gains
  local log = {}
  local monA = { hp = 10, level = 12 }
  local monB = { hp = 10, level = 9 }
  local egg = { hp = 10, level = 3, species = 412 }
  local battle = gen3Battle("average", { monA, monB, egg })
  local ctx = {
    battle = battle,
    participants = 1,
    alive = { monA },
    applyShare = function(mon, split) log[#log + 1] = { mon = mon, split = split } end,
  }
  ex3.awardAverage(ctx)
  T.eq(#log, 2, "gen3 egg average: fighter + the below-average bench mon")
  T.eq(log[1].mon, monA, "gen3 egg average: the fighter keeps the full amount")
  T.eq(log[2].mon, monB, "gen3 egg average: monB is under the non-egg average")
  T.eq(log[2].split, 2, "gen3 egg average: bench gets half a fighter's share")
  for _, entry in ipairs(log) do
    T.neq(entry.mon, egg, "gen3 egg average: the egg gets no share")
  end
end

-- ---- Gen 3 hook wiring

do
  -- OFF on Gen 3 defers to the vanilla split and shows no share line
  withGen3Ui(function(pushed)
    local sawVanilla = false
    local battle = gen3Battle("off", { { hp = 10 } })
    Runtime.call("battle.exp_award", function() sawVanilla = true end,
      { battle = battle })
    T.eq(sawVanilla, true, "gen3 OFF calls through to the vanilla split")
    T.eq(#pushed, 0, "gen3 OFF pushes no share line")
  end)
end

do
  -- GEN 5+ on Gen 3 replaces the vanilla split and reaches the hook through
  -- the Gen 3 shape (no save, game or party on the battle)
  withGen3Ui(function(pushed)
    local sawVanilla = false
    local calls = {}
    local monA, monB = { hp = 10 }, { hp = 10 }
    local battle = gen3Battle("gen5", { monA, monB })
    local ctx = {
      battle = battle,
      participants = 1,
      alive = { monA },
      applyShare = function(mon, split) calls[#calls + 1] = split end,
    }
    Runtime.call("battle.exp_award", function() sawVanilla = true end, ctx)
    T.eq(sawVanilla, false, "gen3: GEN 5+ replaces the vanilla split")
    T.eq(#calls, 2, "gen3: the mod's split ran instead")
    T.eq(#pushed, 1, "gen3: the share line went through Ui.push")
  end)
end

-- ---- Gen 3 title-screen row

do
  -- before any save exists the title-screen OPTIONS menu hands the row a game
  -- with no save and the root options table; the row must still step it and
  -- persist through writeOptions
  local written = 0
  local game = {
    options = { expShare = "off" },
    writeOptions = function(self)
      assert(type(self) == "table" and self.options ~= nil,
             "writeOptions must be called with a colon")
      written = written + 1
    end,
  }
  local row = findRow(game)
  T.neq(row, nil, "gen3 title: the EXP SHARE row joins the options menu")
  T.eq(row.value(game), "OFF", "gen3 title: defaults to OFF")
  T.eq(row.step(game, 1), true, "gen3 title: stepping right works with no save")
  T.eq(game.options.expShare, "gen1", "gen3 title: OFF cycles to GEN 1 on game.options")
  T.eq(row.value(game), "GEN 1", "gen3 title: value follows game.options")
  T.eq(written, 1, "gen3 title: the step calls writeOptions")
end

-- ---- Gen 3 share message

do
  -- the share line goes through the Gen 3 battle UI (Ui.push) and does not
  -- throw when the battle has no sayNext or emit
  withGen3Ui(function(pushed)
    local monA, monB = { hp = 10 }, { hp = 10 }
    local battle = gen3Battle("gen5", { monA, monB })
    local ok, err = pcall(ex3.awardGen5, {
      battle = battle,
      participants = 1,
      alive = { monA },
      applyShare = function() end,
    })
    T.eq(ok, true, "gen3 share message does not throw: " .. tostring(err))
    T.eq(pushed[1], "EXP is shared\namongst the party!",
      "gen3 share message goes through Ui.push")
  end)
end

-- ---- Gen 3 OPTIONS menu

do
  -- the live Gen 3 option_rows module, the same instance the mod wrapped at
  -- load, so its Rows.GROUPS carries the mod's group.battle members.  The ROM
  -- text cache is not in the test checkout, so the RomText lookups the native
  -- rows make are swapped on the live rom_text table for the section and put
  -- back after.  Only native row ids are asserted, not their labels.
  local RomText = require("src.core.game3.rom_text")
  local Rows = package.loaded["src.ui.game3.option_rows"]
  T.neq(Rows, nil, "gen3 menu: option_rows is loaded by the Gen 3 load")
  local stubbed = {
    plain = function(key) return key end,
    box = function(key) return key end,
    ascii = function(key) return key end,
    at = function(name, i) return name .. "[" .. tostring(i) .. "]" end,
    count = function() return 6 end,
    has = function() return true end,
    key = function(name, i) return name .. "[" .. tostring(i) .. "]" end,
  }
  local saved = {}
  for name, fn in pairs(stubbed) do
    saved[name] = RomText[name]
    RomText[name] = fn
  end

  local MOD_IDS = {
    exp_share = true, exp_share_percent_slot = true, exp_share_percent = true,
    exp_share_single = true, exp_share_jingle = true,
  }

  local function byId(rows, id)
    for _, row in ipairs(rows) do
      if row.id == id then return row end
    end
    return nil
  end

  -- the OPTIONS screen's ctx: game may be nil on the title screen, options is
  -- the engine table, and the BATTLE OPTIONS page is opened through activate
  local function screenCtx(game, engine)
    return { game = game, session = {}, options = engine }
  end

  -- returns the flat list, the top-level list, and the BATTLE OPTIONS page
  local function openScreen(ctx)
    local flat = Rows.build(ctx)
    local page
    local top = Rows.group(flat, function(_, members) page = members end)
    local battle = byId(top, "group.battle")
    if battle then battle.activate(ctx) end
    return flat, top, page
  end

  local function idsOf(rows)
    local out = {}
    for i, row in ipairs(rows or {}) do out[i] = tostring(row.id) end
    return table.concat(out, ",")
  end

  do
    -- the mod's rows live on the BATTLE OPTIONS page, after the native battle
    -- rows, and nowhere on the top-level list
    local engine = {}
    local game = { save = { options = engine }, writeOptions = function() end }
    local ctx = screenCtx(game, engine)
    local _, top, page = openScreen(ctx)

    local loose = {}
    for _, row in ipairs(top) do
      if MOD_IDS[row.id] then loose[#loose + 1] = row.id end
    end
    T.eq(#loose, 0, "gen3 menu: no EXP SHARE row on the top-level list")
    T.neq(byId(top, "group.battle"), nil, "gen3 menu: BATTLE OPTIONS group row is on the top level")
    T.neq(page, nil, "gen3 menu: BATTLE OPTIONS activate opens a page")
    T.eq(idsOf(page),
      "battleScene,battleStyle,exp_share,exp_share_percent_slot,exp_share_percent,"
        .. "exp_share_single,exp_share_jingle",
      "gen3 menu: BATTLE OPTIONS page lists the native rows, then the mod rows in order")
    T.eq(byId(page, "exp_share").label, "EXP SHARE", "gen3 menu: EXP SHARE label")
    T.eq(byId(page, "exp_share_percent_slot").label, "PERCENT SLOT", "gen3 menu: PERCENT SLOT label")
    T.eq(byId(page, "exp_share_percent").label, "PERCENT", "gen3 menu: PERCENT label")
    T.eq(byId(page, "exp_share_single").label, "SINGLE EXP SHARE", "gen3 menu: SINGLE EXP SHARE label")
    T.eq(byId(page, "exp_share_jingle").label, "LEVEL UP JINGLE", "gen3 menu: LEVEL UP JINGLE label")

    -- the EXP SHARE row on the page steps the engine table through game.save
    local expRow = byId(page, "exp_share")
    T.eq(expRow.value(ctx), "OFF", "gen3 menu: EXP SHARE reads OFF by default")
    T.eq(expRow.step(ctx, 1), true, "gen3 menu: EXP SHARE steps on the OPTIONS page")
    T.eq(engine.expShare, "gen1", "gen3 menu: the step stores GEN 1 in the engine options")
    T.eq(expRow.value(ctx), "GEN 1", "gen3 menu: the EXP SHARE value label follows")
  end

  do
    -- PERCENT SLOT and PERCENT read "--" and refuse to step outside CUSTOM
    local engine = {}
    local game = { save = { options = engine }, writeOptions = function() end }
    local ctx = screenCtx(game, engine)
    local _, _, page = openScreen(ctx)
    local slotRow = byId(page, "exp_share_percent_slot")
    local pctRow = byId(page, "exp_share_percent")
    local expRow = byId(page, "exp_share")

    T.eq(slotRow.value(ctx), "--", "gen3 menu: PERCENT SLOT reads -- when OFF")
    T.eq(pctRow.value(ctx), "--", "gen3 menu: PERCENT reads -- when OFF")
    T.eq(slotRow.step(ctx, 1), false, "gen3 menu: PERCENT SLOT does not step when OFF")
    T.eq(pctRow.step(ctx, 1), false, "gen3 menu: PERCENT does not step when OFF")
    T.eq(engine.expSharePercent, nil, "gen3 menu: refused PERCENT step stores nothing")

    -- walk EXP SHARE up the ladder through the real row to CUSTOM
    for _, want in ipairs({ "gen1", "gen5", "balanced", "average", "custom" }) do
      T.eq(expRow.step(ctx, 1), true, "gen3 menu: EXP SHARE steps toward " .. want)
      T.eq(engine.expShare, want, "gen3 menu: EXP SHARE reaches " .. want)
    end
    T.eq(pctRow.value(ctx), "100%", "gen3 menu: PERCENT reads 100% in CUSTOM")
    T.eq(pctRow.step(ctx, 1), true, "gen3 menu: PERCENT steps in CUSTOM")
    T.eq(engine.expSharePercent, 10, "gen3 menu: the step stores the next percent")
    T.eq(pctRow.value(ctx), "10%", "gen3 menu: the PERCENT label changes after the step")
  end

  do
    -- ctx.game is nil on the title screen: every row must still read and step
    -- without throwing, and the mod's rows stay inert
    local engine = {}
    local ctx = screenCtx(nil, engine)
    local ok, err = pcall(function()
      local _, _, page = openScreen(ctx)
      T.neq(page, nil, "gen3 title menu: the BATTLE OPTIONS page opens")
      for _, id in ipairs({ "exp_share", "exp_share_percent_slot", "exp_share_percent",
                            "exp_share_single", "exp_share_jingle" }) do
        local row = byId(page, id)
        T.neq(row, nil, "gen3 title menu: " .. id .. " is listed")
        row.value(ctx)
        row.step(ctx, 1)
      end
    end)
    T.eq(ok, true, "gen3 title menu: rows read and step with no game: " .. tostring(err))

    local _, _, page = openScreen(ctx)
    T.eq(byId(page, "exp_share_percent").value(ctx), "--",
      "gen3 title menu: PERCENT reads -- with no game")
    T.eq(byId(page, "exp_share_percent").step(ctx, 1), false,
      "gen3 title menu: PERCENT does not step with no game")
    T.eq(byId(page, "exp_share").step(ctx, 1), false,
      "gen3 title menu: EXP SHARE has no save to write, so it does not step")
  end
  for name, fn in pairs(saved) do RomText[name] = fn end
end

run3.release()
run.release()
T.finish("exp_share")
