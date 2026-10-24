-- Exp Share: an OPTIONS row that turns party-wide experience on in
-- five flavors.  GEN 1 mirrors the Exp. All key item -- the fighters
-- split half of the exp (and stat exp), and the whole party splits the
-- other half, re-divided by the party count (the participant-division
-- bug included, engine/battle/experience.asm).  GEN 5+ mirrors the
-- modern Exp. Share -- the fighters keep the full amount split between
-- them, and every alive bench mon gets half a fighter's share.
-- BALANCED is the GEN 5+ split with a level gate: a bench mon only
-- gains exp while it is below the active fighter's level, so the bench
-- trails the party instead of racing ahead of it.  AVERAGE is the same
-- gate measured against the party's average level instead.
-- Shared recipients get ONE "EXP is shared amongst the party" line
-- instead of a per-mon "X gained N EXP. Points!" message.
--
-- CUSTOM keeps the fighters at their full participant share and lets the
-- bench receive 10%..100% of that amount.  PERCENT SLOT (ALL / 1..6)
-- selects whether PERCENT edits the global value or one party slot.
--
-- SINGLE EXP SHARE (ALL / 1..6) still scopes those shared recipients
-- to one party slot: set to a slot number, the shared exp
-- goes only to the mon in that slot instead of the whole bench.  ALL
-- (the default) keeps the party-wide behaviour above.

local ORDER = { "off", "gen1", "gen5", "balanced", "average", "custom" }
local ORDER_INDEX = {}
for i, mode in ipairs(ORDER) do ORDER_INDEX[mode] = i end
local LABELS = { off = "OFF", gen1 = "GEN 1", gen5 = "GEN 5+",
                 balanced = "BALANCED", average = "AVERAGE", custom = "CUSTOM" }
local SHARE_TEXT = "EXP is shared\namongst the party!"
local SLOT_ORDER = { "all", "1", "2", "3", "4", "5", "6" }
local SLOT_INDEX = {}
for i, slot in ipairs(SLOT_ORDER) do SLOT_INDEX[slot] = i end
local SLOT_LABELS = { all = "ALL", ["1"] = "1", ["2"] = "2", ["3"] = "3",
                      ["4"] = "4", ["5"] = "5", ["6"] = "6" }
local JINGLE_ORDER = { "level_up", "item" }
local JINGLE_INDEX = { level_up = 1, item = 2, default = 1 }
local JINGLE_LABELS = { level_up = "LEVEL UP", item = "ITEM", default = "LEVEL UP" }
local PERCENT_ORDER = { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }
local PERCENT_INDEX = {}
for i, percent in ipairs(PERCENT_ORDER) do PERCENT_INDEX[percent] = i end

local api = {
  lastOptions = nil,
}

-- Gen 3's battle is the raw state table: it has no save, game or party,
-- only playerParty and the session.  The session's engineOptions is the same
-- table as game.save.options (save_schema_firered.lua:359), so it is the
-- options block the rows write to.
local function isGen3(battle)
  return battle.playerParty ~= nil and battle.session ~= nil
end

-- the save behind a battle ctx on any generation: Gen 1's BattleState
-- carries the live game (battle.game.save); Gen 2's Battle carries the save
-- itself (battle.save) with battle.party aliasing save.party.
-- eggs sit in the party as ordinary mons; Gen 3's Pokemon.isEgg
-- (pokemon.lua:1463) checks the flag or SPECIES_EGG.  Gen 1 / Gen 2 deny the
-- require, so there the check is always false.
local function isEgg(mon)
  if mon.isEgg == true or mon.egg == true then return true end
  local okPokemon, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okPokemon and type(Pokemon) == "table" and Pokemon.isEgg then
    return Pokemon.isEgg(mon) and true or false
  end
  return false
end

