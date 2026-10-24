-- Standalone focused tests for the CUSTOM EXP SHARE controls.
-- Run from the mod root with: lua tests/custom_test.lua
local function eq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. "\nexpected: "
      .. tostring(expected) .. "\nactual: " .. tostring(actual), 2)
  end
end
local function hasRow(rows, id)
  for _, row in ipairs(rows) do
    if row.id == id then return row end
  end
  return nil
end
-- The mod's entry chunk only needs a tiny engine surface for these public
-- seams. The real headless loader supplies the same hook/event interfaces.
package.preload["src.core.Sound"] = function()
  return {}
end
local wrappers = {}
local mod = {
  events = {},
  hooks = {},
  exports = {},
}
function mod.events:on(name, fn)
  self[name] = fn
end
function mod.hooks:wrap(name, fn)
  wrappers[name] = fn
end
-- resolve main.lua beside this test's own tests/ folder, so the run works from
-- the mod root, from an engine root that has the mod symlinked, and under the
-- engine's runner, where the cwd is not the mod
local here = debug.getinfo(1, "S").source:gsub("^@", "")
local modRoot = (here:gsub("tests/custom_test%.lua$", ""))
local entry = assert(loadfile(modRoot .. "main.lua"))()
entry(mod)
local ex = mod.exports
local game = {
  save = { options = {} },
  writeOptions = function(self)
    self.writes = (self.writes or 0) + 1
  end,
}
local function optionRows()
  return wrappers["ui.options.rows"](function(_, rows) return rows end,
    game, { { id = "vanilla" } })
end
local rows = optionRows()
local modeRow = hasRow(rows, "exp_share")
for _, expectedMode in ipairs({ "gen1", "gen5", "balanced", "average", "custom", "off" }) do
  eq(modeRow.step(game, 1), true, "EXP SHARE cycles to " .. expectedMode)
  eq(game.save.options.expShare, expectedMode,
    "existing mode ladder remains intact through CUSTOM")
end
game.save.options.expShare = "average"
rows = optionRows()
modeRow = hasRow(rows, "exp_share")
eq(modeRow.step(game, 1), true, "EXP SHARE can enter CUSTOM in an open menu")
eq(hasRow(rows, "exp_share_percent") ~= nil, true,
  "CUSTOM controls appear immediately in the open menu")
eq(modeRow.step(game, 1), true, "EXP SHARE can leave CUSTOM in an open menu")
eq(hasRow(rows, "exp_share_percent"), nil,
  "CUSTOM controls disappear when leaving CUSTOM")
eq(hasRow(rows, "exp_share_percent"), nil,
  "CUSTOM percentage row is hidden while EXP SHARE is OFF")
eq(hasRow(rows, "exp_share_percent_slot"), nil,
  "CUSTOM percentage slot row is hidden while EXP SHARE is OFF")
eq(hasRow(rows, "exp_share_single") ~= nil, true,
  "the existing SINGLE EXP SHARE option remains available")
game.save.options.expShare = "custom"
rows = optionRows()
local percentRow = hasRow(rows, "exp_share_percent")
local percentSlotRow = hasRow(rows, "exp_share_percent_slot")
eq(percentRow ~= nil, true, "CUSTOM exposes the PERCENT row")
eq(percentSlotRow ~= nil, true, "CUSTOM exposes the PERCENT SLOT row")
eq(percentRow.value(game), "100%", "CUSTOM defaults to 100%")
eq(percentSlotRow.value(game), "ALL", "percentage target defaults to ALL")
eq(percentSlotRow.step(game, 1), true, "percentage target can select slot 1")
eq(game.save.options.expSharePercentSlot, "1",
  "percentage target persists the selected slot")
eq(percentRow.step(game, -1), true, "slot percentage can be changed")
eq(game.save.options.expSharePercent1, 90,
  "slot percentage is stored separately from the global percentage")
eq(percentRow.value(game), "90%", "slot percentage is displayed")
eq(percentSlotRow.step(game, -1), true, "percentage target can return to ALL")
eq(percentSlotRow.value(game), "ALL", "percentage target returns to ALL")
eq(percentRow.value(game), "100%",
  "global percentage is still 100% after changing slot 1")
eq(percentRow.step(game, -1), true, "global percentage can be changed")
eq(game.save.options.expSharePercent, 90,
  "global percentage is stored separately")
local monA, monB, monC, monD = { hp = 10 }, { hp = 10 }, { hp = 10 }, { hp = 10 }
local log = {}
local battle = {
  game = { save = { options = {
    expShare = "custom",
    expSharePercent = 100,
    expSharePercent2 = 50,
    expSharePercent3 = 10,
  }, party = { monA, monB, monC, monD } } },
  sayNext = function(_, text)
    log[#log + 1] = { kind = "say", text = text }
  end,
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
ex.awardCustom(ctx)
eq(log[1].split, 2, "CUSTOM keeps the full participant share")
eq(log[2].split, 2, "CUSTOM keeps the full share for the second fighter")
eq(log[3].kind, "say", "CUSTOM queues one shared-exp line")
eq(log[4].mon, monC, "CUSTOM awards the bench Pokémon")
eq(log[4].split, 20, "CUSTOM applies the selected 10% slot percentage")
eq(log[4].announce, nil, "CUSTOM bench gains remain silent")
eq(log[5].mon, monD, "CUSTOM awards an unconfigured bench slot")
eq(log[5].split, 2, "CUSTOM defaults an unconfigured slot to the global 100%")
print("custom EXP SHARE tests passed")