local function saveOf(battle)
  if not battle then return nil end
  local save = battle.save or (battle.game and battle.game.save)
  if save or not isGen3(battle) then return save end
  return { party = battle.playerParty, options = battle.session.engineOptions }
end

local function partyOf(battle)
  local save = saveOf(battle)
  return (battle and battle.party) or (save and save.party) or {}
end

local function optionsOf(battle)
  local save = saveOf(battle)
  return save and save.options
end

local function modeFromOptions(options)
  local mode = options and options.expShare
  if mode == "gen1" or mode == "gen5" or mode == "balanced"
      or mode == "average" or mode == "custom" then
    return mode
  end
  return "off"
end

local function slotFromOptions(options)
  local slot = tonumber(options and options.expShareSingle)
  if slot and slot >= 1 and slot <= 6 then return slot end
  return nil
end

local function jingleFromOptions(options)
  local jingle = options and options.expShareJingle
  if jingle == "item" or jingle == true then
    return "item"
  end
  return "level_up"
end

-- the share line: Gen 1's BattleState:sayNext, Gen 2's Battle:emit, Gen 3's
-- battle text box (Ui.push, the same queue exp_seq pushes its messages to)
local function sayShare(battle, text)
  if not battle then return end
  if battle.sayNext then
    battle:sayNext(text)
  elseif battle.emit then
    battle:emit({ kind = "message", text = text })
  else
    local okUi, Ui = pcall(require, "src.core.game3.battle.ui")
    if okUi and Ui and Ui.push then Ui.push(text) end
  end
end

-- the options block behind an OPTIONS row's game.  Gen 1 / Gen 2 keep it at
-- game.save.options.  Gen 3's title-screen menu opens before any save exists,
-- so with no save it reads the root options table on the game itself
-- (Game3.options, which writeOptions persists).
local function gameOptions(game)
  if type(game) ~= "table" then return nil end
  local options = game.save and game.save.options
  if options then return options end
  if game.save == nil and type(game.options) == "table" then return game.options end
  return nil
end

-- normalized mode: nil / garbage -> "off"
function api.modeOf(game)
  return modeFromOptions(gameOptions(game))
end

-- the row's step body: LEFT/RIGHT cycle OFF -> GEN 1 -> GEN 5+ ->
-- BALANCED -> AVERAGE -> CUSTOM -> OFF.  Returns nil when there is no save (the
-- launcher's stub games), so the row stays inert there like every other
-- options row.
function api.cycle(game, dir)
  local options = gameOptions(game)
  if not options then return nil end
  -- modeOf normalizes, so the ladder position is a direct lookup; the
  -- modulo is the same wrap the engine's own ladder rows use
  local i = ORDER_INDEX[api.modeOf(game)]
  local nextMode = ORDER[((i - 1 + (dir or 1)) % #ORDER) + 1]
  options.expShare = nextMode
  if game.writeOptions then
    game:writeOptions()
  elseif game.persistOptions then
    game:persistOptions()
  end
  return nextMode
end

function api.labelOf(game)
  return LABELS[api.modeOf(game)]
end

-- SINGLE EXP SHARE: nil (missing / "all" / garbage) means the shared exp
-- reaches the whole party; a number 1-6 scopes it to that party slot.
function api.slotOf(game)
  return slotFromOptions(gameOptions(game))
end

-- the row's step body: LEFT/RIGHT cycle ALL -> 1 -> 2 -> ... -> 6 -> ALL.
-- Returns nil when there is no save, like api.cycle.
function api.cycleSlot(game, dir)
  local options = gameOptions(game)
  if not options then return nil end
  local i = SLOT_INDEX[options.expShareSingle] or 1
  local nextSlot = SLOT_ORDER[((i - 1 + (dir or 1)) % #SLOT_ORDER) + 1]
  options.expShareSingle = nextSlot
  if game.writeOptions then
    game:writeOptions()
  elseif game.persistOptions then
    game:persistOptions()
  end
  return nextSlot
end

function api.slotLabel(game)
  local options = gameOptions(game)
  return SLOT_LABELS[options and options.expShareSingle] or "ALL"
end

local function writeOptions(game)
  if game.writeOptions then
    game:writeOptions()
  elseif game.persistOptions then
    game:persistOptions()
  end
end

local function normalizePercent(value)
  local percent = tonumber(value)
  if percent and PERCENT_INDEX[percent] then return percent end
  return 100
end

local function percentSlotFromOptions(options)
  local slot = options and options.expSharePercentSlot
  if slot == nil or slot == "all" then return nil end
  local number = tonumber(slot)
  if number and number % 1 == 0 and number >= 1 and number <= 6 then
    return number
  end
  return nil
end

local function percentKey(slot)
  return "expSharePercent" .. tostring(slot)
end

local function percentForOptions(options, slot)
  if type(options) ~= "table" then return 100 end
  if slot then
    local override = normalizePercent(options[percentKey(slot)])
    if options[percentKey(slot)] ~= nil then return override end
  end
  return normalizePercent(options.expSharePercent)
end

-- PERCENT uses the global value when PERCENT SLOT is ALL, or the selected
-- party-slot override when it names a slot.  Missing/invalid saved values
-- fall back to the safe 100% default.
function api.percentSlotOf(game)
  return percentSlotFromOptions(gameOptions(game))
end

function api.percentForSlot(game, slot)
  local options = gameOptions(game)
  return percentForOptions(options, tonumber(slot))
end

function api.percentOf(game)
  local options = gameOptions(game)
  return percentForOptions(options, percentSlotFromOptions(options))
end

function api.percentLabel(game)
  return tostring(api.percentOf(game)) .. "%"
end

function api.percentSlotLabel(game)
  local options = gameOptions(game)
  local slot = percentSlotFromOptions(options)
  return slot and tostring(slot) or "ALL"
end

-- Cycle the global percentage or the selected slot's percentage, depending
-- on PERCENT SLOT.  Each value is an integer multiple of ten.
function api.cyclePercent(game, dir)
  local options = gameOptions(game)
  if not options then return nil end
  local current = api.percentOf(game)
  local i = PERCENT_INDEX[current] or #PERCENT_ORDER
  local nextPercent = PERCENT_ORDER[((i - 1 + (dir or 1)) % #PERCENT_ORDER) + 1]
  local slot = percentSlotFromOptions(options)
  if slot then
    options[percentKey(slot)] = nextPercent
  else
    options.expSharePercent = nextPercent
  end
  writeOptions(game)
  return nextPercent
end

function api.cyclePercentSlot(game, dir)
  local options = gameOptions(game)
  if not options then return nil end
  local current = tostring(options.expSharePercentSlot or "all")
  local i = SLOT_INDEX[current] or 1
  local nextSlot = SLOT_ORDER[((i - 1 + (dir or 1)) % #SLOT_ORDER) + 1]
  options.expSharePercentSlot = nextSlot
  writeOptions(game)
  return nextSlot
end

local function optionsFrom(target)
  if type(target) ~= "table" then return nil end
  if target.save and target.save.options then return target.save.options end
  if target.options then return target.options end
  if target.expShareJingle ~= nil or target.expShare ~= nil or target.expShareSingle ~= nil then
    return target
  end
  return nil
end

-- LEVEL UP JINGLE: "level_up" (default fanfare) vs "item" (short item pickup chime).
function api.jingleOf(game)
  local options = optionsFrom(game) or api.lastOptions
  if not options then
    local okSave, SaveData = pcall(require, "src.core.SaveData")
    if okSave and type(SaveData) == "table" and SaveData.loadOptions then
      pcall(function() options = SaveData.loadOptions() end)
    end
  end
  return jingleFromOptions(options)
end

function api.cycleJingle(game, dir)
  local options = gameOptions(game)
  if not options then return nil end
  local i = JINGLE_INDEX[api.jingleOf(game)] or 1
  local nextJingle = JINGLE_ORDER[((i - 1 + (dir or 1)) % #JINGLE_ORDER) + 1]
  options.expShareJingle = nextJingle
  api.lastOptions = options
  if game.writeOptions then
    game:writeOptions()
  elseif game.persistOptions then
    game:persistOptions()
  end
  return nextJingle
end

function api.jingleLabel(game)
  return JINGLE_LABELS[api.jingleOf(game)] or "LEVEL UP"
end

function api.shouldRedirectJingle(gameOrData)
  return api.jingleOf(gameOrData) == "item"
end

-- GEN 1 (Exp. All): participants split half the exp; the whole party
-- splits the other half, with the halved-and-participant-divided base
-- divided again by the party count -- the vanilla
-- DivideExpDataByNumMonsGainingExp behavior with the EXP.ALL item held.
-- applyShare(mon, split, announce): split is the number of shares the
-- mon's base exp/stat exp is divided by; announce true prints the
-- individual gain line, nil stays silent (the share line covers it).
-- The share line announces the party pass before any of its silent
-- level-up messages queue.
function api.awardGen1(ctx)
  local battle = ctx.battle
  local party = partyOf(battle)
  local slot = slotFromOptions(optionsOf(battle))
  local single = slot and party[slot]
  local p = math.max(1, ctx.participants)
  local fought = {}
  for _, mon in ipairs(ctx.alive) do fought[mon] = true end
  for _, mon in ipairs(ctx.alive) do
    ctx.applyShare(mon, p * 2, true)
  end
  -- the party pass: every alive party mon, or just the designated slot
  -- when SINGLE EXP SHARE names one (an out-of-range slot means nobody)
  local recipients = {}
  for _, mon in ipairs(party) do
    if mon.hp > 0 and not isEgg(mon) and (not slot or mon == single) then
      recipients[#recipients + 1] = mon
    end
  end
  local line = false
  for _, mon in ipairs(recipients) do
    if not fought[mon] then line = true break end
  end
  if line then sayShare(battle, SHARE_TEXT) end
  -- the divisor counts only mons that can receive exp: eggs are left out
  local partyCount = 0
  for _, mon in ipairs(party) do
    if not isEgg(mon) then partyCount = partyCount + 1 end
  end
  for _, mon in ipairs(recipients) do
    ctx.applyShare(mon, p * partyCount * 2, nil)
  end
end

-- the shared GEN 5+ split: fighters keep the full exp split between
-- them; every alive bench mon that passes `gate` gets half a fighter's
-- share unless `benchSplit` supplies a custom divisor.  The bench gains
-- are silent -- one share line replaces the per-mon messages.  On Gen 1 and
-- Gen 2 it lands after the fighters' own gains and before the bench level-ups;
-- on Gen 3 the award hook runs before the exp sequence queues the fighters'
-- gain lines, so the share line shows before them.
local function awardModern(ctx, gate, benchSplit)
  local battle = ctx.battle
  local party = partyOf(battle)
  local slot = slotFromOptions(optionsOf(battle))
  local single = slot and party[slot]
  local p = math.max(1, ctx.participants)
  local fought = {}
  for _, mon in ipairs(ctx.alive) do fought[mon] = true end
  local bench = {}
  for _, mon in ipairs(party) do
    if mon.hp > 0 and not isEgg(mon) and not fought[mon] and (not gate or gate(mon))
        and (not slot or mon == single) then
      bench[#bench + 1] = mon
    end
  end
  for _, mon in ipairs(ctx.alive) do
    ctx.applyShare(mon, p, true)
  end
  if #bench > 0 then sayShare(battle, SHARE_TEXT) end
  for _, mon in ipairs(bench) do
    local split = benchSplit and benchSplit(mon, p) or p * 2
    ctx.applyShare(mon, split, nil)
  end
end

-- GEN 5+: no gate -- every alive bench mon gets the half share.
function api.awardGen5(ctx)
  return awardModern(ctx, nil)
end

-- BALANCED: the GEN 5+ split with the level gate -- a bench mon only
-- gains exp while it is below the active fighter's level.  A bench mon
-- at or above the mon you are using gets nothing until the fighter
-- levels past it, so the bench trails the party instead of out-leveling
-- the mons that actually fight.
function api.awardBalanced(ctx)
  local battle = ctx.battle
  -- Gen 1 wraps the party mon in a battler (battle.player.mon); Gen 2's
  -- battle.player IS the party mon.  Either way the mon carries `.level`.
  local active = battle.player and (battle.player.mon or battle.player)
  local capLevel = active and active.level or 100
  return awardModern(ctx, function(mon)
    return mon.level < capLevel
  end)
end

-- AVERAGE: the GEN 5+ split with the gate set to the party's average
-- level -- a bench mon only gains exp while it is below that average
-- (whole party minus eggs, fainted included), so the bench trails the party's
-- middle instead of the lead fighter.
function api.awardAverage(ctx)
  local battle = ctx.battle
  local party = partyOf(battle)
  local total, count = 0, 0
  for _, mon in ipairs(party) do
    if not isEgg(mon) then
      total = total + (mon.level or 1)
      count = count + 1
    end
  end
  local capLevel = count > 0 and math.floor(total / count) or 100
  return awardModern(ctx, function(mon)
    return mon.level < capLevel
  end)
end

-- CUSTOM: participants receive the full share based on the number of
-- participants.  Each alive bench mon receives the configured percentage of
-- that same one-participant share; at 100%, the divisor is identical to the
-- fighters' divisor.  The engine floors the resulting EXP/stat EXP values in
-- its normal applyShare path.
function api.awardCustom(ctx)
  local battle = ctx.battle
  local party = partyOf(battle)
  local options = optionsOf(battle)
  return awardModern(ctx, nil, function(mon, participants)
    local slot
    for i, candidate in ipairs(party) do
      if candidate == mon then slot = i break end
    end
    local percent = percentForOptions(options, slot)
    return participants * 100 / percent
  end)
end

local CUSTOM_ROW_IDS = {
  exp_share_percent_slot = true,
  exp_share_percent = true,
}

-- gated (GEN 3): the rows are listed in every mode, because the page's row
-- list is fixed when the menu builds.  Outside CUSTOM they read "--" and do
-- not step.  A nil game (the title-screen menu before any save) is not CUSTOM.
local function customOptionRows(gated)
  local function live(g)
    return not gated or modeFromOptions(gameOptions(g)) == "custom"
  end
  return {
    {
      id = "exp_share_percent_slot",
      label = "PERCENT SLOT",
      value = function(g) return live(g) and api.percentSlotLabel(g) or "--" end,
      step = function(g, dir)
        return live(g) and api.cyclePercentSlot(g, dir) ~= nil
      end,
    },
    {
      id = "exp_share_percent",
      label = "PERCENT",
      value = function(g) return live(g) and api.percentLabel(g) or "--" end,
      step = function(g, dir)
        return live(g) and api.cyclePercent(g, dir) ~= nil
      end,
    },
  }
end

-- OptionsMenu builds one mutable rows list for the lifetime of the screen.
-- Keep that list synchronized when the user changes EXP SHARE to/from CUSTOM
-- instead of waiting for the menu to be reopened.
local function syncCustomOptionRows(rows, game)
  local custom = modeFromOptions(gameOptions(game)) == "custom"
  local seen = {}
  for i = #rows, 1, -1 do
    local id = rows[i].id
    if CUSTOM_ROW_IDS[id] then
      seen[id] = true
      if not custom then table.remove(rows, i) end
    end
  end
  if not custom then return end
  local insertAt = #rows + 1
  for i, row in ipairs(rows) do
    if row.id == "exp_share" then insertAt = i + 1 break end
  end
  for _, row in ipairs(customOptionRows()) do
    if not seen[row.id] then
      table.insert(rows, insertAt, row)
      insertAt = insertAt + 1
    end
  end
end

-- GEN 3 LEVEL UP JINGLE: the level-up fanfare goes through Audio.playFanfare
-- (battle/exp_seq.lua, field.lua).  The audio module is required with pcall:
-- on Gen 1 / Gen 2 that require is denied, so the wrap silently does nothing.
-- It is retried at load, at game.ready and from the battle.exp_award hook,
-- and is idempotent once installed.
local GEN3_ITEM_JINGLE = "MUS_OBTAIN_ITEM"

local function wrapGen3Fanfare()
  local okAudio, Audio = pcall(require, "src.core.game3.audio")
  if not okAudio or type(Audio) ~= "table" then return end
  -- a same-process reload brings a new api; the wrap reads the latest one
  Audio._expShareApi = api
  if Audio._expShareWrapped then return end
  Audio._expShareWrapped = true
  local rawPlayFanfare = Audio.playFanfare
  Audio.playFanfare = function(id, ...)
    if (Audio._expShareApi or api).shouldRedirectJingle() then
      if id == "MUS_LEVEL_UP" or id == (Audio.role("levelUp") or 257) then
        id = GEN3_ITEM_JINGLE
      end
    end
    return rawPlayFanfare(id, ...)
  end
end

-- GEN 3 OPTIONS: the engine's option_rows bridge.  The gate is the mod's boot
-- generation (mod.generation, fixed by the loader), not the require: a plain
-- test runner can load that engine module on any generation.  Only then is
-- the module required, and the pcall covers a denied require.
local function gen3OptionRows(mod)
  if mod.generation ~= 3 then return nil end
  local okRows, Rows = pcall(require, "src.ui.game3.option_rows")
  if okRows and type(Rows) == "table" and type(Rows.GROUPS) == "table" then
    return Rows
  end
  return nil
end

-- Rows.group files a row by its id, so the EXP SHARE ids join the BATTLE OPTIONS
-- page's members.  Without this they land at the top level after MODS.
-- Idempotent: an id already in the group is not added again.
local GEN3_BATTLE_ROW_IDS = {
  "exp_share", "exp_share_percent_slot", "exp_share_percent",
  "exp_share_single", "exp_share_jingle",
}

local function wrapGen3OptionsGroup(mod)
  local Rows = gen3OptionRows(mod)
  if not Rows then return end
  for _, group in ipairs(Rows.GROUPS) do
    if group.id == "group.battle" then
      local present = {}
      for _, id in ipairs(group.members) do present[id] = true end
      for _, id in ipairs(GEN3_BATTLE_ROW_IDS) do
        if not present[id] then
          group.members[#group.members + 1] = id
          present[id] = true
        end
      end
    end
  end
end

return function(mod)
  local Sound = require("src.core.Sound")
  if Sound then
    Sound._expShareApi = api
    if not Sound._expShareWrapped then
      Sound._expShareWrapped = true
      local rawResolve = Sound.resolve
      Sound.resolve = function(data, name)
        local curApi = Sound._expShareApi or api
        if curApi.shouldRedirectJingle(data) then
          if name == "Level_Up" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Get_Item1"] then
              return "Get_Item1"
            elseif sfx and sfx["Sfx_Item"] then
              return "Sfx_Item"
            end
            return "Get_Item1"
          elseif name == "Sfx_DexFanfare5079" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Sfx_Item"] then
              return "Sfx_Item"
            elseif sfx and sfx["Get_Item1"] then
              return "Get_Item1"
            end
            return "Sfx_Item"
          end
        end
        if rawResolve then
          return rawResolve(data, name)
        end
        return name
      end

      local rawPlay = Sound.play
      Sound.play = function(data, name)
        local curApi = Sound._expShareApi or api
        if curApi.shouldRedirectJingle(data) then
          if name == "Level_Up" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Get_Item1"] then
              name = "Get_Item1"
            elseif sfx and sfx["Sfx_Item"] then
              name = "Sfx_Item"
            else
              name = "Get_Item1"
            end
          elseif name == "Sfx_DexFanfare5079" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Sfx_Item"] then
              name = "Sfx_Item"
            elseif sfx and sfx["Get_Item1"] then
              name = "Get_Item1"
            else
              name = "Sfx_Item"
            end
          end
        end
        if rawPlay then
          return rawPlay(data, name)
        end
      end

      local rawPlayStereo = Sound.playStereo
      Sound.playStereo = function(data, name)
        local curApi = Sound._expShareApi or api
        if curApi.shouldRedirectJingle(data) then
          if name == "Level_Up" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Get_Item1"] then
              name = "Get_Item1"
            elseif sfx and sfx["Sfx_Item"] then
              name = "Sfx_Item"
            else
              name = "Get_Item1"
            end
          elseif name == "Sfx_DexFanfare5079" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Sfx_Item"] then
              name = "Sfx_Item"
            elseif sfx and sfx["Get_Item1"] then
              name = "Get_Item1"
            else
              name = "Sfx_Item"
            end
          end
        end
        if rawPlayStereo then
          return rawPlayStereo(data, name)
        end
      end

      local rawDucks = Sound.ducksMusic
      Sound.ducksMusic = function(data, name)
        local curApi = Sound._expShareApi or api
        if curApi.shouldRedirectJingle(data) then
          if name == "Level_Up" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Get_Item1"] then
              name = "Get_Item1"
            elseif sfx and sfx["Sfx_Item"] then
              name = "Sfx_Item"
            else
              name = "Get_Item1"
            end
          elseif name == "Sfx_DexFanfare5079" then
            local sfx = data and data.audio and data.audio.sfx
            if sfx and sfx["Sfx_Item"] then
              name = "Sfx_Item"
            elseif sfx and sfx["Get_Item1"] then
              name = "Get_Item1"
            else
              name = "Sfx_Item"
            end
          end
        end
        if rawDucks then
          return rawDucks(data, name)
        end
        return false
      end

      local rawIsPlaying = Sound.isPlaying
      Sound.isPlaying = function(name)
        local curApi = Sound._expShareApi or api
        if curApi.shouldRedirectJingle() then
          if name == "Level_Up" then
            return (rawIsPlaying and (rawIsPlaying("Get_Item1") or rawIsPlaying("Sfx_Item"))) or (rawIsPlaying and rawIsPlaying(name)) or false
          elseif name == "Sfx_DexFanfare5079" then
            return (rawIsPlaying and (rawIsPlaying("Sfx_Item") or rawIsPlaying("Get_Item1"))) or (rawIsPlaying and rawIsPlaying(name)) or false
          end
        end
        if rawIsPlaying then
          return rawIsPlaying(name)
        end
        return false
      end

      local rawStop = Sound.stop
      Sound.stop = function(name)
        local curApi = Sound._expShareApi or api
        if curApi.shouldRedirectJingle() then
          if name == "Level_Up" then
            if rawStop then rawStop("Get_Item1") rawStop("Sfx_Item") end
          elseif name == "Sfx_DexFanfare5079" then
            if rawStop then rawStop("Sfx_Item") rawStop("Get_Item1") end
          end
        end
        if rawStop then
          rawStop(name)
        end
      end
    end
  end

  wrapGen3Fanfare()
  wrapGen3OptionsGroup(mod)
  mod.events:on("game.ready", function(ev)
    local options = ev and gameOptions(ev.game)
    if options then api.lastOptions = options end
    wrapGen3Fanfare()
    wrapGen3OptionsGroup(mod)
  end)

  -- the OPTIONS row; next() first keeps every other mod's rows
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local options = gameOptions(game)
    if options then api.lastOptions = options end
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    -- Gen 3 copies the returned rows once, so the list is fixed by now:
    -- its percent rows are always listed, and syncCustomOptionRows is skipped
    local gen3 = gen3OptionRows(mod) ~= nil
    out[#out + 1] = {
      id = "exp_share",
      label = "EXP SHARE",
      value = function(g) return api.labelOf(g) end,
      step = function(g, dir)
        local nextMode = api.cycle(g, dir)
        if nextMode ~= nil and not gen3 then syncCustomOptionRows(out, g) end
        return nextMode ~= nil
      end,
    }
    if gen3 then
      for _, row in ipairs(customOptionRows(true)) do out[#out + 1] = row end
    else
      syncCustomOptionRows(out, game)
    end
    out[#out + 1] = {
      id = "exp_share_single",
      label = "SINGLE EXP SHARE",
      value = function(g) return api.slotLabel(g) end,
      step = function(g, dir)
        return api.cycleSlot(g, dir) ~= nil
      end,
    }
    out[#out + 1] = {
      id = "exp_share_jingle",
      label = "LEVEL UP JINGLE",
      value = function(g) return api.jingleLabel(g) end,
      step = function(g, dir)
        return api.cycleJingle(g, dir) ~= nil
      end,
    }
    return out
  end)

  -- battle.exp_award: OFF defers to the vanilla participant/EXP.ALL
  -- split; GEN 1, GEN 5+, BALANCED, AVERAGE and CUSTOM replace it.  ctx is the
  -- engine's { battle, participants, alive, applyShare }.  Priority 90 runs
  -- this wrap before Crystal 251's priority-80 wrap so exp_share wins when
  -- active; in OFF mode we defer through nextFn, which falls through to
  -- Crystal's wrap so Crystal still owns EXP when exp_share is disabled.
  mod.hooks:wrap("battle.exp_award", function(nextFn, ctx)
    -- idempotent: a no-op once wrapped, and a retry if game.ready missed it
    wrapGen3Fanfare()
    local opts = optionsOf(ctx.battle)
    if opts then api.lastOptions = opts end
    local mode = modeFromOptions(opts)
    if mode == "gen1" then return api.awardGen1(ctx) end
    if mode == "gen5" then return api.awardGen5(ctx) end
    if mode == "balanced" then return api.awardBalanced(ctx) end
    if mode == "average" then return api.awardAverage(ctx) end
    if mode == "custom" then return api.awardCustom(ctx) end
    return nextFn(ctx)
  end, 90)

  mod.exports.modeOf = api.modeOf
  mod.exports.cycle = api.cycle
  mod.exports.labelOf = api.labelOf
  mod.exports.slotOf = api.slotOf
  mod.exports.cycleSlot = api.cycleSlot
  mod.exports.slotLabel = api.slotLabel
  mod.exports.percentSlotOf = api.percentSlotOf
  mod.exports.percentForSlot = api.percentForSlot
  mod.exports.percentOf = api.percentOf
  mod.exports.percentLabel = api.percentLabel
  mod.exports.percentSlotLabel = api.percentSlotLabel
  mod.exports.cyclePercent = api.cyclePercent
  mod.exports.cyclePercentSlot = api.cyclePercentSlot
  mod.exports.jingleOf = api.jingleOf
  mod.exports.cycleJingle = api.cycleJingle
  mod.exports.jingleLabel = api.jingleLabel
  mod.exports.shouldRedirectJingle = api.shouldRedirectJingle
  mod.exports.awardGen1 = api.awardGen1
  mod.exports.awardGen5 = api.awardGen5
  mod.exports.awardBalanced = api.awardBalanced
  mod.exports.awardAverage = api.awardAverage
  mod.exports.awardCustom = api.awardCustom
end
